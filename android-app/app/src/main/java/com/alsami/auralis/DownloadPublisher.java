package com.alsami.auralis;

import android.content.ContentResolver;
import android.content.ContentValues;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.os.Environment;
import android.os.ParcelFileDescriptor;
import android.provider.MediaStore;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InterruptedIOException;
import java.util.Locale;
import java.util.function.BooleanSupplier;

final class DownloadPublisher {
    private static final Uri DOWNLOADS = MediaStore.Downloads.EXTERNAL_CONTENT_URI;
    private static final String FOLDER = Environment.DIRECTORY_DOWNLOADS + "/Auralis/";
    private static final String NAME = MediaStore.MediaColumns.DISPLAY_NAME;
    private static final String PENDING = MediaStore.MediaColumns.IS_PENDING;
    private static final String PATH = MediaStore.MediaColumns.RELATIVE_PATH;
    private static final String MIME = MediaStore.MediaColumns.MIME_TYPE;

    private final ContentResolver resolver;

    DownloadPublisher(ContentResolver resolver) {
        this.resolver = resolver;
    }

    String publish(DownloadQueue queue, DownloadItem item, File source, BooleanSupplier stopped)
            throws IOException {
        Uri uri = item.mediaUri;
        try (Cursor row = uri == null ? null : query(uri, new String[]{NAME, PENDING}, null, null)) {
            if (row == null || !row.moveToFirst())
                uri = null;
            else if (row.getInt(1) == 0)
                return row.getString(0);
        }
        checkRunning(stopped);
        if (!source.isFile())
            throw new IOException("The completed temporary file is missing.");
        if (uri == null) {
            final String temporaryName = "auralis-" + item.id + ".bin";
            uri = findPending(temporaryName);
            if (uri == null) {
                ContentValues values = new ContentValues();
                values.put(NAME, temporaryName);
                values.put(MIME, "application/octet-stream");
                values.put(PATH, FOLDER);
                values.put(PENDING, 1);
                uri = resolver.insert(DOWNLOADS, values);
                if (uri == null)
                    throw new IOException("Android could not reserve the file in Downloads.");
            }
            queue.recordMedia(item.id, uri);
        }

        try (FileInputStream input = new FileInputStream(source)) {
            ParcelFileDescriptor descriptor = resolver.openFileDescriptor(uri, "rwt");
            if (descriptor == null)
                throw new IOException("Android could not open the new Downloads file.");
            try (ParcelFileDescriptor.AutoCloseOutputStream output =
                    new ParcelFileDescriptor.AutoCloseOutputStream(descriptor)) {
                final byte[] buffer = new byte[256 * 1024];
                int read;
                while ((read = input.read(buffer)) != -1) {
                    checkRunning(stopped);
                    output.write(buffer, 0, read);
                }
                output.getFD().sync();
            }
        }
        checkRunning(stopped);
        ContentValues ready = new ContentValues();
        ready.put(NAME, item.name);
        ready.put(MIME, mimeType(item.name));
        ready.put(PENDING, 0);
        if (resolver.update(uri, ready, null, null) != 1)
            throw new IOException("Android could not publish the completed file.");
        try (Cursor row = query(uri, new String[]{NAME}, null, null)) {
            return row != null && row.moveToFirst() ? row.getString(0) : item.name;
        }
    }

    void discardPending(DownloadItem item) {
        if (DownloadItem.COMPLETED.equals(item.status))
            return;
        final Uri recorded = item.mediaUri;
        if (recorded != null) {
            try (Cursor row = query(recorded, new String[]{PENDING}, null, null)) {
                if (row != null && row.moveToFirst() && row.getInt(0) == 1)
                    resolver.delete(recorded, null, null);
            }
        }
        final Uri unnamed = findPending("auralis-" + item.id + ".bin");
        if (unnamed != null)
            resolver.delete(unnamed, null, null);
    }

    private Uri findPending(String name) {
        try (Cursor row = query(DOWNLOADS, new String[]{MediaStore.Downloads._ID},
                NAME + " = ? AND " + PATH + " = ? AND " + PENDING + " = 1", new String[]{name, FOLDER})) {
            return row != null && row.moveToFirst()
                ? Uri.withAppendedPath(DOWNLOADS, Long.toString(row.getLong(0))) : null;
        }
    }

    @SuppressWarnings("deprecation")
    private Cursor query(Uri uri, String[] columns, String selection, String[] arguments) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R)
            return resolver.query(MediaStore.setIncludePending(uri), columns, selection, arguments, null);
        Bundle query = new Bundle();
        query.putInt(MediaStore.QUERY_ARG_MATCH_PENDING, MediaStore.MATCH_INCLUDE);
        query.putString(ContentResolver.QUERY_ARG_SQL_SELECTION, selection);
        query.putStringArray(ContentResolver.QUERY_ARG_SQL_SELECTION_ARGS, arguments);
        return resolver.query(uri, columns, query, null);
    }

    private static void checkRunning(BooleanSupplier stopped) throws InterruptedIOException {
        if (stopped.getAsBoolean())
            throw new InterruptedIOException("Publishing paused.");
    }

    private static String mimeType(String name) {
        final int dot = name.lastIndexOf('.');
        if (dot >= 0 && dot < name.length() - 1) {
            String extension = name.substring(dot + 1).toLowerCase(Locale.ROOT);
            String mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension);
            if (mime != null)
                return mime;
        }
        return "application/octet-stream";
    }
}
