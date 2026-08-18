# Late-game escalation — implementation plan

**Status:** Proposed against `main` at `9bfb326`  
**Does not replace:** workflows, modules, perks, `EffectResolver`, or the “old jobs stay small” board rule  
**Design loop to aim at:** build something unsafe → push it → burn → watch a cascade → jackpot or a recoverable fire → spend the winnings on a worse idea

This turns the late-game review into work against the current files: state fields, events, heat/instability equations, `BoardSystem` / `EffectResolver` changes, and a first cascade content batch.

The early game stays as it is. Bedroom and garage are a tutorial. The genre shift starts at GPU Rack.

---

## Audit versus the review

The review’s “change first” list was:

1. Fix heat/cooling from GPU Rack onward  
2. Expose resolver traces and named combos in the burn  
3. Remove late `max_level` caps; let soft constraints and a bigger job board carry late infrastructure  
4. Then Instability / Cascade and a post-Moon depth ladder  
5. Only then write lots of new modules

Items 1 and 2 were assumed already done. On current `main` they are not. Adjacent work exists; the actual requests do not.

### Item 1 — heat is still the inverted curve

`HeatSystem.process_prompt` and `SimulationPreview.heat_outlook` still use:

```text
Δheat = power_draw × gain_per_power − cooling × cooling_factor
```

`content/balance/economy.json` still sets `gain_per_power: 0.06` and `cooling_factor: 0.25` — the exact pairing the review used.

Starter-room ambient heat per prompt, before extra coolers (same arithmetic as the review):

| Location | Starter machine | Power | Location cooling | Ambient Δheat |
|---|---|---:|---:|---:|
| Bedroom | used laptop | 65 | 16 | −0.1 |
| Garage | custom desktop | 350 | 120 | −9 |
| Office | GPU rack | 2000 | 480 | 0 |
| Warehouse | compute cluster | 8000 | 2000 | −20 |
| Datacentre | garage DC | 40k | 15k | −1,350 |
| Private grid | compute warehouse | 300k | 120k | −12,000 |
| Moon | industrial campus | 2M | 700k | −55,000 |

Overclock still authors `+18` pipeline heat (`content/modules/modules.json`, `op.overclock`). On the moon that is noise next to −55,000 ambient.

What *is* already in place, and must be kept:

- `heat` / `heat_capacity` / `heat_ratio` as the player-facing bar (`core/run_state.gd`, `core/state/compute_state.gd`)
- One write path: `HeatSystem.add_heat` / `set_heat`, clamp `[0, capacity × 2]`
- Cooling derived, not accumulated (`ComputeSystem.derive_cooling`)
- Throttle at 80%, fire flag at 100% (`HeatSystem`, `ProgressionSystem`)
- Heat Recycler unlock: above 60% heat, throughput rises (`ComputeSystem.recalculate`)
- COOL still vents at every authored era (`tests/simulation_tests/test_late_game_heat.gd`)
- Bedroom laptop stays net-negative (`tests/simulation_tests/test_early_game_heat_rate.gd`)
- Forecast heat matches the bar (`test_heat.gd`)

`test_late_game_heat.gd` proves the COOL key still sheds heat after you buy era cooling. It does not prove late rigs run under rising thermal pressure.

### Item 2 — the burn is still fixed-time arithmetic

`ui/board/burn_board_screen.gd` still does:

```text
STAGE_SECONDS := 0.9
_animate_batch → for each preview.stages: print _stage_summary (×progress / ±quality / ±bugs) → wait 0.9s
```

`BoardSystem` already returns per-stage `before` / `after`, `repeat_count`, and `module_id`. `EffectResolver` already traces `source_id`, `event_name`, `operation`, `before` / `after`, `phase`, `chain_id` (ADR-002). `ModuleDefinition.active_combos()` already names live adjacency. The workflow editor prints combo names. Operations and Burn Lab can inspect traces.

None of that is a burn spectacle log.

### Items 3–5 — still open, as expected

- Late compute `max_level` is 2 (`content/upgrades/upgrades.json`). `test_upgrade_counts.gd` `_test_major_machine_caps_and_grandfathered_fleets` encodes that as law. `docs/GAME_DESIGN.md` still documents fleet caps.
- Floor space already exists (`dwelling_costs.json` 2 / 4 / 8 / 16 / 40 / 80 / 160) and is the right soft cap. Power cost and recurring cost already scale. They never get to matter because `max_level` stops the shop first.
- Job demand already goes to 8 (`DemandSystem.refresh_demand`). `JobSystem.generate_offers` then clamps to 5.
- Parallel lanes already exist: `ComputeSystem.job_slots()` = floor machines used.
- Contract risk flattens in `content/balance/job_scaling.json`: bug chance 12% and scope creep 5% from warehouse onward.
- Moon / alternate finales are fixed 25T–60T (`content/ascension/contracts.json`). No depth loop.
- No overkill stat. `RunScore` already has lifetime tokens, peak prompt, peak rate.
- Resolver guards are already the right absurdity ceiling: depth 32, 10,000 effects/action, same-event recursion 8 (`core/effect_ops.gd`, `core/chain_guard.gd`).
- Repeat / fork already exist: `stage.repeat_previous`, `repeat_count`, `repeat_strength`. Echo Chamber and Fractal Split already use them.

---

## Non-negotiables

1. Do not replace workflows, perks, modules, or the resolver.
2. Do not rescale live postings off `token_rate`. `test_job_scaling.gd` `_test_upgrades_are_not_matched_by_the_work` stays. One-shotting old work is the jackpot, not the default late contract.
3. Bedroom and garage numbers stay inside current test tolerances. No new meters on the tutorial HUD.
4. Instability, cascade, and depth stay gated until GPU Rack / warehouse / post-Moon as specified. Feature-flag anything that can ship half-finished (`config/feature_flags.json`, ADR-003).
5. Do not start with thirty new modules. Four cascade pieces after the systems work.

---

## Wave 0 — heat load, then burn spectacle

Do these before caps, instability, or new content. They make the existing risk modules mean something again, and they make existing chains readable.

### 0.A Thermal load (item 1)

**Owned files**

```text
systems/heat_system.gd
core/simulation_preview.gd
core/simulation.gd                    # only if it inlines ambient maths
content/balance/economy.json          # heat block
content/balance/dwelling_costs.json   # only if a chapter’s starter load is still ice-cold after the formula change
tests/simulation_tests/test_heat.gd
tests/simulation_tests/test_late_game_heat.gd
tests/simulation_tests/test_early_game_heat_rate.gd
tests/simulation_tests/test_thermal_load.gd   # new
tests/content_validation/test_content_validation.gd  # outlook defaults still say 0.025 / 0.35
```

**Do not touch yet:** modules, perks, burn UI, `max_level`, ascension.

#### Equation

Keep the player-facing bar as `heat / heat_capacity`. Stop treating megawatt cooling and Overclock `+18` as the same absolute unit.

Add one function, used by both the live tick and the forecast:

```gdscript
# HeatSystem.ambient_delta(run_state) -> float
generation = power_draw * gain_per_power
sink = cooling * cooling_factor
tier = JobSystem.rig_work_tier(run_state, ContentDatabase)   # already exists

if tier < 2:
    # Bedroom / garage: current absolute model. Do not change the feel.
    return generation - sink

load_ratio = generation / maxf(sink, 0.001)          # 1.0 = plant matches draw
equilibrium = 1.0 - era_heat_bias * float(tier - 1)  # matched late plants still run warm
stress = load_ratio - equilibrium
return heat_capacity * ambient_rate * stress
```

New `economy.heat` keys (starting values, then sweep):

| Key | Start | Role |
|---|---:|---|
| `gain_per_power` | 0.06 | unchanged; still defines “matched” as `P/C ≈ 4.167` |
| `cooling_factor` | 0.25 | unchanged |
| `ambient_rate` | 0.10 | how much of the bar a unit of stress moves |
| `era_heat_bias` | 0.09 | per era above desktop, lowers the “safe” load ratio |
| `pipeline_heat_ref_capacity` | 100 | bedroom bar; see pipeline scaling |
| `overclock_band` | `[0.70, 0.85]` | reserved for Wave 2; unused in 0.A |
| `fault_band` | `[0.85, 1.00]` | reserved for Wave 2 |
| `catastrophe_ratio` | 1.50 | reserved for Wave 2 (fire moves past 100%) |

Pipeline heat (Overclock and friends) is authored at bedroom scale. From GPU Rack onward, apply it as a slice of the local bar:

```gdscript
# BoardSystem / work_session heat apply
authored = float(batch.heat)   # already folded from stages
if tier >= 2:
    authored *= heat_capacity / pipeline_heat_ref_capacity
HeatSystem.add_heat(run_state, authored)
```

So `+18` is 18% of the bedroom bar, 36 points in the office (capacity 200), 144 on the moon (capacity 800). Compute becomes dangerous in the GPU Rack chapter without rewriting every module.

`HeatSystem.process_prompt` becomes:

```text
add_heat(ambient_delta)
heat_ratio = heat / capacity
throttle at throttle_ratio (unchanged)
fire_risk = heat_ratio >= 1.0     # Wave 2 moves this to catastrophe_ratio
```

`SimulationPreview.heat_outlook` must call `ambient_delta`, not re-implement `P×g − C×f`. Today those two copies already disagree on fallback defaults (`0.025/0.35` vs `0.06/0.25`).

#### Target feel after 0.A (acceptance, not flavour)

| Setup | Wanted ambient | Why |
|---|---|---|
| Bedroom laptop | ≤ 0, about −0.1 | `test_early_game_heat_rate` / `_test_bedroom_sustains_starting_laptop` |
| Garage desktop | < 0 | early game still forgives |
| Office, one GPU rack, no extra cooler | small positive (~+1 to +4 / prompt on a 200 bar) | first “compute is warm” lesson |
| Office, GPU rack + industrial chiller | ≤ 0 or barely + | cooling is a real purchase |
| Office, two GPU racks, no extra cooler | clearly positive, throttle in a handful of burns | stacking iron is the danger |
| Moon, one campus, stock cooling | bar still moves; Overclock is ≥ 5% of the bar | late safety inversion is gone |
| Moon, many campuses, stock cooling | redline without matching cooling | 47 campuses is a thermal problem, not a `MAX_LEVEL` problem |

Do not retune `dwelling_costs.json` cooling unless the formula alone cannot hit the office / moon rows. If you do retune, keep bedroom 16 / garage 120.

#### Tests

- Keep every early-game heat test green without rewriting the assertions.
- New `test_thermal_load.gd`:
  - `ambient_delta` for bedroom equals `generation - sink` within 0.01
  - office GPU rack, no extra cooler: `ambient_delta > 0`
  - moon campus: `abs(ambient_delta) < heat_capacity * 0.2` (no more −55,000)
  - after one Overclock-scale apply on the moon, heat rises by at least 5% of capacity
  - outlook `heat_per_prompt` equals `HeatSystem.ambient_delta` on the same state
- Fix `test_heat.gd` / content validation fallbacks to read live `economy.heat` values instead of `0.025/0.35`.

`test_heat.gd` `_test_rack_needs_industrial_space` currently says a GPU rack is sustainable in the warehouse. That can stay (warehouse cooling is the next chapter’s plant). Do not make a naked rack safe in the office.

### 0.B Burn spectacle (item 2)

**Owned files**

```text
core/burn_spectacle.gd                # new: beats from preview + trace + combos
ui/board/burn_board_screen.gd         # _animate_batch walks beats
ui/board/laptop_screen.gd             # only if a slam / multiplier line needs a hook
ui/common/ui_sound.gd                 # pitch climb on cascade beats
tests/simulation_tests/test_burn_spectacle.gd
```

**Do not change** `EffectResolver` semantics. Consume `get_trace()` / `query_trace_for_target`. If a beat needs a field the trace already has, do not add a parallel log.

#### Beat list

`BurnSpectacle.build(preview, trace, board_slots) -> Array[Dictionary]`

For each `preview.stages[]` row (`BoardSystem` already stamps `module_id`, `name`, `before`, `after`, `repeat_count`, `repeated_previous`):

1. Base stage beat (`kind: "stage"`).
2. If `ModuleDefinition.active_combos(prev_id, next_id)` is non-empty, insert `kind: "combo"` with the authored combo name (Read the Docs, Warm Cache, Caught in Review, …).
3. Trace rows for that stage’s `chain_id` (`board.stage.{slot}.{module_id}`) whose `source_id` starts with `perk.` or `status.` → `kind: "perk"` / `"status"`.
4. If `repeat_count > 0` and `repeated_previous > 0` → `kind: "repeat"` (RECURSIVE FORK).
5. If `after.progress_mult / before.progress_mult ≥ 1.15` (or token_mult) → `kind: "mult"` with the running × chain (`×1.8 → ×3.24 → …`).
6. Wave 3 adds `kind: "cascade"` from a flag on the stage record. The builder should already accept `stage.cascaded`.

Beat shape:

```json
{
  "kind": "combo",
  "label": "WARM CACHE",
  "module_id": "op.token_cache",
  "source_id": "op.token_cache",
  "before_mult": 1.8,
  "after_mult": 3.24,
  "duration_ms": 550,
  "slot_index": 2
}
```

#### Timing (replace `STAGE_SECONDS`)

| Kind | Duration |
|---|---|
| Ordinary stage, no combo / perk / repeat, |Δmult| < 15% | 180ms |
| Named combo, perk fire, modest mult jump | 550ms |
| Repeat / cascade / Δmult ≥ 1.5× | 800ms |
| Final token land | 400ms after the last beat |

Ordinary stages fly. Meaningful triggers slam the console, flash the module, bump the multiplier, climb sound pitch. KILL still discards the current beat.

`_stage_summary` remains as a fallback line under the slam, not the whole show.

#### Tests

- A Token Cache sitting above an expensive model produces a beat labelled Warm Cache.
- A pipeline with no combos / repeats produces only `stage` beats and finishes faster than `n × 0.9s` in the duration totals.
- Repeat-count > 0 produces a `repeat` beat.
- Builder is pure: no `RunState` mutation.

Ship 0.B behind `burn_spectacle_enabled` (default true once tests pass) so it can be flipped without a content rollback.

---

## Wave 1 — soft hardware limits, a board that uses the floor, nastier late contracts

Do this after 0.A so 47 campuses are a thermal problem.

### 1.A Remove late `max_level` caps

**Owned files**

```text
content/upgrades/upgrades.json
docs/GAME_DESIGN.md                   # delete the “four desktops, then two of each rack” paragraph
tests/simulation_tests/test_upgrade_counts.gd
tests/simulation_tests/test_hardware_slots.gd
tests/simulation_tests/test_hardware_purchase_rate.gd
```

Changes:

- `upgrade.gpu_rack`, `compute_cluster`, `garage_datacentre`, `compute_warehouse`, `industrial_campus`: drop `max_level` (or set `0`). `UpgradeSystem.is_maxed` already treats `max_level <= 0` as uncapped.
- Keep `upgrade.custom_desktop` at `max_level: 4`. That is early-game floor teaching, not a late leash.
- Keep cooling / orbital uncapped as they are.
- Leave `cost_growth: 1.15` for now. Money, floor, power, and heat are the brakes. If 47 campuses are free in cash terms after one moon contract, raise late `cost_growth` in a follow-up sweep — do not put `max_level` back.

Rewrite `_test_major_machine_caps_and_grandfathered_fleets`:

- A third GPU rack is allowed when the room has a free floor slot and the player can pay.
- A third rack is refused when the floor is full (`hardware_space_full`).
- Legacy over-count fleets still load and can be sold.

Add a moon test: buying past two industrial campuses is legal; `heat_outlook` / `ambient_delta` goes positive without extra cooling.

### 1.B Job board scales with machines

**Owned files**

```text
systems/job_system.gd                 # generate_offers clamp
systems/demand_system.gd              # only if the demand ceiling must rise with slots
tests/simulation_tests/test_job_scaling.gd
tests/simulation_tests/test_parallel_and_bonus.gd
```

Today:

```gdscript
var count: int = clampi(int(run_state.business.get("demand", 3.0)), 1, 5)
```

Change to:

```gdscript
var offer_cap: int = maxi(5, ComputeSystem.job_slots(run_state))
var count: int = clampi(int(run_state.business.get("demand", 3.0)), 1, offer_cap)
```

If `DemandSystem` still caps demand at 8, raise that ceiling to `maxi(8, job_slots)` so advertising and a 16-machine warehouse can actually fill the board.

Keep: one windfall, one stretch, “one familiar local + authored service-tier posts” when the rig outruns the room. Do not start live-scaling old contracts.

Acceptance: a warehouse with 8 machines can see more than 5 offers when demand is high; a bedroom still sees 1–5.

### 1.C Un-flatten late contract risk

**Owned files**

```text
content/balance/job_scaling.json
tests/simulation_tests/test_job_scaling.gd   # pin the new ladders
```

Replace the flattened tails. Do not touch bedroom / garage values.

```json
"revision_risk_cap_by_tier": [0.04, 0.08, 0.12, 0.16, 0.20, 0.26, 0.32],
"bug_chance_by_tier":        [0.04, 0.07, 0.10, 0.13, 0.16, 0.20, 0.25],
"scope_creep_pct_by_tier":   [0.02, 0.03, 0.04, 0.06, 0.08, 0.11, 0.15]
```

`JobSystem._scale_job` already reads these arrays. No code change unless a test hard-codes 0.12.

---

## Wave 2 — Instability and recoverable faults

GPU Rack introduces temper. Compute Cluster introduces faults you can live with. Fire becomes the far end of the bar, not the first failure.

**Owned files**

```text
systems/heat_system.gd
systems/compute_system.gd
systems/progression_system.gd
core/event_bus.gd
core/run_state.gd
core/state/compute_state.gd
core/run_lifecycle.gd                 # persist / reset
content/balance/economy.json          # heat bands
content/events/events.json            # optional fault copy
ui/board/burn_board_screen.gd         # heat meter: “redlined” / “fault”
ui/board/heat_gauge.gd                # band colours
tests/simulation_tests/test_instability.gd
tests/simulation_tests/test_heat.gd   # fire threshold move
```

### State

Add to `run_state.compute` (and `ComputeState`):

```text
instability: float          # 0..1, derived each prompt, not a resource the player banks
```

Do **not** add a second player-facing meter in the bedroom. From GPU Rack, the existing heat bar gains band copy (“warm”, “redline”, “fault”). Instability is a derived number for rules and traces.

Faults reuse `build.status_effects`. That path already has duration, subscriptions, and expiry (`test_heat.gd` `_test_status_effects_wear_off`). A dead rack is a status, not a new subsystem.

```json
{
  "id": "status.fault.dead_rack",
  "name": "Rack offline",
  "rounds": 2,
  "repair_cost": 0,
  "subscriptions": [{
    "event": "compute.recalculate",
    "priority": 0,
    "conditions": [],
    "effects": [
      {"operation": "multiply", "target": "compute.local_rate", "value": 0.82}
    ]
  }]
}
```

`repair_cost` can be 0 (waits out) or a cash amount a later REPAIR command spends to clear early. First ship: duration-only. Cluster chapter is “you can keep working at −18%.”

### Events

```text
EventBus.EVENT_CASCADE_TRIGGERED   := "board.cascade_triggered"   # reserved; Wave 3 emits
EventBus.EVENT_FAULT_STARTED       := "compute.fault_started"
EventBus.EVENT_FAULT_CLEARED       := "compute.fault_cleared"
```

`EVENT_HEAT_THRESHOLD_CROSSED` stays. Fault rolls subscribe to it or run inside `HeatSystem.process_prompt` after `fire_risk` is set.

### Instability equation (from `work_tier >= 2` only)

```text
r = heat / heat_capacity

if r < 0.70:           instability = 0
elif r < 0.85:         instability = lerp(0.00, 0.25, (r - 0.70) / 0.15)   # overclock band
elif r < 1.00:         instability = lerp(0.25, 0.55, (r - 0.85) / 0.15)   # cascade + faults
elif r < 1.40:         instability = lerp(0.55, 0.85, (r - 1.00) / 0.40)   # redline
else:                  instability = 1.0
```

Effects, also gated by tier:

| Band | GPU Rack (tier ≥ 2) | Cluster onward (tier ≥ 3) |
|---|---|---|
| 0.70–0.85 | `token_rate *= 1 + 0.15 × band_t` (baseline Heat Recycler feel; the unlock can still add on top) | same |
| 0.85–1.00 | Wave 3 reads `instability` as cascade bonus | plus `fault_chance = 0.08 × band_t` per prompt |
| 1.00–1.40 | dropped-stage chance `0.10 × band_t`; quality noise; optional extra heat | plus pump / power-trip statuses |
| ≥ 1.40 | `fire_risk = true` | same |
| ≥ `catastrophe_ratio` (1.50) and still `fire_risk` | existing hardware-fire loss | same |

`ProgressionSystem.check_loss` today fires at `fire_risk && heat >= capacity`. Change to `heat >= capacity * catastrophe_ratio` so crossing 100% is a decision, not a run end.

Statistics to add: `faults_suffered`, `max_instability`.

### Redline batch twists (tier ≥ 2, `heat_ratio >= 1.0`)

Inside `BoardSystem` resolve (Wave 2 can stub; Wave 3 uses the same rolls):

- `drop_stage_chance`: skip this stage’s fold, keep it in the spectacle log as `kind: "fault"`.
- `corrupt_quality`: subtract a small quality chunk, message “output scrambled”.
- `random_rerun`: set `stage.repeat_count += 1` at reduced strength and extra heat.

All rolls go through the existing stage `rng.derive(...)`. Preview must use the same streams so the animation matches the commit (already true for burns).

### Tests

- Bedroom at 90% heat: `instability == 0`, no faults, fire still only from the old rules if you leave them for tier < 2.
- Office GPU rack at 75% heat: `instability > 0`, rate ≥ baseline.
- Cluster at 90% heat: after N prompts, a status fault can appear; `token_rate` drops; run does not end.
- Cluster at 100% heat: no fire loss.
- Cluster at 150% heat with `fire_risk`: fire loss.
- Fault status expires and rate returns.

---

## Wave 3 — Cascade mechanic and the first four pieces of content

Warehouse is where recursive / cascade builds become real. The resolver already allows it. `BoardSystem._fold` already replays `previous_stage`. This wave makes heat *raise the odds* and gives the player a few modules that lean on that.

**Owned files**

```text
systems/board_system.gd
core/event_bus.gd
content/modules/modules.json
content/perks/perks.json
content/balance/economy.json          # cascade_base, cascade_heat_scale
tests/simulation_tests/test_burn_board.gd
tests/simulation_tests/test_cascade.gd
tests/content_validation/test_content_validation.gd
```

**EffectResolver:** no new operations. Optional: include `metadata.cascade = true` on the triggering effect’s trace row. Do not raise guard limits.

### BoardSystem

Add to `STAGE_DEFAULTS`:

```text
cascade_chance: 0.0
cascade_strength: 1.0
```

After the authored `repeat_previous` loop, and only when `work_tier >= 4` (warehouse / garage DC) *or* when `cascade_chance > 0` (so a module can bring cascade online earlier):

```gdscript
var heat_bonus: float = 0.0
if heat_ratio >= 0.85:
    heat_bonus = (heat_ratio - 0.85) * cascade_heat_scale   # start 0.40
var chance: float = clampf(float(stage.cascade_chance) + heat_bonus, 0.0, 0.65)
if chance > 0.0 and not previous_stage.is_empty():
    if rng.derive("cascade_%d" % index).next_float() < chance:
        _fold(batch, previous_stage, cascade_strength * effective_multiplier, pending_cost_mult)
        run_state.statistics["cascades_triggered"] = ... + 1
        stages[-1]["cascaded"] = true
        EventBus.emit_event(EVENT_CASCADE_TRIGGERED, {"module_id": module.id, "heat_ratio": heat_ratio})
```

Same-event recursion 8 and depth 32 already stop genuine infinity. Do not add a second cap unless a test can spin a 10-second resolve.

`ModifierContext.extras` already has `heat_ratio`. Modules can author `stage.cascade_chance` the same way they author `stage.repeat_previous`.

### First content batch (only after the hook exists)

Four modules, one perk. Copy tone from Overclock / Echo Chamber / Fractal Split. Gate with `min_location_tier` so the bedroom never sees them.

| Id | Name | Rarity | min tier | What it does |
|---|---|---|---|---|
| `op.recursive_compiler` | Recursive Compiler | rare | 3 (warehouse) | `cascade_chance = 0.25`, `cascade_strength = 1.0`. Replays the parent when it hits. |
| `op.memory_leak` | Memory Leak | uncommon | 3 | Each `board.cascade_triggered` / each repeat: `repeat_strength += 0.15`, `stage.heat += 8` (bedroom-scale, then Wave 0 pipeline scale). |
| `op.thermal_lottery` | Thermal Lottery | rare | 2 (office / GPU rack) | If `$heat_ratio >= 0.90`, `25%` chance `stage.progress_mult *= 3` and `stage.heat += 12`. |
| `op.dead_mans_switch` | Dead Man’s Switch | legendary | 4 | On `board.batch_finalizing`, if `heat_ratio` crossed 1.0 this batch and the run did not fault-kill the batch: `batch.progress_mult *= 10`. If a fault landed, `batch.progress_mult *= 0.4` instead. |
| `perk.redline_rider` | Redline Rider | — | unlock with Heat Recycler or warehouse | While `heat_ratio >= 0.85`, `cascade_chance += 0.10` and cooling efficiency −15% (`compute.cooling` multiply 0.85). |

Thermal Lottery can ship in the GPU Rack chapter (item 1’s “compute is dangerous” toy). The other three wait for warehouse so the tutorial stays clean.

Do not write more than this batch until a playable warehouse run has produced a visible cascade in the spectacle log.

---

## Wave 4 — Overkill and the post-Moon depth ladder

Moon stays the last *authored chapter*. After it, the leash comes off. Do not add a new dwelling.

### 4.A Overkill

**Owned files**

```text
core/work_session.gd                  # on complete
core/run_score.gd
core/run_state.gd                     # statistics
systems/job_system.gd                 # optional rarity bias
ui/board/burn_board_screen.gd         # slam “412% OVERKILL”
ui/screens/session_summary.gd / run_end.gd
tests/simulation_tests/test_overkill.gd
```

On contract complete (tokens delivered ≥ requirement):

```text
overkill_ratio = tokens_applied / max(requirement, 1)
overkill_pct = max(0, overkill_ratio - 1) * 100
```

`tokens_applied` is requirement − final `tokens_remaining` plus any overflow from the completing burn (the last burn can overshoot; that overflow *is* the point).

Statistics: `peak_overkill`, `lifetime_overkill` (sum of `max(0, ratio - 1)`).

`RunScore.compute` adds `peak_overkill` and an overkill score term, e.g. `floor(lifetime_overkill * 100)` so 4.12× on a 20T job is a headline, not “contract done”.

Optional, small, first ship only one:

- Next draft: rarity weight `× (1 + min(0.25, overkill_ratio - 1))` for one pick, or
- Status `status.overkill_high`: next batch `token_mult × 1.05` for one prompt

Presentation: if `overkill_ratio ≥ 1.25`, spectacle final beat `kind: "overkill"`, label `412% OVERKILL`.

One-shotting a 20T job with 100T is the jackpot. Ordinary late work should still take 4–8 burns; that is Wave 4.B’s job, not a live rescale of old postings.

### 4.B Deep Burn / Compute Depth

**Owned files**

```text
systems/ascension_system.gd
systems/job_system.gd
core/run_state.gd
core/run_score.gd
content/ascension/contracts.json      # moon still 25T; add depth config, not a new location
content/balance/job_scaling.json      # depth_requirement_mult, depth_affixes
ui/screens/run_end.gd / investor_call.gd
tests/simulation_tests/test_ascension.gd
tests/simulation_tests/test_depth.gd
```

After `ascension.final_prompt` (or any moon-tier win), do not end the campaign as “no more numbers”. Offer **Deep Burn**:

```text
run_state.depth = {
  "level": 1,
  "affixes": [],
  "score_mult": 1.0,
  "requirement_mult": 1.0
}
```

Each level:

1. Show three affix cards (authored in `job_scaling.depth_affixes` or `content/ascension/depth_affixes.json`).
2. Player picks one. Stack it. Multiply `score_mult` and apply the downside.
3. Next workload `token_requirement *= depth_growth[level]` where growth is `3, 5, 10, 10, …` — orders of magnitude, not a tracking curve.
4. Quality / deadline / risk also tick up. Use the existing job fields plus the affix.

First affix set (three is enough to start):

| Id | Player-facing | Effect | Score |
|---|---|---|---|
| `depth.target_x5` | Target ×5 | this depth’s requirement `×5` | `×3` |
| `depth.thin_cooling` | Cooling efficiency −35% | `compute.cooling *= 0.65` while the depth is live | `×2` |
| `depth.hidden_bug` | Every recursive / cascade stage adds a hidden bug | on `board.cascade_triggered` / repeat: `hidden_bugs += 1` | `×4` |

Failing a depth job is a failed contract, not necessarily a run end. Walking away keeps the score. `RunScore` already has the plumbing; add `depth_reached` and `depth_score`.

Moon’s 25T contract stays the chapter win. Depth is voluntary and meant to hurt.

Gate with `depth_ladder_enabled` until the affix picker UI is real.

---

## Wave 5 — more content, only after the loop works

Only once Waves 0–4 have been played: a warehouse cascade is visible, a moon campus can cook itself, and a depth pick can ruin a safe plant.

Then add modules/perks that the new verbs are missing (more cascade payoffs, more recoverable faults, more “survive the redline” bets). Do not start here.

---

## New events and fields (checklist)

### `EventBus` (`core/event_bus.gd`)

| Constant | String | Wave |
|---|---|---|
| `EVENT_CASCADE_TRIGGERED` | `board.cascade_triggered` | 3 (declare in 2 if HeatSystem needs the name) |
| `EVENT_FAULT_STARTED` | `compute.fault_started` | 2 |
| `EVENT_FAULT_CLEARED` | `compute.fault_cleared` | 2 |
| `EVENT_OVERKILL` | `job.overkill` | 4 |
| `EVENT_DEPTH_ADVANCED` | `depth.advanced` | 4 |

Existing `EVENT_HEAT_THRESHOLD_CROSSED` stays the perk hook for “we just entered a band”.

### `run_state.compute`

| Field | Wave | Notes |
|---|---|---|
| `instability` | 2 | derived, 0..1 |
| `heat`, `heat_capacity`, `cooling`, `power_draw` | — | unchanged meaning |

### `run_state.statistics`

| Field | Wave |
|---|---|
| `cascades_triggered` | 3 |
| `faults_suffered` | 2 |
| `max_instability` | 2 |
| `peak_overkill` | 4 |
| `lifetime_overkill` | 4 |
| `depth_reached` | 4 |

### `run_state.depth` (new dict, Wave 4)

`level`, `affixes`, `score_mult`, `requirement_mult`

### `BoardSystem` stage record (extra keys)

`cascaded: bool`, `dropped: bool`, `cascade_chance`, `cascade_strength`

### Feature flags

```json
"burn_spectacle_enabled": true,
"thermal_load_enabled": true,
"instability_enabled": false,
"cascade_enabled": false,
"depth_ladder_enabled": false
```

Turn each on only when its tests pass. Bedroom path must ignore them (tier < 2).

---

## Suggested PR sequence

One PR per wave, in order. Do not bundle 47 campuses with a new module pack.

| PR | Wave | Why it is a single merge |
|---|---|---|
| 1 | 0.A Thermal load | All ambient / outlook / pipeline-heat scale in one place; early tests are the regression net |
| 2 | 0.B Spectacle | Presentation only; can land on old heat if 0.A slips, but feels much better after 0.A |
| 3 | 1.A + 1.B + 1.C | Caps, board size, risk ladders — content/balance, needs 0.A so uncapped fleets cook |
| 4 | 2 Instability / faults | Depends on a bar that still moves late |
| 5 | 3 Cascade hook + four cards | Depends on spectacle (or the hook is invisible) and instability (or cascade has no heat story) |
| 6 | 4 Overkill + depth | Depends on late work not being one-shot by default |

---

## What this plan deliberately does not do

- New chapters after the moon (no Mars, no Dyson).
- Live-scaling old jobs to the current token rate.
- Removing one-shots of leftover early contracts.
- A second effect language. Cascade is a `BoardSystem` fold plus existing repeats.
- Instant-run-end at 100% heat.
- Changing resolver guard limits.
- Rewriting the tutorial HUD.

---

## Immediate next implementation step

Open Wave 0.A. Extract `HeatSystem.ambient_delta`, switch `process_prompt` and `heat_outlook` to it, add the load-ratio branch for `work_tier >= 2`, scale pipeline heat by `heat_capacity / 100` from that tier, and lock it with `test_thermal_load.gd` plus the existing early-game heat tests.

Until that lands, every later wave is decorating a machine that gets safer as it gets bigger.
