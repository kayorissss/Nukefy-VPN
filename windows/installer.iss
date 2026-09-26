; Inno Setup script for Nukefy VPN (built in GitHub Actions).
#ifndef AppVersion
  #define AppVersion "2.2.0"
#endif
#ifndef SourceDir
  #define SourceDir "..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{7D1D2E7B-4C0A-4E36-9B2E-7A9C3E1F5A10}
AppName=Nukefy VPN
AppVersion={#AppVersion}
AppVerName=Nukefy VPN {#AppVersion}
AppPublisher=@kayorisan
AppPublisherURL=https://github.com/kayorissss/Nukefy-VPN
DefaultDirName={autopf}\Nukefy VPN
DefaultGroupName=Nukefy VPN
UninstallDisplayIcon={app}\nukefy_vpn.exe
OutputDir=..\
OutputBaseFilename=NukefyVPN-Setup-x64
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Nukefy VPN"; Filename: "{app}\nukefy_vpn.exe"
Name: "{group}\{cm:UninstallProgram,Nukefy VPN}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Nukefy VPN"; Filename: "{app}\nukefy_vpn.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\nukefy_vpn.exe"; Description: "{cm:LaunchProgram,Nukefy VPN}"; Flags: nowait postinstall skipifsilent shellexec

[UninstallRun]
Filename: "taskkill"; Parameters: "/F /IM winws.exe"; Flags: runhidden; RunOnceId: "killwinws"
Filename: "taskkill"; Parameters: "/F /IM nukefy_vpn.exe"; Flags: runhidden; RunOnceId: "killapp"
Filename: "schtasks"; Parameters: "/Delete /TN NukefyVPN /F"; Flags: runhidden; RunOnceId: "deltask"
