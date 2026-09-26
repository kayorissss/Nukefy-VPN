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
            var asm = Assembly.GetExecutingAssembly();
            var version = asm.GetName().Version.ToString();
            var root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), AppName);
            var appDir = Path.Combine(root, "app");
            var marker = Path.Combine(root, "version.txt");
            var exe = Path.Combine(appDir, "nukefy_vpn.exe");

            var current = File.Exists(marker) ? File.ReadAllText(marker).Trim() : "";
            if (current != version || !File.Exists(exe))
            {
                KillRunning();
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

    static void KillRunning()
    {
        foreach (var name in new[] { "nukefy_vpn", "winws", "sing-box" })
        {
            foreach (var p in Process.GetProcessesByName(name))
            {
                try { p.Kill(); p.WaitForExit(3000); } catch { }
            }
        }
    }
}
