# 08 — Acceptance tests

## Visual and responsive

- [ ] CRT occupies at least 65% of usable width and 50% of usable height at every required target.
- [ ] 1600×900 and 1280×720 show ten workflow bays in one row.
- [ ] 1024×768, 960×540 and 854×480 show a readable 5×2 bay layout.
- [ ] No interactive content is clipped by decorative art or display safe areas.
- [ ] No action label/body text falls below the minimum sizes in the layout spec.
- [ ] Decorative sides crop before the CRT, commit control, lever, telemetry or dock shrink below minimum.

## Navigation

- [ ] Run, Contracts, Modules, Market and Perks are reachable as CRT tabs.
- [ ] Back from a non-Run tab follows the agreed tab/back policy without opening a legacy venue.
- [ ] Back/menu from operation view opens Maintenance.
- [ ] Back/Resume from Maintenance returns to the same tab, selection and scroll position.
- [ ] No core run action requires Maintenance.

## Commit control

- [ ] No selection produces a shuttered disabled state and a useful instruction.
- [ ] Contract selection arms ACCEPT with reward/deadline consequence.
- [ ] Module selection arms BUY with price and remaining cash or blocker.
- [ ] System selection arms UPGRADE with tier/cost/effect.
- [ ] Module seating arms SEAT with the exact bay.
- [ ] SELL requires a 650 ms hold and cancels cleanly on pointer/focus release.
- [ ] Commit is disabled and says WORKING during burn playback.
- [ ] Commit never skips playback.
- [ ] Disabled actions state the blocker in plain language.

## Dock and input

- [ ] Tap-to-arm/tap-to-seat works without drag or hover.
- [ ] Keyboard/controller focus follows bay order across 10×1 and 5×2 profiles.
- [ ] Locked bays cannot focus, accept drops or emit pressed actions.
- [ ] Selected/target/active/locked states remain distinguishable in grayscale.
- [ ] All required actions work with mouse, touch and keyboard/controller.

## Burn and flow regression

- [ ] Accepting a contract does not alter unrelated run state.
- [ ] Burn preview heat/cost/output matches execution.
- [ ] Cooldown and override retain current mechanics.
- [ ] Round debrief, bills, angel choice and run-end overlays still complete in order.
- [ ] Abort/abandon retains current policy restrictions.

## Saves and systems

- [ ] Save fixtures for all seven old dwelling keys load successfully.
- [ ] Migration preserves cash, round, contracts, modules, perks, workflows, achievements and RNG state.
- [ ] Migrated workflow and hardware capacities never decrease.
- [ ] System tiers are always integers in 1–4.
- [ ] Visual generation is derived and never changes simulation numbers.
- [ ] Upgrade save persists before installation reveal starts.

## Cleanup

- [ ] No runtime layout reads socket positions from the retired plate catalog.
- [ ] No permanent Next Action node remains.
- [ ] Idle Burn Feed consumes no layout space.
- [ ] No player-facing property purchase or venue navigation remains.
- [ ] Old plate/venue assets are deleted only after reference and migration searches are clean.

