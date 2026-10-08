import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  /// Writes the cleanup script and starts it detached. The caller should quit
  /// the app right after: the script waits for this process to disappear.
  Future<void> start(UninstallOptions options) async {
    if (!Platform.isWindows) {
      await _cleanupNonWindows(options);
      return;
    }
    final support = (await getApplicationSupportDirectory()).path;
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
    await Process.start(
      'powershell.exe',
      [
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        'Start-Process powershell -Verb RunAs -WindowStyle Hidden -ArgumentList \'-NoProfile -ExecutionPolicy Bypass -File "${file.path}"\'',
      ],
      mode: ProcessStartMode.detached,
    );
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
      ..writeln(r'"Nukefy uninstall start $(Get-Date -Format o)" | Out-File -Encoding utf8 $log')
      // Wait for the app to close so nothing is locked while we work.
      ..writeln('Wait-Process -Id $pid -Timeout 90 -ErrorAction SilentlyContinue')
      ..writeln('Start-Sleep -Milliseconds 900')
      ..writeln(r'"target exe: ' + exe + r'" | Out-File -Append -Encoding utf8 $log');

    if (options.stopZapret) {
      buffer
        // Only OUR service and OUR capture: other zapret installs stay intact.
        ..writeln(r'sc.exe stop nukefy-zapret | Out-Null')
        ..writeln(r'sc.exe delete nukefy-zapret | Out-Null')
        ..writeln(r'''Get-CimInstance Win32_Process | Where-Object { $_.Name -eq "winws.exe" -and $_.ExecutablePath -like "*nukefy*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }''')
        ..writeln(r'taskkill /F /IM sing-box.exe /T | Out-Null')
        ..writeln(r'taskkill /F /IM xray.exe /T | Out-Null')
        ..writeln(r'sc.exe stop WinDivert | Out-Null')
        ..writeln(r'"zapret stack stopped" | Out-File -Append -Encoding utf8 $log');
    }

    if (options.removeAutostart) {
      buffer
        ..writeln(r'schtasks /Delete /TN NukefyVPN /F | Out-Null')
        ..writeln(r'schtasks /Delete /TN "Nukefy Client" /F | Out-Null')
        ..writeln(r'Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "NukefyVPN" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "Nukefy Client" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-Item -Recurse -Force "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\Nukefy*" -ErrorAction SilentlyContinue')
        ..writeln(r'"autostart cleaned" | Out-File -Append -Encoding utf8 $log');
    }

    if (options.removeUserData) {
      buffer
        ..writeln('Remove-Item -Recurse -Force "$support" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-Item -Recurse -Force "$env:APPDATA\kayorisan" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-Item -Recurse -Force "$env:LOCALAPPDATA\NukefyVPN" -ErrorAction SilentlyContinue')
        ..writeln(r'Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Nukefy Client" -ErrorAction SilentlyContinue')
        ..writeln(r'"user data removed" | Out-File -Append -Encoding utf8 $log');
    }

    if (options.removeAppFiles) {
      buffer
        // Prefer the installer's own silent uninstall (it also removes
        // shortcuts and registry entries), and fall back to deleting the
        // folder for portable copies.
        ..writeln(r'$entry = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*" | Where-Object { $_.DisplayName -like "*Nukefy*" } | Select-Object -First 1')
        ..writeln(r'if ($entry -and $entry.UninstallString) {')
        ..writeln(r'  $cmd = $entry.UninstallString')
        ..writeln(r'  $cmd = $cmd -replace "\\?$", ""')
        ..writeln(r'  Start-Process -FilePath $cmd -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait')
        ..writeln(r'  "installer uninstall done" | Out-File -Append -Encoding utf8 $log')
        ..writeln('  } else {')
        ..writeln('  Start-Sleep -Milliseconds 500')
        ..writeln('  Remove-Item -Recurse -Force "$exeDir" -ErrorAction SilentlyContinue')
        ..writeln(r'  "portable folder removed" | Out-File -Append -Encoding utf8 $log')
        ..writeln('  }');
    }

    buffer.writeln(r'"Nukefy uninstall finished" | Out-File -Append -Encoding utf8 $log');
    return buffer.toString();
  }
}
