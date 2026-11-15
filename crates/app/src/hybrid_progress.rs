//! Compact, GPU-painted download progress visualizations.
//!
//! The graph uses rates observed from the app's live Item; the matrix samples the
//! real byte ranges exposed by mdm-engine::Snapshot. This does NOT attribute
//! transfers to network adapters: Snapshot does not expose adapter ownership.
//! Visual styling is inspired by Zajil and Plexo; no source code is copied.

use std::collections::VecDeque;

use egui::{Color32, Painter, Pos2, Rect, Stroke, StrokeKind, Ui, pos2, vec2};
use mdm_engine::Snapshot;
use mdm_engine::download::SegmentView;

const COLUMNS: usize = 48;
const ROWS: usize = 4;
const CELLS: usize = COLUMNS * ROWS;
/// The additional vertical room needed between the matrix and connections.
pub const EXTRA_HEIGHT: f32 = 64.0;

const BACKGROUND: Color32 = Color32::from_rgb(24, 29, 33);
const PANEL_EDGE: Color32 = Color32::from_rgb(54, 67, 73);
const EMPTY: Color32 = Color32::from_rgb(38, 46, 51);
const TEAL: Color32 = Color32::from_rgb(70, 193, 180);
const AMBER: Color32 = Color32::from_rgb(222, 164, 64);
const BLUE: Color32 = Color32::from_rgb(133, 159, 217);

/// A small throughput waveform within the existing status page's progress track.
/// The highlighted region is *file completion*; peaks are measured transfer rate.
pub fn graph_bar(p: &Painter, rect: Rect, completion: f32, rates: &VecDeque<f32>) {
    if rect.width() <= 0.0 || rect.height() <= 0.0 {
        return;
    }
    let fraction = completion.clamp(0.0, 1.0);
    p.rect_filled(rect, 3.0, BACKGROUND);
    let inner = rect.shrink(1.0);
    let filled_width = inner.width() * fraction;
    if filled_width > 0.0 {
        p.rect_filled(
            Rect::from_min_size(inner.min, vec2(filled_width, inner.height())),
            2.0,
            Color32::from_rgb(33, 80, 75),
        );
    }

    if rates.len() > 1 {
        let peak = rates
            .iter()
            .copied()
            .filter(|v| v.is_finite())
            .fold(0.01_f32, f32::max);
        let last = rates.len().saturating_sub(1) as f32;
        let mut previous: Option<Pos2> = None;
        let right = inner.left() + filled_width;
        for (i, v) in rates.iter().enumerate() {
            let x = inner.left() + i as f32 / last * inner.width();
            let value = if v.is_finite() { v.max(0.0) } else { 0.0 };
            let y = inner.bottom() - 2.0
                - (value / peak).clamp(0.0, 1.0) * (inner.height() - 4.0).max(0.0);
            let point = pos2(x, y);
            if let Some(prev) = previous {
                let color = if (prev.x + point.x) * 0.5 <= right { TEAL } else {
                    Color32::from_rgb(97, 117, 125)
                };
                p.line_segment([prev, point], Stroke::new(1.8, color));
            }
            previous = Some(point);
        }
    }

    // Golden playhead denotes the actual fraction; it is not a speed estimate.
    let marker = inner.left() + filled_width;
    p.line_segment(
        [pos2(marker, inner.top()), pos2(marker, inner.bottom())],
        Stroke::new(1.4, AMBER),
    );
    p.rect_stroke(rect, 3.0, Stroke::new(1.0, PANEL_EDGE), StrokeKind::Inside);
}

/// Fraction of a given byte interval already received, plus its first contributing
/// engine segment. Multiple segments inside one visual tile are accounted for.
fn coverage(
    start: u64,
    end: u64,
    segments: &[SegmentView],
    fallback_downloaded: u64,
) -> (f32, Option<usize>) {
    let length = end.saturating_sub(start);
    if length == 0 {
        return (0.0, None);
    }
    if segments.is_empty() {
        let covered = fallback_downloaded.min(end).saturating_sub(start);
        return ((covered as f64 / length as f64) as f32, None);
    }
    let mut covered = 0u64;
    let mut source = None;
    for (index, segment) in segments.iter().enumerate() {
        let last = segment.cursor.min(segment.end).max(segment.start);
        let overlap = last.min(end).saturating_sub(segment.start.max(start));
        if overlap != 0 {
            covered = covered.saturating_add(overlap);
            if source.is_none() {
                source = Some(index);
            }
        }
    }
    ((covered.min(length) as f64 / length as f64) as f32, source)
}

/// A 4-row, 192-cell visualization of sampled FILE BYTE RANGES, not 192 engine
/// chunks. Colors distinguish the segment covering the sample (not the adapter).
/// A neutral color is used where the engine supplies no individual segments.
pub fn chunk_matrix(
    ui: &mut Ui,
    painter: &Painter,
    origin: Pos2,
    total_bytes: Option<u64>,
    downloaded: u64,
    snap: Option<&Snapshot>,
) {
    let outer = crate::winui::r(origin, 17.0, 249.0, 513.0, 61.0);
    painter.rect_filled(outer, 5.0, BACKGROUND);
    painter.rect_stroke(outer, 5.0, Stroke::new(1.0, PANEL_EDGE), StrokeKind::Inside);
    let _hover = ui
        .interact(outer, ui.id().with("hybrid-range-matrix"), egui::Sense::hover())
        .on_hover_text("Byte-range progress (192 visual samples). Colors identify download segments, not network adapters.");

    let Some(total) = total_bytes.filter(|n| *n > 0) else {
        return;
    };
    let segments: &[SegmentView] = snap.map_or(&[], |s| s.segments.as_slice());
    let pad_x = 8.0;
    let pad_y = 7.0;
    let gap_x = 2.0;
    let gap_y = 3.0;
    let tile_width = (outer.width() - 2.0 * pad_x - (COLUMNS - 1) as f32 * gap_x)
        / COLUMNS as f32;
    let tile_height = (outer.height() - 2.0 * pad_y - (ROWS - 1) as f32 * gap_y)
        / ROWS as f32;

    for index in 0..CELLS {
        let (first, last) = (
            ((index as u128 * total as u128) / CELLS as u128) as u64,
            (((index + 1) as u128 * total as u128) / CELLS as u128) as u64,
        );
        let (progress, segment_index) = coverage(first, last, segments, downloaded);
        let column = index % COLUMNS;
        let column = if crate::i18n::rtl() { COLUMNS - 1 - column } else { column };
        let row = index / COLUMNS;
        let pos = pos2(
            outer.left() + pad_x + column as f32 * (tile_width + gap_x),
            outer.top() + pad_y + row as f32 * (tile_height + gap_y),
        );
        let tile = Rect::from_min_size(pos, vec2(tile_width, tile_height));
        painter.rect_filled(tile, 1.5, EMPTY);
        if progress > 0.0 {
            let color = match segment_index.map(|n| n % 3) {
                Some(0) => TEAL,
                Some(1) => AMBER,
                Some(_) => BLUE,
                None => TEAL,
            };
            let fill = Rect::from_min_size(pos, vec2(tile_width * progress, tile_height));
            painter.rect_filled(fill, 1.5, color);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::coverage;
    use mdm_engine::download::SegmentView;

    #[test]
    fn samples_real_received_intervals() {
        let segments = vec![
            SegmentView { start: 0, cursor: 20, end: 50 },
            SegmentView { start: 50, cursor: 75, end: 100 },
        ];
        assert_eq!(coverage(0, 10, &segments, 0), (1.0, Some(0)));
        assert_eq!(coverage(20, 50, &segments, 0), (0.0, None));
        assert_eq!(coverage(50, 100, &segments, 0), (0.5, Some(1)));
        assert_eq!(coverage(10, 70, &segments, 0), (0.5, Some(0)));
    }

    #[test]
    fn unknown_segments_use_downloaded_byte_count_without_fake_ownership() {
        assert_eq!(coverage(0, 100, &[], 45), (0.45, None));
        assert_eq!(coverage(50, 100, &[], 45), (0.0, None));
    }

    #[test]
    fn zero_length_samples_are_safe() {
        assert_eq!(coverage(3, 3, &[], 3), (0.0, None));
    }
}
