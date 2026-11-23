package com.alsami.auralis;

import android.Manifest;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.text.TextUtils;
import android.text.format.Formatter;
import android.util.Patterns;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.widget.AbsListView;
import android.widget.BaseAdapter;
import android.widget.Button;
import android.widget.EditText;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ListView;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.net.URISyntaxException;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collections;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Set;
import java.util.UUID;
import java.util.regex.Matcher;

public final class MainActivity extends Activity implements DownloadQueue.Listener {
    private static final int WINDOW = 0xff171523;
    private static final int SURFACE = 0xff252137;
    private static final int FIELD = 0xff1c192d;
    private static final int BORDER = 0xff53486c;
    private static final int TEXT = 0xfff7f2ff;
    private static final int MUTED = 0xffccc2df;
    private static final int ACCENT = 0xffc1a7ff;
    private static final int ON_ACCENT = 0xff231335;
    private static final int COMPLETE = 0xff8de3b9;
    private static final int PAUSED = 0xffffd088;
    private static final int ERROR = 0xffffa9b7;
    private static final int REQUEST_NOTIFICATIONS = 1;
    private static final int REQUEST_LINK_DOCUMENT = 2;
    private static final int MAX_BATCH_SIZE = 256 * 1024;
    private static final int MAX_BATCH_LINKS = 200;
    private static final String DRAFT_URL = "draftUrl";
    private static final String BATCH_DRAFT = "batchDraft";
    private static final String STATUS_FILTER = "statusFilter";
    private static final String[] FILTERS = {
            "", DownloadItem.DOWNLOADING, DownloadItem.QUEUED, DownloadItem.PAUSED,
            DownloadItem.COMPLETED, DownloadItem.ERROR
    };
    private static final int[] FILTER_LABELS = {
            R.string.main_filter_all, R.string.main_downloading, R.string.main_queued,
            R.string.main_paused, R.string.main_complete, R.string.main_failed
    };
    private static final int[] PRIORITIES = {
            DownloadItem.PRIORITY_HIGH, DownloadItem.PRIORITY_NORMAL, DownloadItem.PRIORITY_LOW
    };
    private static final int[] PRIORITY_LABELS = {
            R.string.main_priority_high, R.string.main_priority_normal, R.string.main_priority_low
    };

    private DownloadQueue queue;
    private DownloadsAdapter adapter;
    private ListView downloads;
    private EditText urlInput;
    private TextView urlProblem;
    private TextView queueSummary;
    private Button filterButton;
    private Button pauseAll;
    private Button resumeAll;
    private int filterSelection;
    private AlertDialog batchDialog;
    private EditText batchInput;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        queue = DownloadQueue.get(this);
        if (savedInstanceState != null) {
            filterSelection = Math.max(0, Math.min(FILTERS.length - 1, savedInstanceState.getInt(STATUS_FILTER)));
        }
        setContentView(createContent());
        if (savedInstanceState == null) {
            prefillFromShare(getIntent());
        } else {
            urlInput.setText(savedInstanceState.getString(DRAFT_URL, ""));
            if (savedInstanceState.containsKey(BATCH_DRAFT)) {
                String draft = savedInstanceState.getString(BATCH_DRAFT, "");
                downloads.post(() -> showBatchEditor(draft));
            }
        }
    }

    @Override
    protected void onStart() {
        super.onStart();
        queue.addListener(this);
        onQueueChanged();
    }

    @Override
    protected void onStop() {
        queue.removeListener(this);
        super.onStop();
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        prefillFromShare(intent);
    }

    @Override
    protected void onSaveInstanceState(Bundle state) {
        state.putString(DRAFT_URL, urlInput.getText().toString());
        state.putInt(STATUS_FILTER, filterSelection);
        if (batchInput != null) {
            String draft = batchInput.getText().toString();
            state.putString(BATCH_DRAFT, draft.length() <= MAX_BATCH_SIZE ? draft : "");
        }
        super.onSaveInstanceState(state);
    }

    @Override
    public void onQueueChanged() {
        List<DownloadItem> visible = new ArrayList<>();
        int active = 0;
        int waiting = 0;
        boolean resumable = false;
        String filter = FILTERS[filterSelection];
        for (DownloadItem item : queue.list()) {
            if (DownloadItem.DOWNLOADING.equals(item.status)) {
                active++;
            } else if (DownloadItem.QUEUED.equals(item.status)) {
                waiting++;
            } else if (DownloadItem.PAUSED.equals(item.status)) {
                resumable = true;
            }
            if (filter.isEmpty() || filter.equals(item.status)) {
                visible.add(item);
            }
        }
        adapter.update(visible);
        queueSummary.setText(getString(R.string.main_queue_summary, active, waiting));
        queueSummary.setVisibility(active + waiting > 0 ? View.VISIBLE : View.GONE);
        pauseAll.setEnabled(active + waiting > 0);
        resumeAll.setEnabled(resumable);
        pauseAll.setAlpha(pauseAll.isEnabled() ? 1f : .52f);
        resumeAll.setAlpha(resumeAll.isEnabled() ? 1f : .52f);
    }

    private View createContent() {
        LinearLayout content = column();
        content.setBackgroundColor(WINDOW);
        content.setFocusableInTouchMode(true);
        alignWithSystemBars(content);

        LinearLayout brand = row();
        brand.setPadding(dp(18), dp(13), dp(18), dp(14));
        ImageView mark = new ImageView(this);
        mark.setImageResource(R.drawable.auralis_mark);
        mark.setScaleType(ImageView.ScaleType.FIT_CENTER);
        mark.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        brand.addView(mark, new LinearLayout.LayoutParams(dp(35), dp(35)));
        TextView title = label(23, TEXT, true);
        title.setText(R.string.main_brand);
        title.setSingleLine(true);
        title.setEllipsize(TextUtils.TruncateAt.END);
        title.setAccessibilityHeading(true);
        LinearLayout.LayoutParams titleSize = rowWeight();
        titleSize.setMarginStart(dp(11));
        brand.addView(title, titleSize);
        Button browser = button(R.string.main_browser, false);
        browser.setOnClickListener(view -> BrowserActivity.open(this));
        addBeside(brand, browser, 6);
        Button settings = button(R.string.main_settings, false);
        settings.setOnClickListener(view -> startActivity(new Intent(this, DownloadSettingsActivity.class)));
        addBeside(brand, settings, 6);
        content.addView(brand, fullWidth());

        downloads = new ListView(this);
        downloads.setDivider(null);
        downloads.setSelector(new ColorDrawable(Color.TRANSPARENT));
        downloads.setItemsCanFocus(true);
        downloads.setClipToPadding(false);
        downloads.setPadding(dp(18), 0, dp(18), dp(8));
        downloads.addHeaderView(createQueueHeader(), null, false);
        adapter = new DownloadsAdapter();
        downloads.setAdapter(adapter);
        content.addView(downloads, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f));
        content.requestFocus();
        return content;
    }

    private void alignWithSystemBars(View content) {
        Window window = getWindow();
        window.setStatusBarColor(Color.TRANSPARENT);
        window.setNavigationBarColor(Color.TRANSPARENT);
        window.setNavigationBarContrastEnforced(false);
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        if (Build.VERSION.SDK_INT >= 30) {
            window.setDecorFitsSystemWindows(false);
            WindowInsetsController controller = window.getDecorView().getWindowInsetsController();
            if (controller != null) {
                controller.setSystemBarsAppearance(0, WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                        | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);
            }
        } else {
            window.getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                    | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION);
        }
        content.setOnApplyWindowInsetsListener((view, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                Insets safe = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                Insets keyboard = insets.getInsets(WindowInsets.Type.ime());
                view.setPadding(safe.left, safe.top, safe.right, Math.max(safe.bottom, keyboard.bottom));
            } else {
                view.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                        insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
            }
            return insets;
        });
    }

    private View createQueueHeader() {
        LinearLayout header = column();
        LinearLayout form = card();
        TextView urlLabel = label(15, TEXT, true);
        urlLabel.setText(R.string.main_url);
        form.addView(urlLabel, fullWidth());

        urlInput = new EditText(this);
        urlInput.setId(View.generateViewId());
        urlLabel.setLabelFor(urlInput.getId());
        urlInput.setSingleLine(true);
        urlInput.setTextSize(16);
        urlInput.setHint(R.string.main_url_hint);
        urlInput.setHintTextColor(MUTED);
        urlInput.setTextColor(TEXT);
        urlInput.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        urlInput.setImeOptions(EditorInfo.IME_ACTION_GO);
        urlInput.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);
        urlInput.setMinHeight(dp(50));
        urlInput.setPadding(dp(12), dp(8), dp(12), dp(8));
        urlInput.setBackground(shape(FIELD, 12, BORDER));
        urlInput.setOnEditorActionListener((view, actionId, event) -> {
            if (actionId != EditorInfo.IME_ACTION_GO) {
                return false;
            }
            enqueueDraft();
            return true;
        });
        addBelow(form, urlInput, 8);

        urlProblem = label(14, ERROR, false);
        urlProblem.setAccessibilityLiveRegion(View.ACCESSIBILITY_LIVE_REGION_POLITE);
        urlProblem.setVisibility(View.GONE);
        addBelow(form, urlProblem, 7);

        Button add = button(R.string.main_add, true);
        add.setOnClickListener(view -> enqueueDraft());
        Button batch = button(R.string.main_add_links, false);
        batch.setOnClickListener(view -> showBatchEditor(""));
        addBelow(form, buttonPair(add, batch), 10);
        header.addView(form, fullWidth());

        LinearLayout queueHeading = row();
        TextView heading = label(18, TEXT, true);
        heading.setText(R.string.main_downloads);
        heading.setAccessibilityHeading(true);
        queueHeading.addView(heading, rowWeight());
        queueSummary = label(13, MUTED, false);
        queueSummary.setGravity(Gravity.END);
        queueSummary.setMaxWidth(dp(154));
        queueSummary.setVisibility(View.GONE);
        queueHeading.addView(queueSummary);
        LinearLayout.LayoutParams headingSpace = fullWidth();
        headingSpace.topMargin = dp(20);
        headingSpace.bottomMargin = dp(8);
        header.addView(queueHeading, headingSpace);
        filterButton = button(FILTER_LABELS[filterSelection], false);
        updateFilterLabel();
        filterButton.setOnClickListener(view -> showFilterChoices());
        header.addView(filterButton, fullWidth());
        pauseAll = button(R.string.main_pause_all, false);
        pauseAll.setOnClickListener(view -> performDownloadAction(() -> DownloadService.pauseAll(this)));
        resumeAll = button(R.string.main_resume_all, false);
        resumeAll.setOnClickListener(view -> performDownloadAction(() -> DownloadService.resumeAll(this)));
        LinearLayout.LayoutParams controls = fullWidth();
        controls.topMargin = dp(7);
        controls.bottomMargin = dp(10);
        header.addView(buttonPair(pauseAll, resumeAll), controls);
        return header;
    }

    private void updateFilterLabel() {
        String label = getString(FILTER_LABELS[filterSelection]);
        filterButton.setText(label);
        filterButton.setContentDescription(getString(R.string.main_filter_current, label));
    }

    private void showFilterChoices() {
        new AlertDialog.Builder(this)
                .setTitle(R.string.main_filter_downloads)
                .setSingleChoiceItems(choiceLabels(FILTER_LABELS), filterSelection, (dialog, index) -> {
                    filterSelection = index;
                    updateFilterLabel();
                    onQueueChanged();
                    dialog.dismiss();
                })
                .setNegativeButton(android.R.string.cancel, null)
                .show();
    }

    private void showPriorityChoices(DownloadItem item) {
        int selected = 1;
        for (int index = 0; index < PRIORITIES.length; index++) {
            if (PRIORITIES[index] == item.priority) {
                selected = index;
                break;
            }
        }
        new AlertDialog.Builder(this)
                .setTitle(R.string.main_queue_priority)
                .setSingleChoiceItems(choiceLabels(PRIORITY_LABELS), selected, (dialog, index) -> {
                    performDownloadAction(() -> DownloadService.setPriority(this, item.id, PRIORITIES[index]));
                    dialog.dismiss();
                })
                .setNegativeButton(android.R.string.cancel, null)
                .show();
    }

    private String[] choiceLabels(int[] resourceIds) {
        String[] labels = new String[resourceIds.length];
        for (int index = 0; index < labels.length; index++) {
            labels[index] = getString(resourceIds[index]);
        }
        return labels;
    }

    private void showBatchEditor(String draft) {
        if (batchDialog != null || isFinishing()) {
            return;
        }
        LinearLayout form = column();
        form.setPadding(dp(22), dp(14), dp(22), 0);
        EditText input = new EditText(this);
        input.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_FLAG_MULTI_LINE
                | InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        input.setMinLines(5);
        input.setMaxLines(8);
        input.setTextSize(15);
        input.setGravity(Gravity.TOP | Gravity.START);
        input.setTextColor(TEXT);
        input.setHintTextColor(MUTED);
        input.setHint(R.string.main_batch_hint);
        input.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO);
        input.setBackground(shape(FIELD, 12, BORDER));
        input.setPadding(dp(12), dp(10), dp(12), dp(10));
        input.setText(draft);
        form.addView(input, fullWidth());

        AlertDialog editor = new AlertDialog.Builder(this)
                .setTitle(R.string.main_add_links_title)
                .setView(form)
                .setNeutralButton(R.string.main_import_links, null)
                .setNegativeButton(android.R.string.cancel, null)
                .setPositiveButton(R.string.main_review_links, null)
                .create();
        batchInput = input;
        batchDialog = editor;
        editor.setOnShowListener(ignored -> {
            editor.getButton(AlertDialog.BUTTON_NEUTRAL).setOnClickListener(view -> chooseLinkDocument(input));
            editor.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(view -> reviewBatch(input));
        });
        editor.setOnDismissListener(ignored -> {
            batchInput = null;
            batchDialog = null;
        });
        editor.show();
    }

    private void chooseLinkDocument(EditText input) {
        Intent picker = new Intent(Intent.ACTION_OPEN_DOCUMENT)
                .setType("text/*")
                .addCategory(Intent.CATEGORY_OPENABLE);
        try {
            startActivityForResult(picker, REQUEST_LINK_DOCUMENT);
        } catch (ActivityNotFoundException error) {
            input.setError(getString(R.string.main_batch_read_failed));
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != REQUEST_LINK_DOCUMENT || resultCode != RESULT_OK || data == null || data.getData() == null) {
            return;
        }
        if (batchDialog == null) {
            showBatchEditor("");
        }
        if (batchInput == null) {
            return;
        }
        EditText input = batchInput;
        Uri document = data.getData();
        new Thread(() -> importLinkDocument(document, input), "Auralis link import").start();
    }

    private void importLinkDocument(Uri document, EditText input) {
        String text = null;
        int failure = 0;
        try (InputStream stream = getContentResolver().openInputStream(document)) {
            if (stream == null) {
                throw new IOException("The document has no content stream");
            }
            ByteArrayOutputStream contents = new ByteArrayOutputStream();
            byte[] buffer = new byte[8192];
            int count;
            while ((count = stream.read(buffer)) != -1) {
                if (contents.size() + count > MAX_BATCH_SIZE) {
                    failure = R.string.main_batch_too_large;
                    break;
                }
                contents.write(buffer, 0, count);
            }
            if (failure == 0) {
                text = new String(contents.toByteArray(), StandardCharsets.UTF_8);
            }
        } catch (IOException | SecurityException error) {
            failure = R.string.main_batch_read_failed;
        }
        String imported = text;
        int issue = failure;
        runOnUiThread(() -> {
            if (isDestroyed() || batchInput != input) {
                return;
            }
            if (issue != 0) {
                input.setError(getString(issue));
            } else {
                input.setError(null);
                input.setText(imported);
            }
        });
    }

    private void reviewBatch(EditText input) {
        String draft = input.getText().toString();
        if (draft.length() > MAX_BATCH_SIZE || draft.getBytes(StandardCharsets.UTF_8).length > MAX_BATCH_SIZE) {
            input.setError(getString(R.string.main_batch_too_large));
            return;
        }
        if (draft.startsWith("\ufeff")) {
            draft = draft.substring(1);
        }
        Set<String> links = new LinkedHashSet<>();
        int skipped = 0;
        for (String line : draft.split("\\R")) {
            String url = line.trim();
            if (url.isEmpty()) {
                continue;
            }
            if (!validUrl(url) || !links.add(url)) {
                skipped++;
            }
            if (links.size() > MAX_BATCH_LINKS) {
                input.setError(getString(R.string.main_batch_too_many, MAX_BATCH_LINKS));
                return;
            }
        }
        if (links.isEmpty()) {
            input.setError(getString(R.string.main_batch_no_links));
            return;
        }
        input.setError(null);
        List<String> accepted = new ArrayList<>(links);
        AlertDialog editor = batchDialog;
        new AlertDialog.Builder(this)
                .setTitle(getResources().getQuantityString(R.plurals.main_batch_confirm, accepted.size(), accepted.size()))
                .setMessage(batchPreview(accepted, skipped))
                .setNegativeButton(R.string.main_edit_links, null)
                .setPositiveButton(R.string.main_add, (dialog, which) -> enqueueReviewedBatch(editor, input, accepted))
                .show();
    }

    private String batchPreview(List<String> urls, int skipped) {
        StringBuilder preview = new StringBuilder();
        if (skipped > 0) {
            preview.append(getResources().getQuantityString(R.plurals.main_batch_skipped, skipped, skipped));
            preview.append("\n\n");
        }
        int shown = Math.min(8, urls.size());
        for (int index = 0; index < shown; index++) {
            String url = urls.get(index);
            if (index > 0) {
                preview.append('\n');
            }
            preview.append(url.length() > 100 ? url.substring(0, 100) + "…" : url);
        }
        int remaining = urls.size() - shown;
        if (remaining > 0) {
            preview.append('\n');
            preview.append(getResources().getQuantityString(R.plurals.main_batch_more, remaining, remaining));
        }
        return preview.toString();
    }

    private void enqueueReviewedBatch(AlertDialog editor, EditText input, List<String> urls) {
        int added;
        try {
            added = DownloadService.enqueueBatch(this, urls);
        } catch (IllegalArgumentException error) {
            input.setError(getString(R.string.main_batch_no_links));
            return;
        } catch (IllegalStateException | SecurityException error) {
            input.setError(getString(R.string.main_queue_failed));
            return;
        }
        editor.dismiss();
        Toast.makeText(this, getResources().getQuantityString(R.plurals.main_batch_added, added, added),
                Toast.LENGTH_SHORT).show();
        requestNotificationAccess();
    }

    private void prefillFromShare(Intent intent) {
        if (intent == null || !Intent.ACTION_SEND.equals(intent.getAction())) {
            return;
        }
        CharSequence shared = intent.getCharSequenceExtra(Intent.EXTRA_TEXT);
        if (shared == null) {
            return;
        }
        String link = shared.toString().trim();
        if (!validUrl(link)) {
            link = "";
            Matcher links = Patterns.WEB_URL.matcher(shared);
            while (links.find()) {
                if (validUrl(links.group())) {
                    link = links.group();
                    break;
                }
            }
        }
        if (link.isEmpty()) {
            showUrlProblem(R.string.main_link_needed);
            downloads.setSelection(0);
            return;
        }
        urlInput.setText(link);
        urlInput.setSelection(link.length());
        urlProblem.setVisibility(View.GONE);
        downloads.setSelection(0);
    }

    private static boolean validUrl(String text) {
        if (text.isEmpty() || text.length() > 16_384) {
            return false;
        }
        try {
            URI parsed = new URI(text);
            String scheme = parsed.getScheme();
            return ("https".equalsIgnoreCase(scheme) || "http".equalsIgnoreCase(scheme))
                    && parsed.getHost() != null && parsed.getUserInfo() == null && parsed.getPort() <= 65_535;
        } catch (URISyntaxException invalid) {
            return false;
        }
    }

    private void enqueueDraft() {
        String url = urlInput.getText().toString().trim();
        if (!validUrl(url)) {
            showUrlProblem(R.string.main_link_needed);
            urlInput.requestFocus();
            return;
        }
        try {
            DownloadService.enqueue(this, url, null);
        } catch (IllegalArgumentException error) {
            showUrlProblem(R.string.main_link_needed);
            return;
        } catch (IllegalStateException | SecurityException error) {
            showUrlProblem(R.string.main_queue_failed);
            return;
        }
        urlProblem.setVisibility(View.GONE);
        InputMethodManager keyboard = getSystemService(InputMethodManager.class);
        if (keyboard != null) {
            keyboard.hideSoftInputFromWindow(urlInput.getWindowToken(), 0);
        }
        urlInput.clearFocus();
        urlInput.setText("");
        requestNotificationAccess();
    }

    private void showUrlProblem(int message) {
        urlProblem.setText(message);
        urlProblem.setVisibility(View.VISIBLE);
    }

    private void requestNotificationAccess() {
        if (Build.VERSION.SDK_INT < 33 || checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS)
                == PackageManager.PERMISSION_GRANTED) {
            return;
        }
        SharedPreferences preferences = getPreferences(MODE_PRIVATE);
        if (!preferences.getBoolean("notificationsRequested", false)) {
            preferences.edit().putBoolean("notificationsRequested", true).apply();
            requestPermissions(new String[]{Manifest.permission.POST_NOTIFICATIONS}, REQUEST_NOTIFICATIONS);
        }
    }

    private void openFile(Uri uri) {
        if (uri == null || !"content".equals(uri.getScheme())) {
            return;
        }
        try {
            String type = getContentResolver().getType(uri);
            Intent view = new Intent(Intent.ACTION_VIEW).setDataAndType(uri, type)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            startActivity(view);
        } catch (ActivityNotFoundException | SecurityException error) {
            Toast.makeText(this, R.string.main_open_failed, Toast.LENGTH_LONG).show();
        }
    }

    private void removeDownload(DownloadItem item) {
        boolean active = DownloadItem.DOWNLOADING.equals(item.status);
        Runnable removal = active ? () -> DownloadService.cancel(this, item.id)
                : () -> DownloadService.remove(this, item.id);
        if (!active && (item.downloaded <= 0 || DownloadItem.COMPLETED.equals(item.status))) {
            performDownloadAction(removal);
            return;
        }
        new AlertDialog.Builder(this)
                .setTitle(active ? R.string.main_cancel_download : R.string.main_remove_download)
                .setMessage(R.string.main_remove_partial)
                .setNegativeButton(active ? R.string.main_keep_downloading : android.R.string.cancel, null)
                .setPositiveButton(active ? R.string.main_cancel : R.string.main_remove,
                        (dialog, which) -> performDownloadAction(removal))
                .show();
    }

    private void performDownloadAction(Runnable action) {
        try {
            action.run();
        } catch (IllegalStateException | SecurityException error) {
            Toast.makeText(this, R.string.main_action_failed, Toast.LENGTH_LONG).show();
        }
    }

    private final class DownloadsAdapter extends BaseAdapter {
        private List<DownloadItem> items = Collections.emptyList();

        void update(List<DownloadItem> latest) {
            items = latest;
            notifyDataSetChanged();
        }

        @Override
        public int getCount() {
            return Math.max(1, items.size());
        }

        @Override
        public DownloadItem getItem(int position) {
            return items.isEmpty() ? null : items.get(position);
        }

        @Override
        public long getItemId(int position) {
            DownloadItem item = getItem(position);
            return item == null ? 0 : UUID.fromString(item.id).getMostSignificantBits();
        }

        @Override
        public boolean hasStableIds() {
            return true;
        }

        @Override
        public int getViewTypeCount() {
            return 2;
        }

        @Override
        public int getItemViewType(int position) {
            return items.isEmpty() ? 0 : 1;
        }

        @Override
        public View getView(int position, View recycled, ViewGroup parent) {
            DownloadItem item = getItem(position);
            if (item == null) {
                TextView empty = recycled == null ? label(15, MUTED, false) : (TextView) recycled;
                if (recycled == null) {
                    empty.setGravity(Gravity.CENTER);
                    empty.setPadding(dp(12), dp(29), dp(12), dp(29));
                }
                empty.setText(filterSelection == 0 ? R.string.main_empty : R.string.main_empty_filter);
                return empty;
            }
            DownloadRow row = recycled == null ? new DownloadRow() : (DownloadRow) recycled.getTag();
            row.bind(item);
            return row.container;
        }
    }

    private final class DownloadRow {
        final LinearLayout container = column();
        final TextView name = label(16, TEXT, true);
        final TextView status = label(13, ACCENT, true);
        final TextView details = label(13, MUTED, false);
        final TextView error = label(13, ERROR, false);
        final ProgressBar progress = new ProgressBar(MainActivity.this, null, android.R.attr.progressBarStyleHorizontal);
        final Button priority = button(R.string.main_queue_priority, false);
        final Button action = button(R.string.main_pause, true);
        final Button remove = button(R.string.main_remove, false);

        DownloadRow() {
            container.setLayoutParams(new AbsListView.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));
            container.setPadding(0, 0, 0, dp(10));
            container.setTag(this);
            LinearLayout card = card();
            name.setMaxLines(2);
            name.setEllipsize(TextUtils.TruncateAt.END);
            card.addView(name, fullWidth());
            LinearLayout state = row();
            state.addView(status, rowWeight());
            addBeside(state, priority, 7);
            addBelow(card, state, 4);
            addBelow(card, details, 4);
            progress.setMax(1000);
            progress.setProgressBackgroundTintList(ColorStateList.valueOf(BORDER));
            addBelow(card, progress, 6);
            error.setMaxLines(3);
            error.setEllipsize(TextUtils.TruncateAt.END);
            addBelow(card, error, 5);
            LinearLayout actions = row();
            actions.addView(action, rowWeight());
            LinearLayout.LayoutParams removeSize = rowWeight();
            removeSize.setMarginStart(dp(7));
            actions.addView(remove, removeSize);
            addBelow(card, actions, 7);
            container.addView(card, fullWidth());
        }

        void bind(DownloadItem item) {
            name.setText(TextUtils.isEmpty(item.name) ? getString(R.string.main_download) : item.name);
            boolean active = DownloadItem.DOWNLOADING.equals(item.status);
            boolean complete = DownloadItem.COMPLETED.equals(item.status);
            boolean failed = DownloadItem.ERROR.equals(item.status);
            boolean paused = DownloadItem.PAUSED.equals(item.status);
            boolean canPause = active || DownloadItem.QUEUED.equals(item.status);
            int color = complete ? COMPLETE : failed ? ERROR : paused ? PAUSED : ACCENT;
            status.setTextColor(color);
            status.setText(complete ? R.string.main_complete : failed ? R.string.main_failed
                    : paused ? R.string.main_paused : active ? R.string.main_downloading : R.string.main_queued);
            priority.setVisibility(complete ? View.GONE : View.VISIBLE);
            int priorityLabel = item.priority == DownloadItem.PRIORITY_HIGH ? R.string.main_priority_high
                    : item.priority == DownloadItem.PRIORITY_LOW ? R.string.main_priority_low : R.string.main_priority_normal;
            priority.setText(getString(R.string.main_priority_current, getString(priorityLabel)));
            priority.setOnClickListener(view -> showPriorityChoices(item));

            long received = Math.max(0, item.downloaded);
            boolean known = item.total > 0;
            String transfer = known ? getString(R.string.main_transfer_amount, size(received), size(item.total))
                    : received > 0 || active ? size(received) : "";
            if (active && item.rate > 0) {
                transfer = getString(R.string.main_transfer_rate, transfer, size(item.rate));
            }
            details.setText(transfer);
            details.setVisibility(transfer.isEmpty() ? View.GONE : View.VISIBLE);
            progress.setVisibility(active || complete || received > 0 ? View.VISIBLE : View.GONE);
            progress.setIndeterminate(active && !known);
            progress.setIndeterminateTintList(ColorStateList.valueOf(color));
            progress.setProgressTintList(ColorStateList.valueOf(color));
            progress.setProgress(complete ? 1000 : known
                    ? (int) Math.min(1000, Math.round((received / (double) item.total) * 1000)) : 0);
            progress.setContentDescription(getString(R.string.main_progress, name.getText()));
            error.setText(item.error);
            error.setVisibility(failed && !TextUtils.isEmpty(item.error) ? View.VISIBLE : View.GONE);

            action.setVisibility(canPause || (complete && item.uri != null) || failed || paused
                    ? View.VISIBLE : View.GONE);
            action.setText(canPause ? R.string.main_pause : complete ? R.string.main_open
                    : paused ? R.string.main_resume : R.string.main_retry);
            action.setOnClickListener(view -> {
                if (canPause) {
                    performDownloadAction(() -> DownloadService.pause(MainActivity.this, item.id));
                } else if (complete) {
                    openFile(item.uri);
                } else {
                    performDownloadAction(() -> DownloadService.resume(MainActivity.this, item.id));
                }
            });
            remove.setText(active ? R.string.main_cancel : complete ? R.string.main_remove_entry : R.string.main_remove);
            ((LinearLayout.LayoutParams) remove.getLayoutParams()).setMarginStart(action.getVisibility() == View.VISIBLE ? dp(7) : 0);
            remove.setOnClickListener(view -> removeDownload(item));
        }
    }

    private String size(long bytes) {
        return Formatter.formatShortFileSize(this, bytes);
    }

    private int dp(float value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }

    private LinearLayout column() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        return layout;
    }

    private LinearLayout row() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.HORIZONTAL);
        layout.setGravity(Gravity.CENTER_VERTICAL);
        return layout;
    }

    private LinearLayout card() {
        LinearLayout layout = column();
        layout.setPadding(dp(14), dp(13), dp(14), dp(13));
        layout.setBackground(shape(SURFACE, 16, BORDER));
        return layout;
    }

    private TextView label(int size, int color, boolean emphasized) {
        TextView text = new TextView(this);
        text.setTextSize(size);
        text.setTextColor(color);
        if (emphasized) {
            text.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        }
        return text;
    }

    private Button button(int title, boolean emphasized) {
        Button button = new Button(this);
        button.setText(title);
        button.setAllCaps(false);
        button.setTextSize(14);
        button.setTextColor(emphasized ? ON_ACCENT : TEXT);
        button.setMinimumHeight(dp(48));
        button.setMinHeight(dp(48));
        button.setMinimumWidth(0);
        button.setMinWidth(0);
        button.setPadding(dp(10), dp(6), dp(10), dp(6));
        button.setBackground(new RippleDrawable(ColorStateList.valueOf(emphasized ? 0x30231335 : 0x45c1a7ff),
                shape(emphasized ? ACCENT : FIELD, 12, emphasized ? Color.TRANSPARENT : BORDER), null));
        button.setStateListAnimator(null);
        return button;
    }

    private GradientDrawable shape(int color, int radius, int border) {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(color);
        shape.setCornerRadius(dp(radius));
        if (border != Color.TRANSPARENT) {
            shape.setStroke(dp(1), border);
        }
        return shape;
    }

    private static LinearLayout.LayoutParams fullWidth() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private static LinearLayout.LayoutParams rowWeight() {
        return new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
    }

    private LinearLayout buttonPair(Button first, Button second) {
        LinearLayout layout = row();
        layout.addView(first, rowWeight());
        LinearLayout.LayoutParams placement = rowWeight();
        placement.setMarginStart(dp(7));
        layout.addView(second, placement);
        return layout;
    }

    private void addBeside(LinearLayout layout, View view, int spacing) {
        LinearLayout.LayoutParams placement = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        placement.setMarginStart(dp(spacing));
        layout.addView(view, placement);
    }

    private void addBelow(LinearLayout layout, View view, int spacing) {
        LinearLayout.LayoutParams placement = fullWidth();
        placement.topMargin = dp(spacing);
        layout.addView(view, placement);
    }
}
