//! Safe, cached user-selected desktop wallpapers for both Mister viewports.
//! Images are local files only; decoded once, size-limited and resized before GPU upload.

use std::path::Path;
use std::sync::{LazyLock, Mutex};

use egui::{
    Color32, ColorImage, Painter, Rect, Stroke, TextureHandle, TextureOptions, Ui, pos2, vec2,
};

/// Cap decoded texture dimensions to avoid a multi-hundred-MB GPU allocation.
const MAX_WIDTH: u32 = 2048;
const MAX_HEIGHT: u32 = 1280;
const MAX_FILE: u64 = 48 * 1024 * 1024;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Target {
    Main,
    Progress,
}

struct Cached {
    path: String,
    blur: u8,
    texture: TextureHandle,
    width: f32,
    height: f32,
    brightness: f32,
}

#[derive(Default)]
struct Wallpapers {
    main: Option<Cached>,
    progress: Option<Cached>,
}

static CACHE: LazyLock<Mutex<Wallpapers>> = LazyLock::new(|| Mutex::new(Wallpapers::default()));

/// A contrast-safe treatment for text drawn directly over an image.
#[derive(Clone, Copy)]
pub struct Contrast {
    pub ink: Color32,
    pub stroke: Color32,
    /// This is a protective surface, not an unprotected image overlay.
    pub glass: Color32,
    pub bright_image: bool,
}

impl Contrast {
    fn for_wallpaper(brightness: f32, dim_percent: u8, glass_percent: u8) -> Self {
        // Even bright white wallpapers stay readable: an opaque-enough protective
        // surface prevents white text from sitting directly on a bright picture.
        // While the app is dark, text above its cards remains white regardless of
        // the picture; standalone text over the image has a dark contrast stroke.
        let bright_image = brightness > 0.55;
        let darkening = dim_percent.min(95) as f32 / 100.0;
        let level = (darkening + if bright_image { 0.36 } else { 0.21 }).clamp(0.45, 0.93);
        let glass_alpha = (glass_percent.clamp(58, 98) as f32 * 2.55).round() as u8;
        let _level = level;
        // On a bright wallpaper with light dimming, labels *directly on the
        // image* switch to dark ink on a light protective plate. The rest of
        // the dark application always uses its high-contrast charcoal cards.
        let light_plate = brightness * (1.0 - darkening * 0.4) > 0.60;
        Self {
            ink: if light_plate {
                Color32::from_rgb(13, 25, 28)
            } else {
                Color32::from_rgb(244, 250, 251)
            },
            stroke: if light_plate {
                Color32::from_rgb(251, 253, 254)
            } else {
                Color32::from_rgb(1, 8, 10)
            },
            glass: if light_plate {
                Color32::from_rgba_unmultiplied(241, 248, 249, glass_alpha)
            } else {
                Color32::from_rgba_unmultiplied(11, 17, 20, glass_alpha)
            },
            bright_image,
        }
    }
}

fn load(ctx: &egui::Context, path: &str, blur: u8, target: Target) -> Option<Cached> {
    let location = Path::new(path);
    let ext = location.extension()?.to_string_lossy().to_ascii_lowercase();
    if !matches!(ext.as_str(), "png" | "jpeg" | "jpg" | "webp") {
        return None;
    }
    if std::fs::metadata(location).ok()?.len() > MAX_FILE {
        return None;
    }
    let mut reader = image::ImageReader::open(location)
        .ok()?
        .with_guessed_format()
        .ok()?;
    reader.limits(image::Limits::default());
    let img = reader.decode().ok()?;
    let img = img.thumbnail(MAX_WIDTH, MAX_HEIGHT).to_rgba8();
    let (width, height) = img.dimensions();
    if width == 0 || height == 0 {
        return None;
    }
    let mut brightness = 0.0_f64;
    let mut count = 0u32;
    // Local samples, rather than guessing contrast from the file's name or its format.
    for y in (0..height).step_by((height / 32).max(1) as usize) {
        for x in (0..width).step_by((width / 32).max(1) as usize) {
            let px = img.get_pixel(x, y).0;
            let luma =
                (0.2126 * px[0] as f64 + 0.7152 * px[1] as f64 + 0.0722 * px[2] as f64) / 255.0;
            brightness += luma;
            count += 1;
        }
    }
    let brightness = (brightness / f64::from(count.max(1))) as f32;
    let img = if blur > 0 {
        image::imageops::blur(&img, blur.min(30) as f32 * 0.65)
    } else {
        img
    };
    let pixels = img.as_raw();
    let color_image = ColorImage::from_rgba_unmultiplied([width as usize, height as usize], pixels);
    let name = format!("hybrid-wallpaper-{target:?}-{path}-blur{blur}");
    let texture = ctx.load_texture(name, color_image, TextureOptions::LINEAR);
    Some(Cached {
        path: path.into(),
        blur,
        texture,
        width: width as f32,
        height: height as f32,
        brightness,
    })
}

/// Renders an aspect-fill wallpaper and contrast-correct dark overlay.
/// Returns false for disabled, missing, invalid, or oversized images.
pub fn paint(
    ui: &Ui,
    rect: Rect,
    path: &str,
    blur: u8,
    dim_percent: u8,
    glass_percent: u8,
    target: Target,
) -> Option<Contrast> {
    if path.is_empty() || rect.width() <= 1.0 || rect.height() <= 1.0 {
        return None;
    }
    let mut cache = CACHE.lock().unwrap_or_else(|err| err.into_inner());
    let slot = match target {
        Target::Main => &mut cache.main,
        Target::Progress => &mut cache.progress,
    };
    if slot
        .as_ref()
        .is_none_or(|s| s.path != path || s.blur != blur)
    {
        *slot = load(ui.ctx(), path, blur, target);
    }
    let loaded = slot.as_ref()?;
    let out = Contrast::for_wallpaper(loaded.brightness, dim_percent, glass_percent);
    let scale = (rect.width() / loaded.width).max(rect.height() / loaded.height);
    let visible_w = (rect.width() / (loaded.width * scale)).clamp(0.0, 1.0);
    let visible_h = (rect.height() / (loaded.height * scale)).clamp(0.0, 1.0);
    let uv = Rect::from_min_max(
        pos2((1.0 - visible_w) * 0.5, (1.0 - visible_h) * 0.5),
        pos2((1.0 + visible_w) * 0.5, (1.0 + visible_h) * 0.5),
    );
    let painter = ui.painter_at(rect);
    painter.image(loaded.texture.id(), rect, uv, Color32::WHITE);

    // Darken whites more than blacks, preserving a uniformly legible
    // canvas for the dark UI. Every readable control has its own surface.
    // V3: a wallpaper must remain genuinely visible. The old formula
    // darkened a normal wallpaper by 72–95% and then placed opaque
    // legacy panels over it. Bright scenes are dimmed moderately;
    // contrast is enforced by the tinted glass surfaces above them.
    let factor = if out.bright_image { 0.72 } else { 0.50 };
    let alpha = ((dim_percent.min(95) as f32 / 100.0 * factor)
        .clamp(0.03, 0.69) * 255.0) as u8;
    painter.rect_filled(rect, 0.0, Color32::from_black_alpha(alpha));
    Some(out)
}

/// Labels directly on wallpapers get a contrasting 1px outline/shadow.
pub fn outlined_label(painter: &Painter, rect: Rect, label: &str, contrast: Contrast) {
    let center = rect.center();
    let font = egui::FontId::proportional(13.0);
    for offset in [
        vec2(-1.0, 0.0),
        vec2(1.0, 0.0),
        vec2(0.0, -1.0),
        vec2(0.0, 1.0),
    ] {
        painter.text(
            center + offset,
            egui::Align2::CENTER_CENTER,
            label,
            font.clone(),
            contrast.stroke,
        );
    }
    painter.text(
        center,
        egui::Align2::CENTER_CENTER,
        label,
        font,
        contrast.ink,
    );
}

/// A translucent protective glass panel, tinted for Mister's charcoal theme.
pub fn glass_panel(painter: &Painter, rect: Rect, opacity: u8, radius: f32) {
    let alpha = ((opacity.clamp(48, 95) as f32 / 100.0) * 255.0) as u8;
    painter.rect_filled(
        rect,
        radius,
        Color32::from_rgba_unmultiplied(14, 21, 24, alpha),
    );
    painter.rect_stroke(
        rect,
        radius,
        Stroke::new(1.0, Color32::from_rgba_unmultiplied(85, 139, 145, 105)),
        egui::StrokeKind::Inside,
    );
}

/// The progress-window wallpaper is either a chosen separate image or the main one.
pub fn progress_path<'a>(main: &'a str, specific: &'a str, inherit: bool) -> &'a str {
    if inherit { main } else { specific }
}

/// Forget both cached textures when a wallpaper is replaced or blur changes.
pub fn clear() {
    *CACHE.lock().unwrap_or_else(|err| err.into_inner()) = Wallpapers::default();
}

#[cfg(test)]
mod tests {
    use super::{Contrast, progress_path};
    #[test]
    fn separate_wallpapers_and_inherit_are_explicit() {
        assert_eq!(progress_path("main.png", "detail.png", true), "main.png");
        assert_eq!(progress_path("main.png", "detail.png", false), "detail.png");
        assert_eq!(progress_path("main.png", "", false), "");
    }
    #[test]
    fn high_brightness_gets_protective_contrast() {
        let bright = Contrast::for_wallpaper(0.95, 50, 80);
        let dark = Contrast::for_wallpaper(0.08, 50, 80);
        assert!(bright.bright_image);
        assert!(!dark.bright_image);
        assert!(bright.glass.a() >= 148);
        let minimally_dimmed = Contrast::for_wallpaper(0.95, 20, 85);
        assert_eq!(minimally_dimmed.ink, egui::Color32::from_rgb(13, 25, 28));
    }
}
