package com.alsami.auralis;

import android.content.Context;

final class NativeDownloader {
    static {
        System.loadLibrary("auralis_android");
    }

    private NativeDownloader() {}

    // Mutations return an error message on failure and null on success.
    static native String initialize(Context context);
    /** Retry allowance for consecutive transient failures on each connection, after the initial attempt. */
    static native String start(String id, String url, String targetPath, int connections,
            int automaticRetries);
    /** Combined cap for all active transfers in bytes per second. Zero removes the limit. */
    static native String setRateLimit(long bytesPerSecond);
    static native String pause(String id);
    static native void forget(String id);
    static native String snapshot(String id);
}
