# Venue Layout Architecture (retired)

> **Superseded by the Burn Cabinet v2 (see `docs/cabinet-v2`).** The per-venue
> painted-room architecture described below — `VenueScene`, `VenuePanel`,
> `VenueSurface`, painted / room / console modes, authored `regions` and
> `planes` per venue, and the desk in `ui/main.gd` — has been removed from the
> tree. This page is kept as a short historical note; nothing in it describes
> current behaviour.

## What replaced it

The whole game now runs on one scene, `res://ui/cabinet/burn_cabinet.tscn`.
Contracts, modules, the market and the perk rack are tabs on the cabinet's
central CRT rather than separate rooms, and the menu, settings and records live
in the cabinet's Maintenance camera rather than a `venue_menu` scene.

The layout contract that replaced this one is documented in
[Technical Architecture — Burn Cabinet shell](TECHNICAL_ARCHITECTURE.md#2a-burn-cabinet-shell).
In short:

- **Geometry comes from data, not paint.** `ui/cabinet/cabinet_layout.gd`
  loads `presentation/cabinet_layout_profiles.json`, picks a profile from the
  window's aspect and width (`wide` ≥ 1.65 with 10×1 bays, `compact` ≥ 1.35
  with 5×2, `tablet` < 1.35 with 5×2 and a telemetry strip), and hands out the
  coarse regions — abort rail, CRT, telemetry, command deck, backplane — as
  fractions of the safe area. Nothing measures a rect off a picture.
- **Art decorates containers.** `ui/cabinet/cabinet_frame.gd` fits the
  generated 9-slice frames (`crt_bezel`, `telemetry_frame`, `deck_plate`,
  `backplane_rail`, `panel_9slice` in the `cabinet_v2` block of
  `presentation/asset_catalog.json`) around a region, scaling each frame so
  its opaque lip is a fixed fraction of the region height and keeping content
  clear of it. The chassis and maintenance wall are cover-cropped backdrops.
- **One tree, three shapes.** The same `OperationGrid` is laid out under every
  profile; the module dock re-grids from `dock_columns × dock_rows`. There is
  no second copy of a screen for a different mode and no console fallback.
- **Safe area and touch floors** are constraints in the same profile file
  (16 px inset, 48 px minimum touch, 44 px at 854×480, 12 px body floor) and
  are asserted by `tests/playtests/pt_cabinet_viewports.gd` at 1600×900,
  1280×720, 1024×768, 960×540 and 854×480.

## Required checks (current)

```powershell
godot --headless res://tests/run_tests.tscn
./tools/run_playtests.ps1 -- --filter=pt_cabinet_viewports
./tools/run_playtests.ps1 -- --filter=pt_cabinet_dock_profiles
./tools/run_playtests.ps1 -- --filter=pt_cabinet_commit_matrix
./tools/run_playtests.ps1 -- --filter=pt_maintenance_view
```

## Historical note

Between the desk prototype and the cabinet, each screen was a photographed
room with live `Control` trees mounted on displays authored as normalised
rectangles and, on native builds, projective four-corner planes rendered
through a `SubViewport`. A landscape handset kept the room and let the player
lean into one panel; anything smaller fell back to one or two scrolling
console columns. The approach was retired because geometry lived in the
paintings: every art change moved rects, every new viewport needed a new
composition, and the venues duplicated the shell around what were really tabs
on one screen. The 9-slice, profile-driven cabinet keeps the "controls mounted
on a machine" feel without any of that coupling.
