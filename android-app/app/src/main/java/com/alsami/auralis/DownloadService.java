package com.alsami.auralis;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ServiceInfo;
import android.database.sqlite.SQLiteException;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.net.URI;
import java.net.URISyntaxException;
import java.util.concurrent.TimeUnit;

public final class DownloadService extends Service {
    private static final String CHANNEL = "auralis-downloads";
    private static final int NOTIFICATION_ID = 1;
    private static final int CONNECTIONS = 8;
    private static final long POLL_MS = 600;
    private static final String PAUSE = "com.alsami.auralis.PAUSE_DOWNLOAD";
    private static final String TRANSFER_ID = "transferId";

    private static volatile DownloadService running;
    // A stopped foreground service can still be waiting for native pause to finish.
    // Own one worker across service instances so the next transfer cannot overlap that one.
    private static DownloadService owner;
    private static final class Worker {
        static final Handler handler = create();
        private static Handler create() {
            HandlerThread thread = new HandlerThread("Auralis download queue");
            thread.start();
            return new Handler(thread.getLooper());
        }
    }

    private final Handler main = new Handler(Looper.getMainLooper());
    private final Runnable cycle = this::tick;
    private DownloadQueue queue;
    private DownloadPublisher publisher;
    private NotificationManager notifications;
    private PowerManager.WakeLock wakeLock;
    private volatile boolean stopping;
    private volatile int lastStart;
    private boolean foreground;
    private volatile Transfer active;
    private boolean nativeReady;

    private static final class Transfer {
        final DownloadItem item;
        // The UI may request interruption during a staged file copy.
        volatile boolean pause;
        volatile boolean cancel;
        boolean nativeActive;
        boolean pauseSent;

        Transfer(DownloadItem item) {
            this.item = item;
        }
    }

    public static String enqueue(Context context, String url, String name) {
        URI address = downloadAddress(url);
        DownloadQueue queue = DownloadQueue.get(context);
        String id = queue.add(address.toASCIIString(), fileName(address, name));
        launch(context, queue, id);
        return id;
    }

    public static void pause(Context context, String id) {
        if (id == null || DownloadQueue.get(context).pauseQueued(id))
            return;
        DownloadService service = running;
        if (service != null)
            service.requestPause(id);
    }

    public static void resume(Context context, String id) {
        DownloadQueue queue = DownloadQueue.get(context);
        if (id != null && queue.resume(id))
            launch(context, queue, id);
    }

    public static void remove(Context context, String id) {
        if (id == null)
            return;
        Context application = context.getApplicationContext();
        DownloadQueue queue = DownloadQueue.get(application);
        Worker.handler.post(() -> removeItem(queue, new DownloadPublisher(application.getContentResolver()), id));
    }

    public static void cancel(Context context, String id) {
        if (id == null)
            return;
        DownloadService service = running;
        if (service != null && service.interruptIfActive(id, true))
            return;
        Context application = context.getApplicationContext();
        Worker.handler.post(() -> {
            if (owner == null || !owner.interruptIfActive(id, true))
                removeItem(DownloadQueue.get(application), new DownloadPublisher(application.getContentResolver()), id);
        });
    }

    private static void removeItem(DownloadQueue queue, DownloadPublisher publisher, String id) {
        DownloadItem item = queue.remove(id);
        if (item == null)
            return;
        try {
            publisher.discardPending(item);
        } catch (RuntimeException failure) {
            Log.w("Auralis", "Could not clean up an unpublished Downloads entry");
        }
        queue.deleteStage(item.id);
    }

    private static void launch(Context context, DownloadQueue queue, String id) {
        try {
            context.startForegroundService(new Intent(context, DownloadService.class).putExtra(TRANSFER_ID, id));
        } catch (RuntimeException failure) {
            queue.failQueued(id, "Android could not start the download. Open Auralis and try again.");
        }
    }

    @Override public void onCreate() {
        super.onCreate();
        notifications = getSystemService(NotificationManager.class);
        NotificationChannel channel = new NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW);
        notifications.createNotificationChannel(channel);
        PowerManager power = getSystemService(PowerManager.class);
        wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Auralis:Download");
        wakeLock.setReferenceCounted(false);
        running = this;
    }

    @Override public IBinder onBind(Intent intent) {
        return null;
    }

    @Override public int onStartCommand(Intent intent, int flags, int startId) {
        lastStart = startId;
        if (stopping)
            return failStart(intent, startId, "The previous download session is stopping. Try again.");
        if (!foreground) {
            try {
                startForeground(NOTIFICATION_ID, notification(null, "Preparing downloads…"),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
                foreground = true;
            } catch (RuntimeException failure) {
                return failStart(intent, startId, "Android could not start the download service.");
            }
        }
        if (intent != null && PAUSE.equals(intent.getAction())) {
            String id = intent.getStringExtra(TRANSFER_ID);
            if (id != null)
                pause(this, id);
        }
        wake();
        return START_NOT_STICKY;
    }

    private int failStart(Intent intent, int startId, String message) {
        String id = intent == null ? null : intent.getStringExtra(TRANSFER_ID);
        if (id != null)
            Worker.handler.post(() -> DownloadQueue.get(this).failQueued(id, message));
        stopSelf(startId);
        return START_NOT_STICKY;
    }

    @Override public void onTimeout(int startId, int foregroundServiceType) {
        // Android 15 dataSync can impose a deadline. Release the foreground service
        // promptly and let the worker checkpoint the active transfer.
        stopping = true;
        try {
            DownloadQueue.get(this).pauseWaiting();
        } catch (SQLiteException failure) {
            Log.w("Auralis", "The download queue could not save its timeout state");
        }
        wake();
        stopSelf();
    }

    @Override public void onDestroy() {
        stopping = true;
        if (running == this)
            running = null;
        if (foreground)
            stopForeground(STOP_FOREGROUND_REMOVE);
        releaseWakeLock();
        wake();
        super.onDestroy();
    }

    private void requestPause(String id) {
        if (!stopping && !interruptIfActive(id, false))
            Worker.handler.post(() -> interruptIfActive(id, false));
    }

    private boolean interruptIfActive(String id, boolean cancel) {
        Transfer transfer = active;
        if (transfer == null || !id.equals(transfer.item.id))
            return false;
        if (cancel)
            transfer.cancel = true;
        transfer.pause = true;
        wake();
        return true;
    }

    private void wake() {
        Worker.handler.removeCallbacks(cycle);
        Worker.handler.post(cycle);
    }

    private void tick() {
        if (active == null) {
            if (stopping)
                return;
            if (owner != null && owner != this) {
                schedule();
                return;
            }
            if (queue == null) {
                queue = DownloadQueue.get(this);
                publisher = new DownloadPublisher(getContentResolver());
            }
            final int expectedStart = lastStart;
            DownloadItem next = queue.claimNext();
            if (next == null) {
                main.post(() -> {
                    if (!stopping && active == null && expectedStart == lastStart && !queue.hasQueued())
                        stopSelfResult(expectedStart);
                });
                return;
            }
            active = new Transfer(next);
            owner = this;
            holdWakeLock();
            begin(active);
        } else {
            poll(active);
        }
        if (!stopping || active != null)
            schedule();
    }

    private void schedule() {
        Worker.handler.removeCallbacks(cycle);
        Worker.handler.postDelayed(cycle, active == null ? 25 : POLL_MS);
    }

    private void begin(Transfer transfer) {
        DownloadItem item = transfer.item;
        final File stage = queue.stageFile(item.id);
        if (stage.isFile() || item.staged) {
            publish(transfer, stage);
            return;
        }
        if (shouldPause(transfer)) {
            finish(DownloadItem.PAUSED, "");
            return;
        }
        try {
            if (!stage.getParentFile().mkdirs() && !stage.getParentFile().isDirectory())
                throw new IOException("Could not open the private download folder.");
            if (!nativeReady) {
                final String initialization = NativeDownloader.initialize(getApplicationContext());
                if (initialization != null) {
                    finish(DownloadItem.ERROR, initialization);
                    return;
                }
                nativeReady = true;
            }
            final String error = NativeDownloader.start(item.id, item.url, stage.getAbsolutePath(), CONNECTIONS);
            if (error != null) {
                finish(DownloadItem.ERROR, error);
                return;
            }
            transfer.nativeActive = true;
            notifyStatus(item, "Downloading…");
        } catch (IOException | RuntimeException | LinkageError failure) {
            finish(DownloadItem.ERROR, "Could not prepare this download.");
        }
    }

    private void poll(Transfer transfer) {
        final String id = transfer.item.id;
        if (shouldPause(transfer) && !transfer.pauseSent) {
            // Native returns only after it records the request. The worker can still
            // be writing the partial file until the snapshot changes state.
            transfer.pauseSent = NativeDownloader.pause(id) == null;
            if (transfer.pauseSent && !stopping)
                notifyStatus(transfer.item, "Pausing…");
        }
        final String snapshot = NativeDownloader.snapshot(id);
        if (snapshot == null) {
            final boolean paused = shouldPause(transfer);
            finish(paused ? DownloadItem.PAUSED : DownloadItem.ERROR, paused ? "" : "The download worker stopped.");
            return;
        }
        try {
            JSONObject state = new JSONObject(snapshot);
            long bytes = Math.max(0, state.optLong("downloaded", 0));
            long total = state.optLong("total", -1);
            long rate = Math.max(0, state.optLong("rate", 0));
            queue.updateProgress(id, bytes, total, rate);
            switch (state.optString("state")) {
                case DownloadItem.COMPLETED:
                    publish(transfer, queue.stageFile(id));
                    break;
                case DownloadItem.PAUSED:
                    finish(DownloadItem.PAUSED, "");
                    break;
                case DownloadItem.ERROR:
                    final boolean paused = shouldPause(transfer);
                    finish(paused ? DownloadItem.PAUSED : DownloadItem.ERROR,
                        paused ? "" : state.optString("error", "The download failed."));
                    break;
                default:
                    if (!transfer.pauseSent)
                        notifyStatus(queue.find(id), "Downloading…");
                    break;
            }
        } catch (JSONException invalidSnapshot) {
            // Preserve the single active slot until the native worker stops.
            transfer.pause = true;
        }
    }

    private void publish(Transfer transfer, File stage) {
        final String id = transfer.item.id;
        if (stage.isFile())
            queue.recordStage(id, stage.length());
        if (shouldPause(transfer)) {
            finish(DownloadItem.PAUSED, "");
            return;
        }
        try {
            DownloadItem item = queue.find(id);
            notifyStatus(item, "Saving to Downloads…");
            String name = publisher.publish(queue, item, stage, () -> shouldPause(transfer));
            queue.complete(id, name);
            queue.deleteStage(id);
            finish(DownloadItem.COMPLETED, "");
        } catch (InterruptedIOException paused) {
            finish(DownloadItem.PAUSED, "");
        } catch (IOException | RuntimeException failure) {
            finish(DownloadItem.ERROR, "Could not save the file to Downloads. Free some space and try again.");
        }
    }

    private boolean shouldPause(Transfer transfer) {
        return stopping || transfer.pause || transfer.cancel;
    }

    private void finish(String status, String error) {
        Transfer transfer = active;
        final String id = transfer.item.id;
        queue.end(id, status, error);
        if (transfer.nativeActive)
            NativeDownloader.forget(id);
        if (transfer.cancel)
            removeItem(queue, publisher, id);
        active = null;
        owner = null;
        releaseWakeLock();
    }

    private synchronized void holdWakeLock() {
        if (!stopping)
            wakeLock.acquire(TimeUnit.HOURS.toMillis(6));
    }

    private synchronized void releaseWakeLock() {
        if (wakeLock.isHeld())
            wakeLock.release();
    }

    private void notifyStatus(DownloadItem item, String message) {
        main.post(() -> {
            if (!stopping)
                notifications.notify(NOTIFICATION_ID, notification(item, message));
        });
    }

    private Notification notification(DownloadItem item, String message) {
        Intent open = new Intent(this, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP);
        PendingIntent content = PendingIntent.getActivity(this, 0, open,
            PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
        Notification.Builder notice = new Notification.Builder(this, CHANNEL)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle(item == null ? "Auralis" : item.name)
            .setContentText(message)
            .setContentIntent(content)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .setCategory(Notification.CATEGORY_PROGRESS);
        if (item != null) {
            int percent = item.total > 0 ? (int) Math.min(100, 100.0 * item.downloaded / item.total) : 0;
            notice.setProgress(100, percent, item.total < 0);
            Intent pause = new Intent(this, DownloadService.class)
                .setAction(PAUSE)
                .putExtra(TRANSFER_ID, item.id);
            PendingIntent action = PendingIntent.getService(this, 1, pause,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
            notice.addAction(new Notification.Action.Builder(null, "Pause", action).build());
        }
        return notice.build();
    }

    private static URI downloadAddress(String url) {
        if (url == null || url.length() > 16_384)
            throw new IllegalArgumentException("Enter a valid HTTP or HTTPS link.");
        try {
            URI address = new URI(url.trim());
            String scheme = address.getScheme();
            if ((!"http".equalsIgnoreCase(scheme) && !"https".equalsIgnoreCase(scheme))
                || address.getHost() == null || address.getUserInfo() != null || address.getPort() > 65535)
                throw new IllegalArgumentException("Enter a valid HTTP or HTTPS link without a username or password.");
            return address;
        } catch (URISyntaxException failure) {
            throw new IllegalArgumentException("Enter a valid HTTP or HTTPS link.");
        }
    }

    private static String fileName(URI address, String preferred) {
        String path = address.getRawPath();
        String name = preferred == null || preferred.trim().isEmpty()
            ? android.net.Uri.decode(path.substring(path.lastIndexOf('/') + 1))
            : preferred;
        StringBuilder clean = new StringBuilder();
        name.codePoints().limit(120).forEach(point -> {
            if (Character.isISOControl(point) || "/\\:*?\"<>|".indexOf(point) >= 0)
                clean.append('_');
            else
                clean.appendCodePoint(point);
        });
        name = clean.toString().trim();
        return name.isEmpty() || name.startsWith(".") ? "download" : name;
    }
}
