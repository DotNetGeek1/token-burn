# Token Burn — Module Expansion Implementation Brief

> Historical brief. UI file references to `ui/venues/*` are superseded by the Burn Cabinet v2 (see `docs/cabinet-v2`); achievements and legacy summaries are now Records in the cabinet's Maintenance view, and the "location tier" gates map onto campaign chapters. The module catalogue design itself still applies.

**Repository:** `DotNetGeek1/token-burn`  
**Design target:** **120 total modules**  
**Reviewed baseline:** commit `b01fd1d22fb9158eef37fc2bc6cd806cc45a010c` (`v0.7.2`)  
**Baseline catalogue at review:** 61 modules  
**New modules in this brief:** 59  
**Target after implementation:** 120 modules

> This document is intended to be handed directly to Cursor. Treat it as the implementation specification for the module-catalogue expansion. Do not redesign the core Burn Board while implementing this work. The goal is to use the systems that now exist, extend progression/telemetry only where required, add the cards, and validate the resulting content thoroughly.

---

## 1. Goal

Expand Token Burn from the current module pool to a launch-scale catalogue of approximately 120 modules while preserving the current data-driven architecture.

The expanded catalogue must:

- support clearly different build archetypes rather than 120 isolated stat sticks;
- deepen over multiple completed runs;
- keep a fresh profile understandable;
- use achievements for skill/behaviour unlocks;
- use victory-count gates for veteran content without generating dozens of duplicate “win X times” achievements;
- make Hard victories unlock genuinely dangerous/endgame cards;
- use existing OUTPUT / QUALITY / THERMAL, heat, bug, recursion, cascade, positional, finalizing and mastery systems wherever possible;
- avoid adding a new engine primitive when an existing effect target can express the card;
- keep previews side-effect free;
- keep deterministic tests for random cards;
- preserve old saves.

The catalogue should encourage overlapping archetypes:

1. One-Shot Benchmark
2. Golden Path / Clean Compile
3. Repair Engine
4. Bug Factory
5. Cold Rig
6. Redline Degenerate
7. Recursive Nightmare
8. Recursive QA
9. Context Engine
10. Long Pipeline
11. Short Pipeline
12. Hardware Execution
13. Quality Monster
14. Friday Shipping
15. Specialist Workflow / Mastery
16. Multi-workflow Consultancy
17. Positional Combo
18. Cascade Casino

The important design rule is **cross-archetype overlap**. Cards should often carry two or three useful identities. Examples:

- HBM Burst = output + hardware + cold-start payoff.
- Mutation Testing = bugs + repair + quality.
- Reviewer Agent = recursion + repair.
- Proof-Carrying Code = quality + mastery.
- Voltage Spike = output + heat + bugs.

---

## 2. Existing architecture to preserve

The project already supports the right shape for this expansion.

`ModuleDefinition` supports:

- `id`
- `name`
- `category`
- `rarity`
- `tags`
- `description_template`
- `badge`
- `parameters`
- `slot_effects`
- `priority`
- `starter`
- `opens_pipeline`
- `unlock_achievement`
- `min_location_tier`
- `max_location_tier`
- `draft_weight`
- `difficulty`
- `combos`
- `finalizing_effects`
- `folded_effects`
- `completion_effects`

Do **not** create card-specific GDScript classes for the new modules unless a mechanic genuinely cannot be represented by the effect resolver.

Prefer patterns already used by the current content:

- `op.power_limit` for heat-conditional branch effects.
- `op.clean_room_gate` for batch-finalizing clean/dirty checks.
- `op.regression_suite` for “created bugs but repaired them” checks.
- `op.benchmark_harness` for completion effects.
- `op.branch_predictor` for next-stage modifiers.
- `op.ecc_memory` for blocking hidden bugs on the next stage.
- `op.thermal_recuperator` for cooling plus a heat-condition payoff.
- `op.batch_scheduler` for pipeline-length conditions.
- `op.debug_symbols` for folded-stage reactions.
- `op.agent_swarm` and existing fork modules for repeats.
- existing cascade modules/perks for `stage.cascade_chance` / `stage.cascade_strength`.

Existing useful effect targets include at least:

```text
stage.progress_mult
stage.token_mult
stage.quality
stage.quality_mult
stage.thermal_mult
stage.cost
stage.heat
stage.bugs
stage.hidden_bugs
stage.fix_bugs
stage.fix_hidden_bugs
stage.reveal_bugs
stage.hide_bugs
stage.quality_to_progress
stage.repeat_previous
stage.repeat_strength
stage.repeat_count
stage.next_multiplier
stage.next_cost_mult
stage.next_hidden_on_bug
stage.next_block_hidden
stage.cascade_chance
stage.cascade_strength

batch.progress_mult
batch.quality_mult

mastery.output_gain
mastery.quality_gain
mastery.thermal_gain

build.hardware_discount
```

Use canonical targets from the current validation list. If the exact name differs, use the existing name; do not add synonyms just for this content pass.

---

## 3. Files expected to change

At minimum inspect/update:

```text
content/modules/modules.json
definitions/module_definition.gd
core/content_database.gd
core/run_state.gd
systems/achievement_system.gd
systems/job_system.gd
systems/workflow_mastery_system.gd
content/achievements/achievements.json
tests/content_validation/test_content_validation.gd
tests/simulation_tests/test_workflow_mastery.gd
tests/simulation_tests/test_achievements.gd
tests/simulation_tests/test_canonical_builds.gd
```

Potentially update if the existing UI has an appropriate surface:

```text
ui/screens/run_end.gd
ui/venues/venue_achievements.gd
ui/venues/venue_legacy.gd
```

Do not touch save format/version unless inspection proves it is required. New statistics should default safely when absent from an older save.

---

# 4. Required progression extension

## 4.1 Why this is needed

`unlock_achievement` is a good fit for behavioural achievements, but it is a bad fit for “win the game twice” progression if every card needs a cloned achievement.

Add two direct meta-progression gates to `ModuleDefinition`:

```gdscript
@export var min_victories: int = 0
@export var min_hard_victories: int = 0
```

Add both to `to_dict()`.

Load them in `ContentDatabase._load_modules()`:

```gdscript
module.min_victories = int(entry.get("min_victories", 0))
module.min_hard_victories = int(entry.get("min_hard_victories", 0))
```

Update `ContentDatabase.module_is_unlocked()` so **all specified gates are ANDed**:

```gdscript
func module_is_unlocked(module: ModuleDefinition) -> bool:
    if module.unlock_achievement != "" and not MetaProgress.has_achievement(module.unlock_achievement):
        return false
    if MetaProgress.victories() < module.min_victories:
        return false
    if MetaProgress.victories_on("hard") < module.min_hard_victories:
        return false
    return true
```

Do not bypass `module_is_unlocked()` in any draft path. Both mixed angel drafts and any module-only draw path should respect it.

Add content validation:

- `min_victories >= 0`
- `min_hard_victories >= 0`
- if `unlock_achievement` is non-empty it must refer to a real achievement whose reward unlocks the same module, preserving the current contract.

### Gate notation used below

| Notation | JSON implementation |
|---|---|
| `OPEN` | no achievement/victory gate |
| `ACH` | `unlock_achievement` set to the specified achievement |
| `V1` | `min_victories: 1` |
| `V2` | `min_victories: 2` |
| `V3` | `min_victories: 3` |
| `V5` | `min_victories: 5` |
| `H1` | `min_hard_victories: 1` |
| `H3` | `min_hard_victories: 3` |

Location tiers remain a separate gate.

Current location order is conceptually:

```text
0 bedroom
1 garage
2 office_unit
3 warehouse
4 datacentre_campus
5 private_power_grid
6 moon_facility
```

Use `min_location_tier`; do not add a second location-gating system.

---

# 5. Required telemetry extension

Achievements should teach the player the mechanics we want them to discover. Add a small set of run statistics rather than using arbitrary cash/token milestones for everything.

Add defaults to `RunState.statistics`:

```text
clean_completions = 0
one_shot_completions = 0
clean_one_shot_completions = 0
cool_completions = 0
hot_one_shot_completions = 0
overkill_2x_completions = 0
bugs_created = 0
hidden_bugs_created = 0
bugs_fixed = 0
hidden_bugs_revealed = 0
```

## 5.1 Completion telemetry

Record completion telemetry at the same point where `WorkflowMasterySystem.evaluate()` has canonical evidence.

Only record in `ResolveMode.COMMIT` and only once per job/mastery evaluation.

Use the same evidence definitions already used by mastery:

- `clean`: no known or hidden bugs were created during the job.
- `one_shot`: `burn_count <= 1`.
- `cool`: peak heat ratio `<= 0.70`.
- `hot_one_shot`: one-shot and hot-start/redline condition. Use the same threshold currently used by the Redline Graduate logic; do not invent a contradictory threshold.
- `overkill_2x`: `overkill_ratio >= 2.0` using the game’s current ratio semantics.

Increment:

```text
mastery evaluation -> no generic count required unless useful
clean -> clean_completions
one_shot -> one_shot_completions
clean && one_shot -> clean_one_shot_completions
cool -> cool_completions
hot && one_shot -> hot_one_shot_completions
overkill_ratio >= 2.0 -> overkill_2x_completions
```

## 5.2 Burn telemetry

On committed burns, aggregate the canonical burn-result counts into run statistics:

```text
bugs_created
hidden_bugs_created
bugs_fixed
hidden_bugs_revealed
```

**Important:** inspect the current burn result keys and use the existing canonical names. Do not add duplicate result fields if the board already calls these `fixed`, `revealed`, etc.

Preview/inspection must not change any of these values.

## 5.3 Achievement context

Expose the new statistics in `AchievementSystem._context()`:

```text
run.clean_completions
run.one_shot_completions
run.clean_one_shot_completions
run.cool_completions
run.hot_one_shot_completions
run.overkill_2x_completions
run.bugs_created
run.hidden_bugs_created
run.bugs_fixed
run.hidden_bugs_revealed
```

Also expose useful statistics that already exist in `RunState.statistics` but are not currently available to achievements:

```text
run.cascades_triggered
run.faults_suffered
run.max_instability
run.peak_overkill
run.lifetime_overkill
```

No OR operator is required for achievements. All achievement conditions below are deliberately expressible using the existing AND list of checks.

Do not add these to lifetime profile counters unless some future achievement actually needs them across runs.

---

# 6. Draft-weight policy

Rarity already affects draft probability. Avoid over-tuning `draft_weight` on every card.

Use these defaults unless a row explicitly says otherwise:

| Rarity | Default `draft_weight` |
|---|---:|
| common | 1.00 |
| uncommon | 0.85 |
| rare | 0.75 |
| legendary | 0.60 |

Veteran “rule-bending” legendary modules (#117–120) may use `0.50`.

Do not make key archetype enablers so rare that the archetype cannot form. Tag affinity should do much of the work once a player has committed to a build.

---

# 7. Achievement-gated modules

Create these new achievements, plus repurpose two existing reward-less achievements.

All new achievements should use the existing achievement JSON schema and reward type:

```json
"reward": {"type": "unlock_module", "module_id": "op.some_module"}
```

The module must set the matching `unlock_achievement`.

## 7.1 New achievements

| Achievement ID | Name | Condition | Unlock |
|---|---|---|---|
| `ach.repo_cartographer` | Repo Cartographer | `run.board_filled >= 5` | `op.repo_map` |
| `ach.vector_search` | Found It in Context | `run.completed_jobs >= 5` AND `run.hidden_bugs_shipped == 0` | `op.vector_index` |
| `ach.dependency_spaghetti` | Dependency Spaghetti | `run.board_filled >= 6` AND `run.stage_repeats >= 5` | `op.dependency_graph` |
| `ach.chaos_prompting` | Temperature: Yes | `run.max_instability >= 0.50` | `op.prompt_mutator` |
| `ach.mixture_of_everything` | Mixture of Everything | `run.modules_owned >= 10` | `op.moe_router` |
| `ach.sparse_operator` | Sparse Operator | `run.max_heat_ratio >= 0.90` AND `run.completed_jobs >= 3` | `op.sparse_expert` |
| `ach.integration_day` | Works on My Machine | `run.completed_jobs >= 6` AND `run.failed_jobs == 0` | `op.integration_tests` |
| `ach.property_owner` | Property Owner | `run.clean_completions >= 3` | `op.property_tests` |
| `ach.fuzzed_prod` | Production Was the Fuzzer | `run.hidden_bugs_created >= 8` | `op.fuzz_tester` |
| `ach.golden_reference` | Golden Reference | `run.clean_one_shot_completions >= 3` | `op.golden_dataset` |
| `ach.graph_capture` | Captured the Graph | `run.stage_repeats >= 15` | `op.cuda_graph` |
| `ach.pinned_down` | Pinned Down | `run.hardware_owned >= 3` | `op.pinned_memory` |
| `ach.cold_operator` | Cold Operator | `run.cool_completions >= 4` | `op.heat_pipe` |
| `ach.code_review` | Reviewed Until It Hurt | `run.bugs_fixed >= 10` | `op.reviewer_agent` |
| `ach.parallel_everything` | Parallel Everything | `run.stage_repeats >= 25` AND `run.cascades_triggered >= 1` | `op.parallel_workers` |
| `ach.watch_this` | Nothing Gets Past Me | `run.hidden_bugs_revealed >= 10` | `op.watchdog_agent` |
| `ach.semantic_reuse` | Seen This Before | `run.one_shot_completions >= 5` | `op.semantic_cache` |
| `ach.canary_keeper` | Canary Still Singing | `run.clean_completions >= 6` AND `run.hidden_bugs_shipped == 0` | `op.canary_release` |

Add flavour copy consistent with the existing achievement file, but do not change these mechanical conditions without a balance reason.

## 7.2 Repurpose existing achievements

These currently have no module reward and fit the new cards well:

### `ach.spotless`

Keep its current condition and copy. Change reward to:

```json
{"type": "unlock_module", "module_id": "op.judge_model"}
```

`op.judge_model.unlock_achievement = "ach.spotless"`.

### `ach.thermal_event`

Keep its current condition and copy. Change reward to:

```json
{"type": "unlock_module", "module_id": "op.thermal_throttle"}
```

`op.thermal_throttle.unlock_achievement = "ach.thermal_event"`.

---

# 8. New module catalogue — 59 cards

## Conventions

- OUTPUT means `stage.progress_mult` unless the card explicitly says throughput/token multiplier.
- QUALITY multiplier means `stage.quality_mult` or `batch.quality_mult` depending on timing.
- THERMAL means `stage.thermal_mult` and therefore reduces positive generated heat using the existing fold semantics.
- Flat quality means `stage.quality`.
- “Clean burn” means `batch.total_bugs_created == 0`.
- A module that intentionally creates then fixes bugs is still **dirty** for mastery.
- Repeats use the existing repeat/fork fields; do not simulate repetitions by multiplying progress directly.
- For random modules, use the deterministic `reroll` operation already supported by the resolver.

---

## 8.1 Prompt / Context — modules 62–71

### 62. System Prompt

```text
id: op.system_prompt
category: prompt
rarity: uncommon
gate: OPEN
min_location_tier: 0
tags: [prompt, context, quality, positional, safe]
badge: NEXT ×1.25
```

**Player text:** `+8 quality. The stage below runs ×1.25 stronger. If this is the first stage, +8 more quality.`

**Effects:**

- `stage.quality += 8`
- `stage.next_multiplier *= 1.25`
- if `$is_first_stage == true`, another `stage.quality += 8`

**Named combo — Stacked Instructions:** if placed after `op.prompt`, +4 additional quality.

---

### 63. Few-Shot Examples

```text
id: op.few_shot_examples
category: context
rarity: common
gate: OPEN
min_location_tier: 0
tags: [context, quality, positional, safe]
badge: NEXT ×1.15
```

**Player text:** `+6 quality. The stage below runs ×1.15 stronger.`

**Effects:**

- `stage.quality += 6`
- `stage.next_multiplier *= 1.15`

**Named combo — Something to Imitate:** if immediately before `op.cheap_model` or `op.small_specialist`, apply another `stage.next_multiplier *= 1.15`.

---

### 64. Repo Map

```text
id: op.repo_map
category: context
rarity: common
gate: ACH ach.repo_cartographer
min_location_tier: 0
tags: [context, quality, positional, scaling]
badge: 4+ NEXT ×1.25
```

**Player text:** `+5 quality. In a pipeline of 4+ stages, the stage below runs ×1.25 stronger.`

**Effects:**

- `stage.quality += 5`
- if `$stage_count >= 4`, `stage.next_multiplier *= 1.25`

---

### 65. Vector Index

```text
id: op.vector_index
category: context
rarity: uncommon
gate: ACH ach.vector_search
min_location_tier: 1
tags: [context, quality, economy, positional]
badge: NEXT −25%
```

**Player text:** `+10 quality. The stage below costs 25% less.`

**Effects:**

- `stage.quality += 10`
- `stage.next_cost_mult *= 0.75`

**Named combo — Indexed Context:** if after `op.large_context`, also `stage.next_multiplier *= 1.20`.

---

### 66. Context Pruner

```text
id: op.context_pruner
category: context
rarity: uncommon
gate: OPEN
min_location_tier: 1
tags: [context, output, cooling, risk]
badge: ×1.25 OUT
```

**Player text:** `×1.25 OUTPUT, ×0.90 QUALITY, ×1.25 THERMAL.`

**Effects:**

- `stage.progress_mult *= 1.25`
- `stage.quality_mult *= 0.90`
- `stage.thermal_mult *= 1.25`

---

### 67. Requirements Doc

```text
id: op.requirements_doc
category: context
rarity: rare
gate: V1
min_location_tier: 1
tags: [context, quality, positional, safe]
badge: FIRST
```

**Player text:** `First stage: +15 quality and the stage below runs ×1.35 stronger. Else +5 quality.`

**Effects:**

- if first: `stage.quality += 15`
- if first: `stage.next_multiplier *= 1.35`
- if not first: `stage.quality += 5`

---

### 68. Dependency Graph

```text
id: op.dependency_graph
category: context
rarity: rare
gate: ACH ach.dependency_spaghetti
min_location_tier: 1
tags: [context, positional, scaling, quality]
badge: MIDDLE ×1.50
```

**Player text:** `+6 quality. If this is neither first nor last, the stage below runs ×1.50 stronger.`

**Effects:**

- `stage.quality += 6`
- if `!$is_first_stage && !$is_last_stage`, `stage.next_multiplier *= 1.50`

---

### 69. Prompt Mutator

```text
id: op.prompt_mutator
category: prompt
rarity: rare
gate: ACH ach.chaos_prompting
min_location_tier: 2
tags: [prompt, output, risk, bugs]
badge: ×?
```

**Player text:** `OUTPUT rerolls between ×0.8 / ×1.0 / ×1.5 / ×2.0. Creates 1 hidden bug.`

**Effects:**

- deterministic reroll `stage.progress_mult` with `[0.8, 1.0, 1.5, 2.0]`
- `stage.hidden_bugs += 1`

---

### 70. Constraint Solver

```text
id: op.constraint_solver
category: context
rarity: rare
gate: V2
min_location_tier: 2
tags: [context, quality, safe, mastery]
badge: CLEAN
```

**Player text:** `×0.90 OUTPUT and ×1.25 QUALITY. If the burn creates no bugs, ×1.15 final OUTPUT.`

**Slot effects:**

- `stage.progress_mult *= 0.90`
- `stage.quality_mult *= 1.25`

**Finalizing:**

- if `batch.total_bugs_created == 0`, `batch.progress_mult *= 1.15`

---

### 71. Memory Palace

```text
id: op.memory_palace
category: context
rarity: legendary
gate: V3
min_location_tier: 3
tags: [context, quality, scaling, positional]
badge: 6+
```

**Player text:** `With 6+ stages: ×1.60 QUALITY and the stage below ×1.50. Otherwise ×1.15 QUALITY.`

**Effects:**

- if `$stage_count >= 6`, `stage.quality_mult *= 1.60`
- if `$stage_count >= 6`, `stage.next_multiplier *= 1.50`
- if `$stage_count < 6`, `stage.quality_mult *= 1.15`

---

## 8.2 Models — modules 72–81

### 72. Small Specialist

```text
id: op.small_specialist
category: model
rarity: common
gate: OPEN
min_location_tier: 0
tags: [model, output, quality]
badge: ×1.30
```

**Player text:** `×1.30 OUTPUT and +6 quality.`

- `stage.progress_mult *= 1.30`
- `stage.quality += 6`

**Named combo — Briefed:** after `op.prompt`, `op.system_prompt` or `op.few_shot_examples`, another `stage.progress_mult *= 1.15`.

---

### 73. MoE Router

```text
id: op.moe_router
category: model
rarity: uncommon
gate: ACH ach.mixture_of_everything
min_location_tier: 1
tags: [model, positional, scaling]
badge: ROUTE
```

**Player text:** `×1.20 OUTPUT and +4 quality. A model directly below runs ×1.25 stronger.`

- `stage.progress_mult *= 1.20`
- `stage.quality += 4`

**Named combo — Routed Expert:** `before` the model IDs in this new/current model family, `stage.next_multiplier *= 1.25`.

Do not apply the next boost to arbitrary tests/hardware; use the combo partner list.

---

### 74. Draft Model

```text
id: op.draft_model
category: model
rarity: uncommon
gate: OPEN
min_location_tier: 1
tags: [model, output, bugs, positional]
badge: ×1.50 +BUG
```

**Player text:** `×1.50 OUTPUT and +1 bug. Before a premium model, that model runs ×1.20 stronger.`

- `stage.progress_mult *= 1.50`
- `stage.bugs += 1`

Combo `before` `op.premium_model`, `op.foundation_model`, `op.world_model`: `stage.next_multiplier *= 1.20`.

---

### 75. Judge Model

```text
id: op.judge_model
category: model
rarity: rare
gate: ACH ach.spotless
min_location_tier: 1
tags: [model, test, quality, bugs, safe]
badge: JUDGE
```

**Player text:** `×0.85 OUTPUT, +20 quality, reveal 1 hidden bug and fix 1 bug.`

- `stage.progress_mult *= 0.85`
- `stage.quality += 20`
- `stage.reveal_bugs += 1`
- `stage.fix_bugs += 1`

---

### 76. Self-Consistency

```text
id: op.self_consistency
category: model
rarity: rare
gate: V1
min_location_tier: 2
tags: [model, recursion, quality, expensive]
badge: REPEAT 60%
```

**Player text:** `Repeat the stage above once at 60% strength. +10 quality, +4 heat, $100.`

- `stage.repeat_previous = 0.60`
- `stage.repeat_count = 1`
- `stage.quality += 10`
- `stage.heat += 4`
- `stage.cost += 100`

---

### 77. Sparse Expert

```text
id: op.sparse_expert
category: model
rarity: uncommon
gate: ACH ach.sparse_operator
min_location_tier: 1
tags: [model, output, hardware, cooling]
badge: ×1.45
```

**Player text:** `×1.45 OUTPUT, ×1.20 THERMAL, ×0.90 QUALITY.`

- progress ×1.45
- thermal ×1.20
- quality ×0.90

---

### 78. Speculative Router

```text
id: op.speculative_router
category: model
rarity: rare
gate: V1
min_location_tier: 2
tags: [model, output, risk, heat]
badge: ×?
```

**Player text:** `OUTPUT rerolls ×0.7 / ×1.4 / ×1.4 / ×1.8. +6 heat.`

- reroll progress with `[0.7, 1.4, 1.4, 1.8]`
- heat +6

---

### 79. Verifier Model

```text
id: op.verifier_model
category: model
rarity: rare
gate: V1
min_location_tier: 2
tags: [model, test, quality, positional]
badge: VERIFY
```

**Player text:** `+14 quality, reveal 1 and fix 1. If this stage catches anything, the stage below runs ×1.30 stronger.`

Slot:

- quality +14
- reveal +1
- fix +1

Folded:

- if `$stage_revealed > 0` or the canonical stage-fixed count is >0, next multiplier ×1.30.

If folded subscriptions cannot express OR, use two subscriptions with ChainGuard-safe equivalent behaviour or choose the single canonical “caught” signal that already exists. Do not add OR syntax just for this card.

---

### 80. Distilled Specialist

```text
id: op.distilled_specialist
category: model
rarity: rare
gate: V2
min_location_tier: 3
tags: [model, output, risk, bugs]
badge: ×1.80
```

**Player text:** `×1.80 OUTPUT and +1 hidden bug. Immediately after Distilled Model, create no hidden bug.`

Base:

- progress ×1.80
- hidden bugs +1

Combo after `op.distillation`:

- hidden bugs −1, leaving zero.

---

### 81. World Model

```text
id: op.world_model
category: model
rarity: legendary
gate: V3
min_location_tier: 4
tags: [model, output, quality, scaling, heat, expensive]
badge: WORLD
```

**Player text:** `Under 6 stages: ×1.50 OUTPUT, +15 quality. At 6+: ×2.30 OUTPUT, +25 quality. +18 heat, expensive.`

Suggested cost: `$500` per batch.

Conditional effects:

- `<6`: progress ×1.50; quality +15
- `>=6`: progress ×2.30; quality +25
- heat +18
- cost +500

---

## 8.3 Test / Quality / Repair — modules 82–91

### 82. Static Analysis

```text
id: op.static_analysis
category: test
rarity: common
gate: OPEN
min_location_tier: 0
tags: [test, quality, bugs]
badge: REVEAL 1
```

`Reveal 1 hidden bug, +5 quality, ×0.95 OUTPUT.`

---

### 83. Integration Tests

```text
id: op.integration_tests
category: test
rarity: uncommon
gate: ACH ach.integration_day
min_location_tier: 1
tags: [test, quality, bugs, safe]
badge: FIX 2
```

`Reveal 2 hidden bugs, fix 2 bugs, +10 quality, ×0.80 OUTPUT.`

---

### 84. Property Tests

```text
id: op.property_tests
category: test
rarity: uncommon
gate: ACH ach.property_owner
min_location_tier: 1
tags: [test, quality, bugs]
badge: REPAIR
```

**Player text:** `Fix 1 bug and +8 quality. If this stage fixes anything, ×1.15 final QUALITY.`

- slot fix +1, quality +8
- folded/finalizing reaction should use canonical fixed evidence; only apply quality multiplier when the stage actually repaired something.

---

### 85. Fuzz Tester

```text
id: op.fuzz_tester
category: test
rarity: uncommon
gate: ACH ach.fuzzed_prod
min_location_tier: 1
tags: [test, bugs, risk, quality]
badge: REVEAL 3
```

`Reveal 3 hidden bugs, create 1 known bug, +5 quality.`

This card is deliberately dirty and is a repair-engine enabler.

---

### 86. Mutation Testing

```text
id: op.mutation_testing
category: test
rarity: rare
gate: V1
min_location_tier: 2
tags: [test, bugs, quality, risk]
badge: MUTATE
```

**Player text:** `Create 2 bugs, then fix up to 3. If this stage fixes both injected bugs, ×1.50 final QUALITY.`

- `stage.bugs += 2`
- `stage.fix_bugs += 3`
- finalizing/folded condition should verify at least two fixes attributable to the stage/burn using canonical evidence.
- quality multiplier ×1.50 on success.

**Important:** the job is still dirty for mastery because bugs were created.

---

### 87. Golden Dataset

```text
id: op.golden_dataset
category: test
rarity: rare
gate: ACH ach.golden_reference
min_location_tier: 1
tags: [test, quality, safe, mastery]
badge: CLEAN ×1.30
```

- quality +12
- finalizing if `batch.total_bugs_created == 0`: `batch.quality_mult *= 1.30`

---

### 88. Canary Test

```text
id: op.canary_test
category: test
rarity: rare
gate: V1
min_location_tier: 2
tags: [test, safe, positional, quality]
badge: NO HIDDEN
```

**Player text:** `+6 quality. The stage below creates no hidden bugs but runs ×0.95 OUTPUT.`

Mirror `op.ecc_memory`:

- `stage.next_multiplier *= 0.95`
- `stage.next_block_hidden += 1`
- own quality +6

---

### 89. Formal Verification

```text
id: op.formal_verification
category: test
rarity: legendary
gate: V5
min_location_tier: 4
tags: [test, quality, bugs, safe, expensive]
badge: PROVE
```

**Player text:** `Reveal and fix everything. ×2 QUALITY, ×0.45 OUTPUT. Extremely expensive.`

Implementation:

- reveal a deliberately huge safe number, e.g. 999
- fix known bugs 999
- fix hidden bugs 999 if the resolver supports it independently
- quality multiplier ×2.0
- progress ×0.45
- cost +1000

Do not introduce an “infinity” sentinel unless one already exists.

---

### 90. Snapshot Tests

```text
id: op.snapshot_tests
category: test
rarity: common
gate: OPEN
min_location_tier: 0
tags: [test, quality, positional]
badge: LAST +20Q
```

- quality +5
- if last stage, another +15 quality.

---

### 91. Root Cause Analysis

```text
id: op.root_cause_analysis
category: test
rarity: rare
gate: V2
min_location_tier: 2
tags: [test, bugs, quality, cooling]
badge: RCA
```

**Player text:** `Fix 2 bugs. If this stage fixes anything, ×1.25 QUALITY and ×1.15 THERMAL.`

Base fix +2; folded conditional on actual stage fixes applies the two multipliers.

---

## 8.4 Hardware / Thermal — modules 92–101

### 92. Kernel Fusion

```text
id: op.kernel_fusion
category: hardware
rarity: uncommon
gate: OPEN
min_location_tier: 1
tags: [hardware, output, heat, local]
badge: ×1.40
```

`×1.40 OUTPUT, +10 heat.`

---

### 93. CUDA Graph

```text
id: op.cuda_graph
category: hardware
rarity: rare
gate: ACH ach.graph_capture
min_location_tier: 2
tags: [hardware, output, scaling, positional]
badge: 5+
```

`With 5+ stages: ×1.60 OUTPUT and +6 heat. Otherwise ×0.90 OUTPUT.`

Mirror the conditional shape of `op.batch_scheduler`.

---

### 94. Pinned Memory

```text
id: op.pinned_memory
category: hardware
rarity: uncommon
gate: ACH ach.pinned_down
min_location_tier: 1
tags: [hardware, output, economy, local]
badge: ×1.15
```

- progress ×1.15
- next cost ×0.80
- heat +3

---

### 95. HBM Burst

```text
id: op.hbm_burst
category: hardware
rarity: rare
gate: V1
min_location_tier: 2
tags: [hardware, output, heat, cooling, risk]
badge: ×1.80
```

- output ×1.80
- heat +20
- if burn/current stage heat ratio is below 0.50 when resolved, thermal ×1.40.

Use the same `$heat_ratio` convention as `op.power_limit`.

---

### 96. Fan Wall

```text
id: op.fan_wall
category: hardware
rarity: common
gate: OPEN
min_location_tier: 0
tags: [hardware, cooling, safe, local]
badge: −12H
```

`−12 heat, ×0.95 OUTPUT.`

---

### 97. Heat Pipe

```text
id: op.heat_pipe
category: hardware
rarity: common
gate: ACH ach.cold_operator
min_location_tier: 1
tags: [hardware, cooling, local]
badge: ×1.35 T
```

`×1.35 THERMAL for $8 per batch.`

---

### 98. Phase Change Cooling

```text
id: op.phase_change
category: hardware
rarity: legendary
gate: V3
min_location_tier: 3
tags: [hardware, cooling, safe, expensive, local]
badge: −30H
```

`−30 heat, ×2 THERMAL, ×0.75 OUTPUT, $150 per batch.`

---

### 99. Emergency Throttle

```text
id: op.thermal_throttle
category: hardware
rarity: uncommon
gate: ACH ach.thermal_event
min_location_tier: 1
tags: [hardware, cooling, safe, positional]
badge: 80%
```

**Player text:** `Below 80% heat: ×1.15 OUTPUT. At 80%+: ×0.65 OUTPUT but ×4 THERMAL.`

Two conditional branches using `$heat_ratio`.

---

### 100. Voltage Spike

```text
id: op.voltage_spike
category: hardware
rarity: rare
gate: V2
min_location_tier: 3
tags: [hardware, output, heat, risk, bugs]
badge: ×2.20
```

- output ×2.20
- heat +30
- hidden bugs +1

---

### 101. Cold Boot

```text
id: op.cold_boot
category: hardware
rarity: rare
gate: V2
min_location_tier: 2
tags: [hardware, cooling, output, quality, risk]
badge: ≤25%
```

**Player text:** `At ≤25% heat: ×1.80 OUTPUT and +12 quality. Otherwise ×0.75 OUTPUT.`

Use `$heat_ratio <= 0.25` and complementary condition.

---

## 8.5 Agent / Recursion — modules 102–109

### 102. Planner Agent

```text
id: op.planner_agent
category: agent
rarity: common
gate: OPEN
min_location_tier: 0
tags: [agent, context, quality, positional]
badge: NEXT ×1.30
```

`+4 quality; stage below ×1.30.`

---

### 103. Reviewer Agent

```text
id: op.reviewer_agent
category: agent
rarity: uncommon
gate: ACH ach.code_review
min_location_tier: 1
tags: [agent, recursion, test, bugs]
badge: REPEAT 35%
```

- repeat previous once at 35%
- fix 1 bug

This is intentionally a recursion card for quality/repair builds.

---

### 104. Parallel Workers

```text
id: op.parallel_workers
category: agent
rarity: rare
gate: ACH ach.parallel_everything
min_location_tier: 2
tags: [agent, recursion, output, heat]
badge: FORK ×2
```

**Player text:** `Run two forks of the stage above at 45% each. +12 heat.`

- repeat strength 0.45
- repeat count 2
- heat +12

Use the same semantics as the existing fork module: two 45% repeats, not one 90% fold.

---

### 105. Watchdog Agent

```text
id: op.watchdog_agent
category: agent
rarity: uncommon
gate: ACH ach.watch_this
min_location_tier: 1
tags: [agent, recursion, test, bugs]
badge: WATCH
```

- repeat previous once at 25%
- reveal 1 hidden bug

---

### 106. Self-Critique

```text
id: op.self_critique
category: agent
rarity: rare
gate: V1
min_location_tier: 2
tags: [agent, recursion, quality]
badge: REPEAT 60%
```

- repeat previous at 60%, count 1
- quality +12
- own progress ×0.90

---

### 107. Tree Search

```text
id: op.tree_search
category: agent
rarity: legendary
gate: V3
min_location_tier: 3
tags: [agent, recursion, output, heat, expensive]
badge: FORK ×3
```

- repeat previous at 40%
- repeat count 3
- heat +25
- cost +300

---

### 108. Backtracking Agent

```text
id: op.backtracking_agent
category: agent
rarity: rare
gate: V1
min_location_tier: 2
tags: [agent, recursion, test, bugs]
badge: BACKTRACK
```

- repeat previous at 50%
- count 1
- fix 1 known bug

---

### 109. Autonomous Loop

```text
id: op.autonomous_loop
category: agent
rarity: legendary
gate: H1
min_location_tier: 4
tags: [agent, recursion, cascade, output, heat, risk, bugs]
badge: LOOP
```

**Player text:** `Repeat the stage above at 100%, +25% cascade chance, +25% repeat/cascade strength, +30 heat and +1 hidden bug.`

Implementation using existing primitives:

- repeat previous = 1.0
- repeat count = 1
- `stage.cascade_chance += 0.25`
- use existing repeat/cascade strength target to multiply/set approximately 1.25 relative strength without adding a new system
- heat +30
- hidden bug +1

If `repeat_strength` is already derived from `repeat_previous`, do not double-apply. Inspect the existing fork/cascade implementation and express exactly one intended +25% strength bonus.

---

## 8.6 Cache / Deploy / Positional — modules 110–116

### 110. Prefix Cache

```text
id: op.prefix_cache
category: cache
rarity: common
gate: OPEN
min_location_tier: 0
tags: [cache, economy, positional]
badge: NEXT −30%
```

- next cost ×0.70
- next strength ×1.10

---

### 111. Semantic Cache

```text
id: op.semantic_cache
category: cache
rarity: uncommon
gate: ACH ach.semantic_reuse
min_location_tier: 1
tags: [cache, quality, economy, positional]
badge: CACHE
```

- quality +8
- quality multiplier ×1.10
- next cost ×0.75

---

### 112. KV Cache

```text
id: op.kv_cache
category: cache
rarity: rare
gate: V1
min_location_tier: 2
tags: [cache, output, hardware, cooling]
badge: ×1.25
```

- output ×1.25
- thermal ×1.25

**Named combo — Long Context Cache:** after `op.large_context`, another output ×1.20.

---

### 113. Canary Release

```text
id: op.canary_release
category: deploy
rarity: uncommon
gate: ACH ach.canary_keeper
min_location_tier: 1
tags: [deploy, safe, quality, risk]
badge: CLEAN
```

Finalizing:

- clean burn -> quality ×1.20
- dirty burn -> output ×0.85

Mirror `op.clean_room_gate` structure.

---

### 114. Blue/Green Deploy

```text
id: op.blue_green
category: deploy
rarity: rare
gate: V1
min_location_tier: 2
tags: [deploy, safe, quality, output, expensive]
badge: BLUE/GREEN
```

**Player text:** `If no hidden bugs remain at finalization: ×1.15 OUTPUT and ×1.15 QUALITY. $100.`

Use the canonical final batch hidden-bug field. Do not check merely “hidden bugs created”; this card cares whether hidden defects remain.

---

### 115. Rollback Plan

```text
id: op.rollback_plan
category: deploy
rarity: uncommon
gate: V2
min_location_tier: 2
tags: [deploy, test, safe, bugs]
badge: ROLLBACK
```

- reveal/fix one hidden bug using the canonical hidden-fix path
- quality +8
- output ×0.90

If a hidden bug must be revealed before it can be fixed, use reveal 1 then fix 1 in the same stage rather than bypassing the bug model.

---

### 116. Friday Deploy

```text
id: op.friday_deploy
category: deploy
rarity: rare
gate: V3
min_location_tier: 3
tags: [deploy, output, heat, risk, bugs, positional]
badge: FRIDAY
```

**Player text:** `Last stage: ×2 OUTPUT, +15 heat and +1 hidden bug. Else only ×1.05 OUTPUT.`

Conditional effects on `$is_last_stage`.

---

## 8.7 Veteran insanity — modules 117–120

These are intentionally rule-bending. Use `draft_weight: 0.50`.

### 117. Singularity Cache

```text
id: op.singularity_cache
category: cache
rarity: legendary
gate: V5
min_location_tier: 4
tags: [cache, positional, output, risk]
badge: NEXT ×3
```

**Player text:** `First stage: this runs ×0.50 OUTPUT but the stage below ×3. Otherwise ×1.20 OUTPUT. +10 heat.`

- first: progress ×0.50 and next ×3.0
- not first: progress ×1.20
- heat +10

---

### 118. Thermodynamic Computer

```text
id: op.thermodynamic_computer
category: hardware
rarity: legendary
gate: H1
min_location_tier: 5
tags: [hardware, output, heat, risk, local]
badge: REDLINE
```

**Player text:** `Below 85% heat: ×0.50 OUTPUT. 85–100%: ×2 OUTPUT. At/above the redline: ×4 OUTPUT but ×0.50 THERMAL.`

Implement three mutually exclusive heat bands using the game’s canonical heat ratio. If the runtime clamps heat to 1.0, interpret the third band as the existing full/redline condition rather than inventing an impossible `>1.0` check.

This card must be tested against the actual heat-cap behaviour before final copy is locked.

---

### 119. Proof-Carrying Code

```text
id: op.proof_carrying_code
category: test
rarity: legendary
gate: V5
min_location_tier: 4
tags: [test, quality, mastery, safe]
badge: +Q MASTERY
```

**Player text:** `×0.70 OUTPUT, +20 quality. A clean completion permanently trains this workflow +0.04 QUALITY.`

Slot:

- progress ×0.70
- quality +20

Completion effect:

- if `$clean == true`, `mastery.quality_gain += 0.04`

Use the existing completion/mastery dispatch; do not mutate the workflow directly from the card.

---

### 120. Benchmark Daemon

```text
id: op.benchmark_daemon
category: test
rarity: legendary
gate: H3
min_location_tier: 6
tags: [test, output, mastery, overkill]
badge: +OUT MASTERY
```

**Player text:** `×1.20 OUTPUT. A one-shot completion trains +0.03 OUTPUT; if it also reaches 2× overkill, train another +0.02.`

Slot:

- progress ×1.20

Completion effects:

- if `$one_shot == true`, `mastery.output_gain += 0.03`
- if `$one_shot == true && $overkill_ratio >= 2.0`, another `mastery.output_gain += 0.02`

This deliberately stacks with mastery perks.

---

# 9. Unlock distribution check

The 59 additions should resolve to:

| Gate | Count |
|---|---:|
| OPEN | 11 |
| achievement | 20 |
| 1 victory | 11 |
| 2 victories | 6 |
| 3 victories | 5 |
| 5 victories | 3 |
| 1 Hard victory | 2 |
| 3 Hard victories | 1 |
| **Total** | **59** |

Do not accidentally expose victory-gated modules simply because their location is available.

The fresh profile should therefore gain only the OPEN portion of the new set, and location tiers reduce that further.

---

# 10. Rarity distribution of the 59 additions

Expected approximate distribution:

| Rarity | Count |
|---|---:|
| common | 9 |
| uncommon | 17 |
| rare | 23 |
| legendary | 10 |
| **Total** | **59** |

This looks top-heavy in isolation because much of this pass is veteran content. That is intentional: the existing pool already contains the basic/starter layer, and many of the new rares/legendaries are locked for several runs.

Do not rebalance rarity counts purely to make the table symmetrical. Balance actual draft frequency using rarity weights, unlock gates and location gates.

---

# 11. Tag policy

Reuse existing tags wherever possible so the current affinity/synergy systems immediately understand the cards.

Core tags to reuse:

```text
prompt
context
model
test
hardware
agent
cache
deploy
output
quality
heat
cooling
risk
safe
bugs
recursion
cascade
positional
scaling
economy
local
expensive
mastery
overkill
```

Tags are not card categories. A card should carry every identity that should matter to draft affinity and tag-density synergies, but do not add decorative tags that no system or future design will ever use.

Do not change the existing global tag-density synergy model during this pass.

---

# 12. Named combo policy

Do not force a named adjacency combo onto all 59 cards. Use named combos where adjacency is part of the card’s fantasy and where the player should be taught to arrange the pipeline deliberately.

Required named combos from this brief:

```text
System Prompt + Hand-Written Prompt -> Stacked Instructions
Few-Shot Examples -> Cheap Model / Small Specialist -> Something to Imitate
Vector Index after Large Context -> Indexed Context
Small Specialist after prompt/context -> Briefed
MoE Router before models -> Routed Expert
Draft Model before premium/foundation/world model -> Draft and Verify
Distilled Specialist after Distilled Model -> Distilled Twice
KV Cache after Large Context -> Long Context Cache
```

Use the module `combos` array as the source of truth so tooltips and mechanics cannot drift apart.

Add more combos only when they create an interesting positional decision, not as free bonus text.

---

# 13. UX requirement for victory-gated cards

Achievement-gated cards already have achievement UI. Direct victory gates need at least minimal player feedback.

Inspect the existing run-end / legacy screens and implement the smallest clean solution:

- when a victory count crosses 1, 2, 3, 5 or Hard 1/3, show a compact line such as:

```text
NEW MODULES ADDED TO ANGEL POOL: Requirements Doc, Self-Consistency, ...
```

or provide equivalent visibility in an existing module/legacy gallery.

Do **not** build a new full-screen progression system solely for this.

The player must be able to understand why a card was unavailable previously and why new cards have appeared.

If there is a locked module detail surface, display:

```text
Win 2 runs to unlock
Win Hard once to unlock
Earn achievement: Golden Reference
Requires Office Unit or later
```

Combine requirements when multiple gates apply.

---

# 14. Content validation changes

Strengthen validation while the catalogue grows.

Required checks:

1. Exactly one module per ID.
2. Every new module has non-empty name/category/rarity/description/tags.
3. Category is one of the existing supported categories.
4. Rarity is valid.
5. `min_location_tier >= 0`.
6. `max_location_tier == -1` or `>= min_location_tier`.
7. `min_victories >= 0`.
8. `min_hard_victories >= 0`.
9. `draft_weight > 0`.
10. Every combo partner exists.
11. Every effect operation is supported.
12. Every effect target is supported.
13. Validate effects in **all four** effect collections:
    - `slot_effects`
    - `folded_effects`
    - `finalizing_effects`
    - `completion_effects`
14. A module should count as mechanically non-empty if **any** of those four collections or `combos` contains effects. Do not falsely reject a folded-only module.
15. Every `unlock_achievement` exists.
16. Every achievement-gated module is actually the module rewarded by that achievement.
17. No achievement reward points to a missing module.
18. Parameters referenced as `$foo` exist.
19. Percentage copy/parameters follow existing content validation conventions.
20. Assert final module count is 120 **only if the baseline catalogue remains 61 when implementing this brief**. If main has legitimately gained modules since this document was written, do not delete them to satisfy the number. In that case report the new total and keep all 59 additions unless there is an ID/design conflict.

---

# 15. Test plan

## 15.1 Meta-progression gates

Add tests proving:

- fresh profile cannot draw V1/V2/V3/V5/H1/H3 modules;
- after 1 normal victory, all V1 modules become eligible and V2+ remain locked;
- after 2 victories, V2 unlocks;
- after 3 victories, V3 unlocks;
- after 5 victories, V5 unlocks;
- a Hard victory unlocks H1;
- three Hard victories unlock H3;
- Hard victory counts also contribute to normal total victories through the current profile semantics; do not double-count manually;
- achievement and victory requirements AND together if a future card uses both.

Do not make tests rely on random drafts to prove eligibility. Prefer direct `module_is_unlocked()` assertions plus one draw-pool integration test.

## 15.2 Achievement telemetry

Tests must prove:

- preview/inspect does not increment any new telemetry;
- a clean completion increments `clean_completions` once;
- a one-shot increments `one_shot_completions` once;
- clean one-shot increments the combined stat once;
- created-then-fixed remains dirty and does not increment clean completion;
- cool completion uses peak-heat evidence consistently with mastery;
- 2× overkill increments once;
- repeated mastery evaluation cannot double-count completion telemetry;
- committed burns aggregate bugs created/fixed/revealed correctly.

## 15.3 Achievement unlocks

For each new achievement, content validation should establish that the target module exists. Add focused behavioural tests for the new telemetry-based achievements rather than 18 near-identical tests.

At minimum explicitly test:

- `ach.property_owner`
- `ach.fuzzed_prod`
- `ach.golden_reference`
- `ach.cold_operator`
- `ach.code_review`
- `ach.watch_this`

Also update existing tests for:

- `ach.spotless` now rewards `op.judge_model`;
- `ach.thermal_event` now rewards `op.thermal_throttle`.

## 15.4 Canonical module mechanics

Add deterministic canonical-build tests for at least these representative cards:

### Context / positional

- Requirements Doc gets first-stage bonus only when first.
- Dependency Graph gets middle bonus only when neither first nor last.
- Memory Palace switches at 6 stages.

### Random

- Prompt Mutator produces deterministic result for a known seed.
- Speculative Router produces deterministic result for a known seed.

### Repair

- Mutation Testing creates bugs, fixes them, gets repair QUALITY bonus, and still counts dirty for mastery.
- Formal Verification clears a deliberately dirty job/burn.
- Canary Test blocks hidden bugs on the next stage.

### Thermal

- Cold Boot receives the cold bonus below threshold and penalty above.
- Emergency Throttle changes branch at 80% heat.
- HBM Burst applies its cold-side thermal bonus correctly.

### Recursion

- Parallel Workers produces **two 45% forks**, not one 90% repeat.
- Tree Search produces 3 × 40% repeats.
- Autonomous Loop repeats once and adds cascade chance without double-scaling repeat strength.

### Deploy

- Friday Deploy gets ×2 only in the last slot.
- Blue/Green checks final hidden bugs remaining, not created-bug history.

### Mastery

- Proof-Carrying Code adds +0.04 QUALITY mastery on clean completion only.
- Benchmark Daemon adds +0.03 OUTPUT for one-shot and +0.02 more for 2× overkill.
- These completion gains interact correctly with Knowledge Sharing, Specialist Silos, Golden Path and existing mastery gain multipliers.

### Veteran heat edge case

- Thermodynamic Computer must have explicit tests for all reachable heat bands based on actual heat-clamp semantics. Adjust player copy if “above 100%” is not a representable runtime state.

---

# 16. Balance guardrails

These numbers are initial balance targets, not sacred constants. However, do not perform an unrelated global rebalance while adding the cards.

Use the following rules:

1. **Commons teach one thing.** Avoid multi-clause commons except simple positional behaviour.
2. **Uncommons establish engines.** They may bridge two archetypes.
3. **Rares reward conditions or demand a trade-off.** Avoid “same card but +30% more.”
4. **Legendaries alter how the player evaluates the pipeline.** They should not merely be best-in-slot stat bundles.
5. Multiplicative cards with no downside should be modest.
6. ×2+ OUTPUT generally needs heat, bugs, cost, position, pipeline length, low probability or a severe unlock gate.
7. Quality cards should not accidentally soften negative quality penalties; preserve the current positive-quality multiplier semantics.
8. Thermal multipliers should only mitigate positive heat generation; preserve negative cooling as cooling.
9. Created-then-fixed bugs must continue to count as created for clean/mastery evidence.
10. Random cards must use deterministic RNG.
11. New mastery modules should dispatch through `workflow.mastery_evaluated`; never edit workflow multipliers directly.
12. Do not let Hardware Discount begin stacking again while touching completion effects.

---

# 17. Expected build interactions

After this pass, these builds should be possible with meaningful internal choices.

## Clean Compiler

Example pieces:

```text
Requirements Doc
Few-Shot Examples
Judge Model
Golden Dataset
Canary Test
Blue/Green Deploy
Proof-Carrying Code
Clean Room Gate
Regression Suite
```

Goal: clean completions, multiplicative quality and permanent QUALITY mastery.

## Repair Engine

```text
Cheap Model
Fuzz Tester
Mutation Testing
Reviewer Agent
Root Cause Analysis
Regression Suite
Gold Master
```

Goal: deliberately generate defects, then earn more from repairing them than a clean pipeline would have earned by avoiding them.

## Cold Rig

```text
Context Pruner
Sparse Expert
Fan Wall
Heat Pipe
Undervolt
Power Limit
Phase Change Cooling
Cold Boot
HBM Burst
```

Goal: hold heat low and convert thermal discipline into output.

## Redline Degenerate

```text
Overclock
Power Virus
Voltage Spike
Autonomous Loop
Thermodynamic Computer
Redline Graduate
```

Goal: operate near maximum heat where normal builds become unsafe.

## Recursive QA

```text
Reviewer Agent
Watchdog Agent
Backtracking Agent
Self-Critique
Verifier Model
Regression Suite
```

Goal: repeats are used to inspect/repair rather than only multiply output.

## Long Pipeline / Context Engine

```text
System Prompt
Repo Map
Vector Index
Dependency Graph
Memory Palace
MoE Router
World Model
CUDA Graph
Batch Scheduler
```

Goal: spend slots preparing a huge downstream stage and benefit from 5+/6+ scaling.

## One-Shot Benchmark

```text
Benchmark Harness
Benchmark Daemon
Cold Boot / Redline burst cards
First Try
Benchmark Chaser
Perpetual Benchmark
```

Goal: massive initial burn, overkill, workflow OUTPUT training.

## Friday Shipping

```text
Ship It
Draft Model
Prompt Mutator
Friday Deploy
Canary Release
Rollback Plan
```

Goal: convert quality/output aggressively and accept deployment risk.

These lists are not recipes that must always win. They are checks that the pool contains enough overlapping support for the archetype to emerge.

---

# 18. Implementation order

Cursor should implement in this order.

## Phase A — progression and telemetry

1. Add `min_victories` / `min_hard_victories` to module schema.
2. Update module loader and `module_is_unlocked()`.
3. Add gate validation.
4. Add new run telemetry defaults.
5. Record telemetry from canonical COMMIT paths only.
6. Expose telemetry/existing useful stats to achievements.
7. Add/update tests for these systems.

Do not start authoring 59 cards until Phase A tests pass.

## Phase B — achievement content

1. Add the 18 new achievements.
2. Repurpose `ach.spotless` and `ach.thermal_event` rewards.
3. Add achievement validation/tests.

## Phase C — module content in families

Add and test modules in these batches:

1. Prompt/Context 62–71
2. Models 72–81
3. Test/Repair 82–91
4. Hardware/Thermal 92–101
5. Agent/Recursion 102–109
6. Cache/Deploy 110–116
7. Veteran 117–120

Run content validation after each family rather than adding all 59 and debugging one giant JSON failure.

## Phase D — canonical tests

Add representative mechanic tests listed in §15.4.

## Phase E — unlock UX

Add minimal victory-gate feedback to the existing run-end/gallery surface.

## Phase F — final verification

Run the complete test suite and fix content/logic failures. Do not suppress validation to make the catalogue load.

---

# 19. Acceptance criteria

The task is complete when all of the following are true:

- [ ] Existing 61 baseline modules remain intact unless there is a documented conflict.
- [ ] All 59 new module IDs exist exactly once.
- [ ] Target catalogue is 120 if baseline is still 61.
- [ ] New modules load through `ContentDatabase` without bespoke registration.
- [ ] `min_victories` and `min_hard_victories` gates work.
- [ ] Fresh profiles do not see veteran modules.
- [ ] Achievement-gated modules remain absent until their achievement is earned.
- [ ] Location gates still apply in addition to meta gates.
- [ ] Achievement rewards and module `unlock_achievement` values agree.
- [ ] New telemetry changes only on COMMIT.
- [ ] Preview/inspect remains mutation-free.
- [ ] Created-then-fixed is still dirty for clean/mastery checks.
- [ ] Random cards are deterministic under seeded tests.
- [ ] Fork cards create the intended number of separate repeats.
- [ ] New completion/mastery cards use the effect resolver and mastery event.
- [ ] No retired Cloud module/system is reintroduced.
- [ ] No Hardware Discount stacking regression is introduced.
- [ ] Content validation checks folded effects as well as slot/finalizing/completion effects.
- [ ] All canonical tests pass.
- [ ] Full project test suite passes.
- [ ] Player can see why victory-gated cards are locked/unlocked.

---

# 20. Explicit non-goals

Do not use this task as an excuse to:

- rewrite `BoardSystem`;
- replace the effect resolver;
- redesign perks;
- change global tag-density synergy semantics;
- add Cloud back;
- redesign the job economy;
- change the save system unnecessarily;
- globally rebalance all existing 61 modules;
- add card-specific script classes when JSON can express the mechanic;
- add a new progression currency;
- expose all 120 cards on a fresh profile.

---

# 21. Final note for implementation

The intended experience is that the card pool becomes **stranger**, not merely stronger, as the player wins more runs.

A new player should understand:

```text
Prompt -> Model -> Test -> Ship
OUTPUT vs QUALITY vs HEAT
```

A veteran should eventually be asking questions like:

```text
Can I intentionally generate four defects, repair all of them, recurse the repair stage,
finish in one burn, hit 2x overkill, stay under 70% heat and train the workflow twice?
```

That is the target for the expanded Token Burn deck-builder.

