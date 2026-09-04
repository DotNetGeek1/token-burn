# 06 — Art asset manifest

## Included usable starter assets

| File | Purpose |
| --- | --- |
| `assets/cabinet_chassis_16x9.svg` | Layerable base chassis with transparent gameplay openings. |
| `assets/commit_button_states.svg` | Four-state horizontal atlas: idle, armed, danger, busy. |
| `assets/module_bay_states.svg` | Five-state horizontal atlas: open, selected, target, active, locked. |
| `assets/cabinet_systems_tiers.svg` | Twenty-cell atlas: five systems × four tiers. |
| `assets/ui_frames.svg` | CRT/panel/card/telemetry frame atlas. |
| `assets/maintenance_backdrop.svg` | Dark maintenance-view backdrop and fixed mounting guides. |
| `data/atlas_regions.json` | Atlas cell coordinates. |

Godot imports SVG directly. Keep the SVG sources in version control; generate raster atlases only if profiling proves vector import/runtime memory unsuitable.

`previews/` contains rasterized validation copies and `asset_contact_sheet.png`. They are convenient for review and prototyping; the SVGs remain authoritative.

## Reference-only art

- `references/cabinet_gameplay_reference.png`
- `references/cabinet_evolution_reference.png`

These establish hierarchy, materials and progression. Do not trace their exact layout or trust their microcopy.

## Assets still requiring final art pass

The supplied SVGs are production-usable starters, but final polish should author:

- Four isolated transparent PNG/SVG tiers for each cabinet system (20 total) if separate textures are preferred over the atlas.
- A 9-slice CRT bezel and chassis corner set matching the final chosen texture resolution.
- Commit button press/depress frames or shader parameters.
- Abort lever final frame set if the existing lever art cannot be separated from the old plate.
- Optional grime/scorch decals (cosmetic only).
- Installation sparks/flicker particles and reduced-motion crossfade.
- Maintenance menu icons consistent with existing cabinet glyphs.

## Reuse from the current branch

- Existing cabinet glyphs under `presentation/cabinet/glyphs/`.
- `job_card_paper.png` if it survives readability tests.
- `module_cartridge.png` if its aspect works in both 10×1 and 5×2 grids.
- Existing sound cues, with one new system-install sting if needed.

## Do not reuse as architecture

- `cabinet_plate.png` as a monolithic UI background.
- `module_dock_panel.png` with baked socket positions.

They may remain temporarily as transition/fallback art only.

## Palette

- Chassis near-black: `#151616`
- Raised steel: `#242322`
- Edge steel: `#4A4640`
- Phosphor: `#D6A64A`
- Bright amber: `#F2C263`
- Paper bone: `#C7B68E`
- Commit red: `#B52B24`
- Danger bright: `#F04B3E`
- Coolant cyan accent: `#79B8B6`

Keep cyan rare and functional. This is grim industrial amber/red, not a neon pick-and-mix aisle.

## Texture rules

- UI geometry and labels remain code/vector-rendered.
- Grime and wear may be baked into decorative layers, never into text or hit targets.
- No asset should include changing numbers, prices, labels or localized copy.
- Maintain transparent openings for CRT, telemetry, dock bays and system mount zones.
