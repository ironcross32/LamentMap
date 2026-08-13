# Accessible Lament Map

This Mudlet package detects complete Lament wilderness maps between real prompt
events and sends them to `LamentMapper.exe` over standard input.

After importing the generated `.mpackage`, run `lamentmapper setup` and select
`LamentMapper.exe`. Use `lamentmapper status` to inspect the configured path and
managed-process state.

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
