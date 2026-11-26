cmake_minimum_required(VERSION 3.21)
project(AuralisQt VERSION 0.3.99 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS
    Core Gui Widgets Qml Quick QuickControls2 Quick3D Concurrent Network Multimedia ShaderTools LinguistTools
)
qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(auralis-download-manager WIN32 MACOSX_BUNDLE
    src/main.cpp
    src/BrowserSetup.cpp
    src/BrowserSetup.h
    src/Engine.cpp
    src/Engine.h
    src/FrameResize.cpp
    src/FrameResize.h
    src/LocalFiles.cpp
    src/LocalFiles.h
    src/Smoke.cpp
    src/Smoke.h
    src/Typography.cpp
    src/Typography.h
    src/WindowOutline.cpp
    src/WindowOutline.h
)

target_compile_definitions(auralis-download-manager PRIVATE AURALIS_VERSION="${PROJECT_VERSION}")
target_link_libraries(auralis-download-manager PRIVATE
    Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Qml Qt6::Quick Qt6::QuickControls2
    Qt6::Quick3D Qt6::Concurrent Qt6::Network Qt6::Multimedia
)

if(WIN32)
    target_sources(auralis-download-manager PRIVATE src/WindowShadow.cpp src/WindowShadow.h)
    find_package(Qt6 6.8 REQUIRED COMPONENTS WebSockets)
    enable_language(RC)
    set(auralis_icon "${CMAKE_CURRENT_SOURCE_DIR}/assets/auralis.ico")
    # Change the generated RC itself on an icon update for the Visual Studio generator.
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${auralis_icon}")
    file(SHA256 "${auralis_icon}" AURALIS_ICON_SHA256)
    set(auralis_file_description "Auralis Download Manager")
    set(auralis_original_filename "auralis-download-manager.exe")
    configure_file(src/WindowsIcon.rc.in "${CMAKE_CURRENT_BINARY_DIR}/WindowsIcon.rc" @ONLY)
    target_sources(auralis-download-manager PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/WindowsIcon.rc")
    target_link_libraries(auralis-download-manager PRIVATE Qt6::WebSockets advapi32 dwmapi gdi32 comctl32 shell32 shlwapi ole32 version)

    if(MSVC)
        set(auralis_file_description "Auralis Chrome Setup")
        set(auralis_original_filename "auralis-chrome-approval.exe")
        configure_file(src/WindowsIcon.rc.in "${CMAKE_CURRENT_BINARY_DIR}/ChromeApprovalIcon.rc" @ONLY)
        add_executable(auralis-chrome-approval src/ChromePolicyApproval.cpp "${CMAKE_CURRENT_BINARY_DIR}/ChromeApprovalIcon.rc")
        set_target_properties(auralis-chrome-approval PROPERTIES
            MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
            AUTOMOC OFF AUTOUIC OFF AUTORCC OFF
        )
        target_link_libraries(auralis-chrome-approval PRIVATE advapi32)
        # Resolve startup imports exclusively from System32, even in a per-user installation.
        target_link_options(auralis-chrome-approval PRIVATE /DEPENDENTLOADFLAG:0x800)

        set(approval_generated "${CMAKE_CURRENT_BINARY_DIR}/chrome-approval/$<CONFIG>")
        set(approval_digest "${approval_generated}/AuralisChromeApprovalDigest.h")
        set(digest_script "${CMAKE_CURRENT_SOURCE_DIR}/packaging/write-chrome-approval-digest.cmake")
        add_custom_command(OUTPUT "${approval_digest}"
            COMMAND "${CMAKE_COMMAND}" -E make_directory "${approval_generated}"
            COMMAND "${CMAKE_COMMAND}" "-DINPUT=$<TARGET_FILE:auralis-chrome-approval>"
                "-DOUTPUT=${approval_digest}" -P "${digest_script}"
            DEPENDS "$<TARGET_FILE:auralis-chrome-approval>" "${digest_script}"
            VERBATIM
        )
        target_sources(auralis-download-manager PRIVATE "${approval_digest}")
        target_include_directories(auralis-download-manager PRIVATE "${approval_generated}")
        target_compile_definitions(auralis-download-manager PRIVATE AURALIS_CHROME_APPROVAL_ENABLED)
    endif()
endif()

if(APPLE)
    set_target_properties(auralis-download-manager PROPERTIES
        MACOSX_BUNDLE_BUNDLE_NAME "Auralis Download Manager"
        MACOSX_BUNDLE_GUI_IDENTIFIER "io.github.4ls4mi.auralis"
        MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
        MACOSX_BUNDLE_ICON_FILE "auralis.icns"
    )
endif()

qt_add_shaders(auralis-download-manager "glass_effects"
    PREFIX "/auralis"
    FILES
        shaders/bubble.frag
        shaders/window-outline.vert
        shaders/window-outline.frag
)

qt_add_resources(auralis-download-manager "branding"
    PREFIX "/auralis"
    BASE "assets"
    FILES
        assets/auralis.png
        assets/auralis.ico
        assets/auralis-progress.png
        assets/default-appearance.json
        assets/sounds/auralis-download-complete.wav
        assets/sounds/auralis-download-failed.wav
        assets/sounds/auralis-queue-started.wav
        assets/sounds/auralis-queue-stopped.wav
)

# Reuse the original icon files and their notices from the desktop engine's source tree.
set(classic_assets "${CMAKE_CURRENT_SOURCE_DIR}/../crates/app/assets")
foreach(icon_kind IN ITEMS tb cat ui ft page)
    file(GLOB matching_icons CONFIGURE_DEPENDS
        "${classic_assets}/themes/*/icons/*/${icon_kind}-*.png"
        "${classic_assets}/themes/*/icons/*/${icon_kind}-*.svg")
    list(APPEND classic_theme_icons ${matching_icons})
endforeach()
list(SORT classic_theme_icons)
file(GLOB classic_icon_notices CONFIGURE_DEPENDS
    "${classic_assets}/themes/*/icons/LICENSE"
    "${classic_assets}/themes/*/icons/COPYING"
    "${classic_assets}/themes/*/icons/SOURCES.txt")
set(classic_silk_icons
    "${classic_assets}/icons/silk/folder.png"
    "${classic_assets}/icons/silk/folder_go.png"
    "${classic_assets}/icons/silk/folder_page.png"
    "${classic_assets}/icons/silk/page_white_zip.png"
    "${classic_assets}/icons/silk/page_white.png"
    "${classic_assets}/icons/silk/music.png"
    "${classic_assets}/icons/silk/application_xp.png"
    "${classic_assets}/icons/silk/film.png"
    "${classic_assets}/icons/silk/tick.png"
    "${classic_assets}/icons/silk/page_white_stack.png"
    "${classic_assets}/icons/silk/readme.txt"
    "${classic_assets}/icons/lucide/LICENSE")

# Include monochrome vector source in the index so Qt can recolor it at the
# current scale without reading local files from QML or flattening the artwork.
set(classic_icon_index ".pragma library\n\nvar paths = {\n")
foreach(icon IN LISTS classic_theme_icons)
    file(RELATIVE_PATH icon_path "${classic_assets}" "${icon}")
    if(icon_path MATCHES "(/metro/.*|-symbolic)[.]svg$")
        set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${icon}")
        file(READ "${icon}" symbolic_svg)
        string(REPLACE "\\" "\\\\" symbolic_svg "${symbolic_svg}")
        string(REPLACE "\"" "\\\"" symbolic_svg "${symbolic_svg}")
        string(REPLACE "\r" "\\r" symbolic_svg "${symbolic_svg}")
        string(REPLACE "\n" "\\n" symbolic_svg "${symbolic_svg}")
        string(REPLACE "\t" "\\t" symbolic_svg "${symbolic_svg}")
        string(APPEND classic_icon_index "    \"${icon_path}\": \"${symbolic_svg}\",\n")
    else()
        list(APPEND classic_image_files "${icon}")
        string(APPEND classic_icon_index "    \"${icon_path}\": true,\n")
    endif()
endforeach()
string(APPEND classic_icon_index "}\n")
qt_add_resources(auralis-download-manager "classic_icons"
    PREFIX "/auralis/classic"
    BASE "${classic_assets}"
    FILES ${classic_image_files} ${classic_icon_notices} ${classic_silk_icons}
)
set(classic_icon_resources "${CMAKE_CURRENT_BINARY_DIR}/ClassicIconResources.js")
file(CONFIGURE OUTPUT "${classic_icon_resources}" CONTENT "${classic_icon_index}" @ONLY)

# Keep the components adjacent in the module so relative JavaScript imports
# behave the same in the compiled package and the Qt tooling.
file(GLOB qml_components CONFIGURE_DEPENDS "qml/*.qml" "qml/*.js")
list(APPEND qml_components "${classic_icon_resources}")
foreach(component IN LISTS qml_components)
    get_filename_component(filename "${component}" NAME)
    set_source_files_properties("${component}" PROPERTIES QT_RESOURCE_ALIAS "${filename}")
endforeach()
set_source_files_properties(
    "${CMAKE_CURRENT_SOURCE_DIR}/qml/MaterialTheme.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/qml/TypographyScale.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/qml/WindowAppearance.qml"
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(auralis-download-manager
    URI Auralis
    VERSION 1.0
    QML_FILES ${qml_components}
)

qt_add_translations(auralis-download-manager
    SOURCE_TARGETS auralis-download-manager
    TS_FILES i18n/auralis_ar.ts i18n/auralis_es.ts i18n/auralis_zh_CN.ts
    RESOURCE_PREFIX "/auralis/i18n"
)
