import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class ScopedAccountService {
  ScopedAccountService._();

  static FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  static Future<String> createApartmentAccount({
    required String immeubleOwnerId,
    required String apartmentName,
    required String email,
    required String password,
  }) async {
    final createdUser = await _createAuthUser(email: email, password: password);
    final apartmentRef = _firestore.collection('hotels').doc();

    final batch = _firestore.batch();
    batch.set(apartmentRef, <String, dynamic>{
      'name': apartmentName,
      'email': email,
      'ownerId': immeubleOwnerId,
      'accountUid': createdUser.uid,
      'propertyProfileType': 'apartment_condo_owner',
      'parentImmeubleId': immeubleOwnerId,
      'status': 'active',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'location': '',
      'city': '',
      'region': '',
      'unitCount': 0,
    });
    batch.set(
        _firestore.collection('users').doc(createdUser.uid),
        <String, dynamic>{
          'uid': createdUser.uid,
          'email': email,
          'username': email.split('@').first,
          'displayName': apartmentName,
          'role': 'Appartement',
          'accountType': 'apartment_account',
          'appAccess': 'stayfix',
          'propertyProfileType': 'apartment_condo_owner',
          'propertyProfileLabel': 'Appartement',
          'propertyIds': <String>[apartmentRef.id],
          'apartmentId': apartmentRef.id,
          'apartmentName': apartmentName,
          'createdByImmeubleId': immeubleOwnerId,
          'status': 'active',
          'termsAccepted': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
    await batch.commit();
    return apartmentRef.id;
  }

  static Future<String> createApartmentManagerAccount({
    required String immeubleOwnerId,
    required String apartmentId,
    required String apartmentName,
    required String fullName,
    required String email,
    required String password,
  }) async {
    final createdUser = await _createAuthUser(email: email, password: password);
    await _firestore.collection('users').doc(createdUser.uid).set({
      'uid': createdUser.uid,
      'email': email,
      'username': email.split('@').first,
      'displayName': fullName,
      'firstName': _firstName(fullName),
      'lastName': _lastName(fullName),
      'role': 'Gestionnaire appartement',
      'accountType': 'apartment_manager',
      'appAccess': 'stayfix',
      'propertyProfileType': 'apartment_condo_owner',
      'propertyProfileLabel': 'Gestionnaire appartement',
      'propertyIds': <String>[apartmentId],
      'apartmentId': apartmentId,
      'apartmentName': apartmentName,
      'createdByImmeubleId': immeubleOwnerId,
      'status': 'active',
      'termsAccepted': false,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return createdUser.uid;
  }

  static Future<String> createConciergeAccount({
    required String immeubleOwnerId,
    required String apartmentId,
    required String apartmentName,
    required String fullName,
    required String email,
    required String password,
  }) async {
    final createdUser = await _createAuthUser(email: email, password: password);
    final batch = _firestore.batch();
    batch.set(
        _firestore.collection('users').doc(createdUser.uid),
        {
          'uid': createdUser.uid,
          'email': email,
          'username': email.split('@').first,
          'displayName': fullName,
          'firstName': _firstName(fullName),
          'lastName': _lastName(fullName),
          'role': 'Concierge',
          'accountType': 'concierge',
          'appAccess': 'stayfix_job',
          'propertyIds': <String>[apartmentId],
          'apartmentId': apartmentId,
          'apartmentName': apartmentName,
          'createdByImmeubleId': immeubleOwnerId,
          'status': 'active',
          'termsAccepted': false,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
    batch.set(
        _firestore.collection('profiles').doc(createdUser.uid),
        {
          'uid': createdUser.uid,
          'email': email,
          'name': fullName,
          'displayName': fullName,
          'role': 'Concierge',
          'accountType': 'concierge',
          'appAccess': 'stayfix_job',
          'apartmentId': apartmentId,
          'apartmentName': apartmentName,
          'createdByImmeubleId': immeubleOwnerId,
          'department': 'Conciergerie',
          'specialties': <String>['Conciergerie immeuble'],
          'isAvailable': true,
          'isStayFixAssigned': true,
          'stayfixBadgeLabel': 'Concierge StayFix',
          'status': 'active',
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
    await batch.commit();
    return createdUser.uid;
  }

  static Future<void> disableScopedUser(String uid) async {
    final batch = _firestore.batch();
    batch.set(
        _firestore.collection('users').doc(uid),
        {
          'status': 'deleted',
          'appAccess': 'disabled',
          'deletedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
    batch.set(
        _firestore.collection('profiles').doc(uid),
        {
          'status': 'deleted',
          'isAvailable': false,
          'deletedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
    await batch.commit();
  }

  static Future<void> deleteScopedUserDocuments(String uid) async {
    final batch = _firestore.batch();
    batch.delete(_firestore.collection('users').doc(uid));
    batch.delete(_firestore.collection('profiles').doc(uid));
    await batch.commit();
  }

  static Future<void> archiveApartment({
    required String apartmentId,
    required String apartmentAccountUid,
  }) async {
    final batch = _firestore.batch();
    batch.set(
        _firestore.collection('hotels').doc(apartmentId),
        {
          'status': 'deleted',
          'deletedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
    batch.set(
        _firestore.collection('users').doc(apartmentAccountUid),
        {
          'status': 'deleted',
          'appAccess': 'disabled',
          'deletedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true));
    await batch.commit();
  }

  static Future<User> _createAuthUser({
    required String email,
    required String password,
  }) async {
    FirebaseApp? secondaryApp;
    try {
      secondaryApp = await Firebase.initializeApp(
        name: 'scoped-account-${DateTime.now().microsecondsSinceEpoch}',
        options: Firebase.app().options,
      );
      final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
      final credential = await secondaryAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw StateError('account-creation-failed');
      }
      await secondaryAuth.signOut();
      return user;
    } finally {
      if (secondaryApp != null) {
        await secondaryApp.delete();
      }
    }
  }

  static String _firstName(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    return parts.isEmpty ? fullName.trim() : parts.first;
  }

  static String _lastName(String fullName) {
    final parts = fullName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
    if (parts.length <= 1) {
      return '';
    }
    return parts.sublist(1).join(' ');
  }
}
