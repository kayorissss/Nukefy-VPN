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
const
  // The key Inno itself creates for this AppId.
  UninstallKey = 'Software\Microsoft\Windows\CurrentVersion\Uninstall\{7D1D2E7B-4C0A-4E36-9B2E-7A9C3E1F5A10}_is1';

// Stops OUR stack only: the service is "nukefy-zapret", winws is killed only
// when its path points into our folder, and a zapret the user installed
// themselves (or their WinDivert driver) is never touched.
procedure StopZapretStack();
var
  Code: Integer;
begin
  Exec(ExpandConstant('{sys}\sc.exe'), 'stop nukefy-zapret', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM nukefy_vpn.exe /T', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Exec('powershell.exe',
    '-NoProfile -ExecutionPolicy Bypass -Command "Get-CimInstance Win32_Process | Where-Object { $_.Name -eq ''winws.exe'' -and $_.ExecutablePath -like ''*nukefy*'' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"',
    '', SW_HIDE, ewWaitUntilTerminated, Code);
  Sleep(1500);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  Result := '';
  StopZapretStack();
end;

// "Remove" in the Windows settings must open the app's own branded uninstall
// window, not a bare silent dialog. Inno writes its uninstall entry as the very
// last installation step, so the values have to be corrected here - a
// [Registry] entry would be wiped by the engine right after.
procedure CurStepChanged(CurStep: TSetupStep);
var
  Command: String;
begin
  if CurStep = ssPostInstall then
  begin
    Command := '"' + ExpandConstant('{app}') + '\nukefy_vpn.exe" --uninstall';
    RegWriteStringValue(HKLM, UninstallKey, 'UninstallString', Command);
    RegWriteStringValue(HKLM, UninstallKey, 'QuietUninstallString', Command);
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then StopZapretStack();
end;

[UninstallRun]
; The zapret stack (service, our winws) is stopped from CurUninstallStepChanged
; in [Code], where no parameter quoting games are needed. A foreign zapret's
; processes and drivers are never touched.
Filename: "taskkill"; Parameters: "/F /IM nukefy_vpn.exe"; Flags: runhidden; RunOnceId: "killapp"
Filename: "schtasks"; Parameters: "/Delete /TN NukefyVPN /F"; Flags: runhidden; RunOnceId: "deltask"
