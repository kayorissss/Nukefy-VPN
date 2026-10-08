import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Screenshots while the client runs elevated.
///
/// Windows blocks the shell (Explorer / Snipping Tool) from seeing the
/// PrintScreen key while an elevated window has focus — that is the whole
/// reason PrtSc "did nothing" in the client. The app itself is elevated, so it
/// can capture the screen and put the image on the clipboard exactly like
/// Windows does, and save a PNG next to the system screenshots.
class ScreenshotService {
  ScreenshotService._();

  static final ScreenshotService instance = ScreenshotService._();

  /// Returns the saved file path, or null when the capture failed.
  Future<String?> capture() async {
    if (!Platform.isWindows) return null;
    try {
      final target = await _screenshotsDir();
      final script = r'''
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.X, $bounds.Y, 0, 0, $bitmap.Size)
$dir = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Screenshots'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$file = Join-Path $dir ('Nukefy_{0:yyyy-MM-dd_HH-mm-ss}.png' -f (Get-Date))
$bitmap.Save($file, [System.Drawing.Imaging.ImageFormat]::Png)
try { [System.Windows.Forms.Clipboard]::SetImage($bitmap) } catch { }
$graphics.Dispose()
$bitmap.Dispose()
Write-Output $file
''';
      final result = await Process.run(
        'powershell.exe',
        ['-NoProfile', '-Sta', '-ExecutionPolicy', 'Bypass', '-Command', script],
      ).timeout(const Duration(seconds: 20));
      final path = '${result.stdout}'.trim().split(RegExp(r'\r?\n')).last.trim();
      if (path.isEmpty || !File(path).existsSync()) {
        // Fall back to our own folder: some locked-down profiles refuse
        // writing into Pictures.
        final fallback = File(p.join(target.path, 'nukefy_${DateTime.now().millisecondsSinceEpoch}.png'));
        final script2 = script.replaceAll(
          r"$dir = Join-Path ([Environment]::GetFolderPath('MyPictures')) 'Screenshots'",
          "\$dir = '${target.path.replaceAll("'", "''")}'",
        );
        final second = await Process.run(
          'powershell.exe',
          ['-NoProfile', '-Sta', '-ExecutionPolicy', 'Bypass', '-Command', script2],
        ).timeout(const Duration(seconds: 20));
        final path2 = '${second.stdout}'.trim().split(RegExp(r'\r?\n')).last.trim();
        if (path2.isNotEmpty && File(path2).existsSync()) return path2;
        fallback.parent.createSync(recursive: true);
        return null;
      }
      return path;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _screenshotsDir() async {
    try {
      final support = await getApplicationSupportDirectory();
      return Directory(p.join(support.path, 'screenshots'));
    } catch (_) {
      return Directory.systemTemp;
    }
  }
}
