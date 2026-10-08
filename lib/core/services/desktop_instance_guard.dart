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

  /// Invoked when another process (the Windows "Remove" entry, which starts a
  /// second copy with --uninstall) asks this instance to shut down so its
  /// files are not locked during removal.
  Future<void> Function()? onQuit;

  /// Returns true when this process owns the instance. Returns false only
  /// after a running instance positively acknowledges the show request.
  ///
  /// [retry] is used by a replacement process spawned for an in-app restart:
  /// the dying parent releases the listener a moment after the child starts,
  /// and binding early used to produce a second, half-dead window. With a
  /// retry budget the child simply waits for the port to free.
  Future<bool> acquire({
    required Future<void> Function() onShow,
    Duration retry = Duration.zero,
  }) async {
    if (_server != null) return true;
    _onShow = onShow;
    final deadline = Stopwatch()..start();
    while (true) {
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
        if (deadline.elapsed >= retry) {
          // A stale listener or an unrelated process occupying the port must
          // not make Nukefy silently exit. Continue without the listener.
          return true;
        }
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }
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
        if (buffer.contains('NUKEFY_QUIT')) {
          handled = true;
          unawaited(_quitExisting(socket));
          return;
        }
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

  Future<void> _quitExisting(Socket socket) async {
    try {
      socket.write('NUKEFY_OK\n');
      await socket.flush();
    } catch (_) {}
    try {
      await socket.close();
    } catch (_) {}
    try {
      await onQuit?.call();
    } catch (_) {}
  }

  /// Asks a running instance to exit. Returns true when it acknowledged.
  Future<bool> requestQuit() async {
    Socket? socket;
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        port,
        timeout: const Duration(milliseconds: 450),
      );
      socket.write('NUKEFY_QUIT\n');
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
