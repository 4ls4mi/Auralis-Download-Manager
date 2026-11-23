cmake_minimum_required(VERSION 3.21)
project(AuralisQt VERSION 0.3.67 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS
    Core Gui Widgets Qml Quick QuickControls2 Quick3D Concurrent Network Multimedia ShaderTools
)
qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(auralis-download-manager WIN32
    src/main.cpp
    src/Engine.cpp
    src/Engine.h
    src/FrameResize.cpp
    src/FrameResize.h
    src/LocalFiles.cpp
    src/LocalFiles.h
    src/Smoke.cpp
    src/Smoke.h
)

target_compile_definitions(auralis-download-manager PRIVATE AURALIS_VERSION="${PROJECT_VERSION}")
target_link_libraries(auralis-download-manager PRIVATE
    Qt6::Core Qt6::Gui Qt6::Widgets Qt6::Qml Qt6::Quick Qt6::QuickControls2
    Qt6::Quick3D Qt6::Concurrent Qt6::Network Qt6::Multimedia
)

if(WIN32)
    enable_language(RC)
    set(auralis_icon "${CMAKE_CURRENT_SOURCE_DIR}/assets/auralis.ico")
    # Change the generated RC itself on an icon update for the Visual Studio generator.
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${auralis_icon}")
    file(SHA256 "${auralis_icon}" AURALIS_ICON_SHA256)
    configure_file(src/WindowsIcon.rc.in "${CMAKE_CURRENT_BINARY_DIR}/WindowsIcon.rc" @ONLY)
    target_sources(auralis-download-manager PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/WindowsIcon.rc")
    target_link_libraries(auralis-download-manager PRIVATE dwmapi comctl32 shell32 ole32)
endif()

qt_add_shaders(auralis-download-manager "glass_effects"
    PREFIX "/auralis"
    FILES shaders/bubble.frag
)

qt_add_resources(auralis-download-manager "branding"
    PREFIX "/auralis"
    BASE "assets"
    FILES
        assets/auralis.png
        assets/auralis.ico
        assets/auralis-progress.png
        assets/sounds/auralis-download-complete.wav
        assets/sounds/auralis-download-failed.wav
        assets/sounds/auralis-queue-started.wav
        assets/sounds/auralis-queue-stopped.wav
)

# Keep the components adjacent in the module so relative JavaScript imports
# behave the same in the compiled package and the Qt tooling.
file(GLOB qml_components CONFIGURE_DEPENDS "qml/*.qml" "qml/*.js")
foreach(component IN LISTS qml_components)
    get_filename_component(filename "${component}" NAME)
    set_source_files_properties("${component}" PROPERTIES QT_RESOURCE_ALIAS "${filename}")
endforeach()
set_source_files_properties(
    "${CMAKE_CURRENT_SOURCE_DIR}/qml/MaterialTheme.qml"
    "${CMAKE_CURRENT_SOURCE_DIR}/qml/WindowAppearance.qml"
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(auralis-download-manager
    URI Auralis
    VERSION 1.0
    QML_FILES ${qml_components}
)
