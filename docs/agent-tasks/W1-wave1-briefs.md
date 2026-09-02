# W1 — Wave 1 Agent Assignments

Wave 1 starts **Phase 1 — Parallel Core Work** from the development plan (section 5). W0-A (effect engine) is complete. Agents work against the current flat repository layout; directory migration is deferred.

**Integration rule:** Do not modify another agent's owned paths. Provide interface requests via task notes or ADRs.

## Ownership map (current layout)

| Path | Team handle | Scope |
|---|---|---|
| `/core/` | `@architecture` | State, simulation shell, effect engine, RNG, save, content loading |
| `/systems/` | `@gameplay` | Job, economy, compute, heat, demand, progression, events, perks, upgrades |
| `/content/` | `@content` | JSON definitions and balance data |
| `/ui/` | `@ui` | Screens, components, view wiring (no gameplay rules) |
| `/tests/` | `@qa` | Unit, integration, simulation, content validation |
| `/presentation/` | `@presentation` | Office diorama, animations, audio, VFX (future) |
| `/definitions/` | `@architecture` | Resource definition classes consumed by content loader |
| `/config/` | `@architecture` | Feature flags and environment config |
| `/docs/agent-tasks/` | `@architecture` | Agent briefs and orchestration docs |

See [CODEOWNERS](../../CODEOWNERS) for review routing.

---

## W1-A — Architecture & Contracts

**Handle:** `@architecture`  
**Depends on:** W0-A (effect engine) complete

### Scope

- Lock and document state/event/effect contracts
- Maintain ADRs in `docs/decisions/`
- Provide mocks for services not yet implemented
- Own `core/simulation.gd`, `core/run_state.gd`, `core/event_bus.gd`, `core/content_database.gd`, `core/save_manager.gd`, `definitions/`

### Must not modify

`systems/`, `ui/`, `content/*.json`, `tests/` (except when adding shared test utilities with `@qa` coordination)

### Wave 1 deliverables

- Documented public APIs for `RunState`, `Simulation`, and service interfaces
- ADRs for any schema changes
- Mock or stub implementations where UI/content agents need them

---

## W1-B — Job & Demand Systems

**Handle:** `@gameplay` (jobs)  
**Depends on:** W0-A, W1-A contracts

### Owned files

```text
systems/job_system.gd
systems/demand_system.gd
tests/simulation_tests/test_job_scaling.gd
tests/simulation_tests/test_run_loop.gd (job lifecycle sections only, coordinate with @qa)
```

### May consume

`EffectResolver`, `RunState`, `ContentDatabase`, `DeterministicRng`, job content JSON

### Wave 1 deliverables

- Deterministic job offer generation and acceptance flow
- Job execution lifecycle integrated with compute and reward events
- Demand/reputation influencing offer weights

---

## W1-C — Economy & Progression

**Handle:** `@gameplay` (economy)  
**Depends on:** W0-A, W1-A contracts

### Owned files

```text
systems/economy_system.gd
systems/progression_system.gd
systems/upgrade_system.gd
tests/simulation_tests/test_economy.gd
```

### Wave 1 deliverables

- Cash, bills, rent, debt, and purchase flows
- Upgrade choice application via effect engine
- Loss-condition checks (in-run progression, not meta)

---

## W1-D — Compute & Heat

**Handle:** `@gameplay` (compute)  
**Depends on:** W0-A, W1-A contracts

### Owned files

```text
systems/compute_system.gd
systems/heat_system.gd
```

### Feature flag

Gate unfinished UI/actions with `FeatureFlags.is_enabled(...)` when adding new entry points (existing behaviour stays enabled by default).

### Wave 1 deliverables

- Token throughput from local hardware
- Heat accumulation, throttling, and cooling interactions
- Rate modifiers from effect engine applied in `recalculate()`

---

## W1-E — Mobile UI Framework

**Handle:** `@ui`  
**Depends on:** W1-A mocks, W0-A trace API

### Owned files

```text
ui/common/
ui/operations/
ui/jobs/
ui/build/
ui/screens/
ui/market/
ui/debug/ (coordinate with @qa for burn lab)
```

### Must not modify

`systems/`, `core/`, `content/`

### Wave 1 deliverables

- Operations, job board, build, and upgrade screens wired to view models or simulation facades
- Shared card, stat row, resource bar components
- Effect trace popup using `query_trace_breakdown()`
- Mobile-safe layout on 1080×1920 viewport

---

## W1-F — Content Pack (Starter)

**Handle:** `@content`  
**Depends on:** W0-A effect vocabulary, W1-A content schemas

### Owned files

```text
content/jobs/
content/perks/
content/upgrades/
content/events/
content/balance/
```

### Must not modify

`definitions/`, resolver code, `systems/`

### Wave 1 deliverables

- Ten jobs, ten perks, five hardware upgrades, three dwellings, five random events
- All effects conform to ADR-001 operations
- Balance values in JSON only — no magic numbers in code

---

## W1-G — Testing & Tooling

**Handle:** `@qa`  
**Depends on:** All W1 agents (interfaces stable enough to test)

### Owned files

```text
tests/
tests/framework/
tests/combo_scanner.gd
tests/batch_runner.gd
```

### Wave 1 deliverables

- Headless test runner (`tests/run_tests.tscn`)
- Determinism and save/load regression tests
- Content validation against effect schemas
- Combo scanner smoke tests for perk interactions

---

## W1-H — Events & Perks Integration

**Handle:** `@gameplay` (events)  
**Depends on:** W0-A, W1-F starter content

### Owned files

```text
systems/event_system.gd
systems/perk_system.gd
tests/combo_tests/
```

### Feature flag

Respect `random_events_enabled` when wiring new random-event entry points.

### Wave 1 deliverables

- Monthly random event trigger pipeline
- Perk equip/acquire flows through effect subscriptions
- At least three perks exercised end-to-end in simulation tests

---

## W2-Scaffolding (this wave)

**Handle:** `@architecture`  
**Status:** In progress

### Delivered

- `docs/agent-tasks/` task template and wave briefs
- `CODEOWNERS` for current flat layout
- `config/feature_flags.json` + `core/feature_flags.gd`
- [ADR-003: Feature flags](../decisions/ADR-003-feature-flags.md)

### Explicitly deferred

- Physical directory restructure (section 2 target layout)
- `project.godot` autoload registration for `FeatureFlags` (manual integration documented in ADR-003)

---

## Parallelism constraints

| Can run in parallel | Must wait for |
|---|---|
| W1-B, W1-C, W1-D, W1-F | W0-A complete |
| W1-E | W1-A mocks + stable simulation read API |
| W1-G | Interfaces under test exist (can start framework immediately) |
| W1-H | W1-F starter events/perks + W1-B job lifecycle |

## Definition of done (Wave 1)

Aligned with plan section 15 first sprint:

1. Seeded run start through job complete/fail
2. Token burn, heat, cash, rent, upgrade choice
3. Three perks via generic effect engine
4. Effect trace inspectable in UI
5. Save/resume and headless tests green
