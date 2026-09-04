# Cursor implementation prompt

You are modifying the Godot project `DotNetGeek1/token-burn`.

Work only from branch `experimental/ui-redesign` (reviewed baseline `e3d36af45933524013ad0abf69db1966d4cd783c`). Create a new feature branch before editing.

Read every file in this handoff pack, especially:

- `spec/01_PRODUCT_DIRECTION.md`
- `spec/02_CHANGE_MAP.md`
- `spec/03_LAYOUT_AND_RESPONSIVE_SPEC.md`
- `spec/04_INTERACTION_SPEC.md`
- `spec/05_CABINET_SYSTEMS.md`
- `spec/07_IMPLEMENTATION_PLAN.md`
- `spec/08_ACCEPTANCE_TESTS.md`
- `data/cabinet_regions_v2.json`
- `data/cabinet_systems.json`

Then inspect the current implementation before proposing changes:

- `ui/cabinet/burn_cabinet.gd`
- `ui/cabinet/cabinet_tab.gd`
- `ui/cabinet/burn_button.gd`
- `ui/cabinet/module_dock.gd`
- all five `ui/cabinet/tab_*.gd` files
- `presentation/asset_catalog.json`
- `systems/upgrade_system.gd`
- `core/run_state.gd` and save migration code
- relevant UI/regression tests

Implement the phases in `spec/07_IMPLEMENTATION_PLAN.md` sequentially. At the start, provide a short file-by-file plan. After each phase, run the smallest relevant tests and keep the project runnable.

Critical requirements:

1. The cabinet is the world; remove player-facing property/venue progression.
2. Preserve modules and perks as the strategic build.
3. Make the CRT and dock dominate the screen at all supported landscape sizes.
4. Replace the monolithic plate/hotspot architecture with layered responsive components.
5. Rename BurnButton to CommitButton and keep `CabinetTab.primary_action()` as the action abstraction.
6. Commit is contextual: BURN, ACCEPT, BUY/SELL, UPGRADE, SEAT/EJECT, FIT/BENCH.
7. Commit is locked while a burn animates; it never skips. Put optional skip inside the CRT.
8. Remove permanent Next Action; collapse Burn Feed when idle.
9. Dock is dynamic: 10×1 wide and 5×2 compact/tablet.
10. Add five tiered cabinet systems and migrate old dwelling saves without reducing capacity.
11. Use included SVGs as starter layers; do not bake dynamic labels or numbers into art.
12. Do not combine the shell rewrite with a blind economy rebalance.

Do not delete legacy assets/data until all callers are removed and migration fixtures pass. Do not manually fabricate Godot `.uid` files.

Required verification:

- Run project/test suite using repository conventions.
- Add/execute viewport checks at 1600×900, 1280×720, 1024×768, 960×540 and 854×480.
- Exercise every contextual Commit action and blocker.
- Load one fixture for each legacy dwelling.
- Report changed files, tests run, failures and any deliberate deviations from the pack.

If a specification conflicts with current gameplay behavior, preserve the gameplay behavior and flag the conflict unless the spec explicitly says it is being removed or replaced.

