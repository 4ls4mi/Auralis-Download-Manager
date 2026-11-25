#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != Darwin ]]; then
    echo "Auralis macOS packages require macOS and Xcode Command Line Tools." >&2
    exit 1
fi

case "$(uname -m)" in
    arm64) architecture=arm64; rust_target=aarch64-apple-darwin ;;
    x86_64) architecture=x86_64; rust_target=x86_64-apple-darwin ;;
    *) echo "Unsupported Mac architecture." >&2; exit 1 ;;
esac

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source_dir="$root/qt-ui"
version="$(sed -n 's/^project(AuralisQt VERSION \([0-9.]*\) .*/\1/p' "$source_dir/CMakeLists.txt")"
: "${version:?Missing AuralisQt project version}"
qt_prefix="$(cd "${AURALIS_MACOS_QT:?Set AURALIS_MACOS_QT to the macOS Qt SDK prefix}" && pwd)"
work_dir="${AURALIS_MACOS_WORK:-$root/target/auralis-qt-macos-$architecture}"
dist_dir="${AURALIS_MACOS_OUTPUT:-$root/target/dist}"
export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-14.4}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$work_dir/cargo}"
mkdir -p "$work_dir" "$dist_dir" "$CARGO_TARGET_DIR"
work_dir="$(cd "$work_dir" && pwd)"
dist_dir="$(cd "$dist_dir" && pwd)"
CARGO_TARGET_DIR="$(cd "$CARGO_TARGET_DIR" && pwd)"
build_dir="$work_dir/cmake"
stage="$(mktemp -d "$work_dir/package.XXXXXX")"
mounted=0
cleanup() {
    if [[ $mounted == 1 ]] && ! hdiutil detach "$stage/mount" -quiet; then
        echo "Could not detach the test disk image at $stage/mount." >&2
        return 1
    fi
    rm -rf -- "$stage"
}
trap cleanup EXIT

qt_version="$("$qt_prefix/bin/qmake" -query QT_VERSION)"
cmake -S "$source_dir" -B "$build_dir" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_PREFIX_PATH="$qt_prefix" -DCMAKE_OSX_ARCHITECTURES="$architecture" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOSX_DEPLOYMENT_TARGET"
AURALIS_ENGINE_REV="$(git -C "$root" log -1 --format=%h -- crates i18n assets Cargo.toml Cargo.lock .cargo rust-toolchain.toml)"
: "${AURALIS_ENGINE_REV:?Missing backend revision}"
export AURALIS_ENGINE_REV
cargo build --manifest-path "$root/Cargo.toml" --locked --release --target "$rust_target" -p auralis-qt-engine
cmake --build "$build_dir" --parallel --target auralis-download-manager

dmg_content="$stage/disk-image"
app_name="Auralis Download Manager"
bundle="$dmg_content/$app_name.app"
mkdir -p "$dmg_content"
ditto "$build_dir/auralis-download-manager.app" "$bundle"
resources="$bundle/Contents/Resources"
mkdir -p "$resources"
cp "$CARGO_TARGET_DIR/$rust_target/release/libauralis_engine.dylib" "$bundle/Contents/MacOS/"
strip -S -x "$bundle/Contents/MacOS/libauralis_engine.dylib"
cp "$root/LICENSE" "$resources/LICENSE.txt"
cp "$root/ATTRIBUTION.md" "$resources/"
{
    printf 'Auralis sources: https://github.com/4ls4mi/Auralis-Download-Manager\n'
    printf 'Qt %s module sources and license notices:\n' "$qt_version"
    printf 'https://download.qt.io/archive/qt/%s/%s/submodules/\n' "${qt_version%.*}" "$qt_version"
    printf 'Qt open-source licensing: https://www.qt.io/licensing/open-source-lgpl-obligations\n'
    printf 'FFmpeg sources and licensing: https://ffmpeg.org/legal.html\n'
} > "$resources/THIRD-PARTY.txt"

iconset="$stage/Auralis.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$source_dir/assets/auralis.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    doubled=$((size * 2))
    sips -z "$doubled" "$doubled" "$source_dir/assets/auralis.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$resources/auralis.icns"

# Sign the Rust library before macdeployqt signs Qt libraries, plugins and the app.
codesign --force --sign - "$bundle/Contents/MacOS/libauralis_engine.dylib"
# Theme icons include SVGs referenced from a resource index. Deploy the SVG image
# plugin explicitly because those files do not link QtSvg or import a QML module.
svg_plugin="$bundle/Contents/PlugIns/imageformats/libqsvg.dylib"
mkdir -p "$(dirname "$svg_plugin")"
cp "$qt_prefix/plugins/imageformats/libqsvg.dylib" "$svg_plugin"
"$qt_prefix/bin/macdeployqt" "$bundle" -qmldir="$source_dir/qml" -executable="$svg_plugin" -appstore-compliant -codesign=-
# Qt SQL can be an indirect framework dependency. Auralis does not load its database plugins,
# some of which reference third-party client libraries outside the application bundle.
if [[ -d "$bundle/Contents/PlugIns/sqldrivers" ]]; then
    rm -rf -- "$bundle/Contents/PlugIns/sqldrivers"
    codesign --force --sign - "$bundle"
fi
plutil -lint "$bundle/Contents/Info.plist"
codesign --verify --deep --strict "$bundle"
ln -s /Applications "$dmg_content/Applications"
dmg_name="Auralis.Download.Manager_${version}_macos-$architecture.dmg"
image="$stage/$dmg_name"
hdiutil create -volname "$app_name" -srcfolder "$dmg_content" -format UDZO "$image"
hdiutil verify "$image"

# Exercise the packaged app without using an existing user profile or SDK paths.
mkdir -p "$stage/mount" "$stage/smoke"
hdiutil attach "$image" -readonly -nobrowse -mountpoint "$stage/mount" -quiet
mounted=1
installed="$stage/mount/$app_name.app"
codesign --verify --deep --strict "$installed"
lipo "$installed/Contents/MacOS/auralis-download-manager" -verify_arch "$architecture"
lipo "$installed/Contents/MacOS/libauralis_engine.dylib" -verify_arch "$architecture"
smoke_status=0
env -u DYLD_LIBRARY_PATH -u DYLD_FRAMEWORK_PATH -u QT_PLUGIN_PATH -u QML_IMPORT_PATH -u QML2_IMPORT_PATH \
    MDM_DATA_DIR="$stage/smoke" QT_QPA_PLATFORM=cocoa QT_QUICK_BACKEND=software \
    "$installed/Contents/MacOS/auralis-download-manager" --engine-smoke || smoke_status=$?
if [[ $smoke_status != 0 || ! -f "$stage/smoke/qt-engine-smoke.ok" ]]; then
    if [[ -f "$stage/smoke/qt-smoke-console.log" ]]; then
        cat "$stage/smoke/qt-smoke-console.log" >&2
    fi
    echo "The packaged macOS app did not pass its download and resume smoke test." >&2
    exit 1
fi
cat "$stage/smoke/qt-engine-smoke.ok"
hdiutil detach "$stage/mount" -quiet
mounted=0

mv -f "$image" "$dist_dir/$dmg_name"
(
    cd "$dist_dir"
    shasum -a 256 "$dmg_name" > "$dmg_name.sha256"
)
printf 'Verified macOS package: %s\n' "$dist_dir/$dmg_name"
