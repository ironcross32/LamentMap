# Accessible Lament Map

This Mudlet package detects complete Lament wilderness maps between real prompt
events and sends them to `LamentMapper.exe` over standard input.

After importing the generated `Accessible-Lament-Map.mpackage`, run
`lamentmapper setup auto` and select the parent folder that should contain the
new `LamentMapper` folder. Automatic setup requires Windows x64 and Mudlet 4.6
or newer. It downloads the latest Windows x64 release, extracts it into that
`LamentMapper` subfolder, validates its runtime files, and saves the inferred
executable path.

To update an existing installation in place, select the folder that contains its
`LamentMapper` folder. Files absent from the release archive, including
`config.toml`, are preserved. For manual setup, download and extract the release
ZIP, run `lamentmapper setup manual`, and select `LamentMapper.exe`. The original
`lamentmapper setup` command continues to invoke manual setup.

Use `lamentmapper status` to inspect the configured path and managed-process
state, including an active automatic-setup stage and whether the saved
executable is absent, invalid, or usable. Installing this hyphenated package
automatically removes the legacy `Accessible Lament Map` package when found and
requires one fresh setup. Uninstalling removes both current and legacy saved-path
files.

Automatic updates extract over the application directory without deleting
user-owned files, so the existing `config.toml` is preserved. In that file,
`mode = "speech"` intentionally disables terrain sounds.

Press Ctrl+Space in Mudlet to focus the managed LamentMapper window when it is
already running. The key reports an unavailable window without launching the mapper.

Every valid grid from a new prompt-delimited response is sent, including a grid
identical to the previous one. This ensures repeated surveys and visually identical
world positions still reset the explorer cursor. A failed process write is retried once.

Mudlet can omit invisible trailing spaces from sparse maps. The detector restores
only those trailing blank cells using the player marker's fixed center position, then
performs strict dimension and terrain-token validation. `lamentmapper status` reports
the exact rejection reason for the most recent prompt if a candidate is invalid.

Landmark glyphs replace the first character of their underlying terrain cell, so
tokens such as `#T` and `@~` are valid and are transmitted as landmarks.

Build this directory with Muddler. Repository automation does this in CI; local
package building is intentionally left to the user.
