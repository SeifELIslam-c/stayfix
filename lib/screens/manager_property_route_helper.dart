import 'package:flutter/material.dart';
import 'package:stayfix/screens/condo_dashboard_screen.dart';
import 'package:stayfix/screens/condu_profile_screen.dart';
import 'package:stayfix/screens/immeuble_dashboard.dart';
import 'package:stayfix/screens/immeuble_profile_screen.dart';
import 'package:stayfix/screens/villa_profile_screen.dart';
import 'package:stayfix/services/app_session_service.dart';
import 'package:stayfix/services/property_scope_service.dart';

String resolveCurrentManagerPropertyType() {
  final data = AppSessionService.currentUserData;
  final accountType = (data['accountType'] as String?)?.trim().toLowerCase();
  if (PropertyScopeService.isApartmentScopedAccountType(accountType)) {
    return 'apartment_condo_owner';
  }
  if (accountType == 'manager' || accountType == 'concierge') {
    return 'building_manager';
  }
  return (data['propertyProfileType'] as String?)?.trim().isNotEmpty == true
      ? (data['propertyProfileType'] as String).trim()
      : 'apartment_condo_owner';
}

String? resolveCurrentManagerAccessRole() {
  final value =
      (AppSessionService.currentUserData['accountType'] as String?)?.trim();
  return value?.isEmpty == true ? null : value;
}

bool isBuildingPropertyType(String? propertyType) {
  final normalized = (propertyType ?? '').trim().toLowerCase();
  return normalized == 'building_manager' || normalized == 'rental_building';
}

Widget buildManagerHomeScreen({
  String? propertyType,
  String? accessRole,
}) {
  final resolvedType = (propertyType ?? resolveCurrentManagerPropertyType())
      .trim()
      .toLowerCase();
  if (isBuildingPropertyType(resolvedType)) {
    return ImmeubleDashboardScreen(
      propertyType: resolvedType,
      accessRole: accessRole ?? resolveCurrentManagerAccessRole(),
    );
  }
  return CondoDashboardScreen(
    propertyType: resolvedType,
    accessRole: accessRole ?? resolveCurrentManagerAccessRole(),
  );
}

Widget buildManagerProfileScreen({
  String? propertyType,
}) {
  final resolvedType = (propertyType ?? resolveCurrentManagerPropertyType())
      .trim()
      .toLowerCase();
  if (resolvedType == 'villa_owner') {
    return const VillaProfileScreen();
  }
  if (isBuildingPropertyType(resolvedType)) {
    return ImmeubleProfileScreen(propertyType: resolvedType);
  }
  return const ConduProfileScreen();
}
