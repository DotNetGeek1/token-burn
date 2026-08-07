# ADR-002: Effect Trace Query API

## Status

Accepted — 2026-07-28

## Context

`EffectResolver.get_trace()` returns a flat chronological list suitable for debug overlays (e.g. Burn Lab). Players and UI need structured attribution for a specific stat path without parsing strings.

## Decision

Keep `get_trace()` unchanged. Add read-only query helpers on `EffectResolver`:

### `query_trace_for_target(target_path, chain_id = "") -> Array[Dictionary]`

Returns trace entries whose `target` matches `target_path`. When `chain_id` is non-empty, filters to that action chain.

### `query_trace_breakdown(target_path, chain_id = "") -> Dictionary`

Returns structured attribution:

```json
{
  "target": "job.reward",
  "chain_id": "reward.job_a",
  "base_value": 100.0,
  "final_value": 300.0,
  "entries": [ /* ordered matching trace rows */ ],
  "totals_by_operation": {
    "add": [ /* entries */ ],
    "multiply": [ /* entries */ ]
  }
}
```

### Enriched trace rows

Each trace entry now includes:

| Field | Description |
|---|---|
| `chain_id` | Action chain identifier |
| `event_name` | Dispatch event |
| `target` | Stable path |
| `operation` | Effect operation |
| `before` / `after` | Values around application |
| `source_id` | Subscription `source_id` or `id` |
| `phase` | `EffectOps.ResolutionPhase` enum value |
| `metadata` | Optional operation-specific data (e.g. `rate_modifier`, `transfer`, `spawned`) |

UI layers format these structures for display; the resolver does not emit presentation strings.

## Consequences

- Tooltip / inspection UI can show attributed breakdowns without re-running simulation logic.
- Tests can assert on structured traces instead of string parsing.
- Trace memory remains capped at `MAX_TRACE_ENTRIES` (500).
