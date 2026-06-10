import 'property_scope_service.dart';

class AppSessionService {
  AppSessionService._();

  static String? _currentUserId;
  static Map<String, dynamic>? _currentUserData;

  static String get currentUserId => _currentUserId?.trim() ?? '';

  static Map<String, dynamic> get currentUserData =>
      _currentUserData ?? const <String, dynamic>{};

  static String get currentRole =>
      (currentUserData['role'] as String?)?.trim() ?? '';

  static String? get propertyProfileType =>
      (currentUserData['propertyProfileType'] as String?)?.trim();

  static String? get accountType =>
      (currentUserData['accountType'] as String?)?.trim();

  static String? get appAccess =>
      (currentUserData['appAccess'] as String?)?.trim();

  static List<String> get propertyIds {
    final raw = currentUserData['propertyIds'];
    if (raw is! List) return const <String>[];
    return raw
        .map((value) => '$value')
        .where((value) => value.trim().isNotEmpty)
        .toList(growable: false);
  }

  static bool get hasCondoAccess {
    final role = currentRole.toLowerCase();
    final profile = (propertyProfileType ?? '').toLowerCase();
    final account = (accountType ?? '').toLowerCase();
    return profile == 'apartment_condo_owner' ||
        profile == 'villa_owner' ||
        profile == 'building_manager' ||
        profile == 'rental_building' ||
        account == 'apartment_account' ||
        account == 'apartment_manager' ||
        account == 'manager' ||
        account == 'concierge' ||
        role.contains('gestionnaire') ||
        role.contains('concierge');
  }

  static bool get isStayFixJobOnly =>
      PropertyScopeService.isStayFixJobOnly(currentUserData);

  static void setCurrentUser({
    required String userId,
    required Map<String, dynamic> data,
  }) {
    _currentUserId = userId.trim();
    _currentUserData = Map<String, dynamic>.from(data);
  }

  static void clear() {
    _currentUserId = null;
    _currentUserData = null;
  }
}
