# Auralis for Android

A standalone Android app for direct HTTP and HTTPS downloads. Share a link to Auralis or paste it in the app, then add it to the download queue. The Rust engine uses multiple connections when the source supports byte ranges. Paused downloads keep their partial data, and completed files are saved to Android Downloads.

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

The debug APK is at `app/build/outputs/apk/debug/app-debug.apk`. Run `./gradlew connectedDebugAndroidTest` with an Android emulator or device attached to exercise a segmented download, pause and resume, and queue order.
