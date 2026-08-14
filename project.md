# LamentMapper

This will be a Windows x64 application written in Rust using wxDragon for its UI, Rodio for audio playback, Prism for screen-reader speech and braille output, and a small Rust wrapper for Prism's C API.

The aim is to allow blind players who rely on a screen reader to access the highly visual wilderness map. A Mudlet package will capture each complete map, preserve its text and formatting, encode it as versioned JSON, and send it to this application. The application will validate and interpret the map before presenting it in an accessible form.

The exploration cursor will be placed at the player's position whenever a new map is received. The arrow keys navigate one cell at a time, with Up being north, Right east, Down south, and Left west. With Num Lock on, numpad 8, 9, 6, 3, 2, 1, 4, and 7 navigate north, northeast, east, southeast, south, southwest, west, and northwest. Space and numpad 5 return the cursor to the player's position. Numpad 0 reads the map dimensions like D.

Speech and short sounds indicate terrain, with configurable announcements of the cursor's displacement from the player, for example: 3 east, 6 north.

The application must **never** take foreground control of its own accord. Receiving a new map resets the exploration cursor to the center and plays a configurable alert, but does not activate the application or move Windows focus away from Mudlet.

Navigation does not wrap. Attempting to move beyond the map boundary leaves the cursor in place and plays the boundary sound. Empty or unseen cells inside the map remain navigable and are announced as unseen.

Every cursor action requests all feedback enabled by the selected mode. Explicit exception: sounds-only mode may be silent when the sound pack, an individual cue, or the audio device is unavailable; this is nonfatal and the Preferences dialog warns before accepting that mode.

Every valid map found in a new prompt-delimited response is transmitted, even when its glyphs and colors exactly match the preceding map. Identical local views can occur at different world positions, and a repeated survey must reset the explorer cursor. The system does not otherwise track stale maps. If game output contains no valid map, Mudlet sends nothing and the application retains its previous map without changing its status or playing the new-map alert.

## Verified map format

The map size varies with natural light, distance vision, night vision, elevation, and obstructing terrain.

A map with `N` logical rows is encoded as exactly `N` text rows of `2N` characters. `N` is odd, and each logical location normally occupies two adjacent characters. Observed examples include six leagues as 13 rows by 26 characters and seven leagues as 15 rows by 30 characters.

Leading spaces, trailing spaces, and rows consisting entirely of spaces are significant and must never be trimmed. They represent unseen locations while preserving the square grid.

The player is shown by a single `*` in the second character of the center cell. This replaces that character rather than being inserted; for example, dense forest at the player position appears as `T*`. Infer terrain only when the remaining first character identifies one documented token uniquely. In that case, announce the terrain followed by `(player's position)` and play its terrain cue together with the player cue. Ambiguous prefixes such as `s*`, `.*`, and `x*` retain the generic player announcement and cue rather than guessing.

Landmarks are markers rather than terrain and obscure the first character of the underlying terrain token. The unobscured second character remains in the map; for example, a landmark over dense forest is `#T`. Both `#` and `@` marker forms share the Landmark semantic and sound.

### Normal terrain legend

The Plains token is two consecutive U+0022 QUOTATION MARK characters.

| Terrain | Token |
| --- | --- |
| Ocean | `^^` |
| Plains | `""` |
| Light Forests | `tt` |
| Dense Forests | `TT` |
| Hills | `nn` |
| Badlands | `V-` |
| Mountains | `/\` |
| High Mountains | `MM` |
| Swamps | `sf` |
| Marshes | `ss` |
| Lakes | `--` |
| Deserts | `..` |
| Dune Deserts | `.n` |
| Scrub Deserts | `.v` |
| Rivers | `~~` |
| Ice Fields | `ii` |
| Road | `==` |

### Wasted terrain and markers

| Terrain or marker | Token |
| --- | --- |
| Wasteland | `x"` |
| Wasted Light Forests | `xt` |
| Wasted Dense Forests | `xT` |
| Light Fungus | `ft` |
| Dense Fungus | `FT` |
| Wasted Ocean | `x^` |
| Wasted Lakes | `x-` |
| Wasted Rivers | `x~` |
| Landmark | `#` in the first character of a cell; the second terrain character remains visible, for example `#T` |
| Landmark | `@` in the first character of a cell; the second terrain character remains visible |
| Complete landmark glyphs | `##` and `@@` remain accepted |
| Player | `*` in the second character of the center cell |

## Map capture and validation

Mudlet's native prompt recognition will delimit server responses. This is preferable to matching the visible prompt because fatigue may add a variable number of `|` characters before `>`, and help text can contain examples that merely look like prompts.

At each real prompt, the Mudlet package examines only output received since the preceding real prompt. It must not search arbitrarily far back through the console buffer because old maps remain in scrollback.

An automatic map ends directly before the prompt when screen-reader mode is off. A `survey leagues` map is followed by the known visibility sentence. If the response contains no map, nothing is sent to the application.

A candidate map has one odd number `N` of contiguous rows and exactly one `*` at the expected center-cell position. Because Mudlet may omit invisible trailing spaces or pad buffer lines beyond their textual content, capture derives `N` from the player marker position, restores missing trailing spaces to `2N`, and removes only an all-space suffix beyond `2N` before strict validation. Leading spaces are never altered. Cells may contain only known terrain tokens, known markers, or spaces. Every valid map in a new prompt-delimited response is sent, even if its content matches the previous map.

Console wrapping or any other malformed capture causes the candidate to be rejected. A bad capture must never replace a valid map.

Mudlet captures the raw rows and per-character foreground and background colors. Rust performs the authoritative validation and terrain interpretation. Newline-delimited JSON messages include a protocol-version field and capture timestamp.

## Mudlet-to-application transport

Mudlet owns the mapper process. The package launches `LamentMapper.exe` with Mudlet's `spawn` API, retains the process handle in `lamentMapper`, and sends one versioned JSON object per line over the child's standard input. This avoids the clipboard, polling temporary files, and an open localhost port.

The application treats each input line as one complete message. Invalid JSON, unsupported protocol versions, and invalid maps are logged and ignored without terminating the application.

The child exits cleanly when its standard-input pipe reaches end-of-file. Mudlet closes the process handle during package cleanup and profile shutdown. If the player closes the application manually, the package launches a new instance when the next valid map is captured and then sends that map.

The package stores the configured path to `LamentMapper.exe`. Release documentation will explain how to set or correct this path. If the executable cannot be found or launched, Mudlet reports a concise error without affecting game input.

## Sounds

Rodio supports Ogg Vorbis, so sounds will use 96 kbps mono Ogg Vorbis.

- Sounds for each terrain type
- A sound for when the cursor lands on the center
- A boundary sound
- A sound for empty or unseen tiles
- A sound when a new map is received

When this app is distributed, the sounds should be packed into a single, proprietary binary format and encrypted. When the app starts, this pack is loaded and decrypted, and all sounds contained within it are loaded into memory and kept there for the duration of the app's existence for fast playback.

Because the application necessarily contains the information needed to decrypt its own assets, this encryption is intended to deter casual extraction rather than provide strong cryptographic protection.

Sound assets are not expected to be present during initial development. Failure to locate a sound must not crash the application; it generates a warning in the log and speech remains available as the fallback. All required sounds must be present before the first published release.

## Multiple instances

Only one LamentMapper process may run at a time. Enforce this with wxDragon's native single-instance checker. A second launch exits cleanly without activating or focusing the existing instance and records the reason when logging is available.

Under normal operation the Mudlet package is the sole owner of the application process. Launching the executable independently is not the supported map-delivery workflow.

## Release format

The supported target for the first release is Windows x64.

The Prism bootstrap uses the official Prism 0.17.3 `prism-windows-x64.zip` release asset, verifies SHA-256 `9a44e81f2caa8f1bf804c182f39a7a415f8b82d6032f4fe686e145a3d09dbb2f`, and stages `dynamic/release/bin/prism.dll` with the bundled Prism license and notice.

This project will be hosted on GitHub. CI should build it and package it into a portable ZIP containing all required runtime files, including the executable, compiled Mudlet package, HTML README, and the sound pack once sounds are available. There shall be no installers.

## Mudlet
All Mudlet triggers, scripts, aliases, etc. will be built with [Muddler](https://github.com/demonnic/muddler). All variables and functions must be stored in a single `lamentMapper` table. Initialization must be idempotent. The package checks the supplied package name when handling `sysInstall` and `sysUninstall`: it initializes its state on installation and closes its process and handlers before setting `lamentMapper` to `nil` on uninstall.

Muddler's documentation can be found [here](https://github.com/demonnic/muddler/wiki).

Do not invoke the muddle or muddler commands yourself, I will do it as its success hinges on several factors, such as Docker running.

The skeleton muddler files are in the accessible_lament_map directory. Feel free to modify them  or even delete them to start from scratch if that would be better.

## Configuration

Application settings are stored in `config.toml` beside the executable. Defaults live in the Rust source, and the file is regenerated whenever it is missing. CI must not ship `config.toml`, and it must be listed in `.gitignore` to prevent personal settings from entering the repository or release artifacts.

The config parser should be robust enough to tell if the configuration is corrupt or invalid values are given. In such cases, it rotates the config to one with a .bak extension and generates a clean config.toml. This will allow the user to fix the config file if they need to, or they can just remove the old .bak one.

### What is configurable?

- Whether to automatically speak directions as the player moves across the map, i.e. 3 east, 6 north. (on by default)
- Cursor feedback mode, as described below.
- Whether the app should sound the new-map alert (on by default).

For the speech and sounds when moving the cursor, these should be a radio button group with the following options:

- Speech
- Speech and sounds
- Sounds

There should be no "none" option since this would render the app useless until the user fixed it.

## UI

The main map area is a keyboard-focusable control. It keeps logical focus while the application is active except when the user opens a menu or dialog. Updating the map while the application is in the background must not activate its window.

The current cell's terrain or marker, relative direction, and relevant application state are exposed to Prism for screen-reader speech and braille output. The visual UI and accessible output must describe the same cursor position.

The wxGrid is a passive visual rendering surface. It cannot receive keyboard focus and exposes no native grid cursor or selection. The keyboard-focus host is a single native client object with no accessible children, keeping wxGrid entirely outside the screen-reader tree without synthetic graphic roles or state flags. On window activation, and for every map-navigation action, terrain and position speech and braille output comes exclusively from Prism.

Prism is a required runtime dependency. If prism.dll cannot be loaded or no Prism backend can be acquired, the application presents a standard accessible native error dialog explaining the failure and exits without opening the map UI. There is no visual-only or native-control announcement fallback.

### Menu bar

#### File
- Preferences - The preferences screen (Accessible anywhere in the app with CTRL+,)
- Exit – quits the app; responds to ALT+F4 as well

#### Help

- View README - Opens the readme that lives next to the executable.

Note: CI should convert the markdown README file to HTML and bundle it in the ZIP. The Markdown file should not be shipped in the ZIP archive.

Runtime files are located relative to the executable rather than the process's current working directory. This includes `config.toml`, `README.html`, the sound pack, and the log directory.

### Status bar

Register the status bar as a standard accessible status bar so screen readers can query it. Indicate:

- If there has never been a map received: Ready
- Relative time of the last map received.

### Preferences screen
This contains all options laid out in the Configuration section. Controls must have programmatically associated labels, a sensible keyboard tab order, and their current values exposed to screen readers.

## Logging

Use the Rust `flexi_logger` crate with the `log` facade. Log startup, clean shutdown, configuration recovery, missing or invalid assets, transport errors, rejected JSON or maps, and every successfully received map. Do not include unrelated MUD output in the log.

## Final protocol contract

Transport is UTF-8 newline-delimited JSON protocol version 1. An input line may not exceed 1 MiB. A map message contains only `protocol_version`, `type`, `captured_at`, `sequence`, `rows`, and `styles`; unknown fields invalidate it. `type` is exactly `map`.

Style runs use zero-based character offsets and contain `start`, `length`, and RGB `foreground` and `background` objects. Runs are nonempty, contiguous, begin at zero, and cover every character exactly once. There are exactly as many style rows as text rows. Invalid input never replaces the current valid map.

```json
{
  "protocol_version": 1,
  "type": "map",
  "captured_at": 1786550400,
  "sequence": 1,
  "rows": ["T*"],
  "styles": [[{
    "start": 0,
    "length": 2,
    "foreground": {"r": 255, "g": 255, "b": 255},
    "background": {"r": 0, "g": 0, "b": 0}
  }]]
}
```

The abbreviated one-row example illustrates the wire fields; production map rows still obey the complete odd-square and two-characters-per-cell rules above.

## Final configuration contract

The file beside the executable has this default content:

```toml
version = 1

[feedback]
mode = "speech_and_sounds"
announce_directions = true
new_map_alert = true
```

Valid modes are `speech`, `speech_and_sounds`, and `sounds`. Missing known values receive defaults. Unknown fields, invalid values, and unsupported versions make the file invalid. An invalid file is renamed to the next available `config.toml.bak`, `.bak.1`, and so forth before defaults are written atomically.
