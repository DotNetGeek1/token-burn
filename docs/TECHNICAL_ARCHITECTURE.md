# Token Burn — Technical Architecture

## 1. Recommended stack

### Engine

Use **Godot 4**.

Reasons:

- Strong 2D and lightweight 3D support
- Responsive container-based UI
- Custom `Resource` types for editable content definitions
- Android and iOS export
- Desktop and web builds for testing
- JSON and CSV integration
- Suitable for deterministic, headless simulation

### Alternatives

- **Defold:** Excellent lightweight mobile option, but a smaller ecosystem.
- **Phaser:** Good for a browser-first prototype, less direct for native mobile.
- **Unity:** Capable, but introduces more overhead than this project needs.

## 2. Architectural principle

Perks, jobs, upgrades, and events must describe behaviour through reusable data primitives. They should not require a bespoke script for every effect.

The simulation should be authoritative. The UI observes state and submits player actions but does not contain economic logic.

The whole UI is one scene, the Burn Cabinet (`res://ui/cabinet/burn_cabinet.tscn`).
Its layout contract is in [section 2a](#2a-burn-cabinet-shell) below; the
earlier per-venue painted-room contract is retired and kept only as history in
[Venue Layout Architecture](VENUE_LAYOUT_ARCHITECTURE.md).

## 2a. Burn Cabinet shell

`ui/cabinet/burn_cabinet.gd` is a coordinator: it builds the instruments,
wires them up and keeps the deck honest. Geometry belongs to `CabinetLayout`,
idle readings to `CabinetReadouts`, round-end paperwork and the title to
`CabinetFlow`, and the batch in flight to `BurnDirector`.

```text
BurnCabinet
├── Backdrop
├── ChassisArt                 cover-crop, decorative only
├── SafeArea
│   ├── MaintenanceWall        hidden until the maintenance camera
│   ├── OperationGrid
│   │   ├── AbortRail          AbortLever
│   │   ├── MainColumn
│   │   │   ├── CrtFrame       9-slice bezel + CabinetScreen (tabs)
│   │   │   ├── CommandDeck    Override, CommitButton, Cooldown, LEDs
│   │   │   └── WorkflowBackplane  WorkflowKeys header + ModuleDock grid
│   │   └── TelemetryRail      MultiplierDrum, HeatMeter, SystemStatus, BurnFeed
│   └── MaintenanceLayer       menu, five system mounts, caption; hidden by default
└── OverlayRoot                debrief, bills, angels, run end, help, title
```

### Layout profiles

`presentation/cabinet_layout_profiles.json` carries three profiles chosen by
the window's aspect and width, tried in order:

| Profile | Selects when | Bays | Telemetry |
|---|---|---|---|
| `wide` | aspect ≥ 1.65 and width ≥ 1100 px | 10 × 1 | vertical rail |
| `compact` | aspect ≥ 1.35 (or a 16:9 window under 1100 px) | 5 × 2 | vertical rail |
| `tablet` | aspect < 1.35 | 5 × 2 | horizontal strip |

Each profile gives the coarse regions — abort rail, CRT, telemetry, command
deck, backplane — as `[x, y, w, h]` fractions of the **safe area**: the
viewport minus the display's own safe-area insets minus a 16 px inset. The
same file holds the 9-slice frame fitting rules, the dock and deck
proportions, the maintenance camera (zoom scale, pivot, duration, menu, caption
and the five `mount_*` rects, with per-profile overrides) and the acceptance
constraints the viewport playtest asserts (minimum touch 48 px, 44 px at
854×480; body font ≥ 12 px; CRT ≥ 65 % of the safe width and ≥ 50 % of its
height).

Art decorates containers. Nothing reads geometry off a painted image, so an
art layer can be regenerated without touching a rect.

### Asset pipeline

Every cabinet layer is generated, style-locked to one shared prompt preamble,
then post-processed by `tools/asset_generator/cabinet_v2_post.py` (crop to
canvas, knock openings out to alpha, slice strips into cells) and
`tools/extract_generated_alpha.gd`. Output lives in `presentation/cabinet/v2/`
and every file is registered in the `cabinet_v2` block of
`presentation/asset_catalog.json` (paths, 9-slice lips, cell indices) and read
through `AssetCatalog`:

- `chassis_backdrop.png`, `maintenance_wall.png` — 1920×1080 backdrops that
  cover-crop.
- `crt_bezel.png`, `telemetry_frame.png`, `deck_plate.png`,
  `backplane_rail.png`, `panel_9slice.png` — 9-slice frames mounted by
  `CabinetFrame`.
- `commit_idle/armed/danger/busy.png` — the commit button's faces.
- `abort_lever_channel.png`, `abort_lever_handle.png`, `bay_shutter.png`.
- `systems/<system>_t1..t4.png` — one square tile per system per tier; tier N
  replaces tier N−1 on a fixed maintenance mount.

Selected, target and active bay states are code-drawn outlines so they read in
grayscale. Install FX are code (`ui/common/ui_fx.gd`) with an `install` sound
cue.

### Commit button and tab contract

`ui/cabinet/cabinet_tab.gd` defines `CabinetTab.primary_action()`, the one
contract between a CRT tab and the physical button:

```text
{ label, enabled, sub, tone: normal|danger, confirm: press|hold, hold_seconds, pressed }
```

`CommitButton` (`ui/cabinet/commit_button.gd`) has five states — `idle`
(shutter, nothing picked), `armed` (one press fires), `danger` (hazard frame,
hold `hold_seconds` while a ring fills; cancels on release, pointer exit or
focus loss), `busy` (`WORKING` during a batch; never skips) and `blocked`
(dark face plus the reason: `NEED $240 MORE`, `MARKET CLOSED`). The shell
listens to `committed`, not `pressed`. Shared blocker strings live on
`CabinetTab` so every tab says the same thing for the same reason.

### Maintenance view

`ui/cabinet/maintenance_layer.gd` is the cabinet's second camera. The
`OperationGrid` scales down about a pivot over the maintenance wall; the layer
shows Resume / Settings / Help / Records / Save & Quit, the five system mounts
with the owned tier's tile, the generation caption and a read-only inspection
readout (`NAME · TIER N · <stats>`). System back walks blocking paper →
maintenance → non-run tab → run tab, and from the run tab opens maintenance;
it never leaves the cabinet. `show_install()` plays the tier swap after a
Market purchase.

### Cabinet systems data

`content/upgrades/cabinet_systems.json` (loaded and validated by
`ContentDatabase`) declares the five systems with `tier_names`, `tier_values`
per stat, per-tier `cost`, the `generation_thresholds`, the
`migration_from_dwelling` table and `chapter_max_tier`.
`systems/cabinet_systems.gd` is the only place a tier becomes a number:

- `BoardSystem` reads `backplane.bays` and `control.workflows`.
- `UpgradeSystem.hardware_slots_total` reads `power.hardware_slots`;
  `location_cooling` reads `cooling.cooling_capacity`; `heat_capacity` is
  written from `cooling.heat_capacity`.
- `ComputeSystem` adds `compute.base_token_rate` to the hardware curves.
- `UpgradeSystem.upgrade_cabinet_system()` charges cash, raises the tier and
  returns the before/after delta for the reveal.

`content/balance/dwelling_costs.json` is the chapter table. `RunLifecycle.apply_run_location`
reads `rent`, `starting_cash`, `starting_hardware` and the chapter key itself
(`build.dwelling`) from it. Its `hardware_slots`, `cooling_capacity` and
`heat_capacity` columns survive as a per-chapter **floor** under the tier table
(`CabinetSystems.chapter_floor`): the tier is the primary source of every
capacity, but the three late chapters (Datacentre, Grid, Moon) out-size tier 4
(40/80/160 slots against 16; 5,280/36,000/216,000 cooling against 1,248), and
the floor is what keeps their numbers. Capacities never decrease on migration.

## 3. Core state model

```text
RunState
├── calendar
│   ├── month
│   ├── day
│   └── deadline_progress
├── economy
│   ├── cash
│   ├── debt
│   ├── recurring_costs
│   └── income
├── compute
│   ├── local_capacity
│   ├── token_rate
│   ├── power_draw
│   ├── cooling
│   └── heat
├── business
│   ├── reputation
│   └── active_jobs
├── build
│   ├── perks
│   ├── hardware
│   ├── upgrades
│   ├── cabinet_systems   {compute, cooling, power, backplane, control} tiers 1–4
│   ├── dwelling          the campaign chapter the run is staked in
│   └── status_effects
└── statistics
    ├── lifetime_tokens
    ├── failed_jobs
    └── absurdity_metrics
```

### Save versions

`RunState.SAVE_VERSION` is 23. `_migrate_to_v23` derives
`build.cabinet_systems` from the save's `build.dwelling` through the
`migration_from_dwelling` table, clamps every tier to the tier range, and
never loses capacity: a tier is raised until it covers the bays, workflows and
floor the save was demonstrably using. The dwelling key is kept in
`build.migration_debug` for one version. Fixtures for all seven chapters live
in `tests/fixtures/saves/dwelling_<key>.json` and are replayed by
`test_save_migration_fixtures.gd`.

## 4. Effect system

A compact effect vocabulary should cover most content:

```text
ADD
MULTIPLY
SET
CAP_MIN
CAP_MAX
CONVERT
COPY
SPAWN
REMOVE
REROLL
REPEAT
DISCOUNT
DEFER_COST
BORROW
TRIGGER
```

Targets use stable paths:

```text
compute.token_rate
compute.heat_generation
job.reward
job.quality
job.tokens_remaining
economy.cash
business.reputation
```

Example effect:

```json
{
  "operation": "multiply",
  "target": "compute.token_rate",
  "value": 1.25
}
```

## 5. Data-driven perk example

```json
{
  "id": "perk.ship_it",
  "name": "Ship It",
  "rarity": "rare",
  "tags": ["deadline", "reward", "risk"],
  "description_template": "Jobs completed with under {threshold}% time remaining pay {multiplier}×.",
  "parameters": {
    "threshold": 0.05,
    "multiplier": 2.0
  },
  "subscriptions": [
    {
      "event": "job.reward_calculated",
      "priority": 50,
      "conditions": [
        {
          "left": "job.time_remaining_ratio",
          "operator": "<",
          "right": "$threshold"
        }
      ],
      "effects": [
        {
          "operation": "multiply",
          "target": "job.reward",
          "value": "$multiplier"
        }
      ]
    }
  ]
}
```

Descriptions should be generated from the same parameters used by the simulation. This prevents tooltip and implementation values from drifting apart.

## 6. Event pipeline

Suggested events:

```text
run.started
month.started
job.offered
job.accepted
job.started
tokens.generated
tokens.consumed
quality.calculated
bug.generated
job.completed
job.failed
reward.calculated
bill.due
upgrade.purchased
perk.acquired
heat.threshold_crossed
run.ended
```

Suggested resolution order:

```text
BASE
→ ADDITIVE
→ MULTIPLICATIVE
→ CONVERSION
→ CAPS
→ TRIGGERS
→ FINALISE
```

Ordering must be deterministic and visible in debug traces.

## 7. Safe broken builds

The system should distinguish:

1. **Intended synergy:** Designed and supported.
2. **Emergent exploit:** Unexpected but valid and fun.
3. **Invalid state:** Infinite recursion, crashes, invalid numbers, or unrecoverable state corruption.

Only the third category must be blocked.

### Trigger-chain safeguards

Every effect chain should track:

```text
chain_id
depth
effects_executed
visited_effects
event_counts
```

Initial safety limits:

```text
Maximum trigger depth:           32
Maximum effects per action:      10,000
Maximum same-event recursion:    8
Maximum spawned entities:        Configurable
Maximum numerical magnitude:     Configurable warning threshold
```

When a guard is reached, terminate the chain gracefully and emit a readable in-game event.

## 8. Compatibility and stacking

Perks should expose tags and stacking rules:

```json
{
  "requires_tags": [],
  "excludes_tags": ["no_cooling"],
  "incompatible_ids": [],
  "stacking": {
    "mode": "multiplicative",
    "limit": 5,
    "diminishing_returns": 0.85
  }
}
```

Hard incompatibilities should be rare. Prefer soft counters, trade-offs, and diminishing returns.

## 9. Balance-data layers

### Layer 1: Godot Resources

Use custom resources for:

- `JobDefinition`
- `PerkDefinition`
- `EffectDefinition`
- `UpgradeDefinition`
- `EventDefinition`
- `HardwareDefinition`
- `BalanceProfile`

### Layer 2: External tables

```text
balance/
├── economy.json
├── job_scaling.json
├── rarity_weights.json
├── dwelling_costs.json        # per chapter: rent, starting_cash, starting_hardware
├── hardware_curves.json
└── difficulty_profiles.json
```

Cabinet system tiers, costs and capacities are content, not balance:
`content/upgrades/cabinet_systems.json`.

Example:

```json
{
  "job_reward_curve": {
    "base": 400,
    "exponent": 1.42
  },
  "token_requirement_curve": {
    "base": 12000000,
    "exponent": 1.85
  },
  "rent_growth": {
    "base": 600,
    "per_tier_multiplier": 2.25
  }
}
```

### Layer 3: Burn Lab

Development builds should contain a hidden tuning screen with:

- Simulation speed controls
- Economy multipliers
- Token requirement multipliers
- Raw token/progress/OUTPUT and workflow-mastery breakdowns
- Perk rarity controls
- Event-probability controls
- Hot reload
- Content spawning
- Run-state manipulation
- Batch simulation
- CSV export
- Full effect trace

## 10. Automated testing

The simulation should run without rendering.

Test suites should cover:

- Random legal builds
- Maximum-throughput builds
- Maximum-discount builds
- Recursive-trigger builds
- Zero-income builds
- Every two-perk pairing
- High-risk three-perk combinations
- Long-duration runs
- Missing or corrupted definitions

Record:

- Win rate
- Average run length
- Peak token rate
- Peak cash and debt
- Perk selection rates
- Job rejection rates
- Dominant builds
- Guard-limit frequency
- Invalid-number frequency

The combo scanner should flag suspicious results without automatically nerfing them.

## 11. Project structure

```text
token-burn/
├── core/
│   ├── run_state.gd
│   ├── simulation.gd
│   ├── event_bus.gd
│   ├── effect_resolver.gd
│   ├── expression_evaluator.gd
│   ├── transaction.gd
│   └── deterministic_rng.gd
├── definitions/
│   ├── job_definition.gd
│   ├── perk_definition.gd
│   ├── effect_definition.gd
│   ├── upgrade_definition.gd
│   └── event_definition.gd
├── systems/
│   ├── job_system.gd
│   ├── economy_system.gd
│   ├── compute_system.gd
│   ├── heat_system.gd
│   ├── board_system.gd
│   ├── cabinet_systems.gd           # five tiered systems -> capacities, generation
│   ├── workflow_mastery_system.gd   # one-shot contract completion training
│   ├── perk_system.gd               # loadout, tag density, synergies
│   └── progression_system.gd
├── content/
│   ├── jobs/
│   ├── perks/
│   ├── upgrades/                    # incl. cabinet_systems.json
│   ├── events/
│   └── balance/
├── ui/
│   ├── cabinet/                     # burn_cabinet.tscn shell, tabs, commit button, maintenance
│   ├── common/
│   ├── screens/                     # overlays: debrief, bills, angels, run end
│   └── debug/
├── presentation/
│   ├── cabinet/v2/                  # generated cabinet layers, registered in asset_catalog.json
│   ├── cabinet_layout_profiles.json
│   ├── effects/
│   └── audio/
└── tests/
    ├── effect_tests/
    ├── combo_tests/
    ├── simulation_tests/
    └── content_validation/
```

## 12. Dependency policy

Use the engine for UI, resources, serialisation, rendering, animation, audio, and input.

Add external packages only for clear gaps:

- Deterministic random number generation
- Large-number or scientific-notation handling
- CSV import and export
- Automated testing
- Crash reporting near external release
- Spreadsheet-to-JSON conversion

Avoid a large generic RPG ability framework. A small custom effect resolver will be easier to reason about and test.

## 13. Initial infrastructure exclusions

Do not build these for the first playable version:

- Backend services
- Accounts
- Server-authoritative economy
- Online multiplayer
- Real AI API calls
- Remote content delivery

The game should simulate token use rather than spend actual API money.
