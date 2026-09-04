# 00 — Current branch audit

Reviewed from GitHub branch `experimental/ui-redesign` at commit `e3d36af45933524013ad0abf69db1966d4cd783c`.

## What is already good

- `project.godot` boots directly to `res://ui/cabinet/burn_cabinet.tscn`.
- The cabinet already consolidates Run, Contracts, Modules, Market and Perks as CRT tabs.
- `CabinetTab.primary_action()` is a useful abstraction for contextual commit behavior.
- Module interaction already supports tap selection and drag/drop.
- The core simulation and round-flow overlays are still wired through the cabinet shell.

## What creates the current squeeze

- `burn_cabinet.gd` fits one 16:9 plate inside the viewport and positions every instrument as a fraction of that plate.
- The current catalog gives the CRT region `[0.158, 0.102, 0.494, 0.385]`, only about 19% of the plate's area.
- The catalog reserves permanent regions for `next_action`, `feed`, `status`, switches and decorative edges.
- The dock reads ten fixed socket rectangles from `presentation/asset_catalog.json`; it is not a responsive grid.
- `cabinet_plate.png` is both decoration and layout authority, so changing hierarchy means repainting and remeasuring the whole machine.

## Interaction findings

- The button already commits contextual tab actions through `primary_action()`.
- `_on_primary()` currently invokes skip when `_burning` is true. v2 removes that overload.
- The button face remains visually red even when disabled because much of its presence is baked into the plate; a separate idle shutter is needed.
- `NEXT ACTION` duplicates information already expressed by selection, blockers and the contextual action.

## Progression mismatch

- Property/dwelling upgrade rows remain in `content/upgrades/upgrades.json`.
- Dwelling mechanics remain in `content/balance/dwelling_costs.json`, including rent, hardware slots, cooling/heat capacity and starting hardware.
- The cabinet compatibility methods `focus_room()`, `focus_control()` and `clear_room_focus()` are currently no-ops.
- `board_dwelling()` still reads `run_state.build["dwelling"]`.

This confirms the redesign is partly complete at the navigation layer but not yet at the layout or progression-model layer.

