package com.alsami.auralis;

import android.net.Uri;

public final class DownloadItem {
    public static final String QUEUED = "queued";
    public static final String DOWNLOADING = "downloading";
    public static final String PAUSED = "paused";
    public static final String COMPLETED = "completed";
    public static final String ERROR = "error";

    public final String id;
    public final String url;
    public final String name;
    public final String status;
    public final String error;
    public final long downloaded;
    public final long total;
    public final long rate;
    public final Uri uri;
    final Uri mediaUri;
    final boolean staged;

    DownloadItem(String id, String url, String name, String status, String error, long downloaded,
                 long total, long rate, Uri mediaUri, boolean staged) {
        this.id = id;
        this.url = url;
        this.name = name;
        this.status = status;
        this.error = error;
        this.downloaded = downloaded;
        this.total = total;
        this.rate = rate;
        this.mediaUri = mediaUri;
        this.uri = COMPLETED.equals(status) ? mediaUri : null;
        this.staged = staged;
    }
}
