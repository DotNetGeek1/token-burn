# Venue Layout Architecture

Venue screens are photographed rooms with live Godot `Control` trees mounted on
displays authored in `presentation/asset_catalog.json`. Every venue extends
`VenueScene`; venue scripts provide content and actions, not independent screen
positioning systems.

## Supported viewports

- Mobile gameplay is landscape only. The UI playtest handset target is `854x480`.
- Desktop and web gameplay are supported from `1920x1080` upward.
- Portrait may use the console fallback as a courtesy, but it is not a release
  target and must not determine new venue composition.

## Layout modes

`VenueScene` chooses one mode for the current viewport:

- **Painted:** controls are registered to display regions in the room artwork.
- **Room:** a landscape handset keeps the room composition and lets the player
  lean into a panel to read and operate it.
- **Console:** panels are reparented into one or two scrolling columns when art
  or authored regions are unavailable, or the viewport cannot carry the room.

The same `VenuePanel` nodes are moved between painted mounts and console
containers. Do not build a second copy of a venue for a different mode.

## Authored geometry

Each venue entry may define:

- `regions`: normalized rectangles `[x, y, width, height]`.
- `planes`: normalized corners in this order: top-left, top-right,
  bottom-right, bottom-left.

Coordinates are fractions of the full artwork and must be finite. Rectangles
must have positive width and height. Planes must have four non-degenerate,
consistently ordered points.

The rectangle is always required. It supplies focus geometry and the safe
fallback when a plane cannot be mounted.

## Mount backends

`VenueScene` owns backend selection; venue content must not inspect the renderer.

- Native measured planes use `VenueSurface`, which renders the panel through a
  `SubViewport` and projectively maps it to the four photographed corners.
- Flat measured planes use the affine `Node2D` mount.
- Rectangular displays use a scaled `Node2D` mount. The panel keeps a readable
  local canvas while the host transform preserves the exact authored
  screen-space rectangle. Content minimum sizes must never move the display.
- A rejected projective or affine mount falls back to the safe axis-aligned
  region instead of hiding the panel.

The Build index currently has an explicit rectangular flat policy because its
art was composed for a straight-on CRT face. Keep exceptional placement policy
explicit and tested; do not copy placement math into other venue scripts.

## Layout lifecycle

A layout pass is guarded against re-entry and runs in this order:

1. Read the current viewport and choose painted, room, or console mode.
2. Compute readability scale and apply `VenuePanel` chrome metrics.
3. Mount and place panels.
4. Apply venue-specific width-dependent metrics in `_on_venue_layout()`.
5. Refit painted mounts once and snapshot panel minimum sizes.

`minimum_size_changed` schedules a deferred pass only when the completed panel
minimum-size snapshot actually changed. This prevents callback storms while
still responding to opened detail sheets and refreshed board content.

Cached routed venues implement `route_activated()` through `VenueScene`, so they
recompute mode and geometry after hidden viewport changes.

## Adding a venue

1. Add art, normalized regions, and optional planes to the asset catalog.
2. Extend `VenueScene` and implement `venue_key()`, `_build_venue()`, and
   `refresh()`.
3. Register content with `add_panel()`. Use `console_order` and `grow` for the
   fallback column. Treat `console_min` as an exceptional minimum, not painted
   geometry.
4. Put width-dependent board, row, and font metrics in `_on_venue_layout()`.
5. Do not assign screen-space panel positions in the venue subclass.
6. Add the route to `pt_venue_layout_matrix.gd` and add a focused playtest for
   any exceptional internal composition.

## Required checks

Run:

```powershell
godot --headless res://tests/run_tests.tscn
./tools/run_playtests.ps1 -- --filter=pt_venue_layout_matrix
./tools/run_playtests.ps1 -- --filter=pt_workflow_resize
./tools/run_playtests.ps1 -- --filter=pt_mobile_scrolling
```

The matrix verifies every visible panel has finite positive screen-space bounds
and remains registered after a repeated layout at Full HD and landscape handset
sizes. Web exports still require a route smoke test because their affine backend
differs from native projective rendering.
