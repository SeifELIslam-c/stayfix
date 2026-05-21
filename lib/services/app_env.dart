import 'package:flutter/services.dart';

class AppEnv {
  AppEnv._();

  static Map<String, String>? _cache;

  static Future<Map<String, String>> _load() async {
    if (_cache != null) return _cache!;

    final values = <String, String>{};
    try {
      final rawEnv = await rootBundle.loadString('.env');
      for (final line in rawEnv.split(RegExp(r'[\r\n]+'))) {
        final trimmed = line.trim();
        if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
        final separatorIndex =
            trimmed.contains('=') ? trimmed.indexOf('=') : trimmed.indexOf(':');
        if (separatorIndex <= 0) continue;
        final key = trimmed.substring(0, separatorIndex).trim();
        final value = trimmed.substring(separatorIndex + 1).trim();
        if (key.isNotEmpty && value.isNotEmpty) {
          values[key] = value;
        }
      }
    } catch (_) {}

    _cache = values;
    return values;
  }

  static Future<String> get(
    String key, {
    String fallback = '',
  }) async {
    final values = await _load();
    return values[key] ?? fallback;
  }
}
