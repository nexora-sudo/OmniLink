; Run after flutter build windows --release, using Inno Setup 6.
[Setup]
AppId={{50EA6CDD-9205-48DD-A146-725EBC338A54}
AppName=OmniLink
AppVersion=0.1.0-alpha
AppPublisher=OmniLink contributors
DefaultDirName={localappdata}\Programs\OmniLink
DefaultGroupName=OmniLink
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\..\dist
OutputBaseFilename=OmniLink-0.1.0-alpha-windows-setup
Compression=lzma2
SolidCompression=yes
LicenseFile=..\..\LICENSE
UninstallDisplayIcon={app}\omnilink.exe

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\OmniLink"; Filename: "{app}\omnilink.exe"

[Registry]
Root: HKCU; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueName: "OmniLink"; Flags: uninsdeletevalue

[Run]
Filename: "{app}\omnilink.exe"; Description: "Abrir OmniLink"; Flags: nowait postinstall skipifsilent
