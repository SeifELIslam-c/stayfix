import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:hotel_lux_os/core/manager_session_guard.dart';
import 'package:hotel_lux_os/models/hotel_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HotelProvider extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  HotelUser? _currentUser;
  Hotel? _selectedHotel;

  StreamSubscription<QuerySnapshot>? _roomsSubscription;
  StreamSubscription<QuerySnapshot>? _hotelsSubscription;

  List<Hotel> _myHotels = [];
  List<HotelUser> _hotelStaff = [];
  List<Room> _rooms = [];

  bool _isLoading = false;

  HotelUser? get currentUser => _currentUser;
  Hotel? get selectedHotel => _selectedHotel;
  List<Hotel> get myHotels => _myHotels;
  List<HotelUser> get hotelStaff => _hotelStaff;
  bool get isLoading => _isLoading;

  List<Room> get rooms {
    final uniqueRoomsMap = {for (var room in _rooms) room.number: room};
    List<Room> sortedRooms = uniqueRoomsMap.values.toList();
    sortedRooms.sort((a, b) => a.numberAsInt.compareTo(b.numberAsInt));
    return sortedRooms;
  }

  bool get isDirector => _currentUser?.role == UserRoles.director;

  HotelProvider() {
    tryAutoLogin();
  }

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  // --- Session Management ---
  Future<void> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedUserId = prefs.getString('userId');

      if (savedUserId != null && savedUserId.isNotEmpty) {
        await _fetchUserData(savedUserId);

        if (_currentUser != null) {
          listenToMyHotels();
          if (_currentUser!.hotelId != null) {
            await _fetchHotelById(_currentUser!.hotelId!);
            listenToHotelData();
          }
        } else {
          await logout();
        }
      }
    } catch (e) {
      debugPrint("AutoLogin Error: $e");
    }
  }

  Future<bool> login(String input, String password) async {
    try {
      _currentUser = null;
      _selectedHotel = null;

      if (input.contains('@')) {
        try {
          UserCredential cred = await _auth.signInWithEmailAndPassword(
              email: input, password: password);
          await _fetchUserData(cred.user!.uid);
          await _saveSession(cred.user!.uid);
          listenToMyHotels();
          return true;
        } catch (e) {
          return await _loginAsStaff(
              field: 'email', value: input, password: password);
        }
      } else {
        return await _loginAsStaff(
            field: 'username', value: input, password: password);
      }
    } catch (e) {
      debugPrint("Login Error: $e");
      return false;
    }
  }

  Future<bool> _loginAsStaff(
      {required String field,
      required String value,
      required String password}) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where(field, isEqualTo: value)
          .where('password', isEqualTo: password)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        await _fetchUserData(doc.id);
        await _saveSession(doc.id);

        if (_currentUser!.hotelId != null) {
          await _fetchHotelById(_currentUser!.hotelId!);
          listenToHotelData();
        }
        return true;
      }
    } catch (e) {
      debugPrint("Staff Login Error: $e");
    }
    return false;
  }

  Future<void> _saveSession(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', userId);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('userId');
    ManagerSessionGuard.reset();
    _roomsSubscription?.cancel();
    _hotelsSubscription?.cancel();
    await _auth.signOut();
    _currentUser = null;
    _selectedHotel = null;
    _rooms = [];
    _myHotels = [];
    notifyListeners();
  }

  void setHotel(Hotel? hotel) {
    _selectedHotel = hotel;
    _rooms = [];
    _roomsSubscription?.cancel();
    if (hotel != null) {
      fetchHotelStaff();
      listenToHotelData();
    }
    notifyListeners();
  }

  void listenToHotelData() {
    if (_selectedHotel == null) return;
    _roomsSubscription?.cancel();
    _roomsSubscription = _firestore
        .collection('hotels')
        .doc(_selectedHotel!.id)
        .collection('rooms')
        .snapshots()
        .listen((snapshot) {
      _rooms =
          snapshot.docs.map((doc) => Room.fromMap(doc.id, doc.data())).toList();
      notifyListeners();
    });
    fetchHotelStaff();
  }

  void listenToMyHotels() {
    if (_currentUser == null) return;
    _hotelsSubscription?.cancel();
    _hotelsSubscription = _firestore
        .collection('hotels')
        .where('ownerId', isEqualTo: _currentUser!.id)
        .snapshots()
        .listen((snapshot) {
      _myHotels = snapshot.docs.map((doc) {
        final data = doc.data();
        return Hotel(
          id: doc.id,
          groupId: data['groupId'] ?? '',
          name: data['name'] ?? '',
          location: data['location'] ?? '',
          ownerId: data['ownerId'] ?? '',
        );
      }).toList();
      notifyListeners();
    });
  }

  Future<void> fetchMyHotels() async {
    listenToMyHotels();
  }

  Future<void> updateRoomStatus(String roomId, String newStatus) async {
    if (_selectedHotel == null) return;
    await _firestore
        .collection('hotels')
        .doc(_selectedHotel!.id)
        .collection('rooms')
        .doc(roomId)
        .update({'status': newStatus});
  }

  Future<void> updateRoomType(String roomId, String newType) async {
    if (_selectedHotel == null) return;
    await _firestore
        .collection('hotels')
        .doc(_selectedHotel!.id)
        .collection('rooms')
        .doc(roomId)
        .update({'type': newType});
  }

  Future<void> deleteRoom(String roomId) async {
    if (_selectedHotel == null) return;
    await _firestore
        .collection('hotels')
        .doc(_selectedHotel!.id)
        .collection('rooms')
        .doc(roomId)
        .delete();
  }

  Future<void> addRoom(String number, String floor) async {
    if (_selectedHotel == null) return;
    await _firestore
        .collection('hotels')
        .doc(_selectedHotel!.id)
        .collection('rooms')
        .add({
      'number': number,
      'status': 'Libre',
      'type': 'King',
      'floor': floor,
    });
  }

  Future<void> renameFloor(String oldFloorName, String newFloorName) async {
    if (_selectedHotel == null) return;
    var snapshot = await _firestore
        .collection('hotels')
        .doc(_selectedHotel!.id)
        .collection('rooms')
        .where('floor', isEqualTo: oldFloorName)
        .get();
    WriteBatch batch = _firestore.batch();
    for (var doc in snapshot.docs) {
      batch.update(doc.reference, {'floor': newFloorName});
    }
    await batch.commit();
  }

  Future<void> createHotel(String name, String location) async {
    if (_currentUser == null) return;
    setLoading(true);
    try {
      DocumentReference docRef = await _firestore.collection('hotels').add({
        'name': name,
        'location': location,
        'ownerId': _currentUser!.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await _generateDefaultRoomsForId(docRef.id);
    } catch (e) {
      debugPrint("Error creating hotel: $e");
    } finally {
      setLoading(false);
    }
  }

  Future<void> _generateDefaultRoomsForId(String hotelId) async {
    WriteBatch batch = _firestore.batch();
    void add(int number) {
      DocumentReference ref = _firestore
          .collection('hotels')
          .doc(hotelId)
          .collection('rooms')
          .doc();
      int floorNum = (number / 100).floor();
      String floorName = "Etage $floorNum";
      batch.set(ref, {
        'number': number.toString(),
        'status': 'Libre',
        'type': 'King',
        'floor': floorName,
      });
    }

    for (int i = 200; i <= 556; i++) {
      add(i);
    }
    List<int> startPoints = [700, 800, 900, 1000, 1100, 1200, 1300, 1400];
    for (int start in startPoints) {
      for (int i = start; i <= start + 13; i++) {
        add(i);
      }
    }
    await batch.commit();
  }

  Future<void> generateDefaultRooms() async {
    if (_selectedHotel != null) {
      setLoading(true);
      await _generateDefaultRoomsForId(_selectedHotel!.id);
      setLoading(false);
    }
  }

  Future<void> _fetchUserData(String uid) async {
    try {
      DocumentSnapshot doc =
          await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        _currentUser = HotelUser(
          id: doc.id,
          email: data['email'] ?? '',
          firstName: data['firstName'] ?? '',
          lastName: data['lastName'] ?? '',
          username: data['username'] ?? '',
          role: data['role'] ?? 'Staff',
          phone: data['phone'] ?? '',
          hotelId: data['hotelId'],
        );
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching user data: $e");
    }
  }

  Future<void> _fetchHotelById(String hotelId) async {
    try {
      DocumentSnapshot doc =
          await _firestore.collection('hotels').doc(hotelId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        _selectedHotel = Hotel(
          id: doc.id,
          groupId: data['groupId'] ?? '',
          name: data['name'] ?? '',
          location: data['location'] ?? '',
          ownerId: data['ownerId'] ?? '',
        );
      }
    } catch (e) {
      debugPrint("Error fetching hotel: $e");
    }
  }

  Future<void> fetchHotelStaff() async {
    if (_selectedHotel == null) return;
    try {
      var snapshot = await _firestore
          .collection('users')
          .where('hotelId', isEqualTo: _selectedHotel!.id)
          .get();
      _hotelStaff = snapshot.docs.map((doc) {
        final data = doc.data();
        return HotelUser(
          id: doc.id,
          email: data['email'] ?? '',
          firstName: data['firstName'] ?? '',
          lastName: data['lastName'] ?? '',
          username: data['username'] ?? '',
          role: data['role'] ?? 'Staff',
          phone: data['phone'] ?? '',
          hotelId: data['hotelId'],
        );
      }).toList();
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching staff: $e");
    }
  }

  Future<void> deleteHotel(String id) async {
    await _firestore.collection('hotels').doc(id).delete();
  }

  Future<bool> loginWithGoogle() async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return false;

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential =
          await _auth.signInWithCredential(credential);
      final User? user = userCredential.user;
      if (user == null) return false;

      final DocumentSnapshot doc =
          await _firestore.collection('users').doc(user.uid).get();

      if (!doc.exists) {
        final String displayName = user.displayName ?? '';
        final List<String> names = displayName.split(' ');
        final String fName = names.isNotEmpty ? names.first : '';
        final String lName = names.length > 1 ? names.last : '';

        await _firestore.collection('users').doc(user.uid).set({
          'firstName': fName,
          'lastName': lName,
          'username': user.email?.split('@')[0] ?? '',
          'email': user.email ?? '',
          'role': UserRoles.director,
          'phone': '',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await _fetchUserData(user.uid);
      await _saveSession(user.uid);
      listenToMyHotels();
      return true;
    } catch (e) {
      debugPrint('Google Login Error: $e');
      return false;
    }
  }

  Future<bool> registerDirector(
      {required String email,
      required String password,
      required String fullName,
      required String phone}) async {
    try {
      UserCredential cred = await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      List<String> names = fullName.split(" ");
      String fName = names.isNotEmpty ? names.first : fullName;
      String lName = names.length > 1 ? names.last : "";

      final newDirector = HotelUser(
        id: cred.user!.uid,
        email: email,
        firstName: fName,
        lastName: lName,
        username: email.split('@')[0],
        role: UserRoles.director,
        phone: phone,
      );

      await _firestore.collection('users').doc(cred.user!.uid).set({
        'firstName': newDirector.firstName,
        'lastName': newDirector.lastName,
        'username': newDirector.username,
        'email': newDirector.email,
        'role': newDirector.role,
        'phone': newDirector.phone,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _currentUser = newDirector;
      await _saveSession(cred.user!.uid);
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> addStaffMember(
      {required String firstName,
      required String lastName,
      required String email,
      required String phone,
      required String username,
      required String password,
      required String role}) async {
    if (_selectedHotel == null) return;
    await _firestore.collection('users').add({
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phone': phone,
      'username': username,
      'password': password,
      'role': role,
      'hotelId': _selectedHotel!.id,
      'addedBy': _currentUser?.id,
      'createdAt': FieldValue.serverTimestamp(),
    });
    fetchHotelStaff();
  }

  Future<bool> updateUserProfile(
      {String? email, String? username, String? password}) async {
    if (_currentUser == null) return false;
    try {
      Map<String, dynamic> updates = {};
      if (email != null && email.isNotEmpty) {
        updates['email'] = email;
      }
      if (username != null && username.isNotEmpty) {
        updates['username'] = username;
      }
      if (password != null && password.isNotEmpty) {
        updates['password'] = password;
      }

      await _firestore
          .collection('users')
          .doc(_currentUser!.id)
          .update(updates);
      _currentUser = HotelUser(
        id: _currentUser!.id,
        email: email ?? _currentUser!.email,
        firstName: _currentUser!.firstName,
        lastName: _currentUser!.lastName,
        username: username ?? _currentUser!.username,
        role: _currentUser!.role,
        phone: _currentUser!.phone,
        hotelId: _currentUser!.hotelId,
      );
      notifyListeners();
      return true;
    } catch (e) {
      return false;
    }
  }
}
