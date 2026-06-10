import 'package:flutter/material.dart';
import 'condo_dashboard_screen.dart';

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
