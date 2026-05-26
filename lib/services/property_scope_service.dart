class PropertyScopeService {
  PropertyScopeService._();

  static String normalizeAccountType(Map<String, dynamic> data) =>
      (data['accountType'] as String?)?.trim().toLowerCase() ?? '';

  static String? normalizeAppAccess(Map<String, dynamic> data) {
    final value = (data['appAccess'] as String?)?.trim().toLowerCase();
    return value == null || value.isEmpty ? null : value;
  }

  static bool isBuildingScopedAccountType(String? value) {
    final accountType = (value ?? '').trim().toLowerCase();
    return accountType == 'manager' || accountType == 'concierge';
  }

  static bool isApartmentScopedAccountType(String? value) {
    final accountType = (value ?? '').trim().toLowerCase();
    return accountType == 'apartment_account' ||
        accountType == 'apartment_manager';
  }

  static bool isStayFixJobOnly(Map<String, dynamic> data) =>
      normalizeAppAccess(data) == 'stayfix_job';

  static bool isDisabled(Map<String, dynamic> data) {
    final status = (data['status'] as String?)?.trim().toLowerCase() ?? '';
    return status == 'deleted' || status == 'disabled' || status == 'archived';
  }

  static List<String> scopedPropertyIds(Map<String, dynamic> data) {
    final ids = <String>{};

    void addValue(dynamic value) {
      final normalized = '$value'.trim();
      if (normalized.isNotEmpty &&
          normalized.toLowerCase() != 'null' &&
          normalized.toLowerCase() != 'none') {
        ids.add(normalized);
      }
    }

    final propertyIds = data['propertyIds'];
    if (propertyIds is List) {
      for (final value in propertyIds) {
        addValue(value);
      }
    }

    for (final key in const [
      'apartmentId',
      'propertyId',
      'accountPropertyId',
      'managedPropertyId',
      'hotelId',
    ]) {
      addValue(data[key]);
    }

    return ids.toList(growable: false);
  }
}
