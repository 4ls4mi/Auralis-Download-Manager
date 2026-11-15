//! Dedicated Appearance & Wallpapers editor for the Plexo Hybrid fork.
//! Applies live; selections are persisted through the existing Settings store.

use crate::{settings::Settings, wallpaper, winui};
use egui::{Color32, Sense, Ui, vec2};

fn wallpaper_button(ui: &mut Ui, key: &'static str, title: &'static str) {
    if ui.button("Choose image…").clicked() {
        let dialog_title = title.to_owned();
        winui::start_pick(ui.ctx(), key, move || {
            winui::file_dialog(&dialog_title)
                .add_filter("Wallpaper images", &["png", "jpg", "jpeg", "webp"])
                .pick_file()
        });
    }
}

fn preview(ui: &mut Ui, path: &str, s: &Settings, target: wallpaper::Target) {
    let width = ui.available_width().max(190.0);
    let (rect, _) = ui.allocate_exact_size(vec2(width, 98.0), Sense::hover());
    let painter = ui.painter_at(rect);
    painter.rect_filled(rect, 9.0, Color32::from_rgb(22, 30, 34));
    let contrast = wallpaper::paint(
        ui,
        rect,
        path,
        s.wallpaper_blur,
        s.wallpaper_dim,
        s.wallpaper_glass,
        target,
    );
    let center = rect.shrink(11.0);
    if let Some(contrast) = contrast {
        painter.rect_filled(center, 7.0, contrast.glass);
        painter.rect_stroke(
            center,
            7.0,
            egui::Stroke::new(1.0, crate::theme::colors().list_frame),
            egui::StrokeKind::Inside,
        );
        wallpaper::outlined_label(
            &painter,
            center,
            "Mister Hybrid • Readable over wallpaper",
            contrast,
        );
    } else {
        wallpaper::glass_panel(&painter, center, s.wallpaper_glass, 7.0);
        painter.text(
            center.center(),
            egui::Align2::CENTER_CENTER,
            "No wallpaper selected — charcoal glass theme",
            egui::FontId::proportional(13.0),
            Color32::from_rgb(220, 237, 238),
        );
    }
}

fn wallpaper_file_ok(path: &str) -> bool {
    !path.is_empty() && std::path::Path::new(path).is_file()
}

pub fn show(ctx: &egui::Context, open: &mut bool, settings: &mut Settings) -> bool {
    let before = settings.clone();
    egui::Window::new("Appearance & Wallpapers")
        .id(egui::Id::unique("mister-hybrid-appearance"))
        .open(open)
        .default_width(540.0)
        .min_width(410.0)
        .resizable(true)
        .vscroll(true)
        .show(ctx, |ui| {
            ui.heading("Mister Hybrid • Appearance");
            ui.label("One consistent theme for the dashboard, download windows, dialogs and icons.");
            ui.add_space(8.0);

            ui.horizontal(|ui| {
                ui.label("Theme:");
                let old = settings.theme.clone();
                egui::ComboBox::from_id_salt("hybrid-theme")
                    .selected_text(match settings.theme.as_str() {
                        "plexo" => "Plexo Dark Glass",
                        "classic" => "Classic",
                        "emerald" => "Emerald",
                        "metro" => "Metro",
                        _ => settings.theme.as_str(),
                    })
                    .show_ui(ui, |ui| {
                        ui.selectable_value(&mut settings.theme, "plexo".to_owned(), "Plexo Dark Glass");
                        ui.selectable_value(&mut settings.theme, "classic".to_owned(), "Classic");
                        ui.selectable_value(&mut settings.theme, "emerald".to_owned(), "Emerald");
                        ui.selectable_value(&mut settings.theme, "metro".to_owned(), "Metro");
                    });
                if settings.theme != old {
                    crate::theme::select(&settings.theme, ctx);
                    crate::theme::apply_theme(ctx);
                    if settings.theme == "plexo" {
                        settings.always_dark = true;
                    }
                    crate::theme::update(settings.dark_mode_support, settings.always_dark, ctx);
                    crate::theme::apply_mode(ctx);
                }
            });
            ui.checkbox(&mut settings.always_dark, "Always use dark mode");
            ui.separator();

            ui.heading("Main window wallpaper");
            ui.horizontal(|ui| {
                wallpaper_button(ui, "app-wallpaper-main", "Choose main window wallpaper");
                if ui.button("Remove").clicked() { settings.wallpaper_main.clear(); wallpaper::clear(); }
            });
            if !settings.wallpaper_main.is_empty() {
                ui.small(&settings.wallpaper_main);
                if !wallpaper_file_ok(&settings.wallpaper_main) {
                    ui.colored_label(Color32::from_rgb(255, 176, 134), "Image could not be found. Choose another.");
                }
            }
            preview(ui, &settings.wallpaper_main, settings, wallpaper::Target::Main);
            ui.add_space(8.0);

            ui.heading("Download window wallpaper");
            ui.checkbox(&mut settings.wallpaper_download_inherit,
                "Use the same wallpaper as the main window");
            if !settings.wallpaper_download_inherit {
                ui.horizontal(|ui| {
                    wallpaper_button(ui, "app-wallpaper-progress", "Choose download window wallpaper");
                    if ui.button("Remove").clicked() { settings.wallpaper_download.clear(); wallpaper::clear(); }
                });
                if !settings.wallpaper_download.is_empty() {
                    ui.small(&settings.wallpaper_download);
                    if !wallpaper_file_ok(&settings.wallpaper_download) {
                        ui.colored_label(Color32::from_rgb(255, 176, 134), "Image could not be found. Choose another.");
                    }
                }
            }
            let download_path = wallpaper::progress_path(
                &settings.wallpaper_main,
                &settings.wallpaper_download,
                settings.wallpaper_download_inherit,
            );
            preview(ui, download_path, settings, wallpaper::Target::Progress);
            ui.separator();

            ui.heading("Glass and readability");
            ui.label("The app dims bright images more strongly, keeps text on protective surfaces, and outlines labels over pictures.");
            ui.add(egui::Slider::new(&mut settings.wallpaper_dim, 0..=90)
                .text("Wallpaper darkness %"));
            ui.add(egui::Slider::new(&mut settings.wallpaper_blur, 0..=28)
                .text("Wallpaper blur px"));
            ui.add(egui::Slider::new(&mut settings.wallpaper_glass, 48..=95)
                .text("Glass-panel opacity %"));
            ui.horizontal(|ui| {
                if ui.button("Reset wallpaper settings").clicked() {
                    settings.wallpaper_main.clear();
                    settings.wallpaper_download.clear();
                    settings.wallpaper_download_inherit = true;
                    settings.wallpaper_dim = 39;
                    settings.wallpaper_blur = 9;
                    settings.wallpaper_glass = 73;
                    wallpaper::clear();
                }
                ui.small("PNG, JPG or WebP • images are loaded locally");
            });
        });
    let changed = *settings != before;
    if changed {
        wallpaper::clear();
        ctx.request_repaint();
    }
    changed
}
