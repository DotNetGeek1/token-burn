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
│   ├── cloud_capacity
│   ├── token_rate
│   ├── power_draw
│   ├── cooling
│   └── heat
├── business
│   ├── reputation
│   ├── demand
│   ├── advertising
│   └── active_jobs
├── build
│   ├── perks
│   ├── hardware
│   ├── upgrades
│   └── status_effects
└── statistics
    ├── lifetime_tokens
    ├── failed_jobs
    └── absurdity_metrics
```

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
economy.cloud_cost
business.reputation
business.job_offer_count
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
  "excludes_tags": ["no_cloud"],
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
- `DwellingDefinition`
- `HardwareDefinition`
- `BalanceProfile`

### Layer 2: External tables

```text
balance/
├── economy.json
├── job_scaling.json
├── rarity_weights.json
├── dwelling_costs.json
├── hardware_curves.json
└── difficulty_profiles.json
```

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
- Cloud-cost controls
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
│   ├── demand_system.gd
│   └── progression_system.gd
├── content/
│   ├── jobs/
│   ├── perks/
│   ├── upgrades/
│   ├── events/
│   └── balance/
├── ui/
│   ├── operations/
│   ├── jobs/
│   ├── build/
│   ├── market/
│   └── debug/
├── presentation/
│   ├── office/
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
