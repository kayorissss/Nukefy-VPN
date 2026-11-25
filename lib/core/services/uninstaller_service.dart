import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'vpn_platform.dart';

/// What the user ticked in the uninstall screen.
class UninstallOptions {
  UninstallOptions({
    this.stopZapret = true,
    this.removeAutostart = true,
    this.removeUserData = false,
    this.removeAppFiles = true,
  });

  /// Stop and delete the zapret service/driver we installed.
  final bool stopZapret;

  /// Remove the scheduled task / Run entries / startup shortcuts.
  final bool removeAutostart;

  /// Delete subscriptions, settings, history and downloaded cores.
  final bool removeUserData;

  /// Remove the program itself (installer-managed or portable folder).
  final bool removeAppFiles;
}

/// Own uninstall flow: the app cleans up after itself and hands the file
/// removal to the installer's own uninstaller.
///
/// Two rules learned the hard way:
///  * a running process cannot delete its own folder, so the work happens in a
///    detached helper that waits for this PID to disappear;
///  * only `unins000.exe` knows where every file of the installation lives, so
///    it is always preferred over deleting the directory by hand. The previous
///    implementation also hijacked the Windows "Remove" button, which is why
///    clicking it only reopened the app — that hijack is gone (see
///    [VpnPlatform.repairUninstallEntry]).
class UninstallerService {
  UninstallerService._();

  static final UninstallerService instance = UninstallerService._();

  /// Name of the uninstaller Inno Setup places next to the executable.
  static const String uninstallerName = 'unins000.exe';

  static String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  /// Stops a process only when its image path exactly matches the one this
  /// installation owns; same-named binaries from other products stay alive.
  static String _killAtPath(String exeName, String path) =>
      'Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { '
      '\$_.Name -eq ${_psQuote(exeName)} -and '
      '[string]::Equals(\$_.ExecutablePath, ${_psQuote(path)}, [System.StringComparison]::OrdinalIgnoreCase) } '
      '| ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }';

  /// Absolute path of `unins000.exe` when this copy was installed by a setup.
  static String? uninstallerPathSync() {
    if (!Platform.isWindows) return null;
    try {
      final dir = File(Platform.resolvedExecutable).parent;
      final candidate = File(p.join(dir.path, uninstallerName));
      return candidate.existsSync() ? candidate.path : null;
    } catch (_) {
      return null;
    }
  }

  /// True when the copy is managed by an installer (so "remove files" can be
  /// delegated to it instead of deleting a folder blindly).
  static bool get isInstalled => uninstallerPathSync() != null;

  /// Writes the cleanup script and starts it detached. The caller quits the
  /// app right after: the script waits for this process to disappear.
  Future<void> start(UninstallOptions options) async {
    if (!Platform.isWindows) {
      await _cleanupNonWindows(options);
      return;
    }
    final support = (await getApplicationSupportDirectory()).path;
    if (options.removeUserData || options.removeAppFiles) {
      // Put global network settings back before we delete the backup that
      // makes the restore possible. A failure here must not block the
      // uninstall: the helper still removes the program, and the log says
      // exactly what could not be restored.
      final platform = VpnPlatform();
      await _tryRestore(() => platform.restoreSystemProxy(), 'system proxy');
      await _tryRestore(() => platform.restoreSystemDns(), 'system DNS');
      await _tryRestore(() => platform.restoreFlowsealTcpTimestamps(), 'TCP timestamps');
    }
    final exe = Platform.resolvedExecutable;
    final exeDir = File(exe).parent.path;
    final script = _script(
      pid: pid,
      exe: exe,
      exeDir: exeDir,
      support: support,
      options: options,
    );
    final file = File(p.join(Directory.systemTemp.path, 'nukefy_uninstall.ps1'));
    await file.writeAsString(script);
    if (await _isElevated()) {
      // The client itself runs elevated (TUN + WinDivert need it), so the
      // helper can start directly, without a second UAC prompt behind the app.
      await Process.start(
        'powershell.exe',
        ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden', '-File', file.path],
        mode: ProcessStartMode.detached,
      );
      return;
    }
    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Start-Process powershell -Verb RunAs -ArgumentList \'-NoProfile -ExecutionPolicy Bypass -File "${file.path}"\'',
      ],
      mode: ProcessStartMode.detached,
    );
  }

  /// Restores a system setting, but never lets a failed restore stop the
  /// uninstall. Returns the message that was written to the log.
  Future<void> _tryRestore(Future<String> Function() action, String what) async {
    try {
      final result = await action().timeout(const Duration(seconds: 25));
      if (result.startsWith('no-') || result.toLowerCase().contains('restored')) return;
    } catch (_) {
      // Reported by the helper's own log; the uninstall continues anyway.
    }
  }

  /// True when this process already runs with an administrator token.
  Future<bool> _isElevated() async {
    try {
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-Command',
        r'([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)',
      ]).timeout(const Duration(seconds: 10));
      return '${result.stdout}'.toLowerCase().contains('true');
    } catch (_) {
      return true;
    }
  }

  /// Removes what a non-Windows build can remove honestly (its own data).
  Future<void> _cleanupNonWindows(UninstallOptions options) async {
    if (!options.removeUserData) return;
    final support = await getApplicationSupportDirectory();
    for (final name in ['core', 'xray', 'run', 'game_icons']) {
      final dir = Directory(p.join(support.path, name));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    }
  }

  String _script({
    required int pid,
    required String exe,
    required String exeDir,
    required String support,
    required UninstallOptions options,
  }) {
    final uninstaller = uninstallerPathSync();
    final buffer = StringBuffer()
      // PowerShell has no backslash escapes inside double quotes; the previous
      // script started with `$ErrorActionPreference = \"SilentlyContinue\"`,
      // which is a parse error, so the whole uninstall silently did nothing.
      ..writeln(r"$ErrorActionPreference = 'SilentlyContinue'")
      ..writeln(r'$log = Join-Path $env:TEMP "nukefy_uninstall.log"')
      ..writeln(r'function Note([string]$text) { "$((Get-Date).ToString("o")) $text" | Out-File -Append -Encoding utf8 $log }')
      ..writeln('Note "Nukefy uninstall start"')
      ..writeln(r'$exeDir = ' + _psQuote(exeDir))
      ..writeln(r'$support = ' + _psQuote(support))
      // Wait for this process to exit so nothing is locked while we work.
      ..writeln(r'$appPid = $pid')
      // Raw strings: `$deadline` and `$appPid` are PowerShell variables, not
      // Dart interpolation — without the r prefix the script got empty names.
      ..writeln(r'$deadline = (Get-Date).AddSeconds(90)')
      ..writeln(r'while ((Get-Process -Id $appPid -ErrorAction SilentlyContinue) -and ((Get-Date) -lt $deadline)) { Start-Sleep -Milliseconds 350 }')
      ..writeln('Start-Sleep -Milliseconds 600')
      ..writeln('Note "app closed or timeout reached"');

    // Our own cores only: exact paths, never a bare image name.
    buffer
      ..writeln(_killAtPath('sing-box.exe', p.join(support, 'core', 'sing-box.exe')))
      ..writeln(_killAtPath('xray.exe', p.join(support, 'xray', 'xray.exe')))
      ..writeln(_killAtPath('NukefyClient.exe', exe))
      ..writeln('Note "own processes stopped"');

    if (options.stopZapret) {
      final winws = p.join(exeDir, 'zapret', 'bin', 'winws.exe');
      buffer
        // Only OUR service and OUR capture: another zapret stays intact.
        ..writeln(r'sc.exe stop nukefy-zapret | Out-Null')
        ..writeln(r'sc.exe delete nukefy-zapret | Out-Null')
        ..writeln(_killAtPath('winws.exe', winws))
        ..writeln('Note "zapret stack stopped"');
    }

    if (options.removeAutostart) {
      buffer
        ..writeln(r'schtasks /Delete /TN NukefyVPN /F | Out-Null')
        ..writeln(r'schtasks /Delete /TN "Nukefy Client" /F | Out-Null')
        ..writeln(r'Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "NukefyVPN" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Nukefy Client" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-Item -Force "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\NukefyVPN.lnk" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-Item -Force "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\Nukefy Client.lnk" -ErrorAction SilentlyContinue')
        ..writeln('Note "autostart cleaned"');
    }

    if (options.removeUserData) {
      buffer
        ..writeln(r'Remove-Item -Recurse -Force $support -ErrorAction SilentlyContinue')
        // Never delete the whole vendor folder: another app may live there.
        ..writeln(r'Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Nukefy Client" -ErrorAction SilentlyContinue')
        ..writeln('Note "user data removed"');
    }

    if (options.removeAppFiles) {
      buffer
        ..writeln(r'Remove-Item -Force "$env:PUBLIC\Desktop\Nukefy Client.lnk" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-Item -Force "$env:USERPROFILE\Desktop\Nukefy Client.lnk" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-Item -Force "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Nukefy Client.lnk" -ErrorAction SilentlyContinue');
      if (uninstaller != null) {
        // The installer's uninstaller owns shortcuts, the registry entry and
        // the file list. /VERYSILENT keeps it from asking anything — the user
        // already answered on our screen.
        buffer
          ..writeln(r'$unins = ' + _psQuote(uninstaller))
          ..writeln(r'if (Test-Path -LiteralPath $unins) {')
          ..writeln(r'  Start-Process -FilePath $unins -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait')
          ..writeln(r'  Note "installer uninstall done"')
          ..writeln(r'} else {')
          ..writeln(r'  Note "uninstaller missing, deleting folder"')
          ..writeln(r'}');
      }
      // Fallback for portable copies and for a half-broken install: remove the
      // folder only if it really is ours (the exe we are running from).
      buffer
        ..writeln(r'Start-Sleep -Milliseconds 500')
        ..writeln(r'$portableRoot = Join-Path $env:LOCALAPPDATA "NukefyVPN"')
        ..writeln(r'$portableApp = Join-Path $portableRoot "app"')
        ..writeln(r'if (Test-Path -LiteralPath (Join-Path $exeDir "NukefyClient.exe")) {')
        ..writeln(r'  if ([String]::Equals([IO.Path]::GetFullPath($exeDir).TrimEnd([IO.Path]::DirectorySeparatorChar), [IO.Path]::GetFullPath($portableApp).TrimEnd([IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) {')
        ..writeln(r'    Remove-Item -Recurse -Force $portableRoot -ErrorAction SilentlyContinue')
        ..writeln(r'  } else {')
        ..writeln(r'    Remove-Item -Recurse -Force $exeDir -ErrorAction SilentlyContinue')
        ..writeln(r'  }')
        ..writeln(r'}')
        ..writeln('Note "application files step finished"');
    }

    buffer.writeln('Note "Nukefy uninstall finished"');
    return buffer.toString();
  }
}
