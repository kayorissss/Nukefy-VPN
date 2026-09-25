import 'dart:convert';

class Base64Utils {
  static String? tryDecodeUtf8(String input) {
    final compact = input.trim().replaceAll(RegExp(r'\s+'), '');
    if (compact.length < 8) return null;
    if (!RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(compact)) return null;
    var normalized = compact.replaceAll('-', '+').replaceAll('_', '/');
    final pad = normalized.length % 4;
    if (pad != 0) normalized += '=' * (4 - pad);
    try {
      final bytes = base64.decode(normalized);
      if (bytes.isEmpty) return null;
      final text = utf8.decode(bytes, allowMalformed: true);
      if (text.contains('\u0000')) return null;
      final printable = text.runes
          .where((r) => r == 10 || r == 13 || r == 9 || (r >= 32 && r != 127))
          .length;
      if (printable / text.runes.length < 0.9) return null;
      return text;
    } catch (_) {
      return null;
    }
  }

  static String encodeUtf8(String value) => base64.encode(utf8.encode(value));

  static String decodeHeaderValue(String raw) {
    final value = raw.trim();
    if (value.toLowerCase().startsWith('base64:')) {
      return tryDecodeUtf8(value.substring(7)) ?? value.substring(7);
    }
    return value;
  }
}
