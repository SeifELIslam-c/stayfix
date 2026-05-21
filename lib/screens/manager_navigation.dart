import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:hotel_lux_os/screens/condo_dashboard_screen.dart';
import 'package:hotel_lux_os/screens/director_type_screen.dart';
import 'package:hotel_lux_os/screens/manager_profile_config.dart';
import 'package:hotel_lux_os/screens/other_property_dashboard.dart';
import 'package:hotel_lux_os/screens/terms_screen.dart';

Future<Widget> resolveManagerDestination() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    return const DirectorTypeScreen();
  }

  final doc =
      await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
  final data = doc.data();
  final bool acceptedTerms = data?['termsAccepted'] == true;
  if (!acceptedTerms) {
    return const TermsScreen();
  }
  final String? profileValue = resolveManagerProfileValue(data);

  if (profileValue == null) {
    return const DirectorTypeScreen();
  }

  if (profileValue == 'apartment_condo_owner') {
    return const CondoDashboardScreen();
  }

  final label = resolveManagerProfileLabel(data, profileValue);
  return OtherPropertyDashboard(propertyType: label);
}
