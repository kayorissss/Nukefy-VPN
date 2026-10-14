import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

enum NetworkFailureKind {
  timeout,
  tls,
  unavailable,
  server,
  other,
}

/// Classifies transport failures without weakening certificate validation.
///
/// Dio wraps the useful exception several times (for example, a
/// HandshakeException inside a connectionError), so classification walks the
/// nested error and its message. The UI can then explain the likely local
/// cause instead of exposing an implementation-specific stack trace.
class NetworkDiagnostics {
  NetworkDiagnostics._();

  static NetworkFailureKind classify(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.transformTimeout:
          return NetworkFailureKind.timeout;
        case DioExceptionType.badCertificate:
          return NetworkFailureKind.tls;
        case DioExceptionType.badResponse:
          final status = error.response?.statusCode ?? 0;
          if (status >= 400) return NetworkFailureKind.server;
          break;
        case DioExceptionType.cancel:
        case DioExceptionType.connectionError:
        case DioExceptionType.unknown:
          break;
      }
      final nested = error.error;
      if (nested != null && !identical(nested, error)) {
        final result = classify(nested);
        if (result != NetworkFailureKind.other) return result;
      }
      return classifyText('${error.message ?? ''} ${error.error ?? ''}');
    }
    if (error is HandshakeException) return NetworkFailureKind.tls;
    if (error is CertificateException) return NetworkFailureKind.tls;
    if (error is TimeoutException) return NetworkFailureKind.timeout;
    if (error is SocketException) return NetworkFailureKind.unavailable;
    if (error is HttpException) return classifyText(error.message);
    return classifyText('$error');
  }

  static NetworkFailureKind classifyText(String value) {
    final text = value.toLowerCase();
    if (text.contains('certificate_verify_failed') ||
        text.contains('unable to get local issuer') ||
        text.contains('handshakeexception') ||
        text.contains('handshake exception') ||
        text.contains('bad certificate') ||
        text.contains('self signed certificate') ||
        text.contains('certificate chain') ||
        text.contains('tls')) {
      return NetworkFailureKind.tls;
    }
    if (text.contains('timeout') || text.contains('timed out') || text.contains('deadline exceeded')) {
      return NetworkFailureKind.timeout;
    }
    if (text.contains('failed host lookup') ||
        text.contains('connection refused') ||
        text.contains('connection reset') ||
        text.contains('network is unreachable') ||
        text.contains('no route to host') ||
        text.contains('socketexception')) {
      return NetworkFailureKind.unavailable;
    }
    if (RegExp(r'\b5\d\d\b').hasMatch(text)) return NetworkFailureKind.server;
    return NetworkFailureKind.other;
  }

  static bool isNetworkError(Object error) => classify(error) != NetworkFailureKind.other;

  /// Returns a localized explanation for a network failure, or the original
  /// text for validation/application errors that should remain specific.
  static String textOrRaw(Object error, String Function(String key) translate) {
    final kind = classify(error);
    if (kind == NetworkFailureKind.other) return '$error';
    return translate(switch (kind) {
      NetworkFailureKind.timeout => 'networkTimeout',
      NetworkFailureKind.tls => 'networkTls',
      NetworkFailureKind.unavailable => 'networkUnavailable',
      NetworkFailureKind.server => 'networkServer',
      NetworkFailureKind.other => 'networkError',
    });
  }
}
