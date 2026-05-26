import 'package:flutter/material.dart';
import 'package:hotel_lux_os/screens/condo_dashboard_screen.dart';

class ImmeubleDashboardScreen extends StatelessWidget {
  const ImmeubleDashboardScreen({
    super.key,
    required this.propertyType,
    this.accessRole,
  });

  final String propertyType;
  final String? accessRole;

  @override
  Widget build(BuildContext context) {
    return CondoDashboardScreen(
      propertyType: propertyType,
      accessRole: accessRole,
    );
  }
}
