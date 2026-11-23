package com.alsami.auralis;

import static org.junit.Assert.assertArrayEquals;
import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.Intent;
import android.os.SystemClock;

import androidx.test.ext.junit.runners.AndroidJUnit4;
import androidx.test.platform.app.InstrumentationRegistry;

import org.junit.Test;
import org.junit.runner.RunWith;

import java.io.BufferedReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.OutputStream;
import java.net.InetAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicLong;
import java.util.function.Predicate;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

@RunWith(AndroidJUnit4.class)
public final class DownloadFlowTest {
    @Test public void segmentsPausesResumesAndRunsQueueInOrder() throws Exception {
        Instrumentation instrumentation = InstrumentationRegistry.getInstrumentation();
        Context context = instrumentation.getTargetContext();
        Activity activity = instrumentation.startActivitySync(
                new Intent(context, MainActivity.class).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
        DownloadQueue queue = DownloadQueue.get(context);
        assertTrue(queue.list().stream().noneMatch(item ->
                DownloadItem.QUEUED.equals(item.status) || DownloadItem.DOWNLOADING.equals(item.status)));

        try (RangeServer server = new RangeServer()) {
            String primaryUrl = server.url("primary");
            String waitingUrl = server.url("waiting");
            instrumentation.runOnMainSync(() -> {
                DownloadService.enqueue(context, primaryUrl, "auralis-engine-test.bin");
                DownloadService.enqueue(context, waitingUrl, "auralis-queue-test.bin");
            });
            DownloadItem primary = await(queue, primaryUrl, item ->
                    DownloadItem.DOWNLOADING.equals(item.status)
                    && item.downloaded >= 512 * 1024 && server.primary.rangeStarts.size() >= 3);
            await(queue, waitingUrl, item -> DownloadItem.QUEUED.equals(item.status));
            assertEquals("The second transfer waits for the active queue slot", 0, server.waiting.requests.get());

            instrumentation.runOnMainSync(() -> DownloadService.pause(context, primary.id));
            DownloadItem paused = await(queue, primaryUrl, item -> DownloadItem.PAUSED.equals(item.status));
            assertTrue(paused.downloaded > 0 && paused.downloaded < server.primary.bytes.length);
            DownloadItem waiting = await(queue, waitingUrl, item -> DownloadItem.COMPLETED.equals(item.status));
            assertEquals("The first transfer stays paused", DownloadItem.PAUSED, queue.find(primary.id).status);
            verifyBytes(context, waiting, server.waiting);

            long transferredBeforeResume = server.primary.bytesSent.get();
            instrumentation.runOnMainSync(() -> DownloadService.resume(context, primary.id));
            DownloadItem resumed = await(queue, primaryUrl, item -> DownloadItem.COMPLETED.equals(item.status));
            verifyBytes(context, resumed, server.primary);
            assertTrue("Resume must reuse previously received bytes",
                    server.primary.bytesSent.get() - transferredBeforeResume < server.primary.bytes.length);

            context.getContentResolver().delete(waiting.uri, null, null);
            context.getContentResolver().delete(resumed.uri, null, null);
            instrumentation.runOnMainSync(() -> {
                DownloadService.remove(context, waiting.id);
                DownloadService.remove(context, resumed.id);
            });
        } finally {
            instrumentation.runOnMainSync(activity::finish);
        }
    }

    private static DownloadItem await(DownloadQueue queue, String url, Predicate<DownloadItem> ready) {
        long deadline = SystemClock.elapsedRealtime() + 45_000;
        DownloadItem last = null;
        do {
            for (DownloadItem item : queue.list()) {
                if (!item.url.equals(url)) continue;
                last = item;
                if (DownloadItem.ERROR.equals(item.status)) throw new AssertionError(item.error);
                if (ready.test(item)) return item;
            }
            SystemClock.sleep(80);
        } while (SystemClock.elapsedRealtime() < deadline);
        throw new AssertionError("The transfer did not reach the expected state: "
                + (last == null ? "missing" : last.status + " after " + last.downloaded + " bytes"));
    }

    private static void verifyBytes(Context context, DownloadItem item, Fixture fixture) throws Exception {
        assertTrue("Completed item has a public Downloads URI", item.uri != null);
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        try (InputStream input = context.getContentResolver().openInputStream(item.uri)) {
            if (input == null) throw new AssertionError("The published download could not be opened");
            byte[] block = new byte[32 * 1024];
            int count;
            while ((count = input.read(block)) != -1) digest.update(block, 0, count);
        }
        assertArrayEquals(MessageDigest.getInstance("SHA-256").digest(fixture.bytes), digest.digest());
    }

    private static final class Fixture {
        final byte[] bytes;
        final int delayMillis;
        final AtomicInteger requests = new AtomicInteger();
        final AtomicLong bytesSent = new AtomicLong();
        final Set<Integer> rangeStarts = ConcurrentHashMap.newKeySet();

        Fixture(int size, int delayMillis) {
            bytes = new byte[size];
            this.delayMillis = delayMillis;
            for (int index = 0; index < size; index++) {
                bytes[index] = (byte) (index * 31 + (index >> 8));
            }
        }
    }

    private static final class RangeServer implements AutoCloseable {
        private static final Pattern RANGE = Pattern.compile("bytes=(\\d+)-(\\d*)", Pattern.CASE_INSENSITIVE);
        final Fixture primary = new Fixture(24 * 1024 * 1024 + 109, 28);
        final Fixture waiting = new Fixture(192 * 1024 + 31, 0);
        private final ServerSocket listener;
        private final ExecutorService workers = Executors.newCachedThreadPool(task -> {
            Thread thread = new Thread(task, "auralis-test-http");
            thread.setDaemon(true);
            return thread;
        });

        RangeServer() throws IOException {
            listener = new ServerSocket(0, 16, InetAddress.getByName("127.0.0.1"));
            workers.execute(() -> {
                while (!listener.isClosed()) {
                    try {
                        Socket socket = listener.accept();
                        workers.execute(() -> reply(socket));
                    } catch (IOException stopped) {
                        return;
                    }
                }
            });
        }

        String url(String path) {
            return "http://127.0.0.1:" + listener.getLocalPort() + "/" + path;
        }

        private void reply(Socket socket) {
            try (Socket connection = socket) {
                connection.setSoTimeout(5_000);
                BufferedReader reader = new BufferedReader(new InputStreamReader(
                        connection.getInputStream(), StandardCharsets.US_ASCII));
                String request = reader.readLine();
                if (request == null) return;
                String[] parts = request.split(" ", 3);
                if (parts.length != 3) return;
                Fixture fixture = "/primary".equals(parts[1]) ? primary : waiting;
                fixture.requests.incrementAndGet();

                int start = 0;
                int end = fixture.bytes.length - 1;
                boolean partial = false;
                String header;
                while ((header = reader.readLine()) != null && !header.isEmpty()) {
                    if (!header.regionMatches(true, 0, "Range:", 0, 6)) continue;
                    Matcher match = RANGE.matcher(header.substring(6).trim());
                    if (!match.matches()) continue;
                    start = Integer.parseInt(match.group(1));
                    if (!match.group(2).isEmpty()) end = Math.min(end, Integer.parseInt(match.group(2)));
                    partial = true;
                }
                OutputStream output = connection.getOutputStream();
                if (start > end) {
                    output.write(("HTTP/1.1 416 Range Not Satisfiable\r\nContent-Range: bytes */"
                            + fixture.bytes.length + "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                            .getBytes(StandardCharsets.US_ASCII));
                    return;
                }

                if (partial) fixture.rangeStarts.add(start);
                String headers = (partial ? "HTTP/1.1 206 Partial Content" : "HTTP/1.1 200 OK")
                        + "\r\nAccept-Ranges: bytes\r\nETag: \"auralis-range-fixture\"\r\n"
                        + "Last-Modified: Fri, 01 Jan 2021 00:00:00 GMT\r\n"
                        + "Content-Type: application/octet-stream\r\nContent-Length: " + (end - start + 1)
                        + (partial ? "\r\nContent-Range: bytes " + start + "-" + end + "/" + fixture.bytes.length : "")
                        + "\r\nConnection: close\r\n\r\n";
                output.write(headers.getBytes(StandardCharsets.US_ASCII));
                if ("HEAD".equals(parts[0])) return;
                for (int offset = start; offset <= end;) {
                    int count = Math.min(16 * 1024, end - offset + 1);
                    output.write(fixture.bytes, offset, count);
                    fixture.bytesSent.addAndGet(count);
                    offset += count;
                    if (fixture.delayMillis != 0) SystemClock.sleep(fixture.delayMillis);
                }
            } catch (IOException disconnected) {
                // Pausing a transfer closes the outstanding range requests.
            }
        }

        @Override public void close() throws IOException {
            listener.close();
            workers.shutdownNow();
        }
    }
}
