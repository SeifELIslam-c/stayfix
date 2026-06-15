import 'dart:convert';
import 'dart:math';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../core/firebase_options.dart';
import '../core/manager_session_guard.dart';
import '../models/hotel_models.dart';
import '../services/app_session_service.dart';
import '../services/property_scope_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

class AccountDeletionResult {
  const AccountDeletionResult._({
    required this.success,
    required this.message,
    this.requiresPassword = false,
  });

  const AccountDeletionResult.success(String message)
      : this._(success: true, message: message);

  const AccountDeletionResult.failure(
    String message, {
    bool requiresPassword = false,
  }) : this._(
          success: false,
          message: message,
          requiresPassword: requiresPassword,
        );

  final bool success;
  final String message;
  final bool requiresPassword;
}

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
  String? _lastAuthErrorMessage;
  bool _lastAuthCreatedAccount = false;

  HotelUser? get currentUser => _currentUser;
  Hotel? get selectedHotel => _selectedHotel;
  List<Hotel> get myHotels => _myHotels;
  List<HotelUser> get hotelStaff => _hotelStaff;
  bool get isLoading => _isLoading;
  String? get lastAuthErrorMessage => _lastAuthErrorMessage;
  bool get lastAuthCreatedAccount => _lastAuthCreatedAccount;

  List<Room> get rooms {
    final uniqueRoomsMap = {for (var room in _rooms) room.number: room};
    List<Room> sortedRooms = uniqueRoomsMap.values.toList();
    sortedRooms.sort((a, b) => a.numberAsInt.compareTo(b.numberAsInt));
    return sortedRooms;
  }

  bool get isDirector => _currentUser?.role == UserRoles.director;
  Set<String> get currentAuthProviders =>
      _auth.currentUser?.providerData
          .map((provider) => provider.providerId)
          .where((provider) => provider.trim().isNotEmpty)
          .toSet() ??
      <String>{};

  HotelProvider() {
    tryAutoLogin();
  }

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void _setAuthError(String? message) {
    _lastAuthErrorMessage = message;
  }

  void _setLastAuthCreatedAccount(bool value) {
    _lastAuthCreatedAccount = value;
  }

  // --- Session Management ---
  Future<void> tryAutoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? savedUserId = prefs.getString('userId');
      final authUser = _auth.currentUser;

      if (savedUserId != null && savedUserId.isNotEmpty) {
        if (authUser == null || authUser.uid.trim() != savedUserId.trim()) {
          await logout();
          return;
        }
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
      _setAuthError(null);
      _setLastAuthCreatedAccount(false);
      _currentUser = null;
      _selectedHotel = null;

      if (input.contains('@')) {
        try {
          UserCredential cred = await _auth.signInWithEmailAndPassword(
              email: input, password: password);
          await _fetchUserData(cred.user!.uid);
          if (PropertyScopeService.isStayFixJobOnly(
                  AppSessionService.currentUserData) ||
              PropertyScopeService.isDisabled(
                  AppSessionService.currentUserData)) {
            await logout();
            return false;
          }
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
        if (PropertyScopeService.isStayFixJobOnly(
                AppSessionService.currentUserData) ||
            PropertyScopeService.isDisabled(
                AppSessionService.currentUserData)) {
          await logout();
          return false;
        }
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
    AppSessionService.clear();
    _currentUser = null;
    _selectedHotel = null;
    _rooms = [];
    _myHotels = [];
    _hotelStaff = [];
    notifyListeners();
    try {
      await _auth.signOut();
    } catch (e) {
      debugPrint('Logout signOut error: $e');
    }
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
        AppSessionService.setCurrentUser(userId: doc.id, data: data);
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
      _setAuthError(null);
      _setLastAuthCreatedAccount(false);
      final GoogleSignIn googleSignIn = _buildGoogleSignIn();
      // Sign out first so the account picker is always shown,
      // even when a previous session is still cached.
      await googleSignIn.disconnect().catchError((_) => null);
      await googleSignIn.signOut();
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
      final bool createdAccount =
          userCredential.additionalUserInfo?.isNewUser == true || !doc.exists;

      if (createdAccount) {
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
          'termsAccepted': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      _setLastAuthCreatedAccount(createdAccount);
      await _fetchUserData(user.uid);
      await _saveSession(user.uid);
      listenToMyHotels();
      return true;
    } on PlatformException catch (e) {
      _setAuthError(_googlePlatformErrorMessage(e));
      debugPrint('Google Login Error: $e');
      return false;
    } catch (e) {
      _setAuthError('Connexion Google impossible pour le moment.');
      debugPrint('Google Login Error: $e');
      return false;
    }
  }

  Future<bool> loginWithApple() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.macOS) {
      return false;
    }
    try {
      _setAuthError(null);
      _setLastAuthCreatedAccount(false);
      final UserCredential userCredential =
          await _signInToFirebaseWithAppleCredential();
      final User? user = userCredential.user;
      if (user == null) return false;
      final appleSignIn = _lastAppleOAuthPayload;
      if (appleSignIn == null) {
        throw FirebaseAuthException(
          code: 'missing-apple-token',
          message: 'Apple identity token missing.',
        );
      }

      final bool createdAccount = await _syncAppleUserProfile(
        user: user,
        userCredential: userCredential,
        appleSignIn: appleSignIn,
      );

      _setLastAuthCreatedAccount(createdAccount);
      await _fetchUserData(user.uid);
      await _saveSession(user.uid);
      listenToMyHotels();
      return true;
    } on FirebaseAuthException catch (e) {
      _setAuthError(_appleFirebaseErrorMessage(e));
      debugPrint('Apple Login Firebase Error: ${e.code} ${e.message}');
      return false;
    } on SignInWithAppleAuthorizationException catch (e) {
      _setAuthError(
        e.code == AuthorizationErrorCode.canceled
            ? 'Connexion Apple annulee.'
            : 'Connexion Apple impossible pour le moment.',
      );
      debugPrint('Apple Login Error: $e');
      return false;
    } catch (e) {
      _setAuthError('Connexion Apple impossible pour le moment.');
      debugPrint('Apple Login Error: $e');
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

  Future<AccountDeletionResult> deleteCurrentAccount({
    String? currentPassword,
  }) async {
    final authUser = _auth.currentUser;
    final currentUser = _currentUser;
    if (authUser == null || currentUser == null) {
      return const AccountDeletionResult.failure(
        'Aucun compte connecte.',
      );
    }

    try {
      await _reauthenticateForSensitiveAction(
        user: authUser,
        currentPassword: currentPassword,
      );

      await _deleteCurrentUserFirestoreData(
        authUid: authUser.uid,
        currentUserId: currentUser.id,
      );

      await authUser.delete();
      await logout();
      return const AccountDeletionResult.success(
        'Votre compte a ete supprime.',
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'wrong-password') {
        return const AccountDeletionResult.failure(
          'Le mot de passe saisi est incorrect.',
          requiresPassword: true,
        );
      }
      if (error.code == 'requires-recent-login') {
        return const AccountDeletionResult.failure(
          'Reconnectez-vous puis relancez la suppression du compte.',
        );
      }
      return AccountDeletionResult.failure(
        'Suppression impossible: ${error.message ?? error.code}',
        requiresPassword: currentAuthProviders.contains('password'),
      );
    } on SignInWithAppleAuthorizationException catch (error) {
      return AccountDeletionResult.failure(
        'Validation Apple annulee: ${error.message}.',
      );
    } on StateError catch (error) {
      final requiresPassword = error.toString().contains('password-required');
      return AccountDeletionResult.failure(
        requiresPassword
            ? 'Saisissez votre mot de passe pour confirmer.'
            : 'Suppression impossible pour le moment.',
        requiresPassword: requiresPassword,
      );
    } catch (error) {
      return const AccountDeletionResult.failure(
        'Suppression impossible pour le moment.',
      );
    }
  }

  Future<void> _deleteCurrentUserFirestoreData({
    required String authUid,
    required String currentUserId,
  }) async {
    final idsToDelete = <String>{authUid, currentUserId}
      ..removeWhere((value) => value.trim().isEmpty);

    final batch = _firestore.batch();
    for (final uid in idsToDelete) {
      batch.delete(_firestore.collection('users').doc(uid));
      batch.delete(_firestore.collection('profiles').doc(uid));
    }
    await batch.commit();
  }

  Future<void> _reauthenticateForSensitiveAction({
    required User user,
    String? currentPassword,
  }) async {
    final providers = currentAuthProviders;
    if (providers.contains('password')) {
      final email = user.email!.trim();
      final password = currentPassword?.trim() ?? '';
      if (email.isEmpty || password.isEmpty) {
        throw StateError('password-required');
      }
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      await user.reauthenticateWithCredential(credential);
      return;
    }

    if (providers.contains('google.com')) {
      final googleSignIn = _buildGoogleSignIn();
      await googleSignIn.disconnect().catchError((_) => null);
      await googleSignIn.signOut();
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw StateError('reauth-cancelled');
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await user.reauthenticateWithCredential(credential);
      return;
    }

    if (providers.contains('apple.com')) {
      final credential = await _buildAppleOAuthCredential();
      await user.reauthenticateWithCredential(credential);
    }
  }

  Future<OAuthCredential> _buildAppleOAuthCredential() async {
    return (await _buildAppleOAuthPayload()).credential;
  }

  _AppleOAuthPayload? _lastAppleOAuthPayload;

  Future<UserCredential> _signInToFirebaseWithAppleCredential() async {
    final appleSignIn = await _buildAppleOAuthPayload();
    _lastAppleOAuthPayload = appleSignIn;

    try {
      return await _auth.signInWithCredential(appleSignIn.credential);
    } on FirebaseAuthException catch (error) {
      if (error.code != 'invalid-credential') rethrow;

      // Apple credentials are short-lived. Request one fresh credential before
      // surfacing a hard failure so review devices do not get stuck on a stale token.
      final retryPayload = await _buildAppleOAuthPayload();
      _lastAppleOAuthPayload = retryPayload;
      return _auth.signInWithCredential(retryPayload.credential);
    }
  }

  Future<_AppleOAuthPayload> _buildAppleOAuthPayload() async {
    final rawNonce = _generateNonce();
    final nonce = _sha256OfString(rawNonce);
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: const [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: nonce,
    );
    final idToken = appleCredential.identityToken;
    if (idToken == null || idToken.isEmpty) {
      throw FirebaseAuthException(
        code: 'missing-apple-token',
        message: 'Apple identity token missing.',
      );
    }
    return _AppleOAuthPayload(
      credential: OAuthProvider('apple.com').credential(
        idToken: idToken,
        rawNonce: rawNonce,
      ),
      email: (appleCredential.email ?? '').trim(),
      firstName: (appleCredential.givenName ?? '').trim(),
      lastName: (appleCredential.familyName ?? '').trim(),
    );
  }

  Future<bool> _syncAppleUserProfile({
    required User user,
    required UserCredential userCredential,
    required _AppleOAuthPayload appleSignIn,
  }) async {
    final userRef = _firestore.collection('users').doc(user.uid);
    final doc = await userRef.get();
    final createdAccount =
        userCredential.additionalUserInfo?.isNewUser == true || !doc.exists;
    final fullName = (userCredential.user?.displayName ?? '').trim();
    final firstName = appleSignIn.firstName.isNotEmpty
        ? appleSignIn.firstName
        : _extractFirstName(fullName);
    final lastName = appleSignIn.lastName.isNotEmpty
        ? appleSignIn.lastName
        : _extractLastName(fullName);
    final resolvedEmail = (user.email ?? appleSignIn.email).trim();

    if (createdAccount) {
      await userRef.set({
        'firstName': firstName,
        'lastName': lastName,
        'username': resolvedEmail.isNotEmpty
            ? resolvedEmail.split('@')[0]
            : 'stayfix_user',
        'email': resolvedEmail,
        'role': UserRoles.director,
        'phone': '',
        'termsAccepted': false,
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      return true;
    }

    final existingData = doc.data() ?? const <String, dynamic>{};
    final updates = <String, dynamic>{};
    if ((existingData['firstName'] as String? ?? '').trim().isEmpty &&
        firstName.isNotEmpty) {
      updates['firstName'] = firstName;
    }
    if ((existingData['lastName'] as String? ?? '').trim().isEmpty &&
        lastName.isNotEmpty) {
      updates['lastName'] = lastName;
    }
    if ((existingData['email'] as String? ?? '').trim().isEmpty &&
        resolvedEmail.isNotEmpty) {
      updates['email'] = resolvedEmail;
    }
    if ((existingData['username'] as String? ?? '').trim().isEmpty &&
        resolvedEmail.isNotEmpty) {
      updates['username'] = resolvedEmail.split('@')[0];
    }
    if (updates.isNotEmpty) {
      await userRef.set(updates, SetOptions(merge: true));
    }
    return false;
  }

  GoogleSignIn _buildGoogleSignIn() {
    final applePlatforms = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    return GoogleSignIn(
      scopes: const ['email'],
      clientId:
          applePlatforms ? DefaultFirebaseOptions.googleIosClientId : null,
      serverClientId: DefaultFirebaseOptions.googleServerClientId,
    );
  }

  String _googlePlatformErrorMessage(PlatformException error) {
    final details = '${error.code} ${error.message ?? ''}'.toLowerCase();
    if (details.contains('apiexception: 10') ||
        details.contains('developer_error')) {
      return 'Google Sign-In est mal configure pour cette application. Verifiez le client OAuth Android et la cle SHA dans Firebase.';
    }
    if (details.contains('network')) {
      return 'Connexion Google impossible sans internet.';
    }
    return 'Connexion Google impossible pour le moment.';
  }

  String _appleFirebaseErrorMessage(FirebaseAuthException error) {
    switch (error.code) {
      case 'invalid-credential':
        return 'Connexion Apple refusee par le service d authentification. Verifiez la configuration Apple dans Firebase et App Store Connect.';
      case 'missing-or-invalid-nonce':
      case 'invalid-oauth-response':
        return 'Connexion Apple impossible a valider. Reessayez dans un instant.';
      case 'operation-not-allowed':
        return 'Connexion Apple non active pour cette application.';
      case 'network-request-failed':
        return 'Connexion Apple impossible sans internet.';
      case 'account-exists-with-different-credential':
        return 'Un compte existe deja avec cet email via une autre methode de connexion.';
      case 'too-many-requests':
        return 'Trop de tentatives Apple. Reessayez plus tard.';
      case 'missing-apple-token':
        return 'Le jeton Apple est manquant. Reessayez.';
      default:
        return 'Connexion Apple impossible pour le moment.';
    }
  }

  String _extractFirstName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  String _extractLastName(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length <= 1) return '';
    return parts.sublist(1).join(' ');
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256OfString(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }
}

class _AppleOAuthPayload {
  const _AppleOAuthPayload({
    required this.credential,
    required this.email,
    required this.firstName,
    required this.lastName,
  });

  final OAuthCredential credential;
  final String email;
  final String firstName;
  final String lastName;
}
