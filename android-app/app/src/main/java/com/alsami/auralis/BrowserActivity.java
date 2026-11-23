package com.alsami.auralis;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Insets;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
import android.text.InputType;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.view.inputmethod.EditorInfo;
import android.view.inputmethod.InputMethodManager;
import android.webkit.CookieManager;
import android.webkit.URLUtil;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.TextView;
import android.widget.Toast;

import org.json.JSONArray;
import org.json.JSONException;

import java.net.URI;
import java.util.ArrayList;
import java.util.List;

public final class BrowserActivity extends Activity {
    public static final String EXTRA_URL = "com.alsami.auralis.BROWSER_URL";
    private static final String BOOKMARKS = "bookmarks";
    private static final String HISTORY = "history";
    private static final int MAX_TABS = 8;
    private static final int MAX_SAVED_SITES = 60;
    private static final int WINDOW = Color.rgb(24, 24, 35);
    private static final int CARD = Color.rgb(42, 40, 59);
    private static final int ACCENT = Color.rgb(195, 175, 255);
    private static final int TEXT = Color.rgb(246, 243, 255);

    public static void open(Context context) {
        open(context, null);
    }

    public static void open(Context context, String initialUrl) {
        Intent browser = new Intent(context, BrowserActivity.class);
        if (!(context instanceof Activity))
            browser.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        if (initialUrl != null)
            browser.putExtra(EXTRA_URL, initialUrl);
        context.startActivity(browser);
    }

    private final ArrayList<WebView> tabs = new ArrayList<>();
    private SharedPreferences savedSites;
    private int selected;
    private EditText address;
    private View blank;
    private FrameLayout viewport;
    private ProgressBar loading;
    private Button tabsButton;
    private Button backButton;
    private Button forwardButton;
    private Button bookmarkButton;
    private AlertDialog downloadPrompt;

    @Override protected void onCreate(Bundle state) {
        super.onCreate(state);
        savedSites = getSharedPreferences("auralis-browser", MODE_PRIVATE);
        setContentView(createContent());
        ArrayList<String> restored = state == null ? null : state.getStringArrayList("tabUrls");
        if (restored == null || restored.isEmpty()) {
            addTab(getIntent().getStringExtra(EXTRA_URL));
        } else {
            for (String url : restored)
                addTab(url);
            showTab(Math.max(0, Math.min(tabs.size() - 1, state.getInt("selectedTab"))));
        }
    }

    private View createContent() {
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(WINDOW);
        getWindow().setNavigationBarContrastEnforced(false);
        getWindow().setStatusBarColor(Color.TRANSPARENT);
        getWindow().setNavigationBarColor(Color.TRANSPARENT);
        if (Build.VERSION.SDK_INT >= 30)
            getWindow().setDecorFitsSystemWindows(false);
        root.setOnApplyWindowInsetsListener((view, insets) -> {
            if (Build.VERSION.SDK_INT >= 30) {
                Insets bars = insets.getInsets(WindowInsets.Type.systemBars() | WindowInsets.Type.displayCutout());
                Insets keyboard = insets.getInsets(WindowInsets.Type.ime());
                view.setPadding(bars.left, bars.top, bars.right, Math.max(bars.bottom, keyboard.bottom));
            }
            return insets;
        });

        LinearLayout title = row();
        title.addView(control(R.string.browser_done, this::finish));
        TextView heading = new TextView(this);
        heading.setText(R.string.browser_title);
        heading.setTextSize(19);
        heading.setTextColor(TEXT);
        heading.setAccessibilityHeading(true);
        heading.setGravity(Gravity.CENTER);
        title.addView(heading, weight());
        tabsButton = control(R.string.browser_tabs, this::chooseTab);
        title.addView(tabsButton);
        root.addView(title);

        LinearLayout location = row();
        address = new EditText(this);
        address.setTextColor(TEXT);
        address.setHintTextColor(Color.rgb(169, 163, 188));
        address.setHint(R.string.browser_url);
        address.setInputType(InputType.TYPE_CLASS_TEXT | InputType.TYPE_TEXT_VARIATION_URI);
        address.setSingleLine();
        address.setImeOptions(EditorInfo.IME_ACTION_GO);
        address.setBackground(surface(CARD));
        address.setPadding(dp(12), 0, dp(12), 0);
        address.setOnEditorActionListener((text, action, event) -> {
            if (action != EditorInfo.IME_ACTION_GO)
                return false;
            navigate();
            return true;
        });
        location.addView(address, new LinearLayout.LayoutParams(0, dp(45), 1));
        location.addView(control(R.string.browser_go, this::navigate));
        root.addView(location);

        LinearLayout tools = row();
        backButton = control(R.string.browser_back, () -> current().goBack());
        forwardButton = control(R.string.browser_forward, () -> current().goForward());
        bookmarkButton = control(R.string.browser_bookmark, this::toggleBookmark);
        tools.addView(backButton, weight());
        tools.addView(forwardButton, weight());
        tools.addView(bookmarkButton, weight());
        tools.addView(control(R.string.browser_library, this::showLibrary), weight());
        root.addView(tools);

        loading = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        loading.setIndeterminateTintList(ColorStateList.valueOf(ACCENT));
        loading.setIndeterminate(true);
        loading.setVisibility(View.INVISIBLE);
        root.addView(loading, new LinearLayout.LayoutParams(-1, dp(3)));
        viewport = new FrameLayout(this);
        TextView empty = new TextView(this);
        empty.setText(R.string.browser_start);
        empty.setTextColor(ACCENT);
        empty.setGravity(Gravity.CENTER);
        blank = empty;
        viewport.addView(blank, new FrameLayout.LayoutParams(-1, -1));
        root.addView(viewport, new LinearLayout.LayoutParams(-1, 0, 1));
        return root;
    }

    private LinearLayout row() {
        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setPadding(dp(8), dp(3), dp(8), dp(3));
        return row;
    }

    private LinearLayout.LayoutParams weight() {
        return new LinearLayout.LayoutParams(0, -2, 1);
    }

    private Button control(int label, Runnable action) {
        Button button = new Button(this);
        button.setAllCaps(false);
        button.setText(label);
        button.setTextColor(ACCENT);
        button.setMinWidth(0);
        button.setMinimumWidth(0);
        button.setPadding(dp(8), 0, dp(8), 0);
        button.setOnClickListener(view -> action.run());
        return button;
    }

    private GradientDrawable surface(int color) {
        GradientDrawable shape = new GradientDrawable();
        shape.setColor(color);
        shape.setCornerRadius(dp(13));
        return shape;
    }

    private int dp(int amount) {
        return Math.round(amount * getResources().getDisplayMetrics().density);
    }

    private void addTab(String initialUrl) {
        if (tabs.size() >= MAX_TABS) {
            Toast.makeText(this, R.string.browser_tab_limit, Toast.LENGTH_SHORT).show();
            return;
        }
        WebView web = new WebView(this);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setSupportMultipleWindows(false);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, false);
        web.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return request.isForMainFrame() && validUrl(request.getUrl().toString()) == null;
            }

            @Override public void onPageStarted(WebView view, String url, android.graphics.Bitmap favicon) {
                if (view == current()) {
                    refresh(url);
                    loading.setVisibility(View.VISIBLE);
                }
            }

            @Override public void onPageFinished(WebView view, String url) {
                if (validUrl(url) != null)
                    remember(HISTORY, url, true);
                if (view == current()) {
                    refresh(url);
                    loading.setVisibility(View.INVISIBLE);
                }
            }
        });
        web.setDownloadListener((url, userAgent, disposition, mime, length) -> confirmDownload(url, disposition, mime));
        tabs.add(web);
        viewport.addView(web, new FrameLayout.LayoutParams(-1, -1));
        showTab(tabs.size() - 1);
        String url = validUrl(initialUrl);
        if (url != null)
            web.loadUrl(url);
    }

    private WebView current() {
        return selected < tabs.size() ? tabs.get(selected) : null;
    }

    private void showTab(int index) {
        selected = index;
        for (int i = 0; i < tabs.size(); i++)
            tabs.get(i).setVisibility(i == index ? View.VISIBLE : View.GONE);
        loading.setVisibility(View.INVISIBLE);
        refresh(current().getUrl());
    }

    private void refresh(String url) {
        boolean hasPage = validUrl(url) != null || current().getUrl() != null;
        blank.setVisibility(hasPage ? View.GONE : View.VISIBLE);
        if (!hasPage)
            blank.bringToFront();
        address.setText(validUrl(url) == null ? "" : url);
        backButton.setEnabled(current().canGoBack());
        forwardButton.setEnabled(current().canGoForward());
        bookmarkButton.setEnabled(validUrl(url) != null);
        bookmarkButton.setSelected(readSites(BOOKMARKS).contains(url));
        tabsButton.setText(getString(R.string.browser_tabs_count, tabs.size()));
    }

    private void navigate() {
        String url = address.getText().toString().trim();
        if (!url.contains("://"))
            url = "https://" + url;
        url = validUrl(url);
        if (url == null) {
            address.setError(getString(R.string.browser_invalid_url));
            return;
        }
        address.clearFocus();
        getSystemService(InputMethodManager.class).hideSoftInputFromWindow(address.getWindowToken(), 0);
        current().loadUrl(url);
    }

    private static String validUrl(String text) {
        if (text == null || text.length() > 16_384)
            return null;
        try {
            URI uri = URI.create(text);
            String scheme = uri.getScheme();
            if (("http".equalsIgnoreCase(scheme) || "https".equalsIgnoreCase(scheme))
                    && uri.getHost() != null && uri.getUserInfo() == null && uri.getPort() <= 65535) {
                return uri.toASCIIString();
            }
        } catch (IllegalArgumentException invalid) {
            return null;
        }
        return null;
    }

    private void chooseTab() {
        CharSequence[] labels = new CharSequence[tabs.size()];
        for (int i = 0; i < labels.length; i++) {
            String title = tabs.get(i).getTitle();
            labels[i] = title == null || title.trim().isEmpty() ? getString(R.string.browser_new_tab) : title;
        }
        new AlertDialog.Builder(this).setTitle(R.string.browser_tabs)
            .setSingleChoiceItems(labels, selected, (dialog, index) -> {
                showTab(index);
                dialog.dismiss();
            })
            .setPositiveButton(R.string.browser_new_tab, (dialog, which) -> addTab(null))
            .setNeutralButton(R.string.browser_close_tab, (dialog, which) -> closeTab())
            .setNegativeButton(android.R.string.cancel, null).show();
    }

    private void closeTab() {
        WebView removed = tabs.remove(selected);
        viewport.removeView(removed);
        removed.destroy();
        if (tabs.isEmpty())
            addTab(null);
        else
            showTab(Math.min(selected, tabs.size() - 1));
    }

    private void confirmDownload(String text, String disposition, String mime) {
        if (isFinishing() || isDestroyed() || downloadPrompt != null && downloadPrompt.isShowing())
            return;
        String url = validUrl(text);
        if (url == null) {
            Toast.makeText(this, R.string.browser_invalid_download, Toast.LENGTH_LONG).show();
            return;
        }
        String file = URLUtil.guessFileName(url, disposition, mime);
        downloadPrompt = new AlertDialog.Builder(this).setTitle(R.string.browser_download_title)
            .setMessage(getString(R.string.browser_download_prompt, file, URI.create(url).getHost()))
            .setPositiveButton(R.string.browser_add_download, (dialog, which) -> {
                DownloadService.enqueue(this, url, file);
                Toast.makeText(this, R.string.browser_download_queued, Toast.LENGTH_SHORT).show();
            })
            .setNegativeButton(android.R.string.cancel, null).show();
    }

    private void toggleBookmark() {
        String url = current().getUrl();
        if (validUrl(url) == null)
            return;
        boolean saved = readSites(BOOKMARKS).contains(url);
        remember(BOOKMARKS, url, !saved);
        bookmarkButton.setSelected(!saved);
        Toast.makeText(this, saved ? R.string.browser_bookmark_removed : R.string.browser_bookmark_saved,
            Toast.LENGTH_SHORT).show();
    }

    private void showLibrary() {
        CharSequence[] choices = {getString(R.string.browser_bookmarks), getString(R.string.browser_history)};
        new AlertDialog.Builder(this).setTitle(R.string.browser_library).setItems(choices, (dialog, which) ->
            showSites(which == 0 ? BOOKMARKS : HISTORY)).show();
    }

    private void showSites(String key) {
        boolean history = HISTORY.equals(key);
        List<String> urls = readSites(key);
        AlertDialog.Builder dialog = new AlertDialog.Builder(this)
            .setTitle(history ? R.string.browser_history : R.string.browser_bookmarks)
            .setNegativeButton(android.R.string.cancel, null);
        if (urls.isEmpty()) {
            dialog.setMessage(R.string.browser_no_sites);
        } else {
            dialog.setItems(urls.toArray(new String[0]), (selectedDialog, index) -> current().loadUrl(urls.get(index)));
            if (history)
                dialog.setNeutralButton(R.string.browser_clear_history, (selectedDialog, which) -> {
                    savedSites.edit().remove(HISTORY).apply();
                    for (WebView web : tabs)
                        web.clearHistory();
                });
        }
        dialog.show();
    }

    private ArrayList<String> readSites(String key) {
        ArrayList<String> urls = new ArrayList<>();
        try {
            JSONArray array = new JSONArray(savedSites.getString(key, "[]"));
            for (int i = 0; i < Math.min(array.length(), MAX_SAVED_SITES); i++) {
                String url = validUrl(array.optString(i));
                if (url != null)
                    urls.add(url);
            }
        } catch (JSONException corrupt) {
            // A later visit rebuilds the list.
        }
        return urls;
    }

    private void remember(String key, String url, boolean put) {
        String address = validUrl(url);
        if (address == null)
            return;
        ArrayList<String> sites = readSites(key);
        sites.remove(address);
        if (put)
            sites.add(0, address);
        if (sites.size() > MAX_SAVED_SITES)
            sites.remove(sites.size() - 1);
        savedSites.edit().putString(key, new JSONArray(sites).toString()).apply();
    }

    @Override protected void onSaveInstanceState(Bundle state) {
        super.onSaveInstanceState(state);
        ArrayList<String> urls = new ArrayList<>();
        for (WebView web : tabs)
            urls.add(validUrl(web.getUrl()));
        state.putStringArrayList("tabUrls", urls);
        state.putInt("selectedTab", selected);
    }

    @Override protected void onDestroy() {
        if (downloadPrompt != null)
            downloadPrompt.dismiss();
        for (WebView web : tabs) {
            viewport.removeView(web);
            web.destroy();
        }
        tabs.clear();
        super.onDestroy();
    }
}
