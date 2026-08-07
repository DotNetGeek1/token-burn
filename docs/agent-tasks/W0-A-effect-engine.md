# W0-A — Effect Engine

**Status:** Complete (2026-07-28)

Foundation agent for the data-driven effect resolver. Wave 0 work; other agents may depend on the public API documented here and in the ADRs below.

## Task

Implement deterministic effect resolution with phased ordering, full operation semantics, trace attribution, and recursion safeguards.

## Owned files

```text
core/effect_resolver.gd
core/effect_ops.gd
core/chain_guard.gd
core/modifier_context.gd
core/transaction.gd
core/expression_evaluator.gd
tests/effect_tests/test_effect_resolver.gd
tests/effect_tests/test_effect_operations.gd
tests/effect_tests/test_chain_guard.gd
docs/decisions/ADR-001-effect-operation-semantics.md
docs/decisions/ADR-002-effect-trace-api.md
```

## May read

```text
core/run_state.gd
definitions/effect_definition.gd
content/perks/
content/events/
content/upgrades/
```

## Must not modify

```text
systems/
ui/
content/*.json
project.godot
```

## Inputs

- `EffectDefinition` / effect dictionaries from content subscriptions
- `ModifierContext` (run state, job slice, parameters, optional `DeterministicRng`)
- Event subscriptions with `event`, `conditions`, `effects`, `priority`, `source_id`

## Outputs

- `EffectResolver.dispatch(event_name, mod_ctx, subscriptions, chain_id)` → `Array[Transaction]`
- `EffectResolver.apply_effects(run_state, effects, chain_id)` for direct application
- `get_trace()`, `query_trace_for_target()`, `query_trace_breakdown()` for attribution
- `ChainGuard` enforcing depth, effect count, spawn limits, and circular-effect detection

## Behaviour delivered

### Resolution phases

Effects resolve in order:

```text
BASE → ADDITIVE → MULTIPLICATIVE → CONVERSION → CAPS → TRIGGERS → FINALISE
```

Entity mutations (`spawn`, `remove`, `reroll`, `repeat`) run in **FINALISE**.

### Operations implemented

| Operation | Phase | Summary |
|---|---|---|
| `add` | ADDITIVE | Increment target |
| `discount` | ADDITIVE | Multiplicative discount |
| `defer_cost` | ADDITIVE | Append to `economy.pending_bills` |
| `borrow` | ADDITIVE | Credit target and increase `economy.debt` |
| `multiply` | MULTIPLICATIVE | Scale target (token-rate exception below) |
| `convert` | CONVERSION | Transfer fraction from `from` to `target` |
| `copy` | CONVERSION | Copy value from path |
| `set`, `cap_min`, `cap_max` | CAPS | Assign or clamp |
| `trigger` | TRIGGERS | Nested dispatch with depth guard |
| `spawn`, `remove`, `reroll`, `repeat` | FINALISE | Entity and array mutations |

### Token-rate exception

When `multiply` targets `compute.token_rate` during `event.*` or `direct.apply`, the resolver registers a **rate modifier** on run state instead of mutating the in-flight value. `ComputeSystem.recalculate()` applies modifiers when rebuilding throughput.

### Trace API

- Flat chronological trace via `get_trace()` (capped at 500 entries)
- `query_trace_for_target(target_path, chain_id)` filters by stat path
- `query_trace_breakdown()` returns base/final values and totals grouped by operation

### Safety

- `ChainGuard`: max trigger depth, max effects per action, max same-event recursion, circular effect detection
- Spawn cap: `EffectOps.MAX_SPAWNED_ENTITIES` (256) per action
- `reroll` requires `ModifierContext.rng` (`DeterministicRng` substream `reroll.<target>`)

## Acceptance criteria (met)

- Same seed and subscriptions produce identical resolution order and values
- All operations in ADR-001 have unit test coverage
- Trace queries return structured attribution without string parsing
- Trigger recursion terminates with a logged reason when limits are exceeded
- Multi-job writeback syncs `job.*` paths to matching `business.active_jobs` entries

## Architecture decisions

- [ADR-001: Effect operation semantics](../decisions/ADR-001-effect-operation-semantics.md)
- [ADR-002: Effect trace query API](../decisions/ADR-002-effect-trace-api.md)

## Consumers

Systems that call `EffectResolver` today:

```text
systems/job_system.gd
systems/event_system.gd
systems/perk_system.gd
systems/upgrade_system.gd
systems/compute_system.gd (indirect via subscriptions)
```

UI that reads traces:

```text
ui/debug/burn_lab.gd
```

## Remaining risks

- Content agents may author effect shapes not yet covered by validation tooling
- New operations require an ADR and resolver change — do not extend ad hoc in systems
