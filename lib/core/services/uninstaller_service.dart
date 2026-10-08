import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'vpn_platform.dart';

/// What the user ticked in the uninstall screen.
class UninstallOptions {
  UninstallOptions({
    this.stopZapret = true,
    this.removeAutostart = true,
    this.removeUserData = true,
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

/// Own uninstall flow: the app cleans up after itself instead of handing the
/// user to a silent system dialog. The heavy lifting happens in a detached
/// elevated PowerShell script because Windows will not let a running process
/// delete its own folder.
class UninstallerService {
  UninstallerService._();

  static final UninstallerService instance = UninstallerService._();

  /// Stop a core only when its image path exactly matches the location this
  /// installation owns; same-named binaries from other apps remain untouched.
  static String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

  static String _killAtPath(String exeName, String path) =>
      'Get-CimInstance Win32_Process | Where-Object { \$_.Name -eq ${_psQuote(exeName)} -and '
      '[string]::Equals(\$_.ExecutablePath, ${_psQuote(path)}, [System.StringComparison]::OrdinalIgnoreCase) } '
      '| ForEach-Object { Stop-Process -Id \$_.ProcessId -Force }';

  /// Writes the cleanup script and starts it detached. The caller should quit
  /// the app right after: the script waits for this process to disappear.
  Future<void> start(UninstallOptions options) async {
    if (!Platform.isWindows) {
      await _cleanupNonWindows(options);
      return;
    }
    final support = (await getApplicationSupportDirectory()).path;
    if (options.removeUserData || options.removeAppFiles) {
      // If the app changed global network settings, restore them before either
      // deleting their backup or removing the app that offers the restore UI.
      final platform = VpnPlatform();
      final proxyResult = await platform.restoreSystemProxy();
      if (proxyResult != 'no-system-proxy-backup' && !proxyResult.startsWith('Previous current-user proxy settings restored')) {
        throw StateError('Could not restore the saved current-user proxy before uninstall: $proxyResult');
      }
      final dnsResult = await platform.restoreSystemDns();
      if (dnsResult != 'no-dns-backup' && !dnsResult.startsWith('Previous DNS restored')) {
        throw StateError('Could not restore the saved system DNS before uninstall: $dnsResult');
      }
      final tcpResult = await platform.restoreFlowsealTcpTimestamps();
      if (tcpResult != 'no-tcp-timestamp-backup' && !tcpResult.startsWith('TCP timestamps restored')) {
        throw StateError('Could not restore the saved TCP timestamp setting before uninstall: $tcpResult');
      }
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
      // helper can start directly. The old code always asked for RunAs, which
      // produced a UAC window behind the app: the screen looked frozen and
      // "nothing happened" until it was dismissed.
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
    final buffer = StringBuffer()
      ..writeln(r'$ErrorActionPreference = "SilentlyContinue"')
      ..writeln(r'$log = Join-Path $env:TEMP "nukefy_uninstall.log"')
      ..writeln(r'$exeDir = ' + _psQuote(exeDir))
      ..writeln(r'$support = ' + _psQuote(support))
      ..writeln(r'"Nukefy uninstall start $(Get-Date -Format o)" | Out-File -Encoding utf8 $log')
      // Wait for the app to close so nothing is locked while we work.
      ..writeln('Wait-Process -Id $pid -Timeout 90 -ErrorAction SilentlyContinue')
      ..writeln('Start-Sleep -Milliseconds 900')
      ..writeln(r'"target exe: ' + exe + r'" | Out-File -Append -Encoding utf8 $log');

    // Full exit must stop our own VPN cores even when the user elects to keep
    // the separately-managed zapret service. Exact executable paths ensure no
    // process with the same name from another product is touched.
    buffer
      ..writeln(_killAtPath('sing-box.exe', p.join(support, 'core', 'sing-box.exe')))
      ..writeln(_killAtPath('xray.exe', p.join(support, 'xray', 'xray.exe')));

    if (options.stopZapret) {
      final winws = p.join(exeDir, 'zapret', 'bin', 'winws.exe');
      buffer
        // Only OUR service and OUR capture: other zapret installs stay intact.
        ..writeln(r'sc.exe stop nukefy-zapret | Out-Null')
        ..writeln(r'sc.exe delete nukefy-zapret | Out-Null')
        ..writeln(_killAtPath('winws.exe', winws))
        // WinDivert is shared with other tools; do not stop or uninstall it.
        ..writeln(r'"zapret stack stopped" | Out-File -Append -Encoding utf8 $log');
    }

    if (options.removeAutostart) {
      buffer
        ..writeln(r'schtasks /Delete /TN NukefyVPN /F | Out-Null')
        ..writeln(r'schtasks /Delete /TN "Nukefy Client" /F | Out-Null')
        ..writeln(r'Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "NukefyVPN" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Nukefy Client" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-Item -Force "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\NukefyVPN.lnk" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-Item -Force "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\Nukefy Client.lnk" -ErrorAction SilentlyContinue')
        ..writeln(r'"autostart cleaned" | Out-File -Append -Encoding utf8 $log');
    }

    if (options.removeUserData) {
      buffer
        ..writeln(r'Remove-Item -Recurse -Force $support -ErrorAction SilentlyContinue')
        // Never delete the whole vendor folder: it can contain other apps.
        // The portable launcher directory is program files, not user data.
        ..writeln(r'Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Nukefy Client" -ErrorAction SilentlyContinue')
        ..writeln(r'"user data removed" | Out-File -Append -Encoding utf8 $log');
    }

    if (options.removeAppFiles) {
      buffer
        // Shortcuts and the "Apps & features" entry belong to the install, so
        // they go with it. Only our own names are touched.
        ..writeln(r'Remove-Item -Force "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Nukefy Client.lnk" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-Item -Force "$env:PUBLIC\Desktop\Nukefy Client.lnk" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-Item -Force "$env:USERPROFILE\Desktop\Nukefy Client.lnk" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-Item -Recurse -Force "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{7D1D2E7B-4C0A-4E36-9B2E-7A9C3E1F5A10}_is1" -ErrorAction SilentlyContinue')
        ..writeln(r'"shortcuts and uninstall entry removed" | Out-File -Append -Encoding utf8 $log')
        // The installer's own uninstaller is preferred: it deletes shortcuts,
        // the registry key and the logged uninstall data. UninstallString must
        // NOT be used as the source, because it points back at our own
        // branded window (running it would just reopen this screen). A
        // portable copy has no unins000.exe, so the folder is deleted instead.
        ..writeln(r'$unins = Get-ChildItem -Path $exeDir -Filter "unins*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1')
        ..writeln(r'if ($unins) {')
        ..writeln(r'  Start-Process -FilePath $unins.FullName -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait')
        ..writeln(r'  "installer uninstall done" | Out-File -Append -Encoding utf8 $log')
        ..writeln('  } else {')
        ..writeln('  Start-Sleep -Milliseconds 500')
        ..writeln(r'  $portableRoot = Join-Path $env:LOCALAPPDATA "NukefyVPN"')
        ..writeln(r'  $portableApp = Join-Path $portableRoot "app"')
        ..writeln(r'  if ([String]::Equals([IO.Path]::GetFullPath($exeDir).TrimEnd([IO.Path]::DirectorySeparatorChar), [IO.Path]::GetFullPath($portableApp).TrimEnd([IO.Path]::DirectorySeparatorChar), [System.StringComparison]::OrdinalIgnoreCase)) {')
        ..writeln(r'    Remove-Item -Recurse -Force $portableRoot -ErrorAction SilentlyContinue')
        ..writeln('  } else {')
        ..writeln(r'    Remove-Item -Recurse -Force $exeDir -ErrorAction SilentlyContinue')
        ..writeln('  }')
        ..writeln(r'  "application files removed" | Out-File -Append -Encoding utf8 $log')
        ..writeln('  }');
    }

    buffer.writeln(r'"Nukefy uninstall finished" | Out-File -Append -Encoding utf8 $log');
    return buffer.toString();
  }
}
