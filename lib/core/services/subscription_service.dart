import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../constants/app_constants.dart';
import '../models/subscription_model.dart';
import '../utils/base64_utils.dart';
import '../utils/link_parser.dart';

class SubscriptionFetch {
  SubscriptionFetch({
    required this.servers,
    this.title,
    this.uploadBytes,
    this.downloadBytes,
    this.totalBytes,
    this.expireAt,
    this.intervalMinutes,
    this.warnings = const [],
  });

  final List<ServerDraft> servers;
  final String? title;
  final int? uploadBytes;
  final int? downloadBytes;
  final int? totalBytes;
  final DateTime? expireAt;
  final int? intervalMinutes;
  final List<String> warnings;
}

class SubscriptionService {
  SubscriptionService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  Future<SubscriptionFetch> fetch(
    SubscriptionModel subscription, {
    String? userAgent,
  }) async {
    final device = await DeviceIdentity.load();
    final response = await _dio.get<String>(
      subscription.url,
      options: Options(
        responseType: ResponseType.plain,
        headers: {
          'User-Agent':
              subscription.userAgent ?? userAgent ?? AppConstants.userAgent,
          'Accept': '*/*',
          // Remnawave/Marzban panels with device limits refuse clients that
          // do not identify themselves ("Включите передачу HWID"). The id is
          // a random UUID generated once per install — nothing personal.
          'x-hwid': device.hwid,
          'x-device-os': device.os,
          'x-ver-os': device.osVersion,
          'x-device-model': device.model,
        },
        validateStatus: (code) => code != null && code < 500,
      ),
    );
    if (response.statusCode != null && response.statusCode! >= 400) {
      throw SubscriptionException('HTTP ${response.statusCode}');
    }
    final body = response.data ?? '';
    final parsed = LinkParser.parseSubscriptionBody(body);
    if (parsed.servers.isEmpty) {
      throw SubscriptionException(
        parsed.warnings.isEmpty ? 'empty-subscription' : parsed.warnings.first,
      );
    }
    final headers = response.headers.map.map(
      (key, value) => MapEntry(key.toLowerCase(), value.join(',')),
    );
    return SubscriptionFetch(
      servers: parsed.servers,
      title: _profileTitle(headers),
      uploadBytes: _userInfo(headers, 'upload'),
      downloadBytes: _userInfo(headers, 'download'),
      totalBytes: _userInfo(headers, 'total'),
      expireAt: _expire(headers),
      intervalMinutes: int.tryParse(headers['profile-update-interval'] ?? ''),
      warnings: parsed.warnings,
    );
  }

  String? _profileTitle(Map<String, String> headers) {
    final raw = headers['profile-title'] ?? headers['content-disposition'];
    if (raw == null || raw.isEmpty) return null;
    if (raw.toLowerCase().contains('filename=')) {
      final match = RegExp(r'filename="?([^";]+)"?').firstMatch(raw);
      return match?.group(1);
    }
    return Base64Utils.decodeHeaderValue(raw);
  }

  int? _userInfo(Map<String, String> headers, String key) {
    final raw = headers['subscription-userinfo'];
    if (raw == null) return null;
    final match = RegExp('$key=(\\d+)').firstMatch(raw);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  DateTime? _expire(Map<String, String> headers) {
    final seconds = _userInfo(headers, 'expire');
    if (seconds == null || seconds <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
  }
}

class SubscriptionException implements Exception {
  SubscriptionException(this.message);
  final String message;
  @override
  String toString() => message;
}


/// Anonymous per-install identity sent to subscription panels that enforce
/// device limits. Created once, stored locally, never sent anywhere else.
class DeviceIdentity {
  DeviceIdentity._(this.hwid, this.os, this.osVersion, this.model);

  final String hwid;
  final String os;
  final String osVersion;
  final String model;

  static DeviceIdentity? _cached;

  static Future<DeviceIdentity> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    var hwid = prefs.getString('device_hwid');
    if (hwid == null || hwid.isEmpty) {
      hwid = const Uuid().v4();
      await prefs.setString('device_hwid', hwid);
    }
    final os = Platform.isAndroid
        ? 'Android'
        : Platform.isIOS
            ? 'iOS'
            : Platform.isWindows
                ? 'Windows'
                : Platform.isMacOS
                    ? 'macOS'
                    : 'Linux';
    final version = Platform.operatingSystemVersion.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
    final identity = DeviceIdentity._(hwid, os, version.isEmpty ? os : version, 'Nukefy VPN ${AppConstants.version}');
    _cached = identity;
    return identity;
  }
}
