# LamentMapper

LamentMapper is a keyboard-driven Windows explorer for Lament wilderness maps.
Mudlet detects complete maps in the current server response and streams their
original text and colors to a native, read-only grid. Prism supplies the required
responsive screen-reader speech and braille; optional terrain sounds are played
through Rodio.

## Requirements

- Windows 10 or 11, x64
- Mudlet with the bundled `Accessible Lament Map.mpackage` installed
- The bundled prism.dll beside LamentMapper.exe
- The portable release files kept together in one directory

LamentMapper is launched and owned by Mudlet. Opening maps from files is not
supported in this release.

## Setup

1. Extract the portable ZIP to a directory you can keep.
2. Import `Accessible Lament Map.mpackage` into the desired Mudlet profile.
3. In that profile, enter `lamentmapper setup`.
4. Select the extracted `LamentMapper.exe`.

Use `lamentmapper status` to report the normalized executable path and whether
the Mudlet-managed child process is running. If the application is closed, the
next valid map starts it again. Closing the profile or uninstalling the package
closes the managed process.

## Exploring a map

The cursor starts on the player whenever a map arrives.

- Arrow keys move north, east, south, and west without wrapping.
- Space returns to the player, including feedback when already centered.
- Ctrl+, opens Preferences.
- Alt+F4 or File > Exit closes LamentMapper.
- Help > View guide opens this guide from beside the executable.

Terrain is announced before position. With directions enabled, an example is
"Dense forest, 3 east, 2 north." Horizontal displacement is announced before
vertical displacement. The player is announced as "Player position, center,"
blank cells as "Unseen," and both landmark symbols as "Landmark."

The visual grid is excluded from the Windows accessibility tree and has no native
selection cursor. Its keyboard-focus host exposes no grid children or synthetic
state flags. Raw glyphs and wxGrid selection changes are therefore never announced;
window-focus and map-navigation speech and braille come from Prism.

Receiving a map never activates LamentMapper or takes focus from Mudlet. The
new map replaces the old one immediately and resets the exploration cursor.

## Preferences and configuration

Preferences offers Speech, Speech and sounds, or Sounds, plus direction and
new-map-alert checkboxes. Settings are stored as `config.toml` beside the
executable. Missing known settings receive defaults. If the file contains an
unsupported version, unknown setting, or invalid value, LamentMapper renames it
to the next available `config.toml.bak`, `.bak.1`, and so on, then writes clean
defaults atomically.

Sounds-only mode is allowed when the sound pack or output device is unavailable,
but it may be silent. The Preferences dialog warns before accepting that choice.

## Troubleshooting

- If Mudlet says the executable is not configured, run `lamentmapper setup`.
- Keep `prism.dll`, `sounds.pack`, and `README.html` beside the executable.
- Prism is required. If prism.dll is missing, corrupt, incompatible, or cannot
  acquire a screen-reader backend, LamentMapper shows a native error dialog and
  exits. The underlying error is also recorded in the logs directory.
- Missing or corrupt sounds are nonfatal. Speech remains available in modes that
  include speech.
- Invalid input maps are logged and discarded; the last valid map stays visible.
- Logs rotate at 1 MiB with five retained files and never contain unrelated MUD
  output.

## Developer build

The MSVC Rust 1.95 toolchain and Windows x64 are the supported build environment.

```powershell
./scripts/bootstrap-prism.ps1
cargo fmt --all --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all-targets --all-features
cargo build --release
```

The Prism bootstrap downloads the official 0.17.3 Windows x64 release archive,
selects `dynamic/release/bin/prism.dll`, and refuses to stage it unless the
archive SHA-256 is
`9a44e81f2caa8f1bf804c182f39a7a415f8b82d6032f4fe686e145a3d09dbb2f`.
From PowerShell, invoke the script as `./scripts/bootstrap-prism.ps1` from the
repository root or `.\bootstrap-prism.ps1` while inside the `scripts` directory.

Do not run Muddler as part of an automated implementation session. CI builds it
from pinned source revision `97125cd7806fe7fdce84533eb4b683fe2503b94d` and
verifies `Accessible Lament Map.mpackage`; local package builds are manual.

To create the encrypted pack from the private mono Ogg sources:

```powershell
cargo run --release --bin pack-sounds -- sounds-src sounds.pack
cargo run --release --bin pack-sounds -- --validate sounds.pack
```

The source repository may omit `sounds.pack` during development. Tagged release
automation requires and validates it before creating a ZIP. The pack key must be
present in public application code, so encryption deters casual extraction but
cannot provide strong secrecy.
