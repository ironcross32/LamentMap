# Accessible Lament Map

## Purpose

[Lament: the Age of Wind and Wolves](https://lament.ghostglass.net/) has a vast wilderness consisting of many thousands of rooms. The MUD presents an ascii map upon request or when traversing these wilderness rooms. This works well for sighted players, but not so for screen reader users. The staff have thoughtfully implemented many accessibility requests throughout the years, among them is a series of textual descriptions that indicate what's around the character.

The problem is, these descriptions do not carry the same level of information as the ascii map. LamentMapper aims to bridge that gap by employing a two-tiered approach. Tier 1 is the Mudlet package whose README you're perusing right now. Its job is to identify these ascii maps, capture them in tact, pack them into JSON, and transmit them. Tier 2 is an app written in Rust using [WxDragon](https://crates.io/crates/wxdragon) for its GUI and [Prism](https://github.com/ethindp/prism) for speech output. The app receives these maps and renders them using a combination of speech and sounds.

⚠️🚓   The mapper app is intended for screen reader users only and may not start if Prism can't determine a route for speech. The app is also intentionally non-visual   🚓⚠️

Cursor keys move from cell to cell, and the preferences screen determines what you hear. Users who become familiar with the sounds can turn off automatic speech, making navigation quicker; though, they'll still have access to it on demand. It's possible to get an overview of all the terrain types the current map shows, and how many of said tiles exist.

An optional audio cue indicates that a new map is received. When this happens, the cursor is placed at the center of the map where the player stands. When exploring, it's possible to hear directions to the target from the player's perspective. These can either be expressed in cardinal directions (north, east, south, and west), or ordinal directions (northeast, southwest, etc. It is also possible to mark a cell for auto-movement, in which the app will transmit directions to Mudlet to be carried out, thus, causing the player's character to walk to the given destination.

### Setup

Install the package into Mudlet using whatever means best suit you, then run:
`lamentmapper setup auto` and select the parent folder that should contain the
new LamentMapper folder. Automatic setup requires Windows x64 and at least Mudlet 4.6. It downloads the latest Windows x64 release, extracts it into that LamentMapper subfolder, validates its runtime files, and saves the inferred
executable path.

To update an existing installation in place, select the folder that contains its
LamentMapper folder. Files absent from the release archive, including
config.toml, are preserved. For manual setup, download and extract the release
ZIP, run `lamentmapper setup manual`, and select LamentMapper.exe.

Use `lamentmapper status` if something isn't working as intended. It can give clues as to what might be wrong.

Use `lamentmapper toggle` to disable map capturing and close the mapper app if open. Run it again to resume capturing.

Map-rejection warnings are disabled by default so messages such as skill-improve
notices are not mistaken for user-facing mapper failures. Run
`lamentmapper debug` to toggle these diagnostics during troubleshooting. The
debug and map-capture states are included in `lamentmapper status`.

### Usage

In Lament, switch on screen reader mode by typing `screenreader on`. The mapper will still work if this is not done; however, the game doesn't send its prompt until after the next action, so this isn't ideal. Screen reader mode resolves this. Because screen reader mode renders textual descriptions, the package will send `survey leagues` to the MUD whenever it detects that the character has moved from one wilderness room into another. This ensures there's always a fresh map.

To view the map, press CTRL+SPACE within Mudlet. This causes the current mapper window to gain focus. Pressing the same shortcut key from within the app will return focus to Mudlet. It is also possible to hide the app from within the preferences dialog. Doing so keeps the app out of your ALT+TAB list. Whichever way you return to Mudlet (either CTRL+SPACE or ALT+TAB) with this preference on will still hide the window.

Navigation is done with the arrow keys or, with the numpad when numlock is turned on. The benefit of using the numpad is that you may also move in ordinal directions. Hitting SPACE will always return the cursor to the center, which is where the player's character is represented.

Movement will produce speech as well as sounds. This can be tailored in preferences. To get an overview of what terrain types are visible on the map, press **T**. The list should be sorted in alphabetical order with the exception of unseen tiles (meaning tiles the player's character cannot see into for various reasons).  Pressing **ESC** backs out of this menu. Pressing **ENTER** on a terrain type finds the nearest tile of said type and places your cursor on it.

Pressing **M** on any tile will send a movement request to Mudlet and your character will walk to that tile. Pressing **D** will give the dimensions of the map. the map size is influenced by various factors like time of day, terrain types, character stats and skills, etc. Pressing **ENTER** on a tile will announce it's type and directions from the player's position. **ESC** from the map grid will cancel any active auto-movement request.