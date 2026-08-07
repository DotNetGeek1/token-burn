# ADR-001: Effect Operation Semantics

## Status

Accepted — 2026-07-28

## Context

The effect resolver exposes a compact vocabulary (`ADD`, `MULTIPLY`, `SET`, `CONVERT`, `SPAWN`, `REMOVE`, `REROLL`, `REPEAT`, `DEFER_COST`, `BORROW`, etc.) used by perks, events, and upgrades. Several operations were stubbed or aliased to simpler behaviour, blocking content agents and making traces misleading.

## Decision

### Resolution phases

Effects resolve in this order:

```text
BASE → ADDITIVE → MULTIPLICATIVE → CONVERSION → CAPS → TRIGGERS → FINALISE
```

Entity mutations (`spawn`, `remove`, `reroll`, `repeat`) run in **FINALISE**, after numeric resolution and triggers.

### Operation semantics

| Operation | Phase | Behaviour |
|---|---|---|
| `add` | ADDITIVE | `target += value` |
| `discount` | ADDITIVE | `target *= (1 - value)` |
| `defer_cost` | ADDITIVE | Append `{amount, target, rounds_until_due}` to `economy.pending_bills`; **does not** change `target` now |
| `borrow` | ADDITIVE | `target += value` **and** `economy.debt += value` |
| `multiply` | MULTIPLICATIVE | `target *= value` (see token-rate exception below) |
| `convert` | CONVERSION | Transfer `from * ratio` to `target`; optional `consume` (default `true`) subtracts from `from` |
| `copy` | CONVERSION | `target = value(path)` |
| `set` | CAPS | `target = value` |
| `cap_min` / `cap_max` | CAPS | clamp target |
| `trigger` | TRIGGERS | dispatch nested event (depth guarded) |
| `spawn` | FINALISE | Append to array at `target`; `value` = item **or** count + `template` |
| `remove` | FINALISE | Remove by count (int) or matcher (`id` string / dict subset) |
| `reroll` | FINALISE | Deterministic reroll via `ModifierContext.rng`; numeric range, `pick`, or shuffle array |
| `repeat` | FINALISE | Run nested `effects` `value` times |

### `convert` schema

```json
{
  "operation": "convert",
  "from": "economy.cash",
  "target": "business.reputation",
  "value": 0.01,
  "consume": true
}
```

`value` and `ratio` are synonyms for the transfer fraction. `target` may also be supplied as `to`.

### `compute.token_rate` multiply exception

When `multiply` targets `compute.token_rate` during `event.*` or `direct.apply`, the resolver registers a **rate modifier** on run state instead of mutating the in-flight value. `ComputeSystem.recalculate()` applies modifiers when rebuilding base throughput.

During `compute.recalculate` (and other events), multiply behaves as a normal in-place multiplication.

Trace entries include `metadata.rate_modifier = true`.

### Randomness

`reroll` requires `ModifierContext.rng` (a `DeterministicRng`). Substreams are derived as `reroll.<target>`.

### Spawn safety

`ChainGuard` enforces `EffectOps.MAX_SPAWNED_ENTITIES` (256) per action.

### Multi-job writeback

`job.*` values finalize into `mod_ctx.job` **and** the matching entry in `business.active_jobs` by `job.id`.

## Consequences

- Content can express deferred billing, borrowing, entity spawn/remove, and conversions without bespoke scripts.
- Callers must inject RNG into `ModifierContext` for reroll effects.
- Token-rate perks stack through `rate_modifiers`, consistent with round ticks.
