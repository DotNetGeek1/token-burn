# Token Burn — Burn Cabinet v2 handoff

This pack is the implementation brief and starter art kit for converting the current Burn Cabinet into a responsive, gameplay-first machine whose visible growth comes from five real cabinet systems.

## Source baseline

- Repository: `DotNetGeek1/token-burn`
- Branch: `experimental/ui-redesign`
- Reviewed commit: `e3d36af45933524013ad0abf69db1966d4cd783c`
- Engine: Godot 4.7 project
- Current entry scene: `res://ui/cabinet/burn_cabinet.tscn`

Do not implement this pack against `main`; it is still the older multi-venue game.

## Start here

1. Check out `experimental/ui-redesign` and create a new feature branch.
2. Read `spec/01_PRODUCT_DIRECTION.md` through `spec/08_ACCEPTANCE_TESTS.md` in order.
3. Give Cursor the contents of `CURSOR_PROMPT.md`.
4. Use `data/cabinet_regions_v2.json` as the initial responsive geometry contract.
5. Use the SVG files under `assets/` as editable starter assets, not as a reason to bake the interface into one image again.
6. Implement the work in the phases in `spec/07_IMPLEMENTATION_PLAN.md`; keep the game runnable after each phase.

## Pack contents

- `spec/`: product decision, removals/additions, layout, interaction, progression, asset list, implementation plan and tests.
- `references/`: two visual direction images. They are reference art, not exact UI geometry and not a source of truth for text.
- `assets/`: scalable, layerable Godot-ready SVG starter assets.
- `previews/`: validated PNG renders of every SVG plus one contact sheet.
- `data/`: proposed responsive regions, system definitions and atlas metadata.
- `CURSOR_PROMPT.md`: a copy/paste implementation prompt.

## Non-negotiable rules

- The cabinet is the world. Properties and venue navigation are removed from the player-facing design.
- Modules and perks remain the strategic build. Cabinet systems provide infrastructure and visible progression.
- The CRT and module dock dominate the screen. Decorative metal may crop; gameplay may not.
- The red physical control is contextual COMMIT: select on the CRT, inspect the consequence, then commit.
- Every visible cabinet assembly maps to a real stat or capability.
- Never return to a single full-screen painted plate with hard-coded fractional hotspots.

## Reference-art caveat

The generated evolution image contains illustrative microcopy and may contain imperfect labels. Follow the written specifications and machine-readable data, not lettering inside reference art.

## Pack integrity note

The pack arrived with every file carrying another file's name (a bad multi-download). The files were renamed by content so the layout above (`spec/`, `data/`, `assets/`, `previews/`) is now accurate. The following files listed in `pack_manifest.json` and `spec/06_ART_ASSET_MANIFEST.md` were not in the download and are missing:

- `ART_PROMPTS.md`
- `assets/cabinet_chassis_16x9.svg`
- `assets/module_bay_states.svg`
- `references/cabinet_gameplay_reference.png`
- `references/cabinet_evolution_reference.png`

The rasterised previews of the two missing SVGs (`previews/cabinet_chassis_16x9.png`, `previews/module_bay_states.png`) did survive.

For this project the SVG assets under `assets/` are reference-only. Final cabinet art is generated to match the style of `presentation/cabinet/cabinet_plate.png`; the geometry contract in `data/cabinet_regions_v2.json` and the system definitions in `data/cabinet_systems.json` remain the machine-readable inputs.
