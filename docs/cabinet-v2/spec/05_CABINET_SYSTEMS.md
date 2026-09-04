# 05 — Cabinet systems and migration

## System model

Each of the five systems has tiers 1–4. A system tier has exactly one functional purpose and one authored visual assembly occupying a fixed attachment zone.

| System | Mechanical responsibility | Visual language |
| --- | --- | --- |
| Compute Stack | Base token throughput | Exposed board → GPU cage → accelerator stack → sealed impossible core |
| Cooling Loop | Heat capacity, cooling/vent effectiveness | Desk fan → radiator → liquid manifold → phase cooler |
| Power Bus | Hardware headroom, power draw tolerance, boost support | Household lead → transformer → busbar bank → unstable power core |
| Workflow Backplane | Active workflow stage/module bay capacity | 3 → 5 → 7 → 10 open physical bays |
| Control Rack | Saved workflow capacity | 1 → 2 → 3 → 4 selectors |

## Purchasing

- Cabinet systems appear under a `SYSTEMS` shelf in Market.
- The next tier is the only purchasable row for each system.
- Buying uses the contextual `UPGRADE` action.
- No independent cabinet-level currency.
- Modules and perks should remain more frequent and tactically interesting; systems are occasional infrastructure decisions.

## Visual-generation resolver

Let each tier be 1–4. Sum the five tiers (`5..20`) and derive presentation only:

| Sum | Generation |
| ---: | --- |
| 5–7 | Improvised Cabinet |
| 8–10 | Spliced Rig |
| 11–14 | Token Furnace |
| 15–18 | Grid Eater |
| 19–20 | Impossible Engine |

Generation may change ambient hum, chassis wear, glow and installation effects. It grants no extra mechanics by itself.

## Content schema

The proposed shape is in `data/cabinet_systems.json`. Keep tuning values data-driven. Do not hard-code costs/effects in UI classes.

Suggested state:

```gdscript
run_state.build["cabinet_systems"] = {
  "compute": 1,
  "cooling": 1,
  "power": 1,
  "backplane": 1,
  "control": 1
}
```

## Migration from properties

Increment the save schema. On first load, if `build.cabinet_systems` is absent, derive it from `build.dwelling`:

| Old dwelling | Compute | Cooling | Power | Backplane | Control |
| --- | ---: | ---: | ---: | ---: | ---: |
| bedroom | 1 | 1 | 1 | 1 | 1 |
| garage | 2 | 2 | 2 | 2 | 1 |
| office_unit | 2 | 2 | 2 | 2 | 2 |
| warehouse | 3 | 3 | 3 | 3 | 2 |
| datacentre_campus | 3 | 3 | 3 | 3 | 3 |
| private_power_grid | 4 | 3 | 4 | 4 | 3 |
| moon_facility | 4 | 4 | 4 | 4 | 4 |

Migration rules:

- Preserve cash, run phase, contracts, modules, perks, workflows, round, achievements and RNG state.
- Do not charge or refund during migration.
- Preserve the old dwelling key in a migration/debug field for one schema version only.
- Translate old board/workflow upgrades to at least the same capacity; never reduce an in-progress save's slot count.
- Clamp impossible combinations to valid tier 1–4 values and log a warning.
- Save immediately after a successful migration.

## Existing upgrade content

The current data mixes properties, machines, cooling appliances, board capacity and components. Replace player-facing dwelling upgrades immediately, but migrate hardware in two safe steps:

1. **Compatibility phase:** existing hardware continues to drive compute/economy under the hood while Market groups it behind the five system headings.
2. **System phase:** consolidate old hardware rows into tiered system definitions only after balance tests cover equivalent output, heat and recurring cost.

This avoids combining a UI rewrite and a total economy rebalance into one unreviewable change.

## Art rules

- A tier replaces the prior tier assembly; it does not pile another random object beside it.
- Each system owns a fixed mount rectangle.
- Small wires, scorch, stickers and patch plates may reflect generation, but never claim to be upgrades.
- A system must be identifiable at gameplay scale by silhouette, not only by a label.

