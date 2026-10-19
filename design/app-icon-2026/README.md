# NeoBili icon · 2026

## Current production revision

Stacked video cards on white. A theme-colored front card carries a rounded white play glyph; two
cards in the same theme color peek above it at 55% and 30% opacity, suggesting a feed. Each piece
is a separate Icon Composer group (front card and play glyph together, then the middle and back
cards), so the system Liquid Glass separates the layers and derives the dark and tinted
appearances. Editable flat master: `Cards-white-master.svg`; README preview:
`Cards-production.png` (exported with `ictool`, Default rendition). The system supplies Liquid
Glass effects.

Production sources: `../../NeoBili/Resources/AppIcons/`. The default icon is
`NeoBiliIcon`; the other 23 are `NeoBiliIcon-<theme-id>`, one per theme color in `AppTheme`, so
the icon follows the user's chosen theme color.

Regenerate through `scripts/generate-app-icons.py` when changing the mark or palette.
The SVG master and production preview describe the current design.
