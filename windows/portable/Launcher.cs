// Portable single-file launcher for Nukefy VPN.
// The whole Flutter build (exe + dlls + data + zapret) is embedded as
// payload.zip. On start it is unpacked to %LOCALAPPDATA%\NukefyVPN\app
// (only when the embedded version differs) and nukefy_vpn.exe is launched.
using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Windows.Forms;

static class Launcher
{
    const string AppName = "NukefyVPN";

    [STAThread]
    static int Main(string[] args)
    {
        try
        {
            // A second launch of the portable exe while the app is running is
            // treated as "open the window", never as a second installation.
            var asm = Assembly.GetExecutingAssembly();
            var version = asm.GetName().Version.ToString();
            var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), AppName);
            var appDir = Path.Combine(root, "app");
            var marker = Path.Combine(root, "version.txt");
            var exe = Path.Combine(appDir, "nukefy_vpn.exe");

            // --uninstall is deliberately passed through to the branded app.
            // It owns confirmation, scope checkboxes and the path-filtered
            // cleanup helper; doing anything here used to delete the portable
            // install before the user had even confirmed.

            var current = File.Exists(marker) ? File.ReadAllText(marker).Trim() : "";
            if (current != version || !File.Exists(exe))
            {
                KillRunning(appDir);
                Extract(asm, appDir);
                Directory.CreateDirectory(root);
                File.WriteAllText(marker, version);
            }

            var psi = new ProcessStartInfo(exe)
            {
                WorkingDirectory = appDir,
                UseShellExecute = false,
                Arguments = string.Join(" ", Array.ConvertAll(args, a => "\"" + a + "\"")),
            };
            Process.Start(psi);
            return 0;
        }
        catch (Exception e)
        {
            MessageBox.Show("Не удалось запустить Nukefy VPN:\n\n" + e, "Nukefy VPN",
                MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    static void Extract(Assembly asm, string appDir)
    {
        using (var stream = asm.GetManifestResourceStream("payload.zip"))
        {
            if (stream == null) throw new Exception("payload.zip is missing in the launcher");
            var tmp = appDir + ".new";
            if (Directory.Exists(tmp)) Directory.Delete(tmp, true);
            using (var zip = new ZipArchive(stream, ZipArchiveMode.Read))
            {
                zip.ExtractToDirectory(tmp);
            }
            // Keep user-editable zapret lists across updates.
            if (Directory.Exists(appDir))
            {
                var oldLists = Path.Combine(appDir, "zapret", "lists");
                var newLists = Path.Combine(tmp, "zapret", "lists");
                if (Directory.Exists(oldLists) && Directory.Exists(newLists))
                {
                    foreach (var f in Directory.GetFiles(oldLists, "*-user.txt"))
                        File.Copy(f, Path.Combine(newLists, Path.GetFileName(f)), true);
                }
                Directory.Delete(appDir, true);
            }
            Directory.Move(tmp, appDir);
        }
    }

    static void KillRunning(string appDir)
    {
        // Replacing the portable payload may close only processes whose image
        // is inside this exact installation. Other VPN clients also use
        // sing-box/winws and must never be killed by process name alone.
        var root = Path.GetFullPath(appDir).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            + Path.DirectorySeparatorChar;
        foreach (var name in new[] { "nukefy_vpn", "winws", "sing-box", "xray" })
        {
            foreach (var process in Process.GetProcessesByName(name))
            {
                try
                {
                    var image = process.MainModule == null ? null : process.MainModule.FileName;
                    if (String.IsNullOrEmpty(image)) continue;
                    var fullImage = Path.GetFullPath(image);
                    if (!fullImage.StartsWith(root, StringComparison.OrdinalIgnoreCase)) continue;
                    process.Kill();
                    process.WaitForExit(3000);
                }
                catch { }
            }
        }
    }
}
