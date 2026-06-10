import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'auth_screen.dart';
import 'condo_dashboard_screen.dart';
import 'director_type_screen.dart';
import 'immeuble_dashboard.dart';
import 'manager_profile_config.dart';
import 'other_property_dashboard.dart';
import 'terms_screen.dart';
import '../services/app_session_service.dart';
import '../services/property_scope_service.dart';

Future<Widget> resolveManagerDestination() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return const DirectorTypeScreen();
  }

  return resolveSessionDestination(user.uid);
}

Future<Widget> resolveSessionDestination(String userId) async {
  if (userId.trim().isEmpty) {
    return const DirectorTypeScreen();
  }

  final doc =
      await FirebaseFirestore.instance.collection('users').doc(userId).get();
  final data = doc.data();
  if (data == null) {
    return const DirectorTypeScreen();
  }
  AppSessionService.setCurrentUser(userId: userId, data: data);
  if (PropertyScopeService.isStayFixJobOnly(data) ||
      PropertyScopeService.isDisabled(data)) {
    return const AuthScreen();
  }
  final bool acceptedTerms = data['termsAccepted'] == true;
  if (!acceptedTerms) {
    return const TermsScreen();
  }
  final String? profileValue = resolveManagerProfileValue(data);

  final accountType = (data['accountType'] as String?)?.trim().toLowerCase();
  if (accountType == 'apartment_account' || accountType == 'apartment_manager') {
    return CondoDashboardScreen(
      propertyType: 'apartment_condo_owner',
      accessRole: accountType,
    );
  }
  if (accountType == 'manager' || accountType == 'concierge') {
    return ImmeubleDashboardScreen(
      propertyType: 'building_manager',
      accessRole: accountType,
    );
  }

  if (profileValue == null) {
    return const DirectorTypeScreen();
  }

  if (profileValue == 'apartment_condo_owner' ||
      profileValue == 'villa_owner') {
    return CondoDashboardScreen(propertyType: profileValue);
  }

  if (profileValue == 'building_manager' || profileValue == 'rental_building') {
    return ImmeubleDashboardScreen(propertyType: profileValue);
  }

  final label = resolveManagerProfileLabel(data, profileValue);
  return OtherPropertyDashboard(propertyType: label);
}
