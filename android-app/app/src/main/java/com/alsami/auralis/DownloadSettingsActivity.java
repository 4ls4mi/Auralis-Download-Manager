package com.alsami.auralis;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.RippleDrawable;
import android.os.Build;
import android.os.Bundle;
import android.text.InputFilter;
import android.text.InputType;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.Button;
import android.widget.EditText;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

public final class DownloadSettingsActivity extends Activity {
    private static final int WINDOW = 0xff171523;
    private static final int SURFACE = 0xff252137;
    private static final int FIELD = 0xff1c192d;
    private static final int BORDER = 0xff53486c;
    private static final int TEXT = 0xfff7f2ff;
    private static final int MUTED = 0xffccc2df;
    private static final int ACCENT = 0xffc1a7ff;
    private static final int ON_ACCENT = 0xff231335;

    private DownloadSettings settings;
    private EditText files;
    private EditText connections;
    private EditText rate;
    private EditText retries;
    private Switch wifi;
    private Switch lowBattery;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        settings = DownloadSettings.get(this);
        setTitle(R.string.download_settings_title);
        ScrollView scroll = new ScrollView(this);
        scroll.setId(R.id.download_settings_scroll);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(WINDOW);
        fitSystemInsets(scroll);

        LinearLayout body = column();
        body.setPadding(dp(18), dp(16), dp(18), dp(18));
        body.setFocusableInTouchMode(true);
        TextView title = label(R.string.download_settings_title, 26, TEXT, true);
        title.setAccessibilityHeading(true);
        body.addView(title, fullWidth());

        LinearLayout transfer = card(R.string.download_settings_transfer);
        files = numberField(transfer, R.id.download_settings_files, R.string.download_settings_files,
                R.string.download_settings_files_help, settings.concurrentFiles(), DownloadSettings.MAX_FILES);
        connections = numberField(transfer, R.id.download_settings_connections, R.string.download_settings_connections,
                R.string.download_settings_connections_help, settings.connectionsPerDownload(), DownloadSettings.MAX_CONNECTIONS);
        rate = numberField(transfer, R.id.download_settings_rate, R.string.download_settings_rate,
                R.string.download_settings_rate_help, settings.rateLimitKiB(), DownloadSettings.MAX_RATE_KIB);
        retries = numberField(transfer, R.id.download_settings_retries, R.string.download_settings_retries,
                R.string.download_settings_retries_help, settings.automaticRetries(), DownloadSettings.MAX_RETRIES);
        addBelow(body, transfer, 16);

        LinearLayout conditions = card(R.string.download_settings_conditions);
        wifi = switchField(conditions, R.id.download_settings_wifi, R.string.download_settings_wifi,
                R.string.download_settings_wifi_help, settings.wifiOnly());
        lowBattery = switchField(conditions, R.id.download_settings_battery, R.string.download_settings_battery,
                R.string.download_settings_battery_help, settings.pauseOnLowBattery());
        addBelow(body, conditions, 12);

        LinearLayout actions = new LinearLayout(this);
        actions.setBaselineAligned(false);
        Button cancel = button(R.string.download_settings_cancel, false);
        cancel.setOnClickListener(view -> finish());
        actions.addView(cancel, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f));
        Button save = button(R.string.download_settings_save, true);
        save.setId(R.id.download_settings_save);
        save.setOnClickListener(view -> save());
        LinearLayout.LayoutParams savePlacement = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        savePlacement.setMarginStart(dp(8));
        actions.addView(save, savePlacement);
        addBelow(body, actions, 14);
        scroll.addView(body);
        setContentView(scroll);
        body.requestFocus();
    }

    private void save() {
        int fileCount = readNumber(files, 1, DownloadSettings.MAX_FILES);
        if (fileCount < 0) return;
        int connectionCount = readNumber(connections, 1, DownloadSettings.MAX_CONNECTIONS);
        if (connectionCount < 0) return;
        int speed = readNumber(rate, 0, DownloadSettings.MAX_RATE_KIB);
        if (speed < 0) return;
        int retryCount = readNumber(retries, 0, DownloadSettings.MAX_RETRIES);
        if (retryCount < 0) return;
        settings.save(fileCount, connectionCount, speed, retryCount, wifi.isChecked(), lowBattery.isChecked());
        setResult(RESULT_OK);
        finish();
    }

    private int readNumber(EditText field, int min, int max) {
        try {
            int value = Integer.parseInt(field.getText().toString().trim());
            if (value >= min && value <= max) return value;
        } catch (NumberFormatException ignored) {
            // Empty and nonnumeric input use the same range feedback.
        }
        field.setError(getString(R.string.download_settings_invalid_number, min, max));
        field.requestFocus();
        return -1;
    }

    private EditText numberField(LinearLayout card, int id, int name, int help, int value, int max) {
        TextView caption = label(name, 15, TEXT, true);
        caption.setLabelFor(id);
        addBelow(card, caption, 12);
        EditText field = new EditText(this);
        field.setId(id);
        field.setSingleLine(true);
        field.setInputType(InputType.TYPE_CLASS_NUMBER);
        field.setFilters(new InputFilter[]{new InputFilter.LengthFilter(Integer.toString(max).length())});
        field.setText(Integer.toString(value));
        field.setTextSize(17);
        field.setTextColor(TEXT);
        field.setMinimumHeight(dp(48));
        field.setPadding(dp(12), dp(6), dp(12), dp(6));
        field.setBackground(shape(FIELD, 10, BORDER));
        addBelow(card, field, 5);
        addBelow(card, label(help, 13, MUTED, false), 4);
        return field;
    }

    private Switch switchField(LinearLayout card, int id, int name, int help, boolean checked) {
        Switch toggle = new Switch(this);
        toggle.setId(id);
        toggle.setText(name);
        toggle.setTextColor(TEXT);
        toggle.setTextSize(15);
        toggle.setMinHeight(dp(48));
        int[][] states = {{android.R.attr.state_checked}, {}};
        toggle.setThumbTintList(new ColorStateList(states, new int[]{ACCENT, MUTED}));
        toggle.setTrackTintList(new ColorStateList(states, new int[]{0xff8063b9, BORDER}));
        toggle.setChecked(checked);
        addBelow(card, toggle, 6);
        addBelow(card, label(help, 13, MUTED, false), 2);
        return toggle;
    }

    private void fitSystemInsets(View content) {
        Window window = getWindow();
        window.setSoftInputMode(WindowManager.LayoutParams.SOFT_INPUT_ADJUST_RESIZE);
        window.setStatusBarColor(WINDOW);
        window.setNavigationBarColor(WINDOW);
        if (Build.VERSION.SDK_INT < 30) return;
        window.setDecorFitsSystemWindows(false);
        window.setNavigationBarContrastEnforced(false);
        WindowInsetsController controller = window.getInsetsController();
        if (controller != null) {
            controller.setSystemBarsAppearance(0, WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                    | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS);
        }
        content.setOnApplyWindowInsetsListener((view, insets) -> {
            Insets safe = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
            Insets keyboard = insets.getInsets(WindowInsets.Type.ime());
            view.setPadding(safe.left, safe.top, safe.right, Math.max(safe.bottom, keyboard.bottom));
            return insets;
        });
    }

    private LinearLayout card(int heading) {
        LinearLayout card = column();
        card.setPadding(dp(14), dp(13), dp(14), dp(13));
        card.setBackground(shape(SURFACE, 16, BORDER));
        TextView title = label(heading, 17, TEXT, true);
        title.setAccessibilityHeading(true);
        card.addView(title, fullWidth());
        return card;
    }

    private TextView label(int text, int size, int color, boolean emphasized) {
        TextView label = new TextView(this);
        label.setText(text);
        label.setTextSize(size);
        label.setTextColor(color);
        if (emphasized) label.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        return label;
    }

    private Button button(int text, boolean primary) {
        Button button = new Button(this);
        button.setText(text);
        button.setTextColor(primary ? ON_ACCENT : TEXT);
        button.setAllCaps(false);
        button.setMinHeight(dp(48));
        button.setMinWidth(0);
        button.setBackground(new RippleDrawable(ColorStateList.valueOf(0x453a175f),
                shape(primary ? ACCENT : FIELD, 12, primary ? Color.TRANSPARENT : BORDER), null));
        button.setStateListAnimator(null);
        return button;
    }

    private GradientDrawable shape(int fill, int radius, int border) {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(fill);
        shape.setCornerRadius(dp(radius));
        if (border != Color.TRANSPARENT) shape.setStroke(dp(1), border);
        return shape;
    }

    private LinearLayout column() {
        LinearLayout layout = new LinearLayout(this);
        layout.setOrientation(LinearLayout.VERTICAL);
        return layout;
    }

    private void addBelow(LinearLayout layout, View child, int spacing) {
        LinearLayout.LayoutParams placement = fullWidth();
        placement.topMargin = dp(spacing);
        layout.addView(child, placement);
    }

    private static LinearLayout.LayoutParams fullWidth() {
        return new LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
