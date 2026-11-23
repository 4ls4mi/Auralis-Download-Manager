Unicode true
RequestExecutionLevel user
CRCCheck force
SetCompressor /SOLID lzma
SetCompressorDictSize 16

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "x64.nsh"
!include "nsDialogs.nsh"

!define PRODUCT "Auralis Download Manager"
!define PUBLISHER "Alsami"
!define APP_EXE "auralis-download-manager.exe"
!define INSTALL_KEY "Software\misterhybrid\${PRODUCT}"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT}"
!define PREFERENCES_KEY "Software\Auralis\${PRODUCT}"
!define DEFAULT_DIRECTORY "auralis-default\${PRODUCT}"

Name "${PRODUCT}"
Caption "${PRODUCT} ${VERSION}"
OutFile "${OUTPUT}"
InstallDir "${DEFAULT_DIRECTORY}"
VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${PRODUCT}"
VIAddVersionKey "FileDescription" "${PRODUCT} Setup"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
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
Var DeleteAppData
Var DeleteSharedProfile
Var AppDataCheckbox
Var SharedProfileCheckbox

!define MUI_PAGE_CUSTOMFUNCTION_PRE SkipInPassiveMode
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!define MUI_PAGE_CUSTOMFUNCTION_PRE SkipInPassiveMode
!define MUI_FINISHPAGE_RUN "$INSTDIR\${APP_EXE}"
!insertmacro MUI_PAGE_FINISH
UninstPage custom un.Confirm un.ConfirmLeave
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
        WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "${PUBLISHER}"
        WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$\"$INSTDIR$\""
        WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$\"$INSTDIR\${SHORTCUT_ICON}$\",0"
        WriteRegStr HKCU "${UNINSTALL_KEY}" "MainBinaryName" "${APP_EXE}"
        WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" "$\"$INSTDIR\uninstall.exe$\""
        WriteRegStr HKCU "${UNINSTALL_KEY}" "URLInfoAbout" "https://github.com/4ls4mi/Auralis-Download-Manager"
        WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
        WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
        # Refresh this installer-owned Start menu shortcut without modifying taskbar pins.
        StrCpy $0 0x0002 # SHCNE_CREATE
        ${If} ${FileExists} "$SMPROGRAMS\${PRODUCT}.lnk"
            StrCpy $0 0x2000 # SHCNE_UPDATEITEM
        ${EndIf}
        CreateShortCut "$SMPROGRAMS\${PRODUCT}.lnk" "$INSTDIR\${APP_EXE}" "" "$INSTDIR\${SHORTCUT_ICON}" 0
        # SHCNF_PATHW | SHCNF_FLUSHNOWAIT
        System::Call 'shell32::SHChangeNotify(i r0, i 0x2005, w "$SMPROGRAMS\${PRODUCT}.lnk", p 0)'
    ${EndIf}
    Goto installed

install_failed:
    MessageBox MB_ICONSTOP|MB_OK "Auralis could not write all installation files. Check free disk space and close any open Auralis windows." /SD IDOK
    SetErrorLevel 2
    Abort
installed:
SectionEnd

Function .onInstSuccess
    ${If} $NoRegistration != 1
        # Refresh the existing executable icon without changing taskbar grouping.
        ExecWait '"$INSTDIR\${APP_EXE}" --refresh-taskbar-icon' $0
    ${EndIf}
    ${If} $Relaunch == 1
        Exec '"$INSTDIR\${APP_EXE}" $LaunchArguments'
    ${EndIf}
FunctionEnd

Function un.onInit
    SetShellVarContext current
    StrCpy $DeleteAppData ${BST_UNCHECKED}
    StrCpy $DeleteSharedProfile ${BST_UNCHECKED}
    ${GetParameters} $0
    ${GetOptions} $0 "/NOREG" $1
    ${IfNot} ${Errors}
        StrCpy $NoRegistration 1
    ${EndIf}
FunctionEnd

Function un.Confirm
    !insertmacro MUI_HEADER_TEXT "Uninstall Auralis" "Remove ${PRODUCT} from this computer."
    nsDialogs::Create 1018
    Pop $0
    ${If} $0 == "error"
        Abort
    ${EndIf}
    GetDlgItem $0 $HWNDPARENT 1
    ${NSD_SetText} $0 "Uninstall"

    ${NSD_CreateLabel} 0 0 100% 25u "Installation folder:$\r$\n$INSTDIR"
    Pop $0
    StrCpy $AppDataCheckbox ""
    StrCpy $SharedProfileCheckbox ""

    Call un.CanDeleteAppData
    ${If} $1 == 1
        ${NSD_CreateCheckbox} 0 30u 100% 12u "Delete app data"
        Pop $AppDataCheckbox
        ${NSD_SetState} $AppDataCheckbox ${BST_UNCHECKED}
        ${NSD_CreateLabel} 12u 45u 93% 23u "Remove Auralis preferences, managed font copies, helper tools and update cache."
        Pop $0

        Call un.FindSharedProfile
        ${If} $1 == 1
            ${NSD_CreateCheckbox} 0 70u 100% 12u "Also clear shared download history and settings"
            Pop $SharedProfileCheckbox
            ${NSD_SetState} $SharedProfileCheckbox ${BST_UNCHECKED}
            EnableWindow $SharedProfileCheckbox 0
            ${NSD_CreateLabel} 12u 85u 93% 32u "Mister Download Manager may also use this history and these settings. Your downloaded files and custom or portable profiles are kept."
            Pop $0
            ${NSD_OnClick} $AppDataCheckbox un.ToggleSharedProfile
        ${Else}
            ${NSD_CreateLabel} 0 75u 100% 24u "Downloaded files and custom or portable profiles are kept."
            Pop $0
        ${EndIf}
    ${Else}
        ${NSD_CreateLabel} 0 30u 100% 24u "App data and downloaded files will be kept."
        Pop $0
    ${EndIf}

    nsDialogs::Show
FunctionEnd

Function un.ToggleSharedProfile
    Pop $0
    ${NSD_GetState} $AppDataCheckbox $0
    ${If} $0 == ${BST_CHECKED}
        EnableWindow $SharedProfileCheckbox 1
    ${Else}
        ${NSD_SetState} $SharedProfileCheckbox ${BST_UNCHECKED}
        EnableWindow $SharedProfileCheckbox 0
    ${EndIf}
FunctionEnd

Function un.ConfirmLeave
    ${If} $AppDataCheckbox != ""
        ${NSD_GetState} $AppDataCheckbox $DeleteAppData
    ${EndIf}
    ${If} $SharedProfileCheckbox != ""
        ${NSD_GetState} $SharedProfileCheckbox $DeleteSharedProfile
    ${EndIf}
FunctionEnd

# Do not clean shared user data from an unregistered, superseded or portable copy.
Function un.CanDeleteAppData
    StrCpy $1 0
    ${If} $NoRegistration == 1
        Return
    ${EndIf}
    ReadRegStr $0 HKCU "${INSTALL_KEY}" ""
    ${If} $0 != $INSTDIR
        Return
    ${EndIf}
    System::Call 'kernel32::GetFileAttributesW(w "$INSTDIR\data") i.r0'
    ${If} $0 = -1
        StrCpy $1 1
    ${EndIf}
FunctionEnd

# Read a directory's attributes without following a reparse point.
Function un.IsOrdinaryDirectory
    System::Call 'kernel32::GetFileAttributesW(w r0) i.r1'
    IntOp $1 $1 & 0x410
    ${If} $1 = 0x10
        StrCpy $1 1
    ${Else}
        StrCpy $1 0
    ${EndIf}
FunctionEnd

Function un.FindSharedProfile
    ReadEnvStr $0 "MDM_DATA_DIR"
    ${If} $0 != ""
        StrCpy $1 0
        Return
    ${EndIf}
    StrCpy $0 "$APPDATA"
    Call un.IsOrdinaryDirectory
    ${If} $1 != 1
        Return
    ${EndIf}
    StrCpy $0 "$APPDATA\misterdownloadmanager"
    Call un.IsOrdinaryDirectory
    ${If} $1 == 1
        System::Call 'kernel32::GetFileAttributesW(w "$0\auralis-interface-version") i.r1'
        IntOp $1 $1 & 0x410
        ${If} $1 = 0
            StrCpy $1 1
        ${Else}
            StrCpy $1 0
        ${EndIf}
    ${EndIf}
FunctionEnd

# This traversal is used only for dedicated Auralis-managed directories.
# NSIS RMDir /r follows directory junctions, so never use it here.
Function un.RemoveManagedDirectory
    Push $1
    Push $2
    Push $3
    Push $4
    Call un.IsOrdinaryDirectory
    ${If} $1 == 1
        ClearErrors
        FindFirst $2 $3 "$0\*"
        ${IfNot} ${Errors}
            ${Do}
                ${If} $3 != "."
                ${AndIf} $3 != ".."
                    System::Call 'kernel32::GetFileAttributesW(w "$0\$3") i.r4'
                    IntOp $4 $4 & 0x410
                    ${If} $4 = 0x10
                        Push $0
                        StrCpy $0 "$0\$3"
                        Call un.RemoveManagedDirectory
                        Pop $0
                    ${ElseIf} $4 = 0
                        Delete "$0\$3"
                    ${EndIf}
                ${EndIf}
                ClearErrors
                FindNext $2 $3
            ${LoopUntil} ${Errors}
            FindClose $2
        ${EndIf}
        RMDir "$0"
    ${EndIf}
    Pop $4
    Pop $3
    Pop $2
    Pop $1
FunctionEnd

Function un.RemoveAppData
    DeleteRegKey HKCU "${PREFERENCES_KEY}"

    StrCpy $0 "$APPDATA"
    Call un.IsOrdinaryDirectory
    ${If} $1 == 1
        StrCpy $0 "$APPDATA\Auralis"
        Call un.IsOrdinaryDirectory
        ${If} $1 == 1
            StrCpy $0 "$APPDATA\Auralis\tools"
            Call un.IsOrdinaryDirectory
            ${If} $1 == 1
                Delete "$0\programs.json"
                Delete "$0\.legacy-helpers-checked"
                StrCpy $0 "$APPDATA\Auralis\tools\yt-dlp"
                Call un.RemoveManagedDirectory
                StrCpy $0 "$APPDATA\Auralis\tools\ffmpeg"
                Call un.RemoveManagedDirectory
                StrCpy $0 "$APPDATA\Auralis\tools\gallery-dl"
                Call un.RemoveManagedDirectory
                RMDir "$APPDATA\Auralis\tools"
                RMDir "$APPDATA\Auralis"
            ${EndIf}
        ${EndIf}
    ${EndIf}

    StrCpy $0 "$LOCALAPPDATA"
    Call un.IsOrdinaryDirectory
    ${If} $1 == 1
        StrCpy $0 "$LOCALAPPDATA\${PRODUCT} Updates"
        Call un.IsOrdinaryDirectory
        ${If} $1 == 1
            Delete "$0\auralis-update-*.exe"
            Delete "$0\auralis-update-*.part"
            RMDir "$0"
        ${EndIf}

        StrCpy $0 "$LOCALAPPDATA\Auralis"
        Call un.IsOrdinaryDirectory
        ${If} $1 == 1
            StrCpy $0 "$LOCALAPPDATA\Auralis\${PRODUCT}"
            Call un.IsOrdinaryDirectory
            ${If} $1 == 1
                StrCpy $0 "$LOCALAPPDATA\Auralis\${PRODUCT}\fonts"
                Call un.IsOrdinaryDirectory
                ${If} $1 == 1
                    # Keep these copy basenames in sync with Typography.cpp.
                    Delete "$0\talina-demo.font"
                    Delete "$0\milkyway.font"
                    Delete "$0\mochi-boom-demo.font"
                    Delete "$0\qilka.font"
                    Delete "$0\qurova-demo.font"
                    Delete "$0\kidzhood-arabic-demo.font"
                    Delete "$0\tinta-arabic.font"
                    Delete "$0\madani-arabic-demo.font"
                    Delete "$0\mahameru-arabic-demo.font"
                    Delete "$0\gumela-arabic-demo.font"
                    Delete "$0\tufuli-arabic-demo.font"
                    Delete "$0\lutfey-arabic-demo.font"
                    RMDir "$0"
                    RMDir "$LOCALAPPDATA\Auralis\${PRODUCT}"
                    RMDir "$LOCALAPPDATA\Auralis"
                ${EndIf}
            ${EndIf}
        ${EndIf}
    ${EndIf}
FunctionEnd

Function un.RemoveSharedProfile
    Call un.FindSharedProfile
    ${If} $1 != 1
        Return
    ${EndIf}

    # The engine holds this file open while it owns the profile. Hold it
    # exclusively throughout the cleanup, then remove the empty lock on close.
    # OPEN_ALWAYS | FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_DELETE_ON_CLOSE.
    System::Call 'kernel32::CreateFileW(w "$0\instance.lock", i 0xC0000000, i 0, p 0, i 4, i 0x04200080, p 0) p.r1'
    ${If} $1 = -1
        DetailPrint "Shared download history was kept because its profile could not be locked."
        Return
    ${EndIf}

    # These files contain the settings and saved list, not the downloaded data.
    Delete "$0\downloads.json"
    Delete "$0\downloads.json.bak"
    Delete "$0\downloads.json.1.bak"
    Delete "$0\downloads.json.2.bak"
    Delete "$0\downloads.json.corrupt-*.bak"
    Delete "$0\rss.json"
    Delete "$0\auralis-interface-version"
    System::Call 'kernel32::CloseHandle(p r1)'
    RMDir "$0"
FunctionEnd

Section "Uninstall"
    # Only the files installed by this package are removed.
    !include "${UNINSTALL_FILES}"
    ${If} $DeleteAppData == ${BST_CHECKED}
    ${AndIfNot} ${FileExists} "$INSTDIR\${APP_EXE}"
        Call un.CanDeleteAppData
        ${If} $1 == 1
            Call un.RemoveAppData
            ${If} $DeleteSharedProfile == ${BST_CHECKED}
                Call un.RemoveSharedProfile
            ${EndIf}
        ${EndIf}
    ${EndIf}
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
