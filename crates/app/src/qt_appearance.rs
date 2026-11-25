//! Shared theme data for the Qt frontend. Keep MDM's colors and controls in the
//! original palette module so both frontends use the same built-in presets.

use crate::palette::{self, ButtonLook, Palette, ProgressLook, Theme};
use egui::Color32;
use serde_json::{Value, json};

fn color(value: Color32) -> String {
    let [red, green, blue, alpha] = value.to_srgba_unmultiplied();
    if alpha == 255 {
        format!("#{red:02x}{green:02x}{blue:02x}")
    } else {
        // QColor expects alpha before the RGB channels.
        format!("#{alpha:02x}{red:02x}{green:02x}{blue:02x}")
    }
}

fn variant(p: &Palette) -> Value {
    json!({
        "light": !p.dark,
        "background": color(p.window),
        "caption": color(p.caption),
        "text": color(p.text),
        "muted": color(p.muted),
        "accent": color(p.accent),
        "divider": color(p.group_line),
        "field": color(p.field),
        "tree": color(p.tree),
        "list": color(p.list),
        "header": color(p.header),
        "button": color(p.button),
        "buttonHot": color(p.button_hot),
        "buttonPressed": color(p.button_pressed),
        "buttonBorder": color(p.button_border),
        "buttonText": color(p.button_text),
        "buttonDisabled": color(p.button_disabled),
        "buttonDisabledBorder": color(p.button_disabled_border),
        "textDisabled": color(p.text_disabled),
        "buttonAccent": color(p.button_accent),
        "buttonAccentText": color(p.button_accent_text),
        "focusRing": color(p.focus_ring),
        "gloss": color(p.gloss),
        "selection": color(p.selection),
        "selectionText": color(p.selection_text),
        "menu": color(p.menu),
        "menuHot": color(p.menu_hot),
        "menuBorder": color(p.menu_border),
        "positive": color(p.success),
        "warning": color(p.warning),
        "error": color(p.error),
        "progressFill": color(p.progress_bar),
        "progressTrack": color(p.progress_track),
        "segmentBorder": color(p.segment_border),
        "segmentCorner": color(p.segment_corner),
        "segmentMissing": p.segments.missing.map(color),
        "segmentDone": p.segments.done.map(color),
        "segmentStart": p.segments.start.map(color)
    })
}

fn profile(theme: &Theme) -> Value {
    let progress = match theme.controls.progress {
        ProgressLook::Line => "line",
        ProgressLook::Bar => "bar",
        ProgressLook::Blocks => "blocks",
        ProgressLook::Gloss => "gloss",
    };
    json!({
        "name": theme.name.as_ref(),
        "radius": theme.metrics.control_radius,
        "buttonRadius": theme.metrics.button_radius,
        "glossyButtons": matches!(theme.controls.button, ButtonLook::Luna | ButtonLook::Aero | ButtonLook::Aqua),
        "progress": progress,
        "light": variant(&theme.light),
        "dark": variant(&theme.dark),
    })
}

pub fn embedded_appearance_presets(system_accent: &str) -> Value {
    let mut presets = serde_json::Map::new();
    for theme in palette::builtins() {
        presets.insert(format!("mdm-{}", theme.id), profile(theme));
    }
    let native = crate::native::theme(&crate::native::System {
        accent: palette::parse_hex(system_accent).map(crate::native::Accent::from_color),
        ..Default::default()
    });
    presets.insert("mdm-native".into(), profile(&native));
    Value::Object(presets)
}
