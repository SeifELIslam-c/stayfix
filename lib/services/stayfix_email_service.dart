import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'app_env.dart';

class StayfixEmailService {
  StayfixEmailService._();

  static const String _webAppUrlFallback =
      'https://script.google.com/macros/s/AKfycbwNi9a1j-TLmNZexdMcRRT0Rtg7TnYUi4qirLFmwhCpQ2VkHPH2ZNtPxbyEdtUHXcEulA/exec';
  static const Duration _timeout = Duration(seconds: 15);

  static Future<StayfixEmailResult> sendApartmentCreatedEmail({
    required String to,
    required String recipientName,
    required String apartmentName,
    required String loginEmail,
    required String temporaryPassword,
  }) {
    return _send(
      type: 'apartment_created',
      to: to,
      recipientName: recipientName,
      apartmentName: apartmentName,
      loginEmail: loginEmail,
      temporaryPassword: temporaryPassword,
    );
  }

  static Future<StayfixEmailResult> sendManagerCreatedEmail({
    required String to,
    required String recipientName,
    required String apartmentName,
    required String loginEmail,
    required String temporaryPassword,
  }) {
    return _send(
      type: 'manager_created',
      to: to,
      recipientName: recipientName,
      apartmentName: apartmentName,
      loginEmail: loginEmail,
      temporaryPassword: temporaryPassword,
    );
  }

  static Future<StayfixEmailResult> sendConciergeCreatedEmail({
    required String to,
    required String recipientName,
    required String apartmentName,
    required String loginEmail,
    required String temporaryPassword,
  }) {
    return _send(
      type: 'concierge_created',
      to: to,
      recipientName: recipientName,
      apartmentName: apartmentName,
      loginEmail: loginEmail,
      temporaryPassword: temporaryPassword,
    );
  }

  static Future<StayfixEmailResult> _send({
    required String type,
    required String to,
    required String recipientName,
    required String apartmentName,
    required String loginEmail,
    required String temporaryPassword,
  }) async {
    final webAppUrl = await AppEnv.get(
      'STAYFIX_EMAIL_WEB_APP_URL',
      fallback: _webAppUrlFallback,
    );
    final secret = await AppEnv.get('STAYFIX_EMAIL_SECRET');
    if (secret.trim().isEmpty) {
      return const StayfixEmailResult.failure(
        'STAYFIX_EMAIL_SECRET is missing.',
      );
    }

    final uri = Uri.tryParse(webAppUrl.trim());
    if (uri == null) {
      return const StayfixEmailResult.failure(
        'Invalid StayFix email service URL.',
      );
    }

    try {
      final payload = <String, dynamic>{
        'secret': secret,
        'STAYFIX_EMAIL_SECRET': secret,
        'type': type,
        'to': to,
        'recipientName': recipientName,
        'apartmentName': apartmentName,
        'loginEmail': loginEmail,
        'temporaryPassword': temporaryPassword,
      };
      final client = http.Client();
      try {
        final request = http.Request('POST', uri)
          ..followRedirects = false
          ..headers.addAll(const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          })
          ..body = jsonEncode(payload);

        final streamedResponse = await client.send(request).timeout(_timeout);
        final response = await _resolveResponse(
          client: client,
          response: streamedResponse,
        );
        final result = _parseResponse(response);
        if (!result.success) {
          debugPrint(
            'StayfixEmailService failure [$type]: ${result.message}',
          );
        }
        return result;
      } finally {
        client.close();
      }
    } on TimeoutException {
      return const StayfixEmailResult.failure('Email request timed out.');
    } on SocketException {
      return const StayfixEmailResult.failure('No internet connection.');
    } on http.ClientException catch (error) {
      return StayfixEmailResult.failure(error.message);
    } catch (error) {
      return StayfixEmailResult.failure(error.toString());
    }
  }

  static Future<http.Response> _resolveResponse({
    required http.Client client,
    required http.StreamedResponse response,
  }) async {
    if (!_isRedirect(response.statusCode)) {
      return http.Response.fromStream(response);
    }

    final locationHeader = response.headers['location']?.trim() ?? '';
    if (locationHeader.isEmpty) {
      return http.Response.fromStream(response);
    }

    final redirectedUri = Uri.tryParse(locationHeader);
    if (redirectedUri == null) {
      return http.Response.fromStream(response);
    }

    final redirectedResponse = await client.get(
      redirectedUri,
      headers: const <String, String>{
        'Accept': 'application/json',
      },
    ).timeout(_timeout);
    return redirectedResponse;
  }

  static StayfixEmailResult _parseResponse(http.Response response) {
    if (response.statusCode != 200) {
      return StayfixEmailResult.failure(
        'Unexpected HTTP ${response.statusCode}.',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      return StayfixEmailResult.failure(
        'Invalid JSON response: ${response.body}',
      );
    }

    if (decoded is! Map<String, dynamic>) {
      return const StayfixEmailResult.failure('Invalid JSON payload.');
    }

    final success = decoded['success'] == true;
    final message = (decoded['message'] as String?)?.trim().isNotEmpty == true
        ? (decoded['message'] as String).trim()
        : (success ? 'Email sent successfully.' : 'Email sending failed.');

    if (!success) {
      final error = (decoded['error'] as String?)?.trim();
      final fullMessage =
          error != null && error.isNotEmpty ? '$message ($error)' : message;
      return StayfixEmailResult.failure(fullMessage);
    }

    return StayfixEmailResult.success(message);
  }

  static bool _isRedirect(int statusCode) =>
      statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}

class StayfixEmailResult {
  const StayfixEmailResult._({
    required this.success,
    required this.message,
  });

  const StayfixEmailResult.success(String message)
      : this._(success: true, message: message);

  const StayfixEmailResult.failure(String message)
      : this._(success: false, message: message);

  final bool success;
  final String message;
}
