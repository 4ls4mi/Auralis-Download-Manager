package com.alsami.auralis;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.net.ConnectivityManager;
import android.net.Network;
import android.net.NetworkCapabilities;
import android.os.BatteryManager;
import android.os.Build;

final class DownloadConditions {
    private final Context context;
    private final ConnectivityManager connectivity;
    private final Runnable changed;
    private volatile boolean lowBattery;
    private boolean watchingNetwork;

    private final ConnectivityManager.NetworkCallback network = new ConnectivityManager.NetworkCallback() {
        @Override public void onAvailable(Network available) { changed.run(); }
        @Override public void onLost(Network lost) { changed.run(); }
        @Override public void onCapabilitiesChanged(Network current, NetworkCapabilities capabilities) {
            changed.run();
        }
    };

    private final BroadcastReceiver battery = new BroadcastReceiver() {
        @Override public void onReceive(Context receiverContext, Intent intent) {
            updateBattery(intent);
        }
    };

    DownloadConditions(Context context, Runnable changed) {
        this.context = context;
        this.changed = changed;
        connectivity = context.getSystemService(ConnectivityManager.class);
        if (connectivity != null) {
            try {
                connectivity.registerDefaultNetworkCallback(network);
                watchingNetwork = true;
            } catch (RuntimeException unavailable) {
                // The service also checks current conditions as part of its normal work.
            }
        }
        IntentFilter filter = new IntentFilter(Intent.ACTION_BATTERY_CHANGED);
        Intent initial = Build.VERSION.SDK_INT >= 33
            ? context.registerReceiver(battery, filter, Context.RECEIVER_NOT_EXPORTED)
            : context.registerReceiver(battery, filter);
        updateBattery(initial);
    }

    String pauseReason(DownloadSettings settings) {
        if (settings.wifiOnly() && !isWifi())
            return "Waiting for Wi-Fi";
        if (settings.pauseOnLowBattery() && lowBattery)
            return "Waiting for battery power";
        return null;
    }

    void stop() {
        if (watchingNetwork)
            connectivity.unregisterNetworkCallback(network);
        context.unregisterReceiver(battery);
    }

    private boolean isWifi() {
        if (connectivity == null)
            return false;
        Network current = connectivity.getActiveNetwork();
        NetworkCapabilities capabilities = connectivity.getNetworkCapabilities(current);
        return capabilities != null && capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI);
    }

    private void updateBattery(Intent intent) {
        if (intent == null)
            return;
        int level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1);
        int scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1);
        boolean next = level >= 0 && scale > 0 && level * 100L < scale * 15L
            && intent.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) == 0;
        if (next != lowBattery) {
            lowBattery = next;
            changed.run();
        }
    }
}
