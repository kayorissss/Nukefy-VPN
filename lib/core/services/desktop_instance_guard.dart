import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Keeps desktop launches single-instance while still allowing a tray/taskbar
/// launch to bring the existing window to the foreground.
///
/// A loopback socket is used instead of a lock file because a lock alone can
/// only reject the second launch; it cannot recover the already running
/// window. The protocol is deliberately tiny and accepts only the local
/// `NUKEFY_SHOW` command.
class DesktopInstanceGuard {
  DesktopInstanceGuard({this.port = 45837});

  /// The active guard is used by the controlled restart hand-off. Closing the
  /// listener before spawning the replacement lets the new process acquire
  /// the port instead of racing the old Flutter engine during shutdown.
  static DesktopInstanceGuard? active;

  final int port;
  ServerSocket? _server;
  Future<void> Function()? _onShow;

  /// Returns true when this process owns the instance. Returns false only
  /// after a running instance positively acknowledges the show request.
  Future<bool> acquire({required Future<void> Function() onShow}) async {
    if (_server != null) return true;
    _onShow = onShow;
    try {
      _server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      _server!.listen(_handleClient, onError: (_) {});
      active = this;
      return true;
    } on SocketException {
      final delivered = await _notifyExisting();
      if (delivered) return false;
      // A stale listener or an unrelated process occupying the port must not
      // make Nukefy silently exit. Let the current process continue normally.
      return true;
    }
  }

  Future<bool> _notifyExisting() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 450),
      );
      socket.write('NUKEFY_SHOW\n');
      await socket.flush();
      final response = await utf8.decoder.bind(socket.cast<List<int>>()).join().timeout(const Duration(milliseconds: 900));
      return response.contains('NUKEFY_OK');
    } catch (_) {
      return false;
    } finally {
      try {
        await socket?.close();
      } catch (_) {}
    }
  }

  void _handleClient(Socket socket) {
    var buffer = '';
    var handled = false;
    socket.cast<List<int>>().transform(utf8.decoder).listen(
      (chunk) {
        if (handled) return;
        buffer += chunk;
        if (!buffer.contains('NUKEFY_SHOW')) return;
        handled = true;
        unawaited(_showExisting(socket));
      },
      onError: (_) => socket.destroy(),
      onDone: () {
        if (!handled) socket.destroy();
      },
      cancelOnError: true,
    );
  }

  Future<void> _showExisting(Socket socket) async {
    try {
      await _onShow?.call();
      socket.write('NUKEFY_OK\n');
      await socket.flush();
    } catch (_) {
      socket.write('NUKEFY_ERROR\n');
      try {
        await socket.flush();
      } catch (_) {}
    } finally {
      try {
        await socket.close();
      } catch (_) {}
    }
  }

  /// Releases the listener before a replacement process is spawned.
  Future<void> prepareRestart() async {
    if (active != this) return;
    final server = _server;
    _server = null;
    await server?.close();
    if (active == this) active = null;
  }

  /// Reclaims the listener if Process.start failed. This keeps a failed
  /// restart from leaving the still-running window without single-instance
  /// protection.
  Future<void> restore() async {
    if (_server != null) return;
    try {
      _server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port, shared: false);
      _server!.listen(_handleClient, onError: (_) {});
      active = this;
    } on SocketException {
      _server = null;
    }
  }

  Future<void> dispose() async {
    await prepareRestart();
    _onShow = null;
  }
}
