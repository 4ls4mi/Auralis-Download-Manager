# Auralis for Android

A standalone Android app for direct HTTP and HTTPS downloads. Paste or share a link, or review a batch of links pasted into the app or imported from a text file. The queue supports priorities, status filters, and bulk pause and resume. Finished files are saved to Android Downloads.

Settings allow up to five active files and sixteen connections per transfer when the server supports byte ranges. A shared speed limit applies immediately. Connections and retry settings apply on the next start or resume. Wi-Fi and low-battery settings pause transfers until the conditions clear while the download service is running.

Open Browser for tabs, bookmarks, history, and confirmed handoff of direct download links to the queue.

The APK supports Android 10 and later on ARM64 and x86-64. Open Auralis and resume interrupted downloads after a system restart.

## Build

Install JDK 17, Android SDK platform 35, build tools 35.0.0, NDK 29.0.14206865, and a stable Rust toolchain. Set `ANDROID_HOME` to your SDK directory. From the repository root, run these commands.

```sh
rustup target add aarch64-linux-android x86_64-linux-android
cargo install cargo-ndk --version 4.1.2 --locked
bash android-app/build-native.sh
cd android-app
./gradlew assembleDebug
```

The debug APK is at `app/build/outputs/apk/debug/app-debug.apk`. Run `./gradlew connectedDebugAndroidTest` with an Android emulator or device attached to exercise segmentation, pause and resume, concurrent transfers, and queue priority.
