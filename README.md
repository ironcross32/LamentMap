# LamentMapper

LamentMapper is a keyboard-driven Windows explorer for [Lament](https://lament.ghostglass.net/) wilderness maps.
Mudlet detects complete maps in the current server response and streams their
original text and colors to a native, read-only grid. Prism supplies the required
responsive screen-reader speech and braille; optional terrain sounds are played
through Rodio.

## Requirements

- Windows 10 or 11, x64
- Mudlet with the bundled `Accessible-Lament-Map.mpackage` installed
- The bundled prism.dll beside LamentMapper.exe
- The portable release files kept together in one directory

LamentMapper is launched and owned by Mudlet. Opening maps from files is not
supported in this release.

## Setup

The easiest way to get going is to install the package directly in Mudlet like this:

```lua
lua uninstallPackage"Accessible-Lament-Map";installPackage"https://github.com/ironcross32/LamentMap/releases/latest/download/Accessible-Lament-Map.mpackage"
```

Once downloaded, it'll prompt you what to do next. The easiest method is automatic setup, which works as follows:
1. Type `lamentmapper setup auto
2. Select the folder where the app will be extracted Note: the folder you select will be the parent folder that will contain the LamentMapper folder
3. The app will be downloaded to a tempoerary location, and the archive will be extracted to the location you specified

Automatic setup requires Windows x64 and Mudlet 4.6 or newer. It downloads the
latest Windows x64 release over HTTPS, creates or reuses a `LamentMapper`
subfolder beneath the selected folder, and configures its inferred
`LamentMapper.exe` path. To update an existing installation in place, select the
folder that contains its `LamentMapper` folder. Files that are not in the release
archive, including `config.toml`, are preserved.

For manual setup, download and extract the latest Windows x64 release ZIP, enter
`lamentmapper setup manual`, and select the extracted `LamentMapper.exe`.
The original `lamentmapper setup` command remains an alias for manual setup.

Use `lamentmapper status` to check if things are working properly. Use
`lamentmapper debug` to toggle extra messages on or off which might be helpful if
things aren't working as intended. `lamentmapper toggle` disables all map capture
and closes the mapper; run it again to resume capture. The mapper stays closed
until the next valid map is captured.

## Exploring a map

The cursor starts on the player whenever a map arrives.

- Arrow keys move north, east, south, and west without wrapping.
- Space returns to the player, including feedback when already centered.
- With Num Lock on, numpad keys move in their corresponding directions:
- Numpad 5 returns to the player, and numpad 0 reads the map dimensions.
- Enter or numeric-keypad Enter reads the terrain under the exploration cursor.
- T opens the terrain-types menu. Use Up and Down to browse, Home and End to
  jump to either end, Page Up and Page Down to move by about ten percent, and
  Left and Right to adjust an item when a menu offers multiple values. The
  terrain menu wraps from either end. Press Enter or numeric-keypad Enter to
  choose a terrain, or Escape to close the menu without moving the cursor.
- D reads the map dimensions as columns by rows.
- H reads the cursor's direction from the player. Press H again within 0.5 seconds
  to hear the alternate cardinal-only or diagonal-aware directions.
- M requests automatic movement from the player to the selected non-player tile.
- Escape cancels a pending or active automatic movement route.
- Ctrl+Space switches focus back to the paired Mudlet window. It can optionally
  hide LamentMapper after the switch succeeds.
- Ctrl+, opens Preferences.
- Alt+F4 or File > Exit closes LamentMapper.
- Help > View guide opens this guide from beside the executable.

Terrain is announced before position. Roads also include their visible connections
in all eight compass directions, for example "Road, east-west" or
"Road, northeast-southwest." A road, player,
or landmark cell with at least three road connections is announced as a crossroads,
for example "Crossroads, east, south, west." Connections are always announced
clockwise as north, northeast, east, southeast, south, southwest, west, northwest.
With directions enabled, you hear how many units away in each direction the cell
is from your position. The optional shortest-path setting uses diagonal steps
first, so a position 3 east and 2 north is announced as "2 northeast, 1 east"
instead of "3 east, 2 north." H reads only this relative direction regardless of
whether automatic direction announcements are enabled.

The terrain-types menu lists only terrain present on the current map, with a
tile count for each type; unseen cells appear last. Choosing an entry moves the
exploration cursor to the closest matching tile using eight-way distance. If
several tiles are equally close, the first one in row-by-row map order is used.
The map host keeps keyboard focus while this virtual menu is open.

By default, "Dynamic terrain descriptions" gives eligible plains and forests
more specific spoken names based on all eight neighboring cells. Plains beside
a river are announced as "Riverbank," and plains beside an ocean as "Seashore."
Forests beside a river, lake, or mountain are announced as "Wooded riverbank,"
"Forested lakeside," or "Forested mountainside." River takes priority over ocean
for plains; river, lake, then mountain is the priority order for forests. These
names affect speech and braille terrain text only: map glyphs, colors, terrain
sounds, roads, and automatic movement are unchanged.

Automatic movement uses the cursor's coordinate displacement; it does not inspect
terrain, roads, or obstacles. The shortest eight-way route always sends diagonal
steps first, regardless of the direction-announcement preference. Mudlet waits a
random 0.5 to 1.5 seconds before each command, sends the full direction name with
command echo disabled, and will not schedule the next direction until Lament's
existing room-entry message confirms arrival. If that confirmation never arrives,
movement waits indefinitely. Mudlet rejects a new route while one is active and
reports the rejection; Escape cancels the pending timer and route. LamentMapper's
own confirmation means only that the request reached Mudlet, not that Mudlet
accepted it.

Ctrl+Space switches between Mudlet and the map viewer as long as Mudlet launched
the mapper. This is a shortcut managed by Mudlet and LamentMapper, not a
system-wide hotkey. If "Hide mapper window when switching to Mudlet" is enabled,
switching from LamentMapper to its paired Mudlet window with Ctrl+Space, Alt+Tab,
or the mouse hides the mapper so it no longer appears in Alt+Tab. Press Ctrl+Space
in Mudlet to restore and focus the hidden mapper. With the preference disabled,
switching to Mudlet leaves LamentMapper visible in Alt+Tab.

## Preferences and configuration

Preferences offers Speech, Speech and sounds, or Sounds, plus automatic-direction,
shortest-path diagonal, dynamic-terrain-description, new-map-alert, and optional
mapper-hiding checkboxes. "Dynamic terrain descriptions" is on by default;
diagonal directions and mapper hiding are off by default. Settings are stored as
`config.toml` beside the
executable. Missing known settings receive defaults. If the file contains an
unsupported version, unknown setting, or invalid value, LamentMapper renames it
to the next available `config.toml.bak`, `.bak.1`, and so on, then writes clean
defaults atomically. `mode = "speech"` intentionally disables terrain sounds;
choose `speech_and_sounds` or `sounds` to enable them.

## Troubleshooting

- If Mudlet says the executable is not configured, run
  `lamentmapper setup auto`, or use `lamentmapper setup manual` for an
  existing extracted installation.
- If automatic setup fails, download and extract the latest Windows x64 release
  ZIP, then run `lamentmapper setup manual` and select `LamentMapper.exe`.
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
