# Accessible Lament Map

This Mudlet package detects complete Lament wilderness maps between real prompt
events and sends them to `LamentMapper.exe` over standard input.

After importing the generated `.mpackage`, run `lamentmapper setup auto` and
select the folder where LamentMapper should be installed. Automatic setup requires
Windows x64 and Mudlet 4.6 or newer. It downloads the latest Windows x64 release,
extracts it into the selected folder, validates its runtime files, and saves the
inferred executable path.

Selecting an existing LamentMapper folder performs an in-place update. Files absent
from the release archive, including `config.toml`, are preserved. For manual
setup, download and extract the release ZIP, run `lamentmapper setup manual`, and
select `LamentMapper.exe`. The original `lamentmapper setup` command continues to
invoke manual setup.

Use `lamentmapper status` to inspect the configured path and managed-process
state.

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
