; Silicon LogiX / SLX CellProof
; Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
; Author: Marco Pezzullo
; License: Silicon LogiX Evaluation License 1.0. See LICENSE.

#ifndef RuntimeDir
  #error RuntimeDir must point to an audited runtime package
#endif
#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef OutputDir
  #error OutputDir is required
#endif
#ifndef AppId
  #define AppId "SiliconLogix.CellProof"
#endif
#ifndef AppMutexName
  #define AppMutexName "Local\SLX.CellProof.Running"
#endif
#ifndef OutputName
  #define OutputName "slx-cellproof-" + AppVersion + "-windows-x64-setup"
#endif

[Setup]
AppId={#AppId}
AppName=SLX CellProof
AppVersion={#AppVersion}
AppPublisher=Silicon LogiX
AppPublisherURL=https://www.siliconlogix.it/
AppSupportURL=https://github.com/Silicon-Logix/slx-cellproof/issues
AppUpdatesURL=https://github.com/Silicon-Logix/slx-cellproof/releases
DefaultDirName={localappdata}\Programs\Silicon LogiX\CellProof
DefaultGroupName=Silicon LogiX\CellProof
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
LicenseFile={#RuntimeDir}\LICENSE
SetupIconFile=..\godot\assets\cellproof.ico
UninstallDisplayIcon={app}\CellProof.exe
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2/normal
SolidCompression=yes
DiskSpanning=no
AppMutex={#AppMutexName}
SetupMutex=Local\{#AppId}.Setup
CloseApplications=no
RestartApplications=no
ChangesAssociations=yes
VersionInfoVersion={#AppVersion}.0
VersionInfoCompany=Silicon LogiX
VersionInfoDescription=SLX CellProof installer
VersionInfoCopyright=Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
#ifdef SignedRelease
SignTool=slxsign
SignedUninstaller=yes
#else
SignedUninstaller=no
AppVerName=SLX CellProof {#AppVersion} Preview (unsigned)
#endif

[Languages]
Name: english; MessagesFile: compiler:Default.isl

[Tasks]
Name: desktopicon; Description: Create a desktop shortcut; Flags: unchecked
Name: associatefiles; Description: Associate .cellproof projects with CellProof

[Files]
Source: "{#RuntimeDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\CellProof"; Filename: "{app}\CellProof.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\CellProof"; Filename: "{app}\CellProof.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Registry]
Root: HKCU; Subkey: "Software\Classes\.cellproof"; ValueType: string; ValueName: ""; ValueData: "{#AppId}.Project"; Flags: uninsdeletevalue; Tasks: associatefiles
Root: HKCU; Subkey: "Software\Classes\{#AppId}.Project"; ValueType: string; ValueName: ""; ValueData: CellProof project; Flags: uninsdeletekey; Tasks: associatefiles
Root: HKCU; Subkey: "Software\Classes\{#AppId}.Project\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\CellProof.exe,0"; Tasks: associatefiles
Root: HKCU; Subkey: "Software\Classes\{#AppId}.Project\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\CellProof.exe"" -- ""%1"""; Tasks: associatefiles

[Run]
Filename: "{app}\CellProof.exe"; Description: Launch CellProof; WorkingDir: "{app}"; Flags: nowait postinstall skipifsilent

[Code]
function VersionPart(Value: String; Index: Integer): Integer;
var
  I, Dot: Integer;
begin
  for I := 0 to Index - 1 do begin
    Dot := Pos('.', Value);
    if Dot = 0 then begin Result := 0; Exit; end;
    Delete(Value, 1, Dot);
  end;
  Dot := Pos('.', Value);
  if Dot > 0 then Value := Copy(Value, 1, Dot - 1);
  Result := StrToIntDef(Value, 0);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  Installed: String;
  I, ExistingPart, NewPart: Integer;
begin
  Result := '';
  if ExpandConstant('{param:ALLOWDOWNGRADE|0}') = '1' then Exit;
  if GetVersionNumbersString(ExpandConstant('{app}\CellProof.exe'), Installed) then begin
    for I := 0 to 3 do begin
      ExistingPart := VersionPart(Installed, I);
      NewPart := VersionPart('{#AppVersion}', I);
      if ExistingPart > NewPart then begin
        Result := 'A newer CellProof version is already installed. Use a verified previous installer with /ALLOWDOWNGRADE=1 only when deliberately restoring an older version.';
        Exit;
      end;
      if ExistingPart < NewPart then Exit;
    end;
  end;
end;
