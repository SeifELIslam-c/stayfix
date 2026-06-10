import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'app_env.dart';
import 'package:mime/mime.dart';

class VpsUploadedMedia {
  const VpsUploadedMedia({
    required this.fileId,
    required this.url,
    required this.mimeType,
    this.sizeBytes,
    this.width,
    this.height,
    this.durationMs,
    this.kind,
  });

  final String fileId;
  final String url;
  final String mimeType;
  final int? sizeBytes;
  final int? width;
  final int? height;
  final int? durationMs;
  final String? kind;

  factory VpsUploadedMedia.fromJson(Map<String, dynamic> json) {
    return VpsUploadedMedia(
      fileId: (json['fileId'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      mimeType: (json['mimeType'] as String?) ?? 'application/octet-stream',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      kind: json['kind'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fileId': fileId,
      'url': url,
      'mimeType': mimeType,
      'sizeBytes': sizeBytes,
      'width': width,
      'height': height,
      'durationMs': durationMs,
      'kind': kind,
    };
  }
}

class VpsMediaService {
  VpsMediaService._();

  static const String _fallbackBaseUrl = 'https://159.89.98.134:8080';
  static const String _publicFallbackBaseUrl = 'https://159.89.98.134';

  static Future<String> _baseUrl() async {
    final raw = await AppEnv.get(
      'VPS_MEDIA_BASE_URL',
      fallback: _fallbackBaseUrl,
    );
    final normalized =
        raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    _ensureSecureTransport(normalized);
    return normalized;
  }

  static Future<Map<String, String>> _headers() async {
    final headers = <String, String>{};
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final token = await user.getIdToken();
      headers['Authorization'] = 'Bearer $token';
      headers['X-User-Id'] = user.uid;
    }
    return headers;
  }

  static Future<VpsUploadedMedia> uploadFile({
    required File file,
    required String category,
    String? conversationId,
    int? durationMs,
  }) async {
    final mimeType = lookupMimeType(file.path) ??
        _fallbackMimeType(file.path, category: category);
    final baseUrl = await _baseUrl();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/media/upload'),
    );
    request.headers.addAll(await _headers());
    request.fields['category'] = category;
    if (conversationId != null && conversationId.isNotEmpty) {
      request.fields['conversationId'] = conversationId;
    }
    if (durationMs != null) {
      request.fields['durationMs'] = durationMs.toString();
    }
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType.parse(mimeType),
      ),
    );

    final response = await request.send();
    final payload = await response.stream.bytesToString();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('upload failed: ${response.statusCode} $payload');
    }

    final body = jsonDecode(payload) as Map<String, dynamic>;
    final json = body['media'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final normalizedUrl = await normalizeMediaUrl(json['url'] as String?);
    return VpsUploadedMedia.fromJson(<String, dynamic>{
      ...json,
      'url': normalizedUrl,
    });
  }

  static Future<String> normalizeMediaUrl(String? rawUrl) async {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty) return '';

    final baseUrl = await _baseUrl();
    final mediaUri = Uri.tryParse(value);
    final publicUri = Uri.tryParse(baseUrl);
    if (mediaUri == null || publicUri == null) return value;

    if (!mediaUri.hasAuthority || mediaUri.path.isEmpty) {
      return value;
    }

    final normalized = publicUri.replace(
      path: mediaUri.path,
      query: mediaUri.hasQuery ? mediaUri.query : null,
    );
    return normalized.toString();
  }

  static String normalizeMediaUrlSync(String? rawUrl) {
    final value = rawUrl?.trim() ?? '';
    if (value.isEmpty) return '';

    final mediaUri = Uri.tryParse(value);
    final publicUri = Uri.tryParse(_publicFallbackBaseUrl);
    if (mediaUri == null || publicUri == null || !mediaUri.hasAuthority) {
      return value;
    }

    final normalized = publicUri.replace(
      path: mediaUri.path,
      query: mediaUri.hasQuery ? mediaUri.query : null,
    );
    return normalized.toString();
  }

  static String? resolveProfileImageUrl(Map<String, dynamic> data) {
    const candidateKeys = [
      'photoUrl',
      'photoURL',
      'profileImageUrl',
      'profileImage',
      'avatarUrl',
      'avatar',
      'imageUrl',
      'image',
    ];
    for (final key in candidateKeys) {
      final value = (data[key] as String?)?.trim();
      if (value != null && value.isNotEmpty) {
        return normalizeMediaUrlSync(value);
      }
    }
    return null;
  }

  static Future<void> deleteFiles(List<String> fileIds) async {
    final cleaned =
        fileIds.where((id) => id.trim().isNotEmpty).toSet().toList();
    if (cleaned.isEmpty) return;

    final baseUrl = await _baseUrl();
    final response = await http.post(
      Uri.parse('$baseUrl/api/media/delete-many'),
      headers: <String, String>{
        'Content-Type': 'application/json',
        ...await _headers(),
      },
      body: jsonEncode(<String, dynamic>{'fileIds': cleaned}),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('delete failed: ${response.statusCode} ${response.body}');
    }
  }

  static String _fallbackMimeType(
    String path, {
    required String category,
  }) {
    final extension = path.split('.').last.toLowerCase();
    if (category == 'chat-audio') {
      switch (extension) {
        case 'm4a':
        case 'mp4':
          return 'audio/mp4';
        case 'aac':
          return 'audio/aac';
        case 'wav':
          return 'audio/wav';
        case 'mp3':
          return 'audio/mpeg';
      }
      return 'audio/mp4';
    }

    switch (extension) {
      case 'pdf':
        return 'application/pdf';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'doc':
        return 'application/msword';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
      case 'heif':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  static void _ensureSecureTransport(String url) {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme.toLowerCase() == 'https') {
      return;
    }
    throw StateError(
      'StayFix requires an HTTPS media endpoint on iOS App Store builds.',
    );
  }
}
