#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-${ANDROID_HOME:?Set ANDROID_HOME to your Android SDK}/ndk/29.0.14206865}"
if [[ ! -f "$ANDROID_NDK_HOME/source.properties" ]]; then
    printf 'Android NDK was not found in %s\n' "$ANDROID_NDK_HOME" >&2
    exit 1
fi

export CARGO_PROFILE_RELEASE_LTO="${CARGO_PROFILE_RELEASE_LTO:-thin}"
export CARGO_PROFILE_RELEASE_CODEGEN_UNITS="${CARGO_PROFILE_RELEASE_CODEGEN_UNITS:-4}"
cargo ndk --platform 29 --target arm64-v8a --target x86_64 \
    --output-dir "$root/android-app/app/src/main/jniLibs" \
    build --locked --release --package auralis-android
