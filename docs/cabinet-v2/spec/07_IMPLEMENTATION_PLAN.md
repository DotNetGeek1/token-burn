# 07 — Implementation plan

Work from `experimental/ui-redesign` in small, runnable commits.

## Phase 0 — Guardrails

1. Add screenshot fixtures for the five required viewports.
2. Add tests for current tab switching, primary actions, dock seating and round flow.
3. Record old-save fixtures for every dwelling tier.
4. Keep the existing plate behind a temporary feature flag for comparison only.

Exit: tests can detect broken routing, invisible actions and reduced capacity.

## Phase 1 — Split cabinet responsibilities

1. Extract responsive layout/profile logic from `burn_cabinet.gd` into a focused component/resource.
2. Extract commit-action presentation/dispatch from burn flow.
3. Keep simulation calls and tab classes unchanged.
4. Rename BurnButton to CommitButton and remove burn-skip dispatch from it.

Exit: behavior matches the old branch with no visual redesign required yet.

## Phase 2 — Layered responsive shell

1. Replace global `PLATE_ASPECT` fitting with the hierarchy in the layout spec.
2. Introduce `wide`, `compact` and `tablet` profiles from `cabinet_regions_v2.json` or equivalent Resources.
3. Mount layered chassis/CRT/telemetry/deck/backplane assets.
4. Delete the permanent Next Action well.
5. Collapse Burn Feed when idle.
6. Move workflow selectors to the backplane header.
7. Compute bay positions dynamically: 10×1 wide, 5×2 compact/tablet.

Exit: all target viewports are readable and functional; old plate can be toggled only for comparison.

## Phase 3 — Commit interaction

1. Extend `primary_action()` with `tone`, `confirm`, and `hold_seconds`.
2. Implement idle/armed/danger/busy/blocked Commit states.
3. Require hold for SELL and destructive lever actions.
4. Put skip inside the CRT during burn playback.
5. Preserve selection and scroll after successful actions where appropriate.

Exit: action matrix and accessibility tests pass.

## Phase 4 — Maintenance view

1. Replace the no-op `focus_room`, `focus_control`, `clear_room_focus` compatibility methods with a simple operation/maintenance camera state.
2. Route system back/menu to Maintenance when no blocking overlay is open.
3. Add Resume, Settings, Help, Records/Achievements and Save & Quit.
4. Make cabinet assemblies inspectable but read-only.

Exit: no core-loop action requires leaving operation view.

## Phase 5 — Cabinet system compatibility layer

1. Add `cabinet_systems` state with five tier values.
2. Add old-save migration using the mapping in `05_CABINET_SYSTEMS.md`.
3. Group existing hardware behind Systems presentation without changing simulation balance yet.
4. Resolve and display the visual generation.
5. Add installation reveal.

Exit: existing saves preserve or exceed previous capacities and outcomes.

## Phase 6 — Content consolidation and cleanup

1. Move tuning to `content/upgrades/cabinet_systems.json` or the project's chosen content path.
2. Replace property upgrade rows and property copy.
3. Consolidate old hardware rows only with explicit balance coverage.
4. Remove dead venue/property routes and retired assets.
5. Remove the temporary old-plate feature flag.

Exit: repository search finds no player-facing Bedroom/Garage/etc. progression copy; save migration still accepts the prior schema.

## Likely source touchpoints

- `ui/cabinet/burn_cabinet.gd`
- `ui/cabinet/burn_cabinet.tscn`
- `ui/cabinet/burn_button.gd` → `commit_button.gd`
- `ui/cabinet/cabinet_tab.gd`
- `ui/cabinet/cabinet_screen.gd`
- `ui/cabinet/module_dock.gd`
- `ui/cabinet/workflow_keys.gd`
- `ui/cabinet/burn_feed.gd`
- `ui/cabinet/tab_market.gd`
- `core/run_state.gd`
- `core/save_manager.gd`
- `systems/upgrade_system.gd`
- `content/upgrades/upgrades.json`
- `content/balance/dwelling_costs.json`
- `presentation/asset_catalog.json`
- `tests/ui/`

## Scope controls

- Do not rebalance modules/perks while changing the shell.
- Do not rewrite simulation math in the layout phases.
- Do not delete legacy save fields before migration fixtures pass.
- Do not manually invent `.uid` files; let Godot preserve or regenerate them correctly.
- Do not commit generated `.godot/` cache content.

