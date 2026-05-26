import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

class InviteEmailService {
  InviteEmailService._();

  static Future<void> sendAccountInvite({
    required String email,
    required String fullName,
    required String username,
    required String password,
    required String accountType,
    required List<String> propertyNames,
  }) async {
    final payload = <String, dynamic>{
      'email': email,
      'fullName': fullName,
      'username': username,
      'password': password,
      'accountType': accountType,
      'propertyNames': propertyNames,
      'sentAt': FieldValue.serverTimestamp(),
      'status': 'queued',
    };

    final queueRef = await FirebaseFirestore.instance
        .collection('outbound_emails')
        .add(payload);

    final config = await FirebaseFirestore.instance
        .collection('app_config')
        .doc('email')
        .get();
    final data = config.data() ?? const <String, dynamic>{};
    final webhookUrl = (data['inviteWebhookUrl'] as String?)?.trim() ?? '';
    final webhookToken = (data['inviteWebhookToken'] as String?)?.trim() ?? '';

    if (webhookUrl.isEmpty) return;

    try {
      await http.post(
        Uri.parse(webhookUrl),
        headers: <String, String>{
          'Content-Type': 'application/json',
          if (webhookToken.isNotEmpty) 'Authorization': 'Bearer $webhookToken',
        },
        body: jsonEncode(<String, dynamic>{
          'queueDocId': queueRef.id,
          'email': email,
          'fullName': fullName,
          'username': username,
          'password': password,
          'accountType': accountType,
          'propertyNames': propertyNames,
        }),
      );
    } catch (_) {
      // Firestore queue remains available for retry by a backend worker.
    }
  }
}
