# ADR-003: Feature Flags

## Status

Accepted — 2026-07-28

## Context

Multiple agents will land partial features in parallel (office diorama, random events, meta progression, analytics). Incomplete work must merge without breaking the playable build. Plan section 13 requires configuration-driven flags, not scattered conditional literals.

## Chosen approach

### Configuration file

Flags live in `config/feature_flags.json`:

```json
{
  "office_diorama_enabled": false,
  "random_events_enabled": true,
  "meta_progression_enabled": false,
  "analytics_enabled": false
}
```

Defaults preserve **current behaviour**: features that exist today stay enabled; features not yet built (office diorama, meta progression, analytics) default to off.

### Loader

`core/feature_flags.gd` exposes a static query API:

```gdscript
FeatureFlags.is_enabled("office_diorama_enabled")  # -> false
```

- Loads JSON lazily on first call
- Caches parsed flags for the process lifetime
- Unknown flag names return `false`
- Reload via `FeatureFlags.reload()` for tests or debug tooling

### Integration

**Autoload is not registered in `project.godot` in this change.** Adding autoloads is a high-conflict file (plan section 7). Integration is manual when ready:

```ini
[autoload]
FeatureFlags="*res://core/feature_flags.gd"
```

Until then, call `FeatureFlags.is_enabled()` directly from any script — the class loads without autoload.

### Usage pattern

Guard **new entry points** and **incomplete subsystems**, not every internal line:

```gdscript
if FeatureFlags.is_enabled("office_diorama_enabled"):
    _office_layer.show()
else:
    _office_layer.hide()
```

Prefer early returns at system boundaries (UI buttons, simulation tick hooks, analytics emitters) rather than deep nesting.

## Alternatives considered

| Approach | Rejected because |
|---|---|
| LaunchDarkly / external SDK | Overhead for local multi-agent dev; no network dependency desired for core gameplay |
| `#ifdef`-style literals in code | Scattered, hard to audit, merge conflicts |
| Autoload singleton in this PR | Requires `project.godot` edit; skipped to avoid test/autoload churn |

## Consequences

- Agents can merge partial features behind flags without disabling existing gameplay
- Flag defaults must be updated deliberately when a feature ships globally
- New flags require an entry in `config/feature_flags.json` and a note in the agent task brief

## Migration impact

None for saves or content. Flags are read at runtime only; they are not persisted in run state unless an agent explicitly adds that later (would require a new ADR).
