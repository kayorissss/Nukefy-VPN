; Nukefy Client — Windows installer (Inno Setup 6).
;
; Why this file exists: the previous setup was a hand-written WinForms
; self-extractor. It unpacked the payload itself and wrote its own
; "Programs and features" entry whose UninstallString pointed back at the
; application ("NukefyClient.exe --uninstall"). Clicking Remove in Windows
; Settings therefore launched the app instead of removing it, and there was no
; uninstaller to fall back to. Inno Setup ships a real uninstaller
; (unins000.exe), writes the standard Add/Remove entry, supports silent
; uninstall for the updater and cleans up after itself.
;
; Build (CI):
;   ISCC.exe /DAppVersion=1.2.0 /DSourceDir=<...>\Release Nukefy.iss
;
; The AppId is the one the old installer used, so an existing installation is
; upgraded in place: Windows keeps a single entry and the stale brand-string
; registry values (UninstallString/QuietUninstallString) are overwritten by
; Inno with the real uninstaller.

#define AppName "Nukefy Client"
#define AppExeName "NukefyClient.exe"
#define AppPublisher "kayorisan"
#define AppUrl "https://t.me/kayorisan"
#define AppReleases "https://github.com/kayorissss/Nukefy-VPN/releases"

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
; Same AppId as the previous installer: an upgrade replaces the old entry
; instead of creating a second "Nukefy" in Programs and features.
AppId={{7D1D2E7B-4C0A-4E36-9B2E-7A9C3E1F5A10}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}
AppUpdatesURL={#AppReleases}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} setup
VersionInfoProductName={#AppName}
DefaultDirName={autopf}\Nukefy Client
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableWelcomePage=no
OutputDir=..\..\dist
OutputBaseFilename=NukefyClient-{#AppVersion}-x64
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
WizardStyle=modern
WizardImageFile=..\installer_art\wizard.bmp
WizardSmallImageFile=..\installer_art\small.bmp
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
; The client itself needs administrator rights (TUN adapter + WinDivert), so
; the installer asks for them once. Uninstall uses the same elevation.
CloseApplications=no
RestartApplications=no
AllowNoIcons=yes
; Non-solid ZIP keeps the payload inspectable by antivirus products, which is
; the policy described in RELEASE_SECURITY.md (packed payloads get flagged).
Compression=zip
SolidCompression=no
SetupLogging=yes
UsePreviousAppDir=yes
UsePreviousTasks=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"
; Autostart is off by default on purpose: a VPN client that opens a maximised
; window at every logon is the first thing people disable. When it is ticked,
; the app starts hidden in the tray (see install-options.json below).
Name: "autostart"; Description: "{cm:AutoStartProgram,{#AppName}}"; GroupDescription: "{cm:AutoStartProgramGroupDescription}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "..\..\README.md"; DestDir: "{app}"; Flags: ignoreversion isreadme

[InstallDelete]
; Files that belonged to the old self-extractor / older builds and must not
; survive an upgrade. Never touch user data or zapret lists here.
Type: files; Name: "{app}\install-options.json"
Type: files; Name: "{app}\NukefyVPN.exe"
Type: files; Name: "{app}\payload.zip"
Type: files; Name: "{app}\unins000.dat"
Type: filesandordirs; Name: "{app}\logs"

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(AppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; Only our own service and our own capture: a zapret installed by the user
; (service name "zapret") is left alone.
Filename: "{sys}\sc.exe"; Parameters: "stop nukefy-zapret"; Flags: runhidden; RunOnceId: "StopZapret"
Filename: "{sys}\sc.exe"; Parameters: "delete nukefy-zapret"; Flags: runhidden; RunOnceId: "DeleteZapret"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""NukefyVPN"" /F"; Flags: runhidden; RunOnceId: "DelTaskOld"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""Nukefy Client"" /F"; Flags: runhidden; RunOnceId: "DelTaskNew"

[UninstallDelete]
; Everything the app writes into its own folder (logs, generated configs).
Type: filesandordirs; Name: "{app}\logs"
Type: files; Name: "{app}\*.log"
Type: files; Name: "{app}\install-options.json"
Type: dirifempty; Name: "{app}"

[Code]
function JsonBool(Value: Boolean): String;
begin
  if Value then
    Result := 'true'
  else
    Result := 'false';
end;

{ Both the bundled cores and the copies the app keeps in %APPDATA% must be
  stopped, but only if they belong to this installation. A sing-box started by
  another product is never touched. }
procedure StopOurProcesses();
var
  ResultCode: Integer;
  Script: String;
begin
  Script :=
    'Get-CimInstance Win32_Process | Where-Object { ' +
    '$_.Name -in @(''NukefyClient.exe'',''sing-box.exe'',''xray.exe'',''winws.exe'') -and (' +
    '$_.ExecutablePath -like ''' + ExpandConstant('{app}') + '\*'' -or ' +
    '$_.ExecutablePath -like ''*KAYORI-SAN\Nukefy Client\*'' -or ' +
    '$_.ExecutablePath -like ''*kayorisan\Nukefy VPN\*'') } | ' +
    'ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }';
  Exec('powershell.exe', '-NoProfile -ExecutionPolicy Bypass -Command "' + Script + '"', '',
    SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

{ The old setup could leave a second, dead "Nukefy" entry behind (the C#
  installer plus an older Inno layout). Remove only our own identifiers. }
procedure RemoveLegacyEntries();
var
  ResultCode: Integer;
begin
  Exec('schtasks.exe', '/Delete /TN "NukefyVPN" /F', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  DelTree(ExpandConstant('{commonappdata}\Microsoft\Windows\Start Menu\Programs\Nukefy VPN'), True, True, True);
  DelTree(ExpandConstant('{autopf}\Nukefy VPN'), True, True, True);
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  Options: String;
begin
  if CurStep = ssInstall then
  begin
    StopOurProcesses();
    RemoveLegacyEntries();
  end;
  if CurStep = ssPostInstall then
  begin
    { Hand the wizard choices to the application: it owns autostart (scheduled
      task with highest privileges) and removes a stale desktop shortcut.
      autostart always means "start hidden in the tray" — nobody wants a
      maximised VPN window at every logon. }
    Options :=
      '{"autostart":' + JsonBool(WizardIsTaskSelected('autostart')) + ',' +
      '"startInTray":true,' +
      '"desktopShortcut":' + JsonBool(WizardIsTaskSelected('desktopicon')) + '}';
    SaveStringToFile(ExpandConstant('{app}\install-options.json'), Options, False);
  end;
end;

procedure CurUninstallStepChanged(CurStep: TUninstallStep);
var
  DataDir: String;
begin
  if CurStep = usUninstall then
    StopOurProcesses();

  if CurStep = usPostUninstall then
  begin
    { User data lives in %APPDATA%\KAYORI-SAN\Nukefy Client (Roaming) and in
      the portable launcher folder. Ask once in the interactive uninstaller;
      a silent uninstall (the in-app "remove" and the updater) keeps data so
      an upgrade never loses subscriptions. }
    if not UninstallSilent then
    begin
      if MsgBox('Удалить также подписки, настройки, историю и скачанные ядра?',
        mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      begin
        DataDir := ExpandConstant('{userappdata}\KAYORI-SAN\Nukefy Client');
        DelTree(DataDir, True, True, True);
        DataDir := ExpandConstant('{userappdata}\kayorisan\Nukefy VPN');
        DelTree(DataDir, True, True, True);
        DataDir := ExpandConstant('{localappdata}\NukefyVPN');
        DelTree(DataDir, True, True, True);
      end;
    end;
    { Leftovers an interrupted upgrade may have produced. }
    DelTree(ExpandConstant('{app}\logs'), True, True, True);
  end;
end;
