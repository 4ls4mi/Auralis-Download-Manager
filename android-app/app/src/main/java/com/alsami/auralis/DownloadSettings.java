package com.alsami.auralis;

import android.content.Context;
import android.content.SharedPreferences;

/** Download policy shared by the settings screen and the transfer service. */
public final class DownloadSettings {
    static final int MAX_FILES = 5;
    static final int MAX_CONNECTIONS = 16;
    static final int MAX_RATE_KIB = 1_048_576;
    static final int MAX_RETRIES = 5;

    private static final String FILES = "concurrentFiles";
    private static final String CONNECTIONS = "connectionsPerDownload";
    private static final String RATE = "rateLimitKiB";
    private static final String RETRIES = "automaticRetries";
    private static final String WIFI = "wifiOnly";
    private static final String BATTERY = "pauseOnLowBattery";

    private final SharedPreferences preferences;

    private DownloadSettings(SharedPreferences preferences) {
        this.preferences = preferences;
    }

    public static DownloadSettings get(Context context) {
        return new DownloadSettings(context.getSharedPreferences("download-settings", Context.MODE_PRIVATE));
    }

    public int concurrentFiles() {
        return bounded(preferences.getInt(FILES, 1), 1, MAX_FILES);
    }

    public int connectionsPerDownload() {
        return bounded(preferences.getInt(CONNECTIONS, 8), 1, MAX_CONNECTIONS);
    }

    public int rateLimitKiB() {
        return bounded(preferences.getInt(RATE, 0), 0, MAX_RATE_KIB);
    }

    public int automaticRetries() {
        return bounded(preferences.getInt(RETRIES, MAX_RETRIES), 0, MAX_RETRIES);
    }

    public boolean wifiOnly() {
        return preferences.getBoolean(WIFI, false);
    }

    public boolean pauseOnLowBattery() {
        return preferences.getBoolean(BATTERY, false);
    }

    // SharedPreferences delivers callbacks on the main thread. Keep a strong
    // reference to the listener until it is unregistered.
    public void registerChangeListener(SharedPreferences.OnSharedPreferenceChangeListener listener) {
        preferences.registerOnSharedPreferenceChangeListener(listener);
    }

    public void unregisterChangeListener(SharedPreferences.OnSharedPreferenceChangeListener listener) {
        preferences.unregisterOnSharedPreferenceChangeListener(listener);
    }

    void save(int files, int connections, int rateKiB, int retries, boolean wifiOnly, boolean pauseOnLowBattery) {
        preferences.edit()
                .putInt(FILES, bounded(files, 1, MAX_FILES))
                .putInt(CONNECTIONS, bounded(connections, 1, MAX_CONNECTIONS))
                .putInt(RATE, bounded(rateKiB, 0, MAX_RATE_KIB))
                .putInt(RETRIES, bounded(retries, 0, MAX_RETRIES))
                .putBoolean(WIFI, wifiOnly)
                .putBoolean(BATTERY, pauseOnLowBattery)
                .apply();
    }

    private static int bounded(int value, int min, int max) {
        return Math.max(min, Math.min(value, max));
    }
}
