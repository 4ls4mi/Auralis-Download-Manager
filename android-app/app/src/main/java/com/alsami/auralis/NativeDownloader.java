package com.alsami.auralis;

import android.content.Context;

final class NativeDownloader {
    static {
        System.loadLibrary("auralis_android");
    }

    private NativeDownloader() {}

    // Mutations return an error message on failure and null on success.
    static native String initialize(Context context);
    static native String start(String id, String url, String targetPath, int connections);
    static native String pause(String id);
    static native void forget(String id);
    static native String snapshot(String id);
}
