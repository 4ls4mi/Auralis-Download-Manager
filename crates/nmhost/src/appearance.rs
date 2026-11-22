//! The browser can read this small, desktop-written appearance record without
//! launching the app or reading any of the engine's other settings.

use std::fs::File;
use std::io::Read;
use std::path::Path;

use serde::{Deserialize, Serialize};

const MAX_BYTES: u64 = 64 * 1024;

#[derive(Deserialize, Serialize)]
pub(super) struct Snapshot {
    version: u8,
    current: Theme,
    themes: Vec<Theme>,
}

#[derive(Deserialize, Serialize)]
struct Theme {
    id: String,
    label: String,
    light: bool,
    colors: Colors,
    #[serde(skip_serializing_if = "Option::is_none")]
    opaque: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    radius: Option<u8>,
}

#[derive(Deserialize, Serialize)]
struct Colors {
    background: String,
    surface: String,
    text: String,
    muted: String,
    accent: String,
    border: String,
    positive: String,
    caution: String,
    destructive: String,
}

impl Theme {
    fn valid(&self) -> bool {
        let colors = &self.colors;
        !self.id.is_empty()
            && self.id.len() <= 96
            && self
                .id
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
            && !self.label.trim().is_empty()
            && self.label.encode_utf16().count() <= 100
            && !self.label.chars().any(char::is_control)
            && self.radius.is_none_or(|radius| radius <= 24)
            && [
                &colors.background,
                &colors.surface,
                &colors.text,
                &colors.muted,
                &colors.accent,
                &colors.border,
                &colors.positive,
                &colors.caution,
                &colors.destructive,
            ]
            .iter()
            .all(|color| {
                color.len() == 7
                    && color.starts_with('#')
                    && color.as_bytes()[1..].iter().all(u8::is_ascii_hexdigit)
            })
    }
}

fn read(source: impl Read) -> Option<Snapshot> {
    let mut bytes = Vec::new();
    source.take(MAX_BYTES + 1).read_to_end(&mut bytes).ok()?;
    if bytes.len() as u64 > MAX_BYTES {
        return None;
    }
    let appearance: Snapshot = serde_json::from_slice(&bytes).ok()?;
    (appearance.version == 1
        && appearance.current.valid()
        && appearance.themes.len() <= 64
        && appearance.themes.iter().all(Theme::valid))
    .then_some(appearance)
}

pub(super) fn load(profile: &Path) -> Option<Snapshot> {
    read(File::open(profile.join("extension-appearance.json")).ok()?)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn only_bounded_theme_fields_reach_the_browser() {
        let theme = json!({
            "id": "violet-rail", "label": "Violet Rail", "light": false,
            "radius": 8, "opaque": true, "account": "private",
            "colors": {
                "background": "#242634", "surface": "#262837", "text": "#f6f3ff",
                "muted": "#c3bfd6", "accent": "#b199f7", "border": "#403e53",
                "positive": "#82dec1", "caution": "#ffcf87", "destructive": "#ff899b",
                "cookie": "private"
            }
        });
        let mut document =
            json!({"version": 1, "current": theme, "themes": [theme], "path": "private"});
        let preserved = read(document.to_string().as_bytes()).unwrap();
        let response = serde_json::to_string(&preserved).unwrap();
        assert!(response.contains("Violet Rail"));
        assert!(!response.contains("private"));

        document["current"]["colors"]["accent"] = json!("url(https://example.org)");
        assert!(read(document.to_string().as_bytes()).is_none());
        assert!(read(&vec![b' '; MAX_BYTES as usize + 1][..]).is_none());
    }
}
