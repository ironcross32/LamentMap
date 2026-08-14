# Repository Guidelines

## Project Structure & Module Organization

`src/` contains the Rust 2024 application. `main.rs` starts the Windows GUI, `lib.rs` exposes shared modules, and `src/bin/pack_sounds.rs` provides the sound-pack utility. Keep domain logic in focused modules such as `protocol.rs`, `navigation.rs`, or `audio.rs`. Integration tests and JSON fixtures live under `tests/`; module-level unit tests stay beside their implementation. `accessible_lament_map/` holds the Mudlet Lua package and Muddler metadata. PowerShell automation is in `scripts/`, while `.github/workflows/` defines CI and release packaging. Treat `target/`, `dist/`, `deps/`, runtime logs/configuration, and local sound sources as generated or ignored artifacts.

## Build, Test, and Development Commands

Use Windows x64 with the MSVC Rust 1.95 toolchain.

```powershell
./scripts/bootstrap-prism.ps1
cargo fmt --all --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all-targets --all-features
cargo build --release
```

The bootstrap script stages the pinned Prism DLL after checksum verification. Formatting, Clippy, and the full test suite match CI; the final command builds the release application. To validate the committed audio bundle, run `cargo run --release --bin pack-sounds -- --validate sounds.pack`. Do not run Muddler during automated work; CI builds the Mudlet package from its pinned revision.

## Coding Style & Naming Conventions

Follow standard Rust conventions: four-space indentation, `snake_case` functions/modules, `CamelCase` types, and `SCREAMING_SNAKE_CASE` constants. `rustfmt.toml` sets a 110-column maximum and enables field-init shorthand. Keep Clippy warning-free and handle fallible operations with contextual errors rather than unchecked panics outside tests. Lua handlers use the established `LamentMapper_*` filenames and `lamentMapper.*` namespace.

## Testing Guidelines

Add focused `#[test]` unit tests in each module's `tests` block. Put cross-module behavior in `tests/*.rs` and reusable inputs in `tests/fixtures/`. Name tests as behavioral statements, for example `parses_real_thirteen_by_thirteen_html_log_map`. Run the full CI test command before submitting; no numeric coverage threshold is configured.

## Commit & Pull Request Guidelines

History currently contains a single concise, imperative-style subject (`Initial LamentMapper implementation`). Continue with short subjects that describe one logical change. Pull requests should explain user-visible behavior, list validation commands, and link relevant issues. Include screenshots for visual grid/dialog changes and describe screen-reader, braille, or audio verification for accessibility changes. Never commit `config.toml`, logs, downloaded dependencies, build outputs, or private raw sound sources.
