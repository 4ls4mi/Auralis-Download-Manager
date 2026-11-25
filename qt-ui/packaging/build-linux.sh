#!/usr/bin/env bash
# Build the native Debian 13 application, then exercise the packaged executable.
set -euo pipefail

repo=$(cd "$(dirname "$0")/../.." && pwd)
cd "$repo"
if [[ $(uname -m) != x86_64 ]] || ! grep -qx 'VERSION_CODENAME=trixie' /etc/os-release; then
    echo 'Build this amd64 package on Debian 13 (trixie).' >&2
    exit 1
fi

version=$(sed -nE 's/^project\(AuralisQt VERSION ([0-9]+\.[0-9]+\.[0-9]+) LANGUAGES CXX\)$/\1/p' qt-ui/CMakeLists.txt)
engine_version=$(sed -nE 's/^version = "([0-9]+\.[0-9]+\.[0-9]+)"$/\1/p' crates/auralis-qt-engine/Cargo.toml)
if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || $version != "$engine_version" ]]; then
    echo 'The Qt and Rust engine versions must match.' >&2
    exit 1
fi

build=${AURALIS_LINUX_BUILD_DIR:-$repo/target/auralis-qt-linux}
mkdir -p "$build" "$build/dist"
build=$(realpath "$build")
cmake -S qt-ui -B "$build/ui" -G Ninja -DCMAKE_BUILD_TYPE=Release
CARGO_TARGET_DIR="$build/engine" cargo build --locked --release -p auralis-qt-engine --lib
cmake --build "$build/ui"

stage=$(mktemp -d "$build/package.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
tree=$stage/tree
app=$tree/usr/lib/auralis-download-manager
doc=$tree/usr/share/doc/auralis-download-manager
exe=$app/auralis-download-manager
plugin=$app/libauralis_engine.so
install -Dm755 "$build/ui/auralis-download-manager" "$exe"
install -Dm755 "$build/engine/release/libauralis_engine.so" "$plugin"
strip --strip-unneeded "$exe" "$plugin"
install -d "$tree/usr/bin" "$tree/usr/share/applications" "$tree/DEBIAN"
ln -s ../lib/auralis-download-manager/auralis-download-manager "$tree/usr/bin/auralis-download-manager"
install -Dm644 qt-ui/assets/auralis.png "$tree/usr/share/icons/hicolor/256x256/apps/auralis-download-manager.png"
install -Dm644 LICENSE "$doc/LICENSE"
install -Dm644 ATTRIBUTION.md "$doc/ATTRIBUTION.md"
printf 'https://github.com/4ls4mi/Auralis-Download-Manager/tree/%s\n' "$(git rev-parse HEAD)" > "$doc/source.txt"

cat > "$tree/usr/share/applications/auralis-download-manager.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Auralis Download Manager
Comment=Manage direct downloads and torrents
Exec=auralis-download-manager
Icon=auralis-download-manager
Terminal=false
Categories=Network;FileTransfer;
StartupWMClass=auralis-download-manager
EOF

mkdir "$stage/debian"
cat > "$stage/debian/control" <<'EOF'
Source: auralis-download-manager
Section: net
Priority: optional
Maintainer: Auralis Download Manager contributors <4ls4mi@users.noreply.github.com>

Package: auralis-download-manager
Architecture: amd64
Description: Auralis Download Manager
EOF

# The QML modules and image/media plugins are discovered at runtime, outside ELF dependencies.
linked=$(cd "$stage" && dpkg-shlibdeps -O -e"$exe" -e"$plugin")
linked=${linked#shlibs:Depends=}
if [[ -z $linked ]]; then
    echo 'Could not determine the shared library dependencies.' >&2
    exit 1
fi
qml_dependencies='qml6-module-qtcore, qml6-module-qtqml, qml6-module-qtqml-models, qml6-module-qtqml-workerscript, qml6-module-qtmultimedia, qml6-module-qtquick, qml6-module-qtquick-controls, qml6-module-qtquick-dialogs, qml6-module-qtquick-layouts, qml6-module-qtquick-shapes, qml6-module-qtquick-templates, qml6-module-qtquick-window, qml6-module-qtquick3d'
cat > "$tree/DEBIAN/control" <<EOF
Package: auralis-download-manager
Version: $version
Architecture: amd64
Section: net
Priority: optional
Maintainer: Auralis Download Manager contributors <4ls4mi@users.noreply.github.com>
Depends: $linked, ca-certificates, qt6-svg-plugins, $qml_dependencies
Recommends: qt6-wayland
Homepage: https://github.com/4ls4mi/Auralis-Download-Manager
Description: Graphical download manager for direct files and torrents
 Auralis brings segmented downloads, transfer monitoring, and customizable
 appearance to the desktop.
EOF

name="Auralis.Download.Manager_${version}_debian13_amd64.deb"
dpkg-deb --root-owner-group --build "$tree" "$stage/$name"
dpkg-deb --extract "$stage/$name" "$stage/installed"
installed="$stage/installed/usr/bin/auralis-download-manager"
run_smoke() {
    local fixture=$1
    shift
    install -d -m 700 "$fixture" "$fixture"/{profile,runtime,config,cache,data}
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
        MDM_DATA_DIR="$fixture/profile" XDG_RUNTIME_DIR="$fixture/runtime" \
        XDG_CONFIG_HOME="$fixture/config" XDG_CACHE_HOME="$fixture/cache" XDG_DATA_HOME="$fixture/data" \
        "$@"
}
smoke_status=0
run_smoke "$stage/smoke" timeout 120 "$installed" --engine-smoke || smoke_status=$?
if (( smoke_status != 0 )) || [[ ! -f "$stage/smoke/profile/qt-engine-smoke.ok" ]]; then
    log="$stage/smoke/profile/qt-smoke-console.log"
    if [[ -f $log ]]; then
        cat "$log" >&2
    fi
    echo "The packaged Debian app failed its smoke test (exit $smoke_status)." >&2
    # Capture a symbolic trace on CI. The retry is diagnostic and cannot pass the gate.
    if (( smoke_status == 139 )) && command -v gdb >/dev/null; then
        debug="$stage/debug"
        install -Dm755 "$build/ui/auralis-download-manager" "$debug/auralis-download-manager"
        install -Dm755 "$build/engine/release/libauralis_engine.so" "$debug/libauralis_engine.so"
        run_smoke "$debug/smoke" timeout 45 gdb -nx -batch \
            -ex 'set debuginfod enabled off' -ex 'set disable-randomization off' \
            -ex run -ex 'thread apply all bt 20' \
            --args "$debug/auralis-download-manager" --engine-smoke >&2 || true
    fi
    exit "$((smoke_status == 0 ? 1 : smoke_status))"
fi
cat "$stage/smoke/profile/qt-engine-smoke.ok"

mv -- "$stage/$name" "$build/dist/$name"
(cd "$build/dist" && sha256sum "$name" > "$name.sha256")
printf '%s\n' "$build/dist/$name"
