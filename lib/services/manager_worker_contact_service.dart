import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:hotel_lux_os/services/app_session_service.dart';
import 'package:hotel_lux_os/services/vps_media_service.dart';

class WorkerBlockedException implements Exception {
  const WorkerBlockedException(this.conversationId);

  final String conversationId;
}

class ManagerWorkerConversationHandle {
  const ManagerWorkerConversationHandle({
    required this.conversationId,
    required this.title,
    required this.subtitle,
    required this.avatarBase64,
    required this.avatarUrl,
    required this.isAvailable,
    required this.phone,
    this.openingBanner,
  });

  final String conversationId;
  final String title;
  final String subtitle;
  final String? avatarBase64;
  final String? avatarUrl;
  final bool isAvailable;
  final String? phone;
  final String? openingBanner;
}

class ManagerWorkerContactService {
  ManagerWorkerContactService._();

  static String get _currentUid =>
      FirebaseAuth.instance.currentUser?.uid ??
      AppSessionService.currentUserId;

  static Future<bool> isBlocked({
    required String workerId,
  }) async {
    final uid = _currentUid;
    if (uid.isEmpty) return false;
    final conversation = await _findExistingConversation(
      managerUid: uid,
      workerId: workerId,
    );
    if (conversation == null) return false;
    final blockedBy = ((conversation.data()?['blockedBy'] as List?) ?? const [])
        .map((e) => '$e')
        .toList();
    return blockedBy.contains(uid);
  }

  static Future<void> unblockWorker({
    required String workerId,
  }) async {
    final uid = _currentUid;
    if (uid.isEmpty) return;
    final conversation = await _findExistingConversation(
      managerUid: uid,
      workerId: workerId,
    );
    if (conversation == null) return;
    await conversation.reference.set({
      'blockedBy': FieldValue.arrayRemove([uid]),
    }, SetOptions(merge: true));
  }

  static Future<ManagerWorkerConversationHandle> openConversation({
    required String workerId,
    String? workerName,
    String? workerRole,
    String? workerDepartment,
    String? workerPhotoBase64,
    bool? isWorkerAvailable,
    String? workerPhone,
    bool sendSelectionMessage = false,
  }) async {
    final uid = _currentUid;
    if (uid.isEmpty) {
      throw StateError('User must be signed in to contact a worker.');
    }

    final profileDoc = await FirebaseFirestore.instance
        .collection('profiles')
        .doc(workerId)
        .get();
    final profile = profileDoc.data() ?? const <String, dynamic>{};

    final resolvedName =
        _resolveWorkerName(profile, workerName: workerName).trim();
    final resolvedRole = _resolveWorkerRole(
      profile,
      workerRole: workerRole,
      workerDepartment: workerDepartment,
    ).trim();
    final resolvedPhotoBase64 = _resolveFirstNonEmpty(
        <String?>[workerPhotoBase64, _readPhotoBase64(profile)]);
    final resolvedPhotoUrl = VpsMediaService.resolveProfileImageUrl(profile);
    final resolvedPhone = _resolveFirstNonEmpty(
        <String?>[workerPhone, (profile['phone'] as String?)?.trim()]);
    final resolvedAvailable = isWorkerAvailable ??
        profile['isAvailable'] == true || profile['availableNow'] == true;
    final managerIdentity = await _loadManagerIdentity(uid);

    final conversationRef = await _findOrCreateConversation(
      managerUid: uid,
      workerId: workerId,
      title: resolvedName.isNotEmpty ? resolvedName : 'Intervenant',
      subtitle: resolvedRole,
    );

    final blockedBy =
        ((await conversationRef.get()).data()?['blockedBy'] as List? ??
                const [])
            .map((e) => '$e')
            .toList();
    if (blockedBy.contains(uid)) {
      throw WorkerBlockedException(conversationRef.id);
    }

    final selectionBanner = sendSelectionMessage
        ? (resolvedRole.isNotEmpty
            ? 'Vous avez choisi cet intervenant pour le role de $resolvedRole.'
            : 'Vous avez choisi cet intervenant pour votre demande.')
        : null;

    await conversationRef.set({
      'title': resolvedName.isNotEmpty ? resolvedName : 'Intervenant',
      'subtitle': resolvedRole,
      'photoUrl': resolvedPhotoUrl,
      'workerId': workerId,
      'managerId': uid,
      'workerDisplayName':
          resolvedName.isNotEmpty ? resolvedName : 'Intervenant',
      'workerSubtitle': resolvedRole,
      'managerDisplayName': managerIdentity.displayName,
      'managerSubtitle': managerIdentity.subtitle,
      'managerPhotoUrl': managerIdentity.photoUrl,
      'managerPhotoBase64': managerIdentity.photoBase64,
      'type': 'intervenant',
      'isActive': true,
      if (selectionBanner != null) 'systemBannerText': selectionBanner,
      if (selectionBanner != null)
        'systemBannerAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    return ManagerWorkerConversationHandle(
      conversationId: conversationRef.id,
      title: resolvedName.isNotEmpty ? resolvedName : 'Intervenant',
      subtitle: resolvedRole,
      avatarBase64: resolvedPhotoBase64,
      avatarUrl: resolvedPhotoUrl,
      isAvailable: resolvedAvailable,
      phone: resolvedPhone,
      openingBanner: selectionBanner,
    );
  }

  static Future<DocumentReference<Map<String, dynamic>>>
      _findOrCreateConversation({
    required String managerUid,
    required String workerId,
    required String title,
    required String subtitle,
  }) async {
    final query = await FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: managerUid)
        .get();

    for (final doc in query.docs) {
      final data = doc.data();
      final participants =
          (data['participants'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => value.toString())
              .toList();
      final type = (data['type'] as String?)?.trim() ?? '';
      final storedWorkerId = (data['workerId'] as String?)?.trim() ?? '';
      if (type == 'intervenant' &&
          participants.contains(workerId) &&
          (storedWorkerId.isEmpty || storedWorkerId == workerId)) {
        return doc.reference;
      }
    }

    return FirebaseFirestore.instance.collection('conversations').add({
      'type': 'intervenant',
      'title': title,
      'subtitle': subtitle,
      'participants': <String>[managerUid, workerId],
      'workerId': workerId,
      'managerId': managerUid,
      'workerDisplayName': title,
      'workerSubtitle': subtitle,
      'lastMessage': '',
      'lastMessageAt': FieldValue.serverTimestamp(),
      'unreadBy': <String, int>{managerUid: 0, workerId: 0},
      'lastReadAt': <String, dynamic>{
        managerUid: FieldValue.serverTimestamp(),
        workerId: FieldValue.serverTimestamp(),
      },
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': managerUid,
      'isActive': true,
      'blockedBy': <String>[],
    });
  }

  static Future<DocumentSnapshot<Map<String, dynamic>>?>
      _findExistingConversation({
    required String managerUid,
    required String workerId,
  }) async {
    final query = await FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: managerUid)
        .get();

    for (final doc in query.docs) {
      final data = doc.data();
      final participants =
          (data['participants'] as List<dynamic>? ?? const <dynamic>[])
              .map((value) => value.toString())
              .toList();
      final type = (data['type'] as String?)?.trim() ?? '';
      final storedWorkerId = (data['workerId'] as String?)?.trim() ?? '';
      if (type == 'intervenant' &&
          participants.contains(workerId) &&
          (storedWorkerId.isEmpty || storedWorkerId == workerId)) {
        return doc;
      }
    }
    return null;
  }

  static Future<_ManagerIdentity> _loadManagerIdentity(
      String managerUid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(managerUid)
          .get();
      final data = doc.data() ?? const <String, dynamic>{};
      final displayName = _resolveFirstNonEmpty(<String?>[
        _joinName(
          (data['firstName'] as String?)?.trim(),
          (data['lastName'] as String?)?.trim(),
        ),
        (data['displayName'] as String?)?.trim(),
        (data['fullName'] as String?)?.trim(),
        (data['username'] as String?)?.trim(),
        _emailHandle((data['email'] as String?)?.trim()),
      ]);
      final subtitle = _resolveFirstNonEmpty(<String?>[
        (data['directorType'] as String?)?.trim(),
        (data['roleLabel'] as String?)?.trim(),
        (data['role'] as String?)?.trim(),
        'Manager',
      ]);
      return _ManagerIdentity(
        displayName: (displayName != null && displayName.isNotEmpty)
            ? displayName
            : 'Manager',
        subtitle:
            (subtitle != null && subtitle.isNotEmpty) ? subtitle : 'Manager',
        photoUrl: VpsMediaService.resolveProfileImageUrl(data),
        photoBase64: _readPhotoBase64(data),
      );
    } catch (_) {
      return const _ManagerIdentity(
        displayName: 'Manager',
        subtitle: 'Manager',
      );
    }
  }

  static String _joinName(String? firstName, String? lastName) {
    return <String>[firstName ?? '', lastName ?? '']
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' ')
        .trim();
  }

  static String? _emailHandle(String? email) {
    final value = email?.trim() ?? '';
    if (value.isEmpty) return null;
    return value.split('@').first.trim();
  }

  static String _resolveWorkerName(
    Map<String, dynamic> profile, {
    String? workerName,
  }) {
    final provided = workerName?.trim() ?? '';
    if (provided.isNotEmpty) return provided;

    for (final key in <String>[
      'username',
      'fullName',
      'displayName',
      'firstName',
    ]) {
      final value = (profile[key] as String?)?.trim() ?? '';
      if (value.isNotEmpty) return value;
    }

    final firstName = (profile['firstName'] as String?)?.trim() ?? '';
    final lastName = (profile['lastName'] as String?)?.trim() ?? '';
    final combined = '$firstName $lastName'.trim();
    if (combined.isNotEmpty) return combined;

    final email = (profile['email'] as String?)?.trim() ?? '';
    if (email.isNotEmpty) return email.split('@').first;
    return 'Intervenant';
  }

  static bool _isQualifiedLaborDepartment(String? department) {
    final normalized = (department ?? '')
        .toLowerCase()
        .replaceAll('œ', 'oe')
        .replaceAll('é', 'e')
        .replaceAll('è', 'e')
        .replaceAll('ê', 'e')
        .replaceAll(RegExp(r'[^a-z]'), '');
    return normalized.contains('maindoeuvrequalifiee') ||
        normalized.contains('mainoeuvrequalifiee');
  }

  static String _resolveWorkerRole(
    Map<String, dynamic> profile, {
    String? workerRole,
    String? workerDepartment,
  }) {
    final role = _resolveFirstNonEmpty(<String?>[
      workerRole,
      (profile['role'] as String?)?.trim(),
      (profile['jobTitle'] as String?)?.trim(),
      (profile['maintenanceType'] as String?)?.trim(),
    ]);
    final department = _resolveFirstNonEmpty(<String?>[
      workerDepartment,
      (profile['department'] as String?)?.trim(),
    ]);

    if (_isQualifiedLaborDepartment(department)) {
      // Show specialty directly — never prefix with the department label
      String? specialty = _resolveFirstNonEmpty(<String?>[
        (profile['specialty'] as String?)?.trim(),
        (profile['speciality'] as String?)?.trim(),
      ]);
      if (specialty == null) {
        final list = profile['specialties'];
        if (list is List) {
          for (final item in list) {
            final v = item?.toString().trim() ?? '';
            if (v.isNotEmpty) {
              specialty = v;
              break;
            }
          }
        }
      }
      final candidate = specialty ?? role;
      if (candidate != null && !_isQualifiedLaborDepartment(candidate)) {
        return candidate;
      }
      return role ?? department ?? '';
    }

    if (role != null && department != null && role != department) {
      return '$department - $role';
    }
    return role ?? department ?? '';
  }

  static String? _readPhotoBase64(Map<String, dynamic> profile) {
    for (final key in <String>[
      'photoBase64',
      'profilePhotoBase64',
      'imageBase64',
      'avatarBase64',
    ]) {
      final value = (profile[key] as String?)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  static String? _resolveFirstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}

class _ManagerIdentity {
  const _ManagerIdentity({
    required this.displayName,
    required this.subtitle,
    this.photoUrl,
    this.photoBase64,
  });

  final String displayName;
  final String subtitle;
  final String? photoUrl;
  final String? photoBase64;
}
