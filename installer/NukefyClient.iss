; Nukefy Client — Windows installer (Inno Setup 6).
;
; Behaviour the users asked for:
;  * monochrome (black-and-white) wizard, no foreign green/blue artwork;
;  * installing over an old "Nukefy VPN" (or an older Nukefy Client)
;    closes the running app, runs the old uninstaller when one exists,
;    removes the legacy install folder and replaces the program in place,
;    so there is never a second copy left on the machine;
;  * per-user install, no administrator rights required.

#define AppName "Nukefy Client"
#define AppVersion "1.1.0"
#define AppExe "nukefy_vpn.exe"
; Stable identity of the NEW product. The legacy "Nukefy VPN" product is
; detected by display name below and removed explicitly.
#define AppId "{{8F3A2C41-6D9E-4B7A-9E21-5C0F7A1D44B2}"

[Setup]
AppId={#AppId}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=kayorisan
AppPublisherURL=https://github.com/kayorissss/Nukefy-VPN
DefaultDirName={localappdata}\Programs\Nukefy Client
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputBaseFilename=NukefyClient-Setup
SetupIconFile=..\assets\icons\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
WizardStyle=modern
WizardImageFile=wizard.bmp
WizardSmallImageFile=wizard_small.bmp
WizardImageStretch=yes
DisableWelcomePage=no
CloseApplications=yes
CloseApplicationsFilter={#AppExe}
RestartApplications=no
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes

[Languages]
Name: "russian"; MessagesFile: "compiler:Languages\Russian.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; Flutter Windows release payload (staged by the release workflow and by
; `flutter build windows` locally).
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[Code]
const
  UninstallRoots =
    'Software\Microsoft\Windows\CurrentVersion\Uninstall';

{ Kill the running app (any historical exe name) so files are not locked
  and the old copy never survives next to the new one. Core processes are
  children of the app and are stopped by the app itself on exit; the taskkill
  /T also takes the whole tree down. }
procedure KillRunningApp();
var
  ResultCode: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM nukefy_vpn.exe',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM NukefyVPN.exe',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM "Nukefy VPN.exe"',
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
end;

{ Run the uninstaller of a previous "Nukefy VPN"/"NukefyVPN" product when
  one is registered, whatever AppId it used. }
procedure RemoveLegacyByDisplayName();
var
  Roots: array[0..1] of Integer;
  RootKey: Integer;
  Subkeys: TArrayOfString;
  R, I: Integer;
  Key, DisplayName, UninstallString, QuietString: String;
  ResultCode: Integer;
begin
  Roots[0] := HKCU;
  Roots[1] := HKLM;
  for R := 0 to 1 do
  begin
    RootKey := Roots[R];
    if RegGetSubkeyNames(RootKey, UninstallRoots, Subkeys) then
    begin
      for I := 0 to GetArrayLength(Subkeys) - 1 do
      begin
        Key := UninstallRoots + '\' + Subkeys[I];
        if RegQueryStringValue(RootKey, Key, 'DisplayName', DisplayName) then
        begin
          if (Pos('Nukefy VPN', DisplayName) > 0) or
             (Pos('NukefyVPN', DisplayName) > 0) then
          begin
            if RegQueryStringValue(RootKey, Key, 'QuietUninstallString', QuietString) then
              { QuietUninstallString contains exe + args in one string: run via cmd. }
              Exec(ExpandConstant('{cmd}'), '/C ' + QuietString, '',
                SW_HIDE, ewWaitUntilTerminated, ResultCode)
            else if RegQueryStringValue(RootKey, Key, 'UninstallString', UninstallString) then
              Exec(ExpandConstant('{cmd}'),
                '/C ' + UninstallString + ' /SILENT /SUPPRESSMSGBOXES /NORESTART', '',
                SW_HIDE, ewWaitUntilTerminated, ResultCode);
          end;
        end;
      end;
    end;
  end;
end;

{ ZIP installs of the old version have no uninstaller: delete their known
  folders (only when they really contain the old exe and are not {app}). }
procedure RemoveLegacyFolders();
var
  Candidates: array of String;
  I: Integer;
  Dir: String;
begin
  SetArrayLength(Candidates, 4);
  Candidates[0] := ExpandConstant('{localappdata}\Programs\Nukefy VPN');
  Candidates[1] := ExpandConstant('{localappdata}\Programs\NukefyVPN');
  Candidates[2] := ExpandConstant('{pf}\Nukefy VPN');
  Candidates[3] := ExpandConstant('{pf}\NukefyVPN');
  for I := 0 to GetArrayLength(Candidates) - 1 do
  begin
    Dir := Candidates[I];
    if (CompareText(Dir, ExpandConstant('{app}')) <> 0) and
       FileExists(Dir + '\nukefy_vpn.exe') then
      DelTree(Dir, True, True, True);
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  KillRunningApp();
  RemoveLegacyByDisplayName();
  RemoveLegacyFolders();
  Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    RemoveLegacyFolders();
end;
