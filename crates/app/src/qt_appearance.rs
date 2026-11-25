//! Shared theme data for the Qt frontend. Keep MDM's colors and controls in the
//! original palette module so both frontends use the same built-in presets.

use crate::palette::{self, ButtonLook, CaptionLook, IconStyle, Palette, ProgressLook, Theme};
use egui::Color32;
use serde_json::{Map, Value, json};

fn color(value: Color32) -> String {
    let [red, green, blue, alpha] = value.to_srgba_unmultiplied();
    if alpha == 255 {
        format!("#{red:02x}{green:02x}{blue:02x}")
    } else {
        // QColor expects alpha before the RGB channels.
        format!("#{alpha:02x}{red:02x}{green:02x}{blue:02x}")
    }
}

fn caption_stops(look: CaptionLook, bar: Color32, gloss: Color32) -> Value {
    use crate::derive::{mix, shade};
    let stops = match look {
        CaptionLook::Luna => vec![
            (0.0, mix(bar, gloss, 0.45)),
            (0.12, mix(bar, gloss, 0.12)),
            (0.5, bar),
            (1.0, shade(bar, -0.06)),
        ],
        CaptionLook::Aero => vec![
            (0.0, mix(bar, gloss, 0.45)),
            (0.5, mix(bar, gloss, 0.2)),
            (0.5, bar),
            (1.0, mix(bar, gloss, 0.1)),
        ],
        CaptionLook::Aqua => vec![(0.0, mix(bar, gloss, 0.6)), (1.0, bar)],
        _ => Vec::new(),
    };
    Value::Array(
        stops
            .into_iter()
            .map(|(position, fill)| json!({ "position": position, "color": color(fill) }))
            .collect(),
    )
}

fn variant(p: &Palette, caption: CaptionLook) -> Value {
    let mut fields = [
        ("background", p.window),
        ("caption", p.caption),
        ("captionInactive", p.caption_inactive),
        ("captionText", p.caption_text),
        ("captionInactiveText", p.caption_text_inactive),
        ("captionButton", p.caption_button),
        ("captionHot", p.caption_hot),
        ("captionPressed", p.caption_pressed),
        ("captionClose", p.caption_close),
        ("captionCloseText", p.caption_close_text),
        ("text", p.text),
        ("muted", p.muted),
        ("accent", p.accent),
        ("divider", p.group_line),
        ("field", p.field),
        ("tree", p.tree),
        ("list", p.list),
        ("header", p.header),
        ("headerLine", p.header_line),
        ("tabPage", p.tab_page),
        ("tab", p.tab),
        ("tabHot", p.tab_hot),
        ("menubar", p.menubar),
        ("menubarHot", p.menubar_hot),
        ("menubarOpen", p.menubar_open),
        ("toolbarHot", p.toolbar_hot),
        ("toolbarHotBorder", p.toolbar_hot_border),
        ("toolbarPressed", p.toolbar_pressed),
        ("iconDisabled", p.icon_disabled),
        ("iconDisabledEnd", p.icon_disabled_end),
        ("button", p.button),
        ("buttonHot", p.button_hot),
        ("buttonPressed", p.button_pressed),
        ("buttonBorder", p.button_border),
        ("buttonText", p.button_text),
        ("buttonDisabled", p.button_disabled),
        ("buttonDisabledBorder", p.button_disabled_border),
        ("textDisabled", p.text_disabled),
        ("buttonAccent", p.button_accent),
        ("buttonAccentText", p.button_accent_text),
        ("focusRing", p.focus_ring),
        ("gloss", p.gloss),
        ("selection", p.selection),
        ("selectionText", p.selection_text),
        ("menu", p.menu),
        ("menuHot", p.menu_hot),
        ("menuBorder", p.menu_border),
        ("positive", p.success),
        ("warning", p.warning),
        ("error", p.error),
        ("statusValue", p.status_value),
        ("progressFill", p.progress_bar),
        ("progressTrack", p.progress_track),
        ("segmentBorder", p.segment_border),
        ("segmentCorner", p.segment_corner),
    ]
    .into_iter()
    .map(|(key, fill)| (key.to_owned(), Value::String(color(fill))))
    .collect::<Map<_, _>>();
    fields.extend([
        ("light".to_owned(), Value::Bool(!p.dark)),
        (
            "segmentMissing".to_owned(),
            json!(p.segments.missing.map(color)),
        ),
        ("segmentDone".to_owned(), json!(p.segments.done.map(color))),
        (
            "segmentStart".to_owned(),
            json!(p.segments.start.map(color)),
        ),
        (
            "captionStops".to_owned(),
            caption_stops(caption, p.caption, p.gloss),
        ),
        (
            "captionInactiveStops".to_owned(),
            caption_stops(
                caption,
                if p.caption_inactive.a() > 0 {
                    p.caption_inactive
                } else {
                    p.caption
                },
                p.gloss,
            ),
        ),
    ]);
    Value::Object(fields)
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
        "iconSet": theme.icon_set.as_deref(),
        "iconStyle": match theme.icons {
            IconStyle::Color => "color",
            IconStyle::Mono => "mono",
            IconStyle::Accent => "accent",
        },
        "radius": theme.metrics.control_radius,
        "buttonRadius": theme.metrics.button_radius,
        "listRow": theme.metrics.list_row,
        "listHeader": theme.metrics.list_header,
        "captionStyle": match theme.controls.caption {
            CaptionLook::System => "system",
            CaptionLook::Metro => "metro",
            CaptionLook::Adwaita => "adwaita",
            CaptionLook::Breeze => "breeze",
            CaptionLook::Luna => "luna",
            CaptionLook::Aero => "aero",
            CaptionLook::Aqua => "aqua",
        },
        "glossyButtons": matches!(theme.controls.button, ButtonLook::Luna | ButtonLook::Aero | ButtonLook::Aqua),
        "progress": progress,
        "light": variant(&theme.light, theme.controls.caption),
        "dark": variant(&theme.dark, theme.controls.caption),
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
