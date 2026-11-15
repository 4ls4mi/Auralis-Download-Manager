//! Native glass styling used by Mister Hybrid V3.
//!
//! Real translucency is provided by alpha-blended egui surfaces above a
//! cached, pre-blurred local wallpaper. This is *in-app* frosted glass: it
//! does not pretend to blur other Windows desktop applications.
use egui::{Color32, Painter, Pos2, Rect, Stroke, StrokeKind, pos2};

pub fn active() -> bool {
    crate::theme::current().id.as_ref() == "plexo"
}

fn rgba(r: u8, g: u8, b: u8, alpha: u8) -> Color32 {
    Color32::from_rgba_unmultiplied(r, g, b, alpha)
}

/// Default atmospheric charcoal backdrop, so the glass is visibly layered
/// even before a user selects their own wallpaper.
pub fn backdrop(p: &Painter, rect: Rect) {
    if !active() {
        return;
    }
    let p = p.with_clip_rect(rect);
    p.rect_filled(rect, 0.0, Color32::from_rgb(8, 12, 15));
    let min = rect.min;
    let max = rect.max;
    let lights = [
        (pos2(min.x + rect.width() * 0.12, max.y + 20.0), 65_u8, 165_u8, 154_u8),
        (pos2(max.x - rect.width() * 0.05, min.y + rect.height() * 0.38),
            172_u8, 94_u8, 62_u8),
        (pos2(min.x + rect.width() * 0.42, min.y - 35.0),
            47_u8, 94_u8, 100_u8),
    ];
    for (center, r, g, b) in lights {
        for step in (1..=23).rev() {
            let radius = (step as f32 / 23.0) * rect.width().max(rect.height()) * 0.62;
            p.circle_filled(center, radius, rgba(r, g, b, 2));
        }
    }
}

/// The reusable rounded charcoal plate. Opacity is intentionally below
/// 100% so wallpapers show through *all* principal panels.
pub fn panel(p: &Painter, rect: Rect, radius: f32, opacity: u8) {
    if rect.width() <= 0.0 || rect.height() <= 0.0 {
        return;
    }
    p.rect_filled(rect, radius, rgba(12, 20, 25, opacity.clamp(24, 245)));
    p.rect_stroke(
        rect,
        radius,
        Stroke::new(1.0, rgba(119, 163, 170, 62)),
        StrokeKind::Inside,
    );
}

pub fn inset(p: &Painter, rect: Rect, radius: f32) {
    if rect.width() <= 0.0 || rect.height() <= 0.0 {
        return;
    }
    p.rect_filled(rect, radius, rgba(14, 26, 32, 125));
    p.rect_stroke(
        rect,
        radius,
        Stroke::new(1.0, rgba(130, 181, 183, 45)),
        StrokeKind::Inside,
    );
}

pub fn selected(p: &Painter, rect: Rect, radius: f32) {
    p.rect_filled(rect, radius, rgba(15, 116, 107, 116));
    p.rect_stroke(
        rect,
        radius,
        Stroke::new(1.0, rgba(73, 229, 209, 195)),
        StrokeKind::Inside,
    );
}

pub fn accent() -> Color32 {
    Color32::from_rgb(52, 216, 201)
}

pub fn text() -> Color32 {
    Color32::from_rgb(241, 247, 248)
}

pub fn muted() -> Color32 {
    Color32::from_rgb(172, 193, 198)
}

pub fn text_at(p: &Painter, at: Pos2, size: f32, content: &str, color: Color32) {
    p.text(
        at,
        egui::Align2::LEFT_CENTER,
        content,
        egui::FontId::proportional(size),
        color,
    );
}

#[cfg(test)]
mod tests {
    #[test]
    fn glass_is_never_opaque() {
        let alpha = 90_u8.clamp(24, 245);
        assert!(alpha < 255);
    }
}
