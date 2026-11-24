Unicode True
!include "MUI2.nsh"
!include "LogicLib.nsh"
Name "Claw’d Companion"
OutFile "${OUTFILE}"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\Programs\Clawd Companion"
SetCompressor /SOLID lzma
ManifestDPIAware true
ShowInstDetails show
VIProductVersion "${VERSION}.0"
VIAddVersionKey /LANG=1033 "ProductName" "Claw’d Companion"
VIAddVersionKey /LANG=1033 "FileVersion" "${VERSION}"
VIAddVersionKey /LANG=1033 "FileDescription" "Claw’d Companion Setup"
VIAddVersionKey /LANG=1033 "LegalCopyright" "ZUMBYTE-AppSolution"
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "German"

Section "Companion"
  SetShellVarContext current
  SetRegView 64
  SetOutPath "$INSTDIR\versions\${VERSION}"
  File /r "${SOURCE}\*.*"
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortcut "$SMPROGRAMS\Clawd Companion.lnk" "$INSTDIR\versions\${VERSION}\ClawdCompanion.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClawdCompanion" "DisplayName" "Claw’d Companion"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClawdCompanion" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClawdCompanion" "Publisher" "ZUMBYTE-AppSolution"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClawdCompanion" "DisplayIcon" "$INSTDIR\versions\${VERSION}\ClawdCompanion.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClawdCompanion" "UninstallString" '"$INSTDIR\Uninstall.exe"'
SectionEnd

Section "Uninstall"
  SetShellVarContext current
  SetRegView 64
  Delete "$SMPROGRAMS\Clawd Companion.lnk"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\ClawdCompanion"
  RMDir /r "$INSTDIR\versions"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
SectionEnd
