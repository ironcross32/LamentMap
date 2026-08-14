# LamentMapper

LamentMapper is a keyboard-driven Windows explorer for [Lament](https://lament.ghostglass.net/) wilderness maps.
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
- With Num Lock on, numpad keys move in their corresponding directions:
- Numpad 5 returns to the player, and numpad 0 reads the map dimensions.
- Enter or numeric-keypad Enter reads the terrain under the exploration cursor.
- D reads the map dimensions as columns by rows.
- Ctrl+Space switches focus back to the paired Mudlet window.
- Ctrl+, opens Preferences.
- Alt+F4 or File > Exit closes LamentMapper.
- Help > View guide opens this guide from beside the executable.

Terrain is announced before position. Roads also include their visible connections
in all eight compass directions, for example "Road, east-west" or
"Road, northeast-southwest." A road, player,
or landmark cell with at least three road connections is announced as a crossroads,
for example "Crossroads, east, south, west." Connections are always announced
clockwise as north, northeast, east, southeast, south, southwest, west, northwest.
With directions enabled, you hear how many units away in each direction the cell is from your position.

CTRL+SPACE will flip-flop between Mudlet and the map viewer as long as at least one valid map has been received to start it. You should allow Mudlet to start the mapper rather than doing so yourself, because this establishes a parent - child relationship where Mudlet is the parent, and the mapper is the parent. This allows the switch to work properly.

## Preferences and configuration

Preferences offers Speech, Speech and sounds, or Sounds, plus direction and
new-map-alert checkboxes. Settings are stored as `config.toml` beside the
executable. Missing known settings receive defaults. If the file contains an
unsupported version, unknown setting, or invalid value, LamentMapper renames it
to the next available `config.toml.bak`, `.bak.1`, and so on, then writes clean
defaults atomically.

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

The Prism bootstrap prepares Prism for use. invoke the script as `./scripts/bootstrap-prism.ps1` from the
repository root or `.\bootstrap-prism.ps1` while inside the `scripts` directory.
