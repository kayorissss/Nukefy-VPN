import 'package:flutter_test/flutter_test.dart';
import 'package:nukefy_vpn/core/utils/network_diagnostics.dart';

void main() {
  test('TLS failures stay distinct from generic network failures', () {
    expect(
      NetworkDiagnostics.classifyText('CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate'),
      NetworkFailureKind.tls,
    );
    expect(NetworkDiagnostics.classifyText('Connection timed out after 12 seconds'), NetworkFailureKind.timeout);
    expect(NetworkDiagnostics.classifyText('Failed host lookup: api.github.com'), NetworkFailureKind.unavailable);
    expect(NetworkDiagnostics.classifyText('HTTP 503'), NetworkFailureKind.server);
  });

  test('application errors are not swallowed by the network mapper', () {
    expect(NetworkDiagnostics.isNetworkError(StateError('invalid game ID')), isFalse);
    expect(
      NetworkDiagnostics.textOrRaw(StateError('invalid game ID'), (key) => 'translated:$key'),
      'Bad state: invalid game ID',
    );
  });
}
