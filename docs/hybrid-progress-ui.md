# Hybrid progress visualization (Mister + Plexo/Zajil-inspired)

This branch adds a **native Rust/egui** progress view inside Mister Download Manager. It does not embed Electron or port a separate download engine.

## What changed

- The existing per-download progress dialog now displays a compact throughput waveform in place of its standard completion meter (the existing verifying/merging completion meter remains intact).
- The "Show details" area now displays a dark, **48 × 4 matrix** of visual byte-range samples, in the style of Plexo's colored split display, replacing the old thin gradient segment strip.
- The connection table is shifted down to give the matrix adequate height.
- Pause/resume/cancel, download scheduling, and engine behavior are intentionally unchanged.
- Progress data is collected from `Item::rate()`; byte-range coverage comes from `mdm_engine::Snapshot.segments` (start, cursor, end), with a contiguous-progress fallback if the engine reports no segment list.
- Visual samples are **not** direct one-to-one engine chunks. Colors identify which engine segment covered the sample, not different network adapters.

## What is not supported

Mister's `Snapshot` currently does **not** publish the network-adapter identity for each segment. The Plexo-style teal/amber/blue mapping is a visual indicator, **not** an Ethernet 1 / Ethernet 2 / vEthernet attribution. Adding genuine per-adapter split ownership would require separate engine instrumentation.

No executable installers or CI-verified builds are included in this branch.

## Changed files

- `crates/app/src/hybrid_progress.rs` — new native graph and range-grid painter, and coverage tests
- `crates/app/src/progress.rs` — real-time history, painter integration, and detail layout
- `crates/app/src/main.rs` — module registration

## Validate locally

From the repository root, with Rust 1.98+ and Mister's pinned toolchain dependencies available:

```bash
cargo fmt --all -- --check
cargo test -p mdm-app
cargo build -p mdm-app
```

The whole codebase is GPL-3.0-or-later. The new visual components are independently written based on the appearance shown in the request, and do not copy Plexo or Zajil source code.

## References

- Mister: https://github.com/anefzaoui/misterdownloadmanager
- Plexo: https://github.com/anmolkapil/plexo
- Zajil: https://github.com/motalim-ai/zajil-download-manager
