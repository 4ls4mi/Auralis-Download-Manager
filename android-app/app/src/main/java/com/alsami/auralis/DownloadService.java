package com.alsami.auralis;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
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
import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

public final class DownloadService extends Service {
    private static final String CHANNEL = "auralis-downloads";
    private static final int NOTIFICATION_ID = 1;
    private static final int MAX_BATCH_SIZE = 200;
    private static final long POLL_MS = 600;
    private static final String PAUSE = "com.alsami.auralis.PAUSE_DOWNLOAD";
    private static final String PAUSE_ALL = "com.alsami.auralis.PAUSE_ALL_DOWNLOADS";
    private static final String TRANSFER_IDS = "transferIds";

    private static volatile DownloadService running;
    // A stopped foreground service can still be waiting for native pause to finish.
    // Serialize claim and completion across service instances while any native transfer is stopping.
    private static DownloadService owner;
    private static final class Worker {
        static final Handler handler = create();
        static final ExecutorService publisher = Executors.newSingleThreadExecutor(task ->
            new Thread(task, "Auralis save downloads"));
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
    private DownloadSettings settings;
    private DownloadConditions conditions;
    private final SharedPreferences.OnSharedPreferenceChangeListener settingsChanged = (preferences, key) -> wake();
    private NotificationManager notifications;
    private PowerManager.WakeLock wakeLock;
    private volatile boolean stopping;
    private volatile int lastStart;
    private volatile boolean foreground;
    private final ConcurrentHashMap<String, Transfer> active = new ConcurrentHashMap<>();
    private boolean nativeReady;
    private long appliedLimit = -1;

    private static final class Transfer {
        final DownloadItem item;
        // The UI may request interruption during a staged file copy.
        volatile boolean pause;
        volatile boolean cancel;
        volatile boolean waitingForConditions;
        boolean nativeActive;
        boolean pauseSent;
        boolean publishing;

        Transfer(DownloadItem item) {
            this.item = item;
        }
    }

    public static String enqueue(Context context, String url, String name) {
        URI address = downloadAddress(url);
        DownloadQueue queue = DownloadQueue.get(context);
        String id = queue.add(address.toASCIIString(), fileName(address, name));
        launch(context, queue, Collections.singletonList(id));
        return id;
    }

    public static int enqueueBatch(Context context, List<String> urls) {
        if (urls == null || urls.isEmpty() || urls.size() > MAX_BATCH_SIZE)
            throw new IllegalArgumentException("Add between 1 and 200 download links at a time.");
        List<DownloadQueue.NewDownload> requests = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (String url : urls) {
            try {
                URI address = downloadAddress(url);
                String link = address.toASCIIString();
                int fragment = link.indexOf('#');
                if (fragment >= 0)
                    link = link.substring(0, fragment);
                if (seen.add(link))
                    requests.add(new DownloadQueue.NewDownload(link, fileName(address, null)));
            } catch (IllegalArgumentException invalid) {
                // Other links in the batch can still be downloaded.
            }
        }
        if (requests.isEmpty())
            throw new IllegalArgumentException("The batch has no valid HTTP or HTTPS links.");
        DownloadQueue queue = DownloadQueue.get(context);
        List<String> ids = queue.addAll(requests);
        launch(context, queue, ids);
        return ids.size();
    }

    public static void pause(Context context, String id) {
        if (id == null)
            return;
        DownloadQueue queue = DownloadQueue.get(context);
        synchronized (queue) {
            if (queue.pauseQueued(id))
                return;
            DownloadService service = running;
            if (service != null)
                service.interruptIfActive(id, false);
        }
    }

    public static void resume(Context context, String id) {
        DownloadQueue queue = DownloadQueue.get(context);
        if (id != null && queue.resume(id))
            launch(context, queue, Collections.singletonList(id));
    }

    public static void pauseAll(Context context) {
        DownloadQueue queue = DownloadQueue.get(context);
        synchronized (queue) {
            queue.pauseAllQueued();
            DownloadService service = running;
            if (service != null) {
                for (Transfer transfer : service.active.values())
                    transfer.pause = true;
                service.wake();
            }
        }
    }

    public static void resumeAll(Context context) {
        DownloadQueue queue = DownloadQueue.get(context);
        List<String> paused = new ArrayList<>();
        synchronized (queue) {
            for (DownloadItem item : queue.list()) {
                if (DownloadItem.PAUSED.equals(item.status))
                    paused.add(item.id);
            }
            if (queue.resumePaused() == 0)
                return;
        }
        launch(context, queue, paused);
    }

    public static void setPriority(Context context, String id, int priority) {
        if (id != null && DownloadQueue.get(context).setPriority(id, priority)) {
            DownloadService service = running;
            if (service != null)
                service.wake();
        }
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

    private static void launch(Context context, DownloadQueue queue, List<String> ids) {
        try {
            context.startForegroundService(new Intent(context, DownloadService.class)
                .putStringArrayListExtra(TRANSFER_IDS, new ArrayList<>(ids)));
        } catch (RuntimeException failure) {
            for (String id : ids)
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
        settings = DownloadSettings.get(this);
        settings.registerChangeListener(settingsChanged);
        conditions = new DownloadConditions(this, this::wake);
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
                startForeground(NOTIFICATION_ID, notification(null, "Preparing downloads…", 0),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC);
                foreground = true;
            } catch (RuntimeException failure) {
                return failStart(intent, startId, "Android could not start the download service.");
            }
        }
        if (intent != null && PAUSE.equals(intent.getAction())) {
            pause(this, intent.getData() == null ? null : intent.getData().getSchemeSpecificPart());
        } else if (intent != null && PAUSE_ALL.equals(intent.getAction())) {
            pauseAll(this);
        }
        wake();
        return START_NOT_STICKY;
    }

    private int failStart(Intent intent, int startId, String message) {
        ArrayList<String> ids = intent == null ? null : intent.getStringArrayListExtra(TRANSFER_IDS);
        if (ids != null) {
            Worker.handler.post(() -> {
                for (String id : ids)
                    DownloadQueue.get(this).failQueued(id, message);
            });
        }
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
        settings.unregisterChangeListener(settingsChanged);
        conditions.stop();
        if (foreground)
            stopForeground(STOP_FOREGROUND_REMOVE);
        releaseWakeLock();
        wake();
        super.onDestroy();
    }

    private boolean interruptIfActive(String id, boolean cancel) {
        Transfer transfer = active.get(id);
        if (transfer == null)
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
        if (!foreground && !stopping)
            return;
        if (stopping && active.isEmpty())
            return;
        if (owner != null && owner != this) {
            schedule(POLL_MS);
            return;
        }
        if (queue == null) {
            queue = DownloadQueue.get(this);
            publisher = new DownloadPublisher(getContentResolver());
        }
        String blocked = stopping ? null : conditions.pauseReason(settings);
        if (!stopping && nativeReady)
            applyRateLimit();
        for (Transfer transfer : active.values()) {
            if (transfer.publishing)
                continue;
            if (blocked != null)
                transfer.waitingForConditions = true;
            poll(transfer);
        }
        if (!stopping && blocked == null) {
            while (active.size() < settings.concurrentFiles()) {
                Transfer transfer = claim();
                if (transfer == null)
                    break;
                begin(transfer);
            }
        }
        if (!active.isEmpty() || (!stopping && queue.hasQueued())) {
            if (!stopping)
                notifyQueue(blocked);
            schedule(active.isEmpty() && blocked != null ? 5_000 : POLL_MS);
        } else if (!stopping) {
            final int expectedStart = lastStart;
            main.post(() -> {
                if (!stopping && active.isEmpty() && expectedStart == lastStart && !queue.hasQueued())
                    stopSelfResult(expectedStart);
            });
        }
    }

    private Transfer claim() {
        synchronized (queue) {
            if (stopping)
                return null;
            DownloadItem next = queue.claimNext();
            if (next == null)
                return null;
            Transfer transfer = new Transfer(next);
            if (active.isEmpty())
                holdWakeLock();
            active.put(next.id, transfer);
            owner = this;
            return transfer;
        }
    }

    private void schedule(long delay) {
        Worker.handler.removeCallbacks(cycle);
        Worker.handler.postDelayed(cycle, delay);
    }

    private String applyRateLimit() {
        long limit = settings.rateLimitKiB() * 1024L;
        if (limit == appliedLimit)
            return null;
        String error = NativeDownloader.setRateLimit(limit);
        if (error == null)
            appliedLimit = limit;
        return error;
    }

    private void begin(Transfer transfer) {
        DownloadItem item = transfer.item;
        final File stage = queue.stageFile(item.id);
        if (stage.isFile() || item.staged) {
            publish(transfer, stage);
            return;
        }
        if (shouldPause(transfer)) {
            finish(transfer, DownloadItem.PAUSED, "");
            return;
        }
        try {
            if (!stage.getParentFile().mkdirs() && !stage.getParentFile().isDirectory())
                throw new IOException("Could not open the private download folder.");
            if (!nativeReady) {
                final String initialization = NativeDownloader.initialize(getApplicationContext());
                if (initialization != null) {
                    finish(transfer, DownloadItem.ERROR, initialization);
                    return;
                }
                nativeReady = true;
            }
            String error = applyRateLimit();
            if (error == null) {
                error = NativeDownloader.start(item.id, item.url, stage.getAbsolutePath(),
                    settings.connectionsPerDownload(), settings.automaticRetries());
            }
            if (error != null) {
                finish(transfer, DownloadItem.ERROR, error);
                return;
            }
            transfer.nativeActive = true;
        } catch (IOException | RuntimeException | LinkageError failure) {
            finish(transfer, DownloadItem.ERROR, "Could not prepare this download.");
        }
    }

    private void poll(Transfer transfer) {
        final String id = transfer.item.id;
        if (shouldPause(transfer) && !transfer.pauseSent) {
            // Native returns only after it records the request. The worker can still
            // be writing the partial file until the snapshot changes state.
            transfer.pauseSent = NativeDownloader.pause(id) == null;
        }
        final String snapshot = NativeDownloader.snapshot(id);
        if (snapshot == null) {
            final boolean paused = shouldPause(transfer);
            finish(transfer, paused ? DownloadItem.PAUSED : DownloadItem.ERROR,
                paused ? "" : "The download worker stopped.");
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
                    finish(transfer, DownloadItem.PAUSED, "");
                    break;
                case DownloadItem.ERROR:
                    final boolean paused = shouldPause(transfer);
                    finish(transfer, paused ? DownloadItem.PAUSED : DownloadItem.ERROR,
                        paused ? "" : state.optString("error", "The download failed."));
                    break;
                default:
                    break;
            }
        } catch (JSONException invalidSnapshot) {
            // Preserve the active slot until the native worker stops.
            transfer.pause = true;
        }
    }

    private void publish(Transfer transfer, File stage) {
        final String id = transfer.item.id;
        if (stage.isFile())
            queue.recordStage(id, stage.length());
        if (shouldPause(transfer)) {
            finish(transfer, DownloadItem.PAUSED, "");
            return;
        }
        DownloadItem item = queue.find(id);
        transfer.publishing = true;
        Worker.publisher.execute(() -> {
            try {
                String name = publisher.publish(queue, item, stage, () -> shouldPause(transfer));
                Worker.handler.post(() -> {
                    queue.complete(id, name);
                    queue.deleteStage(id);
                    finish(transfer, DownloadItem.COMPLETED, "");
                    wake();
                });
            } catch (InterruptedIOException paused) {
                Worker.handler.post(() -> {
                    finish(transfer, DownloadItem.PAUSED, "");
                    wake();
                });
            } catch (IOException | RuntimeException failure) {
                Worker.handler.post(() -> {
                    finish(transfer, DownloadItem.ERROR, "Could not save the file to Downloads. Free some space and try again.");
                    wake();
                });
            }
        });
    }

    private boolean shouldPause(Transfer transfer) {
        return stopping || transfer.pause || transfer.cancel || transfer.waitingForConditions;
    }

    private void finish(Transfer transfer, String status, String error) {
        final String id = transfer.item.id;
        synchronized (queue) {
            if (DownloadItem.PAUSED.equals(status) && transfer.waitingForConditions
                    && !stopping && !transfer.pause && !transfer.cancel) {
                status = DownloadItem.QUEUED;
            }
            queue.end(id, status, error);
            if (transfer.nativeActive)
                NativeDownloader.forget(id);
            if (transfer.cancel)
                removeItem(queue, publisher, id);
            active.remove(id, transfer);
            if (active.isEmpty()) {
                owner = null;
                releaseWakeLock();
            }
        }
    }

    private synchronized void holdWakeLock() {
        if (!stopping)
            wakeLock.acquire(TimeUnit.HOURS.toMillis(6));
    }

    private synchronized void releaseWakeLock() {
        if (wakeLock.isHeld())
            wakeLock.release();
    }

    private void notifyQueue(String blocked) {
        int count = active.size();
        Transfer only = count == 1 ? active.values().iterator().next() : null;
        DownloadItem item = only == null ? null : queue.find(only.item.id);
        String message;
        if (blocked != null) {
            message = blocked;
        } else if (count > 1) {
            message = getResources().getQuantityString(R.plurals.active_downloads_notification, count, count);
        } else if (only != null) {
            message = only.publishing ? "Saving to Downloads…" : only.pauseSent ? "Pausing…" : "Downloading…";
        } else {
            message = "Preparing downloads…";
        }
        main.post(() -> {
            if (!stopping)
                notifications.notify(NOTIFICATION_ID, notification(item, message, count));
        });
    }

    private Notification notification(DownloadItem item, String message, int count) {
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
                .setData(android.net.Uri.fromParts("auralis-transfer", item.id, null));
            PendingIntent action = PendingIntent.getService(this, 1, pause,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
            notice.addAction(new Notification.Action.Builder(null, "Pause", action).build());
        }
        if (count > 1 || item == null && queue != null && queue.hasQueued()) {
            Intent pauseAll = new Intent(this, DownloadService.class).setAction(PAUSE_ALL);
            PendingIntent action = PendingIntent.getService(this, 2, pauseAll,
                PendingIntent.FLAG_IMMUTABLE | PendingIntent.FLAG_UPDATE_CURRENT);
            notice.addAction(new Notification.Action.Builder(null, "Pause all", action).build());
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
