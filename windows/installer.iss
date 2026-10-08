; Inno Setup script for Nukefy VPN (built in GitHub Actions).
#ifndef AppVersion
  #define AppVersion "2.2.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{7D1D2E7B-4C0A-4E36-9B2E-7A9C3E1F5A10}
AppName=Nukefy Client
AppVersion={#AppVersion}
AppVerName=Nukefy Client {#AppVersion}
AppPublisher=@kayorisan
AppPublisherURL=https://github.com/kayorissss/Nukefy-VPN
DefaultDirName={autopf}\Nukefy VPN
DefaultGroupName=Nukefy VPN
UninstallDisplayIcon={app}\nukefy_vpn.exe
OutputDir=..\
OutputBaseFilename=NukefyVPN-Setup-x64
SetupIconFile=runner\resources\app_icon.ico
; Do not pack the installer with an obfuscating/high-compression profile.
; A transparent ZIP payload is larger but is easier for SmartScreen and AV
; engines to inspect and does not change the runtime DPI implementation.
Compression=zip
SolidCompression=no
WizardStyle=modern
; Branded wizard: the client logo in the header and the artwork people know
; from the app splash on the sidebar of the welcome/finish pages.
WizardImageFile=installer_art\wizard_big.bmp
WizardSmallImageFile=installer_art\small.bmp
WizardImageStretch=yes
ShowLanguageDialog=auto
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

; Shown on the language picker and the welcome page.
[CustomMessages]
english.WelcomeLabel1=Welcome to Nukefy Client Setup
russian.WelcomeLabel1=Установка Nukefy Client
english.WelcomeLabel2=The setup will install Nukefy Client on your computer.%n%nLater, remove the app through its own window "Uninstall Nukefy Client" - do not delete the folder by hand.
russian.WelcomeLabel2=Программа установит Nukefy Client на ваш компьютер.%n%nУдалять приложение нужно через его собственное окно «Удалить Nukefy Client» — не удаляйте папку вручную.
english.FinishedLabel=The installation is complete.
russian.FinishedLabel=Установка завершена.

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; The WinDivert driver binaries stay locked by the kernel while the zapret
; service (or a stray winws.exe) is alive. PrepareToInstall stops the stack
; first; restartreplace is the last-resort fallback so an upgrade never dies
; with "DeleteFile: code 5" again.
Source: "{#SourceDir}\zapret\bin\WinDivert64.sys"; DestDir: "{app}\zapret\bin"; Flags: ignoreversion restartreplace skipifsourcedoesntexist
Source: "{#SourceDir}\zapret\bin\WinDivert32.sys"; DestDir: "{app}\zapret\bin"; Flags: ignoreversion restartreplace skipifsourcedoesntexist
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "zapret\bin\WinDivert64.sys,zapret\bin\WinDivert32.sys"

[Icons]
Name: "{group}\Nukefy VPN"; Filename: "{app}\nukefy_vpn.exe"
Name: "{group}\{cm:UninstallProgram,Nukefy VPN}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Nukefy VPN"; Filename: "{app}\nukefy_vpn.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\nukefy_vpn.exe"; Description: "{cm:LaunchProgram,Nukefy VPN}"; Flags: nowait postinstall skipifsilent shellexec

[Code]
// Stops the zapret service, kills winws and unloads the WinDivert kernel
// driver so locked binaries (WinDivert64.sys) can be replaced or deleted.
procedure StopZapretStack();
var
  Code: Integer;
begin
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop zapret', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM winws.exe /T', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop WinDivert', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop WinDivert14', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop WinDivert2', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Sleep(2000);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  StopZapretStack();
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then StopZapretStack();
end;

; Uninstall points at the app's own window: "Remove" in the Windows settings
; opens the branded screen with the checkboxes, and the app then deletes its
; own files with an elevated helper.
[Registry]
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{{7D1D2E7B-4C0A-4E36-9B2E-7A9C3E1F5A10}_is1"; ValueType: string; ValueName: "UninstallString"; ValueData: "\"{app}\nukefy_vpn.exe\" --uninstall"
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Uninstall\{{7D1D2E7B-4C0A-4E36-9B2E-7A9C3E1F5A10}_is1"; ValueType: string; ValueName: "QuietUninstallString"; ValueData: "\"{app}\nukefy_vpn.exe\" --uninstall"

[UninstallRun]
Filename: "taskkill"; Parameters: "/F /IM winws.exe"; Flags: runhidden; RunOnceId: "killwinws"
Filename: "taskkill"; Parameters: "/F /IM nukefy_vpn.exe"; Flags: runhidden; RunOnceId: "killapp"
Filename: "schtasks"; Parameters: "/Delete /TN NukefyVPN /F"; Flags: runhidden; RunOnceId: "deltask"
