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
import java.util.UUID;
import java.util.concurrent.CopyOnWriteArraySet;

public final class DownloadQueue extends SQLiteOpenHelper {
    private static final String TABLE = "downloads";
    private static DownloadQueue instance;

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
        super(context, "auralis-downloads.db", null, 1);
        staging = new File(context.getFilesDir(), "staging");
        // After a process restart wait for the user before resuming network work.
        getWritableDatabase().update(TABLE, state(DownloadItem.PAUSED, ""),
            "status IN (?, ?)", new String[]{DownloadItem.QUEUED, DownloadItem.DOWNLOADING});
    }

    @Override public void onCreate(SQLiteDatabase db) {
        db.execSQL("CREATE TABLE downloads (sequence INTEGER PRIMARY KEY, id TEXT UNIQUE NOT NULL,"
            + " url TEXT NOT NULL, name TEXT NOT NULL, status TEXT NOT NULL, error TEXT NOT NULL DEFAULT '',"
            + " downloaded INTEGER NOT NULL DEFAULT 0, total INTEGER NOT NULL DEFAULT -1,"
            + " rate INTEGER NOT NULL DEFAULT 0, media_uri TEXT, staged INTEGER NOT NULL DEFAULT 0)");
    }

    @Override public void onUpgrade(SQLiteDatabase db, int oldVersion, int newVersion) {
        throw new IllegalStateException("Unsupported download queue schema");
    }

    public synchronized List<DownloadItem> list() {
        List<DownloadItem> items = new ArrayList<>();
        try (Cursor rows = getReadableDatabase().query(TABLE, null, null, null,
                null, null, "sequence DESC")) {
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
        String id = UUID.randomUUID().toString();
        ContentValues values = state(DownloadItem.QUEUED, "");
        values.put("id", id);
        values.put("url", url);
        values.put("name", name);
        getWritableDatabase().insertOrThrow(TABLE, null, values);
        changed();
        return id;
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
        try (Cursor rows = getReadableDatabase().query(TABLE, null, "status = ?",
                new String[]{DownloadItem.QUEUED}, null, null, "sequence ASC", "1")) {
            if (!rows.moveToNext())
                return null;
            DownloadItem item = read(rows);
            update(state(DownloadItem.DOWNLOADING, ""), "id = ?", new String[]{item.id});
            return item;
        }
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
        update(state(DownloadItem.PAUSED, ""), "status = ?", new String[]{DownloadItem.QUEUED});
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

    private static DownloadItem read(Cursor row) {
        final String media = string(row, "media_uri");
        return new DownloadItem(string(row, "id"), string(row, "url"), string(row, "name"),
            string(row, "status"), string(row, "error"), number(row, "downloaded"),
            number(row, "total"), number(row, "rate"), media == null ? null : Uri.parse(media),
            number(row, "staged") == 1);
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
