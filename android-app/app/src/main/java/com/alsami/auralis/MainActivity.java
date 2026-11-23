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

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
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
    private static final String DRAFT_URL = "draftUrl";

    private DownloadQueue queue;
    private DownloadsAdapter adapter;
    private ListView downloads;
    private EditText urlInput;
    private TextView urlProblem;
    private TextView queueSummary;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        queue = DownloadQueue.get(this);
        setContentView(createContent());
        if (savedInstanceState == null) {
            prefillFromShare(getIntent());
        } else {
            urlInput.setText(savedInstanceState.getString(DRAFT_URL, ""));
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
        super.onSaveInstanceState(state);
    }

    @Override
    public void onQueueChanged() {
        List<DownloadItem> ordered = new ArrayList<>();
        List<DownloadItem> waiting = new ArrayList<>();
        List<DownloadItem> previous = new ArrayList<>();
        for (DownloadItem item : queue.list()) {
            if (DownloadItem.DOWNLOADING.equals(item.status)) {
                ordered.add(item);
            } else if (DownloadItem.QUEUED.equals(item.status)) {
                waiting.add(item);
            } else {
                previous.add(item);
            }
        }
        int active = ordered.size();
        // The queue's history is newest first. Pending transfers run oldest first.
        Collections.reverse(waiting);
        ordered.addAll(waiting);
        ordered.addAll(previous);
        adapter.update(ordered);
        queueSummary.setText(getString(R.string.main_queue_summary, active, waiting.size()));
        queueSummary.setVisibility(active + waiting.size() > 0 ? View.VISIBLE : View.GONE);
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
        title.setAccessibilityHeading(true);
        LinearLayout.LayoutParams titleSize = rowWeight();
        titleSize.setMarginStart(dp(11));
        brand.addView(title, titleSize);
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
            WindowInsetsController controller = window.getInsetsController();
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
        addBelow(form, add, 10);
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
        return header;
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
        if (text.isEmpty() || text.chars().anyMatch(Character::isWhitespace)) {
            return false;
        }
        Uri parsed = Uri.parse(text);
        String scheme = parsed.getScheme();
        return ("https".equalsIgnoreCase(scheme) || "http".equalsIgnoreCase(scheme))
                && !TextUtils.isEmpty(parsed.getHost()) && parsed.getUserInfo() == null;
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
                if (recycled != null) {
                    return recycled;
                }
                TextView empty = label(15, MUTED, false);
                empty.setText(R.string.main_empty);
                empty.setGravity(Gravity.CENTER);
                empty.setPadding(dp(12), dp(29), dp(12), dp(29));
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
            addBelow(card, status, 4);
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

    private void addBelow(LinearLayout layout, View view, int spacing) {
        LinearLayout.LayoutParams placement = fullWidth();
        placement.topMargin = dp(spacing);
        layout.addView(view, placement);
    }
}
