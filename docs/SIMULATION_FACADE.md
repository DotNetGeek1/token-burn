# Simulation facade (#15)

`Simulation` is the only autoload gameplay API. Collaborators:

| Object | Role | Public entry |
|--------|------|----------------|
| `WorkSession` (`_work`) | In-round burns, ticks, settle | `start_work`, `burn_batch`, `execute_tick`, `should_auto_ship`, … |
| `RunLifecycle` (`_life`) | Run/round/angel/save | `begin_round`, `ensure_job_offers`, `accept_perk`, `load_saved_run`, … |
| `SimulationPreview` | Read-only forecasts | `preview_next_burn` |
| `MarketService` | Buy/sell | routed through `Simulation` |

Production UI must call `Simulation.*`, not `_work._…` or `_life._…`.

Collaborator methods used by the facade are public (`execute_tick`, `begin_round`, …). Underscore-prefixed methods remain as implementation details.

`autosave_now()` is the lifecycle hook for Android pause/focus-out.
