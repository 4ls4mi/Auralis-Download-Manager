package com.alsami.auralis;

import android.content.ContentValues;
import android.content.Context;
import android.database.Cursor;
import android.database.sqlite.SQLiteDatabase;
import android.database.sqlite.SQLiteOpenHelper;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;

import java.io.File;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArraySet;

public final class DownloadQueue extends SQLiteOpenHelper {
    private static final int SCHEMA_VERSION = 2;
    private static final String TABLE = "downloads";
    private static final String PRIORITY_COLUMN = "priority INTEGER NOT NULL DEFAULT 0 CHECK (priority BETWEEN -1 AND 1)";
    private static final String QUEUE_ORDER = "priority DESC, sequence ASC";
    private static final String LIST_ORDER = "CASE status WHEN 'downloading' THEN 0 WHEN 'queued' THEN 1 ELSE 2 END, "
        + "CASE WHEN status IN ('downloading', 'queued') THEN priority END DESC, "
        + "CASE WHEN status IN ('downloading', 'queued') THEN sequence END ASC, sequence DESC";
    private static DownloadQueue instance;

    /** A download whose address and name have already been validated by the service. */
    public static final class NewDownload {
        final String url;
        final String name;
        final int priority;

        public NewDownload(String url, String name) {
            this(url, name, DownloadItem.PRIORITY_NORMAL);
        }

        public NewDownload(String url, String name, int priority) {
            this.url = Objects.requireNonNull(url, "url");
            this.name = Objects.requireNonNull(name, "name");
            this.priority = checkedPriority(priority);
        }
    }

    public interface Listener {
        void onQueueChanged();
    }

    public static synchronized DownloadQueue get(Context context) {
        if (instance == null)
            instance = new DownloadQueue(context.getApplicationContext());
        return instance;
    }

    private final File staging;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final CopyOnWriteArraySet<Listener> listeners = new CopyOnWriteArraySet<>();
    private boolean notificationPending;

    private DownloadQueue(Context context) {
        super(context, "auralis-downloads.db", null, SCHEMA_VERSION);
        staging = new File(context.getFilesDir(), "staging");
        // After a process restart wait for the user before resuming network work.
        getWritableDatabase().update(TABLE, state(DownloadItem.PAUSED, ""),
            "status IN (?, ?)", new String[]{DownloadItem.QUEUED, DownloadItem.DOWNLOADING});
    }

    @Override public void onCreate(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE downloads (sequence INTEGER PRIMARY KEY, id TEXT UNIQUE NOT NULL,"
            + " url TEXT NOT NULL, name TEXT NOT NULL, status TEXT NOT NULL, error TEXT NOT NULL DEFAULT '',"
            + " downloaded INTEGER NOT NULL DEFAULT 0, total INTEGER NOT NULL DEFAULT -1,"
            + " rate INTEGER NOT NULL DEFAULT 0, media_uri TEXT, staged INTEGER NOT NULL DEFAULT 0, "
            + PRIORITY_COLUMN + ")");
        createQueueIndex(db);
    }

    @Override public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        if (oldVersion != 1 || newVersion != SCHEMA_VERSION)
            throw new IllegalStateException("Unsupported download queue schema");
        db.execSQL("ALTER TABLE downloads ADD COLUMN " + PRIORITY_COLUMN);
        createQueueIndex(db);
    }

    private static void createQueueIndex(SQLiteDatabase db) {
        db.execSQL("CREATE INDEX downloads_queue ON downloads (status, " + QUEUE_ORDER + ")");
    }

    public synchronized List<DownloadItem> list() {
        List<DownloadItem> items = new ArrayList<>();
        try (Cursor rows = getReadableDatabase().query(TABLE, null, null, null,
                null, null, LIST_ORDER)) {
            while (rows.moveToNext())
                items.add(read(rows));
        }
        return Collections.unmodifiableList(items);
    }

    public void addListener(Listener listener) {
        listeners.add(listener);
    }

    public void removeListener(Listener listener) {
        listeners.remove(listener);
    }

    synchronized String add(String url, String name) {
        return add(url, name, DownloadItem.PRIORITY_NORMAL);
    }

    synchronized String add(String url, String name, int priority) {
        String id = insert(getWritableDatabase(), new NewDownload(url, name, priority));
        changed();
        return id;
    }

    synchronized List<String> addAll(List<NewDownload> downloads) {
        if (downloads.isEmpty())
            return Collections.emptyList();
        List<String> ids = new ArrayList<>(downloads.size());
        SQLiteDatabase db = getWritableDatabase();
        db.beginTransaction();
        try {
            for (NewDownload download : downloads)
                ids.add(insert(db, download));
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
        }
        changed();
        return Collections.unmodifiableList(ids);
    }

    private static String insert(SQLiteDatabase db, NewDownload download) {
        String id = UUID.randomUUID().toString();
        ContentValues values = state(DownloadItem.QUEUED, "");
        values.put("id", id);
        values.put("url", download.url);
        values.put("name", download.name);
        values.put("priority", download.priority);
        db.insertOrThrow(TABLE, null, values);
        return id;
    }

    public synchronized boolean setPriority(String id, int priority) {
        ContentValues values = new ContentValues();
        values.put("priority", checkedPriority(priority));
        if (id == null)
            return false;
        return update(values, "id = ? AND status != ? AND priority != ?",
            new String[]{id, DownloadItem.COMPLETED, Integer.toString(priority)});
    }

    synchronized boolean resume(String id) {
        return update(state(DownloadItem.QUEUED, ""), "id = ? AND status IN (?, ?)",
            new String[]{id, DownloadItem.PAUSED, DownloadItem.ERROR});
    }

    synchronized boolean pauseQueued(String id) {
        return update(state(DownloadItem.PAUSED, ""), "id = ? AND status = ?",
            new String[]{id, DownloadItem.QUEUED});
    }

    synchronized void failQueued(String id, String error) {
        update(state(DownloadItem.ERROR, error), "id = ? AND status = ?",
            new String[]{id, DownloadItem.QUEUED});
    }

    synchronized DownloadItem claimNext() {
        SQLiteDatabase db = getWritableDatabase();
        DownloadItem claimed = null;
        db.beginTransaction();
        try {
            String id;
            try (Cursor rows = db.query(TABLE, new String[]{"id"}, "status = ?",
                    new String[]{DownloadItem.QUEUED}, null, null, QUEUE_ORDER, "1")) {
                id = rows.moveToFirst() ? rows.getString(0) : null;
            }
            if (id != null && db.update(TABLE, state(DownloadItem.DOWNLOADING, ""),
                    "id = ? AND status = ?", new String[]{id, DownloadItem.QUEUED}) == 1)
                claimed = find(id);
            db.setTransactionSuccessful();
        } finally {
            db.endTransaction();
        }
        if (claimed != null)
            changed();
        return claimed;
    }

    synchronized DownloadItem find(String id) {
        try (Cursor rows = getReadableDatabase().query(TABLE, null, "id = ?",
                new String[]{id}, null, null, null, "1")) {
            return rows.moveToNext() ? read(rows) : null;
        }
    }

    synchronized boolean hasQueued() {
        try (Cursor rows = getReadableDatabase().query(TABLE, new String[]{"id"},
                "status = ?", new String[]{DownloadItem.QUEUED}, null, null, null, "1")) {
            return rows.moveToNext();
        }
    }

    synchronized void updateProgress(String id, long bytes, long total, long rate) {
        ContentValues values = new ContentValues();
        values.put("downloaded", bytes);
        values.put("total", total);
        values.put("rate", rate);
        update(values, "id = ? AND status = ? AND (downloaded != ? OR total != ? OR rate != ?)",
            new String[]{id, DownloadItem.DOWNLOADING, Long.toString(bytes), Long.toString(total),
                Long.toString(rate)});
    }

    synchronized void recordStage(String id, long size) {
        ContentValues values = new ContentValues();
        values.put("staged", 1);
        values.put("downloaded", size);
        values.put("total", size);
        values.put("rate", 0);
        updateRunning(id, values);
    }

    synchronized void recordMedia(String id, Uri uri) {
        ContentValues values = new ContentValues();
        values.put("media_uri", uri.toString());
        updateRunning(id, values);
    }

    synchronized void complete(String id, String name) {
        ContentValues values = state(DownloadItem.COMPLETED, "");
        values.put("name", name);
        updateRunning(id, values);
    }

    synchronized void end(String id, String status, String error) {
        updateRunning(id, state(status, error));
    }

    synchronized void pauseWaiting() {
        pauseAllQueued();
    }

    synchronized int pauseAllQueued() {
        return changeStatus(DownloadItem.QUEUED, DownloadItem.PAUSED);
    }

    // An explicit Resume all leaves failed jobs available for individual retry.
    synchronized int resumePaused() {
        return changeStatus(DownloadItem.PAUSED, DownloadItem.QUEUED);
    }

    private int changeStatus(String previous, String next) {
        int count = getWritableDatabase().update(TABLE, state(next, ""), "status = ?", new String[]{previous});
        if (count > 0)
            changed();
        return count;
    }

    synchronized DownloadItem remove(String id) {
        DownloadItem item = find(id);
        if (item == null || DownloadItem.DOWNLOADING.equals(item.status))
            return null;
        if (getWritableDatabase().delete(TABLE, "id = ?", new String[]{id}) != 1)
            return null;
        changed();
        return item;
    }

    File stageFile(String id) {
        return new File(new File(staging, id), "transfer");
    }

    void deleteStage(String id) {
        File directory = stageFile(id).getParentFile();
        File[] entries = directory.listFiles();
        if (entries != null)
            for (File entry : entries)
                entry.delete();
        directory.delete();
    }

    private void updateRunning(String id, ContentValues values) {
        update(values, "id = ? AND status = ?", new String[]{id, DownloadItem.DOWNLOADING});
    }

    private boolean update(ContentValues values, String filter, String[] arguments) {
        if (getWritableDatabase().update(TABLE, values, filter, arguments) == 0)
            return false;
        changed();
        return true;
    }

    private static ContentValues state(String status, String error) {
        ContentValues values = new ContentValues();
        values.put("status", status);
        values.put("error", error);
        values.put("rate", 0);
        return values;
    }

    private static int checkedPriority(int priority) {
        if (priority < DownloadItem.PRIORITY_LOW || priority > DownloadItem.PRIORITY_HIGH)
            throw new IllegalArgumentException("Invalid download priority");
        return priority;
    }

    private static DownloadItem read(Cursor row) {
        final String media = string(row, "media_uri");
        return new DownloadItem(string(row, "id"), string(row, "url"), string(row, "name"),
            string(row, "status"), string(row, "error"), number(row, "downloaded"),
            number(row, "total"), number(row, "rate"), (int) number(row, "priority"),
            media == null ? null : Uri.parse(media), number(row, "staged") == 1);
    }

    private static String string(Cursor row, String column) {
        return row.getString(row.getColumnIndexOrThrow(column));
    }

    private static long number(Cursor row, String column) {
        return row.getLong(row.getColumnIndexOrThrow(column));
    }

    private synchronized void changed() {
        if (notificationPending)
            return;
        notificationPending = true;
        main.post(() -> {
            synchronized (this) {
                notificationPending = false;
            }
            for (Listener listener : listeners)
                listener.onQueueChanged();
        });
    }
}
