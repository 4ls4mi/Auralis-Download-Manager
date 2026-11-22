Unicode true
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetCompressorDictSize 16

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"

!define PRODUCT "Auralis Download Manager"
!define APP_EXE "auralis-download-manager.exe"
!define INSTALL_KEY "Software\misterhybrid\${PRODUCT}"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT}"
!define DEFAULT_DIRECTORY "auralis-default\${PRODUCT}"

Name "${PRODUCT}"
Caption "${PRODUCT} ${VERSION}"
OutFile "${OUTPUT}"
InstallDir "${DEFAULT_DIRECTORY}"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${PRODUCT}"
VIAddVersionKey "FileDescription" "${PRODUCT} Setup"
VIAddVersionKey "CompanyName" "Auralis"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Auralis contributors"
!define MUI_ICON "${ICON}"
!define MUI_UNICON "${ICON}"

Var Passive
Var Upgrade
Var NoRegistration
Var Relaunch
Var LaunchArguments

!define MUI_PAGE_CUSTOMFUNCTION_PRE SkipInPassiveMode
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_PAGE_CUSTOMFUNCTION_PRE SkipInPassiveMode
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Function .onInit
    ${IfNot} ${RunningX64}
        MessageBox MB_ICONSTOP|MB_OK "This Auralis installer requires 64-bit Windows." /SD IDOK
        SetErrorLevel 1
        Abort
    ${EndIf}
    SetShellVarContext current
    ${GetParameters} $0
    ${GetOptions} $0 "/P" $1
    ${IfNot} ${Errors}
        StrCpy $Passive 1
    ${EndIf}
    ${GetOptions} $0 "/UPDATE" $1
    ${IfNot} ${Errors}
        StrCpy $Upgrade 1
    ${EndIf}
    ${GetOptions} $0 "/R" $1
    ${IfNot} ${Errors}
        StrCpy $Relaunch 1
    ${EndIf}
    ${GetOptions} $0 "/ARGS=" $LaunchArguments
    ${If} ${Errors}
        ${GetOptions} $0 "/ARGS" $LaunchArguments
    ${EndIf}
    ${GetOptions} $0 "/NOREG" $1
    ${IfNot} ${Errors}
        StrCpy $NoRegistration 1
        ${If} $INSTDIR == "${DEFAULT_DIRECTORY}"
            SetErrorLevel 1
            Abort
        ${EndIf}
    ${EndIf}

    # /D= takes precedence. Otherwise update the previous Tauri installation in place.
    ${If} $INSTDIR == "${DEFAULT_DIRECTORY}"
        StrCpy $INSTDIR "$LOCALAPPDATA\${PRODUCT}"
        ReadRegStr $0 HKCU "${INSTALL_KEY}" ""
        ${If} $0 != ""
        ${AndIf} ${FileExists} "$0\${APP_EXE}"
            StrCpy $INSTDIR $0
        ${EndIf}
    ${EndIf}
FunctionEnd

Function SkipInPassiveMode
    ${If} $Passive == 1
    ${OrIf} $Upgrade == 1
        Abort
    ${EndIf}
FunctionEnd

# Refuse an in-use install before copying files. Leave a running instance and its data alone.
Function AssertReplaceable
    Exch $0
    Push $1
    ${If} ${FileExists} "$0"
        System::Call 'kernel32::CreateFileW(w r0, i 0x40000000, i 7, p 0, i 3, i 0x80, p 0) i.r1'
        ${If} $1 == -1
            MessageBox MB_ICONSTOP|MB_OK "Close Auralis and its browser connections, then run the installer again." /SD IDOK
            SetErrorLevel 5
            Abort
        ${EndIf}
        System::Call 'kernel32::CloseHandle(i r1)'
    ${EndIf}
    Pop $1
    Pop $0
FunctionEnd

Section "Install Auralis"
    Push "$INSTDIR\${APP_EXE}"
    Call AssertReplaceable
    Push "$INSTDIR\auralis-browser-host.exe"
    Call AssertReplaceable
    SetAutoClose true
    ClearErrors
    SetOutPath "$INSTDIR"
    File /r "${PAYLOAD}\*"
    WriteUninstaller "$INSTDIR\uninstall.exe"
    IfErrors install_failed

    ${If} $NoRegistration != 1
        WriteRegStr HKCU "${INSTALL_KEY}" "" "$INSTDIR"
        WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "${PRODUCT}"
        WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
        WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "Auralis"
        WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$\"$INSTDIR$\""
        WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$\"$INSTDIR\${APP_EXE}$\""
        WriteRegStr HKCU "${UNINSTALL_KEY}" "MainBinaryName" "${APP_EXE}"
        WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
        WriteRegStr HKCU "${UNINSTALL_KEY}" "URLInfoAbout" "https://github.com/4ls4mi/Auralis-Download-Manager"
        WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
        WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
        CreateShortCut "$SMPROGRAMS\${PRODUCT}.lnk" "$INSTDIR\${APP_EXE}"
    ${EndIf}
    Goto installed

install_failed:
    MessageBox MB_ICONSTOP|MB_OK "Auralis could not write all installation files. Check free disk space and close any open Auralis windows." /SD IDOK
    SetErrorLevel 2
    Abort
installed:
SectionEnd

Function .onInstSuccess
    ${If} $Relaunch == 1
        Exec '"$INSTDIR\${APP_EXE}" $LaunchArguments'
    ${EndIf}
FunctionEnd

Function un.onInit
    SetShellVarContext current
    ${GetParameters} $0
    ${GetOptions} $0 "/NOREG" $1
    ${IfNot} ${Errors}
        StrCpy $NoRegistration 1
    ${EndIf}
FunctionEnd

Section "Uninstall"
    # Only the files installed by this package are removed.
    !include "${UNINSTALL_FILES}"
    Delete "$INSTDIR\uninstall.exe"
    ${If} $NoRegistration != 1
        ReadRegStr $0 HKCU "${INSTALL_KEY}" ""
        ${If} $0 == $INSTDIR
            DeleteRegKey HKCU "${INSTALL_KEY}"
            DeleteRegKey HKCU "${UNINSTALL_KEY}"
            Delete "$SMPROGRAMS\${PRODUCT}.lnk"
            Delete "$DESKTOP\${PRODUCT}.lnk"
            DeleteRegValue HKCU "Software\Microsoft\Windows\CurrentVersion\Run" "${PRODUCT}"
        ${EndIf}
    ${EndIf}
    RMDir "$INSTDIR"
SectionEnd
