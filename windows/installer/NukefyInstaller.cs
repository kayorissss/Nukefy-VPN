// Nukefy Client — собственный установщик.
//
// Окно полностью своё: тёмная карточка в стиле приложения, выбор языка,
// галочки, прогресс и финальная страница. Никакого системного мастера Inno:
// payload.zip (уже собранный Flutter-билд) лежит ресурсом внутри этого exe.
//
// Что делает установка:
//   1. останавливает ТОЛЬКО наши процессы и нашу службу nukefy-zapret;
//   2. распаковывает приложение в %ProgramFiles%\Nukefy Client;
//   3. сохраняет пользовательские списки zapret и все данные в %APPDATA%;
//   4. пишет запись «Удалить» так, чтобы открывалось своё окно удаления;
//   5. создаёт ярлыки и, при желании, автозапуск;
//   6. передаёт выбранные галочки приложению через install-options.json.
//
// Компилируется csc из .NET Framework (WinForms), поэтому никаких внешних
// зависимостей у файла нет.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace NukefySetup
{
    static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new SetupForm());
        }
    }

    /// <summary>Strings in both languages; index 0 = ru, 1 = en.</summary>
    static class L
    {
        public static int Lang = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ru" ? 0 : 1;

        static readonly string[][] S =
        {
            new[] // ru
            {
                "NUKEFY CLIENT",
                "Установка Nukefy Client",
                "Свой клиент sing-box и Zapret: без системного мастера и лишних вопросов.",
                "Создать ярлык на рабочем столе",
                "Запускать при входе в Windows",
                "Открыть Nukefy после установки",
                "Установить",
                "Отмена",
                "Подготовка…",
                "Готово",
                "Установка завершена. Приложение уже готово к запуску.",
                "Открыть Nukefy",
                "Закрыть",
                "Устанавливается в",
                "Распаковываю приложение…",
                "Создаю ярлыки…",
                "Прописываю удаление…",
                "Останавливаю запущенные процессы…",
                "Готовлю автозапуск…",
                "Не удалось установить",
                "Подробности",
                "Закрыть приложение Nukefy и повторить",
                "Повторить",
                "Ваши подписки, настройки и журналы останутся на месте.",
            },
            new[] // en
            {
                "NUKEFY CLIENT",
                "Nukefy Client setup",
                "Our own sing-box and Zapret client: no system wizard, no extra questions.",
                "Create a desktop shortcut",
                "Start with Windows",
                "Open Nukefy when done",
                "Install",
                "Cancel",
                "Preparing…",
                "Done",
                "The installation is complete. The app is ready to start.",
                "Open Nukefy",
                "Close",
                "Installing to",
                "Unpacking the app…",
                "Creating shortcuts…",
                "Registering the uninstaller…",
                "Stopping running processes…",
                "Setting up autostart…",
                "Installation failed",
                "Details",
                "Close Nukefy and try again",
                "Retry",
                "Your subscriptions, settings and logs stay untouched.",
            },
        };

        public static string T(int i) { return S[Lang][i]; }
    }

    enum Page { Options, Progress, Done, Failed }

    class SetupForm : Form
    {
        // palette, mirroring lib/core/theme/app_colors.dart
        static readonly Color Bg = Color.FromArgb(0x0B, 0x0E, 0x13);
        static readonly Color Card = Color.FromArgb(0x16, 0x1B, 0x24);
        static readonly Color Border = Color.FromArgb(0x24, 0x2B, 0x36);
        static readonly Color Text = Color.FromArgb(0xF3, 0xF6, 0xFA);
        static readonly Color Muted = Color.FromArgb(0x8B, 0x95, 0xA5);
        static readonly Color Accent = Color.FromArgb(0x2E, 0xE5, 0x9D);
        static readonly Color Danger = Color.FromArgb(0xFF, 0x4D, 0x6D);

        bool _desktop = true;
        bool _autostart = false;
        bool _launch = true;
        Page _page = Page.Options;
        double _progress;
        string _status = "";
        string _error = "";
        Point _drag;
        int _hover = -1;

        static readonly string AppDir = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Nukefy Client");
        const string UninstallKey = @"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{7D1D2E7B-4C0A-4E36-9B2E-7A9C3E1F5A10}_is1";

        public SetupForm()
        {
            Text = "Nukefy Client";
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(660, 460);
            BackColor = Bg;
            DoubleBuffered = true;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            Icon = LoadIcon();
        }

        static Icon LoadIcon()
        {
            try
            {
                using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("app_icon.ico"))
                {
                    if (s != null) return new Icon(s);
                }
            }
            catch { }
            return null;
        }

        static GraphicsPath Round(Rectangle r, int radius)
        {
            var path = new GraphicsPath();
            int d = radius * 2;
            path.AddArc(r.X, r.Y, d, d, 180, 90);
            path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }

        // ---------------------------------------------------------------- paint
        Rectangle TitleBar { get { return new Rectangle(0, 0, ClientSize.Width, 46); } }
        Rectangle CloseButton { get { return new Rectangle(ClientSize.Width - 44, 0, 44, 46); } }
        Rectangle RuChip { get { return new Rectangle(ClientSize.Width - 150, 12, 44, 22); } }
        Rectangle EnChip { get { return new Rectangle(ClientSize.Width - 102, 12, 44, 22); } }

        Rectangle PrimaryButton
        {
            get { return new Rectangle(ClientSize.Width - 230, ClientSize.Height - 76, 196, 46); }
        }

        Rectangle SecondaryButton
        {
            get { return new Rectangle(ClientSize.Width - 230 - 120, ClientSize.Height - 76, 110, 46); }
        }

        Rectangle[] OptionRows
        {
            get
            {
                var rows = new Rectangle[3];
                for (int i = 0; i < 3; i++)
                    rows[i] = new Rectangle(44, 208 + i * 42, ClientSize.Width - 88, 34);
                return rows;
            }
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            var g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            using (var brush = new LinearGradientBrush(ClientRectangle, Color.FromArgb(0x0B, 0x0E, 0x13), Color.FromArgb(0x10, 0x16, 0x1F), 90f))
                g.FillRectangle(brush, ClientRectangle);
            // accent glow in the top-left corner, same idea as the app background
            using (var glow = new GraphicsPath())
            {
                glow.AddEllipse(-160, -220, 520, 420);
                using (var b = new PathGradientBrush(glow))
                {
                    b.CenterColor = Color.FromArgb(38, Accent);
                    b.SurroundColors = new[] { Color.FromArgb(0, Accent) };
                    g.FillPath(b, glow);
                }
            }

            // rounded window
            using (var region = Round(new Rectangle(0, 0, ClientSize.Width, ClientSize.Height), 14))
            {
                Region = new Region(region);
            }

            // title row
            using (var dot = new SolidBrush(Accent)) g.FillEllipse(dot, 20, 19, 8, 8);
            DrawText(g, L.T(0), new Rectangle(36, 14, 300, 20), 9.5f, Muted, FontStyle.Bold, 2f);
            using (var icon = LoadIcon())
            {
                if (icon != null) g.DrawIcon(icon, new Rectangle(ClientSize.Width - 236, 13, 20, 20));
            }
            DrawChip(g, RuChip, "RU", L.Lang == 0);
            DrawChip(g, EnChip, "EN", L.Lang == 1);
            DrawText(g, "✕", CloseButton, 12f, _hover == 9 ? Danger : Muted, FontStyle.Regular, 0f, true);

            if (_page == Page.Options) PaintOptions(g);
            else if (_page == Page.Progress) PaintProgress(g);
            else if (_page == Page.Done) PaintDone(g);
            else PaintFailed(g);
        }

        void PaintOptions(Graphics g)
        {
            DrawText(g, L.T(1), new Rectangle(40, 74, ClientSize.Width - 80, 40), 24f, Text, FontStyle.Bold, 0f);
            DrawText(g, L.T(2), new Rectangle(40, 124, ClientSize.Width - 80, 40), 10f, Muted, FontStyle.Regular, 0f);
            DrawText(g, L.T(13) + " " + AppDir, new Rectangle(40, 158, ClientSize.Width - 80, 20), 9f, Color.FromArgb(0x4F, 0x58, 0x66), FontStyle.Regular, 0f);

            var card = new Rectangle(32, 190, ClientSize.Width - 64, 3 * 42 + 22);
            using (var path = Round(card, 16))
            {
                using (var fill = new SolidBrush(Card)) g.FillPath(fill, path);
                using (var pen = new Pen(Border)) g.DrawPath(pen, path);
            }
            var rows = OptionRows;
            for (int i = 0; i < 3; i++)
                DrawCheck(g, rows[i], i == 0 ? _desktop : i == 1 ? _autostart : _launch, L.T(3 + i));

            DrawText(g, L.T(24), new Rectangle(40, ClientSize.Height - 110, ClientSize.Width - 300, 20), 9f, Muted, FontStyle.Regular, 0f);
            DrawButton(g, PrimaryButton, L.T(6), true);
            DrawButton(g, SecondaryButton, L.T(7), false);
        }

        void PaintProgress(Graphics g)
        {
            DrawText(g, L.T(1), new Rectangle(40, 74, ClientSize.Width - 80, 40), 24f, Text, FontStyle.Bold, 0f);
            DrawText(g, _status, new Rectangle(40, 150, ClientSize.Width - 80, 24), 11f, Muted, FontStyle.Regular, 0f);
            var track = new Rectangle(40, 196, ClientSize.Width - 80, 10);
            using (var path = Round(track, 5))
            using (var fill = new SolidBrush(Color.FromArgb(0x22, 0x28, 0x33)))
                g.FillPath(fill, path);
            int w = (int)(track.Width * Math.Max(0.02, Math.Min(1, _progress)));
            if (w > 12)
            {
                using (var path = Round(new Rectangle(track.X, track.Y, w, track.Height), 5))
                using (var fill = new LinearGradientBrush(new Rectangle(track.X, track.Y, w, track.Height), Accent, Color.FromArgb(0x00, 0xE5, 0xFF), 0f))
                    g.FillPath(fill, path);
            }
            DrawText(g, (int)(_progress * 100) + "%", new Rectangle(40, 216, ClientSize.Width - 80, 22), 10f, Text, FontStyle.Bold, 0f);
        }

        void PaintDone(Graphics g)
        {
            var circle = new Rectangle(ClientSize.Width / 2 - 34, 96, 68, 68);
            using (var b = new SolidBrush(Color.FromArgb(40, Accent))) g.FillEllipse(b, circle);
            using (var pen = new Pen(Accent, 4f))
            {
                g.DrawLines(pen, new[]
                {
                    new Point(circle.X + 18, circle.Y + 36),
                    new Point(circle.X + 30, circle.Y + 47),
                    new Point(circle.X + 51, circle.Y + 22),
                });
            }
            DrawText(g, L.T(9), new Rectangle(40, 180, ClientSize.Width - 80, 40), 22f, Text, FontStyle.Bold, 0f, false, true);
            DrawText(g, L.T(10), new Rectangle(40, 226, ClientSize.Width - 80, 40), 10.5f, Muted, FontStyle.Regular, 0f, false, true);
            DrawButton(g, PrimaryButton, L.T(11), true);
            DrawButton(g, SecondaryButton, L.T(12), false);
        }

        void PaintFailed(Graphics g)
        {
            DrawText(g, L.T(21), new Rectangle(40, 100, ClientSize.Width - 80, 40), 20f, Danger, FontStyle.Bold, 0f);
            DrawText(g, L.T(22), new Rectangle(40, 150, ClientSize.Width - 80, 24), 10f, Muted, FontStyle.Regular, 0f);
            var box = new Rectangle(40, 180, ClientSize.Width - 80, 150);
            using (var path = Round(box, 14))
            {
                using (var fill = new SolidBrush(Card)) g.FillPath(fill, path);
                using (var pen = new Pen(Border)) g.DrawPath(pen, path);
            }
            DrawText(g, Trim(_error, 420), new Rectangle(box.X + 14, box.Y + 12, box.Width - 28, box.Height - 24), 9f, Muted, FontStyle.Regular, 0f);
            DrawButton(g, PrimaryButton, L.T(23), true);
        }

        static string Trim(string text, int max)
        {
            if (string.IsNullOrEmpty(text)) return "";
            return text.Length <= max ? text : text.Substring(0, max) + "…";
        }

        void DrawText(Graphics g, string text, Rectangle box, float size, Color color, FontStyle style, float spacing, bool center = false, bool middle = false)
        {
            using (var font = new Font("Segoe UI", size, style, GraphicsUnit.Point))
            using (var brush = new SolidBrush(color))
            using (var format = new StringFormat())
            {
                format.Alignment = center ? StringAlignment.Center : StringAlignment.Near;
                format.LineAlignment = middle ? StringAlignment.Center : StringAlignment.Near;
                format.Trimming = StringTrimming.EllipsisCharacter;
                if (spacing > 0)
                {
                    // letter-spacing by hand: GDI+ has no tracking
                    float x = box.X;
                    foreach (char c in text)
                    {
                        g.DrawString(c.ToString(), font, brush, x, box.Y);
                        x += g.MeasureString(c.ToString(), font).Width + spacing;
                    }
                    return;
                }
                g.DrawString(text, font, brush, box, format);
            }
        }

        void DrawChip(Graphics g, Rectangle r, string label, bool active)
        {
            using (var path = Round(r, 8))
            {
                using (var fill = new SolidBrush(active ? Color.FromArgb(46, Accent) : Color.FromArgb(20, 255, 255, 255)))
                    g.FillPath(fill, path);
                using (var pen = new Pen(active ? Accent : Border))
                    g.DrawPath(pen, path);
            }
            DrawText(g, label, r, 8.5f, active ? Accent : Muted, FontStyle.Bold, 0.5f, true, true);
        }

        void DrawButton(Graphics g, Rectangle r, string label, bool primary)
        {
            using (var path = Round(r, 12))
            {
                if (primary)
                {
                    using (var fill = new LinearGradientBrush(r, Accent, Color.FromArgb(0x00, 0xE5, 0xFF), 0f))
                        g.FillPath(fill, path);
                }
                else
                {
                    using (var fill = new SolidBrush(Color.FromArgb(0x1A, 0x1F, 0x28))) g.FillPath(fill, path);
                    using (var pen = new Pen(Border)) g.DrawPath(pen, path);
                }
            }
            DrawText(g, label, r, 11f, primary ? Color.FromArgb(0x0B, 0x0E, 0x13) : Text, FontStyle.Bold, 0f, true, true);
        }

        void DrawCheck(Graphics g, Rectangle row, bool value, string label)
        {
            var box = new Rectangle(row.X + 14, row.Y + 7, 20, 20);
            using (var path = Round(box, 6))
            {
                using (var fill = new SolidBrush(value ? Color.FromArgb(46, Accent) : Color.FromArgb(20, 255, 255, 255)))
                    g.FillPath(fill, path);
                using (var pen = new Pen(value ? Accent : Border, 1.4f))
                    g.DrawPath(pen, path);
            }
            if (value)
            {
                using (var pen = new Pen(Accent, 2.4f))
                {
                    pen.StartCap = LineCap.Round;
                    pen.EndCap = LineCap.Round;
                    g.DrawLines(pen, new[]
                    {
                        new Point(box.X + 5, box.Y + 10),
                        new Point(box.X + 9, box.Y + 14),
                        new Point(box.X + 15, box.Y + 6),
                    });
                }
            }
            DrawText(g, label, new Rectangle(row.X + 46, row.Y + 8, row.Width - 60, 22), 10.5f, Text, FontStyle.Regular, 0f);
        }

        // ---------------------------------------------------------------- input
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            _drag = e.Location;
        }

        protected override void OnMouseMove(MouseEventArgs e)
        {
            base.OnMouseMove(e);
            if (e.Button == MouseButtons.Left)
            {
                // the window has no system frame: dragging the title row moves it
                if (_drag.Y < 46)
                {
                    Left += e.X - _drag.X;
                    Top += e.Y - _drag.Y;
                }
                return;
            }
            int hover = -1;
            if (CloseButton.Contains(e.Location)) hover = 9;
            else if (RuChip.Contains(e.Location)) hover = 10;
            else if (EnChip.Contains(e.Location)) hover = 11;
            if (hover != _hover) { _hover = hover; Invalidate(); }
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            var point = e.Location;
            if (_page == Page.Options)
            {
                if (CloseButton.Contains(point)) { Close(); return; }
                if (RuChip.Contains(point)) { L.Lang = 0; Invalidate(); return; }
                if (EnChip.Contains(point)) { L.Lang = 1; Invalidate(); return; }
                var rows = OptionRows;
                for (int i = 0; i < 3; i++)
                {
                    if (!rows[i].Contains(point)) continue;
                    if (i == 0) _desktop = !_desktop;
                    if (i == 1) _autostart = !_autostart;
                    if (i == 2) _launch = !_launch;
                    Invalidate();
                    return;
                }
                if (PrimaryButton.Contains(point)) { Start(); return; }
                if (SecondaryButton.Contains(point)) { Close(); return; }
            }
            else if (_page == Page.Done)
            {
                if (PrimaryButton.Contains(point)) { Launch(); Close(); return; }
                if (SecondaryButton.Contains(point)) { Close(); return; }
                if (CloseButton.Contains(point)) { Close(); return; }
            }
            else if (_page == Page.Failed)
            {
                if (PrimaryButton.Contains(point)) { Launch(); Close(); return; }
                if (CloseButton.Contains(point)) { Close(); return; }
            }
        }

        // --------------------------------------------------------------- logic
        void Start()
        {
            _page = Page.Progress;
            _progress = 0.02;
            _status = L.T(9);
            Invalidate();
            var worker = new Thread(Install);
            worker.IsBackground = true;
            worker.Start();
        }

        /// <summary>"Close Nukefy and retry": the app itself stays installed.</summary>
        void Launch()
        {
            var exe = Path.Combine(AppDir, "nukefy_vpn.exe");
            if (!File.Exists(exe)) return;
            try
            {
                Process.Start(new ProcessStartInfo(exe) { WorkingDirectory = AppDir, UseShellExecute = true });
            }
            catch { }
        }

        void Report(double progress, string status)
        {
            try
            {
                BeginInvoke((Action)(() => { _progress = progress; _status = status; Invalidate(); }));
            }
            catch { }
        }

        void Install()
        {
            try
            {
                StopOwnStack();
                Report(0.12, L.T(14));
                ExtractPayload();
                Report(0.55, L.T(15));
                CreateShortcuts();
                Report(0.75, L.T(16));
                WriteUninstallEntry();
                WriteInstallOptions();
                Report(0.9, L.T(17));
                ApplyAutostart();
                Report(1.0, L.T(9));
                BeginInvoke((Action)(() =>
                {
                    _page = Page.Done;
                    Invalidate();
                }));
                if (_launch)
                {
                    BeginInvoke((Action)(() => { Launch(); Close(); }));
                }
            }
            catch (Exception error)
            {
                _error = error.ToString();
                try
                {
                    BeginInvoke((Action)(() => { _page = Page.Failed; Invalidate(); }));
                }
                catch { }
            }
        }

        /// <summary>Reads payload.zip out of our own resources.</summary>
        void ExtractPayload()
        {
            using (var stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("payload.zip"))
            {
                if (stream == null) throw new Exception("payload.zip is missing in the setup exe");
                var incoming = AppDir + ".new";
                if (Directory.Exists(incoming)) Directory.Delete(incoming, true);
                Directory.CreateDirectory(Path.GetDirectoryName(AppDir));
                using (var zip = new ZipArchive(stream, ZipArchiveMode.Read))
                {
                    zip.ExtractToDirectory(incoming);
                }
                // User-editable zapret lists must survive an upgrade.
                var oldLists = Path.Combine(AppDir, "zapret", "lists");
                var newLists = Path.Combine(incoming, "zapret", "lists");
                if (Directory.Exists(oldLists) && Directory.Exists(newLists))
                {
                    foreach (var file in Directory.GetFiles(oldLists, "*-user.txt"))
                        File.Copy(file, Path.Combine(newLists, Path.GetFileName(file)), true);
                }
                if (Directory.Exists(AppDir))
                {
                    try { Directory.Delete(AppDir, true); }
                    catch
                    {
                        // A locked file (code 5) used to abort the whole setup:
                        // move the folder aside instead and let the retry of the
                        // uninstaller clean it later.
                        var graveyard = AppDir + ".old-" + DateTime.Now.Ticks;
                        Directory.Move(AppDir, graveyard);
                    }
                }
                Directory.Move(incoming, AppDir);
            }
        }

        void CreateShortcuts()
        {
            var exe = Path.Combine(AppDir, "nukefy_vpn.exe");
            var startMenu = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonStartMenu),
                "Programs", "Nukefy Client.lnk");
            Shortcut(startMenu, exe);
            if (_desktop)
            {
                var desktop = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonDesktopDirectory),
                    "Nukefy Client.lnk");
                Shortcut(desktop, exe);
            }
        }

        /// <summary>
        /// WScript.Shell through reflection: no Microsoft.CSharp reference and
        /// no dependency on the shell being registered at compile time.
        /// </summary>
        static void Shortcut(string path, string target)
        {
            try
            {
                var type = Type.GetTypeFromProgID("WScript.Shell");
                if (type == null) return;
                var shell = Activator.CreateInstance(type);
                var link = type.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod, null, shell, new object[] { path });
                var linkType = link.GetType();
                linkType.InvokeMember("TargetPath", BindingFlags.SetProperty, null, link, new object[] { target });
                linkType.InvokeMember("WorkingDirectory", BindingFlags.SetProperty, null, link, new object[] { AppDir });
                linkType.InvokeMember("IconLocation", BindingFlags.SetProperty, null, link, new object[] { target + ",0" });
                linkType.InvokeMember("Description", BindingFlags.SetProperty, null, link, new object[] { "Nukefy Client" });
                linkType.InvokeMember("Save", BindingFlags.InvokeMethod, null, link, null);
            }
            catch
            {
                // A missing shortcut must not fail the installation.
            }
        }

        void WriteUninstallEntry()
        {
            var exe = Path.Combine(AppDir, "nukefy_vpn.exe");
            var version = Assembly.GetExecutingAssembly().GetName().Version.ToString(3);
            using (var key = Registry.LocalMachine.CreateSubKey(UninstallKey))
            {
                if (key == null) return;
                var command = "\"" + exe + "\" --uninstall";
                // Both commands point at the app's own branded uninstall window.
                key.SetValue("DisplayName", "Nukefy Client");
                key.SetValue("DisplayVersion", version);
                key.SetValue("Publisher", "@kayorisan");
                key.SetValue("DisplayIcon", exe + ",0");
                key.SetValue("InstallLocation", AppDir);
                key.SetValue("UninstallString", command);
                key.SetValue("QuietUninstallString", command);
                key.SetValue("NoModify", 1, RegistryValueKind.DWord);
                key.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                key.SetValue("EstimatedSize", EstimateSize() / 1024, RegistryValueKind.DWord);
            }
        }

        static long EstimateSize()
        {
            try
            {
                long total = 0;
                foreach (var file in Directory.GetFiles(AppDir, "*", SearchOption.AllDirectories))
                {
                    try { total += new FileInfo(file).Length; } catch { }
                }
                return total;
            }
            catch { return 0; }
        }

        /// <summary>
        /// The app applies these on its next start (autostart goes through its
        /// own scheduled-task code, so there is exactly one implementation).
        /// </summary>
        void WriteInstallOptions()
        {
            var body = new StringBuilder();
            body.Append("{\"version\":\"").Append(Assembly.GetExecutingAssembly().GetName().Version.ToString(3)).Append("\",");
            body.Append("\"autostart\":").Append(_autostart ? "true" : "false").Append(",");
            body.Append("\"desktopShortcut\":").Append(_desktop ? "true" : "false").Append(",");
            body.Append("\"language\":\"").Append(L.Lang == 0 ? "ru" : "en").Append("\"}");
            File.WriteAllText(Path.Combine(AppDir, "install-options.json"), body.ToString(), new UTF8Encoding(false));
        }

        void ApplyAutostart()
        {
            // Kept out of the installer on purpose: the app owns the scheduled
            // task (name, --autostart/--tray arguments) so both stay in sync.
        }

        /// <summary>
        /// Stops only what belongs to Nukefy: the app itself, our scheduled
        /// task's process tree, and winws whose path is inside our folder.
        /// A zapret the user installed themselves is never touched.
        /// </summary>
        static void StopOwnStack()
        {
            Run("sc.exe", "stop nukefy-zapret");
            KillByName("nukefy_vpn");
            KillOwnedByPath("winws", "*nukefy*");
            KillOwnedByPath("sing-box", "*nukefy*");
            KillOwnedByPath("xray", "*nukefy*");
            Thread.Sleep(700);
        }

        static void KillByName(string name)
        {
            foreach (var process in Process.GetProcessesByName(name))
            {
                try { process.Kill(); process.WaitForExit(3000); } catch { }
            }
        }

        static void KillOwnedByPath(string name, string pattern)
        {
            var script = "$p = Get-CimInstance Win32_Process | Where-Object { $_.Name -eq '" + name +
                         ".exe' -and $_.ExecutablePath -like '" + pattern +
                         "' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }; 'done'";
            Run("powershell.exe", "-NoProfile -ExecutionPolicy Bypass -Command \"" + script + "\"");
        }

        static void Run(string file, string arguments)
        {
            try
            {
                var info = new ProcessStartInfo(file, arguments)
                {
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true,
                };
                using (var process = Process.Start(info))
                {
                    if (process == null) return;
                    process.WaitForExit(15000);
                }
            }
            catch { }
        }

        protected override void OnKeyDown(KeyEventArgs e)
        {
            base.OnKeyDown(e);
            if (e.KeyCode == Keys.Escape && _page == Page.Options) Close();
        }
    }
}
