# 02 — Add / change / remove map

## Keep and improve

| Current element | Decision |
| --- | --- |
| `ui/cabinet/tab_run.gd` | Keep; enlarge its available CRT surface. |
| `tab_contracts.gd`, `tab_market.gd`, `tab_modules.gd`, `tab_perks.gd` | Keep the tab model and domain actions; restyle/reflow within the larger CRT. |
| `cabinet_tab.gd::primary_action()` | Keep as the contextual action contract; extend its returned data. |
| `abort_lever.gd` | Keep. It owns abandon/kill only. Require hold confirmation when destructive. |
| `module_cartridge.gd`, `module_bay.gd` | Keep behavior; re-skin with the supplied layered assets. |
| `burn_feed.gd` | Keep only as live burn telemetry; collapse it completely outside a burn. |
| Existing round-end overlays | Keep behavior; make them CRT sheets or maintenance overlays later. Do not block v2 layout on this polish. |

## Rename / refactor

| Current | Target | Notes |
| --- | --- | --- |
| `BurnButton` / `burn_button.gd` | `CommitButton` / `commit_button.gd` | Contextual physical commit control. Preserve migration history in git; let Godot generate/retain UID safely. |
| `_burn_button` | `_commit_button` | Mechanical rename across cabinet shell. |
| `_on_primary()` | `_on_commit_pressed()` | Must never mean skip. |
| Monolithic `BurnCabinet` responsibilities | Layout + flow/action coordinator components | `burn_cabinet.gd` is about 49 KB and already mixes construction, layout, flow and burn spectacle. |
| Fixed `PLATE_ASPECT` layout | Responsive profiles | Interactive geometry comes from containers/profile data, not the painted image. |
| Painted socket coordinates | Dynamic backplane grid | Desktop 10×1 where space permits; compact 5×2. |

## Remove from the player-facing game

- Property names, property purchasing and room-to-room venue progression.
- The permanent `NEXT ACTION` well and its duplicated instruction copy.
- Permanent Burn Feed space when no burn is active.
- Duplicate vertical workflow selector bank.
- `MENU` as a normal CRT gameplay tab/door. Back/menu zooms to Maintenance.
- Commit-button skip behavior while a burn is running.
- Decorative frame areas wider than required for legibility and touch.
- The full-screen `cabinet_plate.png` as the geometry authority.

## Add

- Responsive `wide`, `compact` and `tablet` layout profiles.
- Layered chassis, CRT bezel, telemetry rail, command deck and backplane assets.
- Commit states: idle shuttered, armed, dangerous/hold, busy locked and blocked-with-reason.
- Maintenance zoom state and menu controls.
- Five cabinet system definitions, four authored visual tiers each.
- A derived visual-generation resolver.
- System-install reveal animation.
- Save migration from `build.dwelling` and old property upgrades.
- Safe-area handling and minimum touch-target checks.
- Screenshot/regression tests at the required viewports.

## Current files to retire after cutover

Do not delete these at the beginning. Remove them only after references are gone and save migration/tests pass.

- `presentation/cabinet/cabinet_plate.png` and `.import`
- `presentation/cabinet/module_dock_panel.png` and `.import`
- `ui/cabinet/cabinet_well.gd` and `.uid` if no remaining caller uses it
- Property-specific room presentation assets and legacy venue UI that are unreachable after routing cleanup
- Dwelling upgrade rows in `content/upgrades/upgrades.json`
- `content/balance/dwelling_costs.json` after its useful economics are migrated to cabinet-system data

Keep old content behind migration compatibility for at least one save-version boundary. “Deleted from UI” and “safe to delete from disk” are separate milestones.

## Commit action matrix

| Screen | Armed label | Action |
| --- | --- | --- |
| Run | BURN / BURN AGAIN | Commit next burn batch. |
| Contracts | ACCEPT | Accept selected contract. |
| Market: Modules | BUY | Purchase selected module. |
| Market: Systems | UPGRADE | Upgrade selected cabinet system. |
| Market: Installed | SELL | Hold to sell selected hardware where still supported. |
| Modules | SEAT / EJECT | Seat armed cartridge or eject selected bay. |
| Perks | FIT / BENCH | Apply selected perk action. |

