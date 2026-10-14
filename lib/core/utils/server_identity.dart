import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Connection identity, not just the label and endpoint. Never display/log it.
class ServerIdentity {
  static String of(String protocol, String address, int port,
      Map<String, dynamic>? outbound, Map<String, dynamic>? endpoint, String? rawLink) {
    Object? canonical(Object? value) {
      if (value is Map) {
        final entries = value.entries
            .map((entry) => MapEntry(entry.key.toString(), canonical(entry.value)))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
        return {for (final entry in entries) entry.key: entry.value};
      }
      if (value is List) return value.map(canonical).toList();
      return value;
    }

    // A subscription may legitimately contain two nodes with the same label
    // and endpoint but different credentials or transports. Keep the complete
    // parsed connection objects in the identity; the display name is not part
    // of it, so renaming a node does not create a duplicate.
    final connection = <String, dynamic>{
      'outbound': canonical(outbound),
      'endpoint': canonical(endpoint),
      if (outbound == null && endpoint == null) 'raw': rawLink,
    };
    return sha256.convert(utf8.encode(jsonEncode([
      protocol.toLowerCase(), address.toLowerCase(), port, connection,
    ]))).toString();
  }

  /// Explicit subscription notices. A failed ping is NEVER evidence of a notice.
  static bool isNotice(String name, String address, int port) {
    final text = name.toLowerCase().trim();
    final message = RegExp(r'перейдите (в|на)|приложение .*поддержива|обновите приложение|остаток трафика|срок подписки|subscription expired|update your app|traffic remaining|subscription expires').hasMatch(text);
    final placeholder = const ['0.0.0.0', '127.0.0.1', 'localhost', '::', '::1', ''].contains(address.toLowerCase()) || port == 0;
    final link = RegExp(r'^(?:[\s⚠→🌐📱]+)?(?:https?://)?(?:t\.me/\S+|[a-z0-9-]+\.[a-z]{2,}/?)$').hasMatch(text);
    return message || (link && text != address.toLowerCase()) || (placeholder && RegExp(r'трафик|подписк|истек|истёк|бот|сайт|expire|traffic|support|обнов|перейти').hasMatch(text));
  }
}
