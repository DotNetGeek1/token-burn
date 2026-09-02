# Token Burn — Progression Refactor Plan

## Goal

Simplify Token Burn into a clear roguelike progression structure:

**Contracts → cash → improve the current rig → qualify for Ascension → beat the Ascension Contract → unlock the next location → start a fresh run.**

The player should no longer purchase Bedroom → Garage → Office → Warehouse etc. during a run.

Instead:

* A run starts in one fixed location.
* That location defines available space, environmental cooling, rent/overheads, hardware tier and other constraints.
* Cash earned during a run is spent on improving the rig inside that location.
* Each location has one primary Ascension objective.
* Beating Ascension wins the run and permanently unlocks the next location.
* New locations may also unlock new hardware, cooling, modules, contracts, perks and mechanics.

Target campaign:

1. Bedroom
2. Garage
3. Office Unit
4. Warehouse
5. Data Centre Campus
6. Private Power Grid
7. Moon Facility

Do not rebalance the entire economy as part of this work. First make the progression model structurally correct, then balance it separately.

---

# Phase 1 — Separate Meta Progression From Run State

## Objective

Introduce persistent campaign progression that exists outside `RunState`.

Currently the dwelling is stored in:

`run_state.build["dwelling"]`

and locations are normal purchasable upgrades.

Change the model so the selected location is determined when a run begins.

## Add a persistent profile/campaign state

Create an appropriate persistent structure, e.g.:

`ProfileState` / `MetaProgressionState`

It should contain at minimum:

```text
unlocked_locations
selected_location
completed_location_ids
meta_unlocks
```

Initial state:

```text
unlocked_locations = ["bedroom"]
selected_location = "bedroom"
completed_location_ids = []
```

The exact class/file should follow the existing save architecture rather than introducing a second unrelated persistence mechanism.

## RunState

Keep a location identifier in the current run, but treat it as immutable during normal gameplay:

```text
run_state.build["dwelling"]
```

may remain for compatibility if changing its name would cause excessive churn.

However, normal gameplay must no longer mutate it through shop purchases.

When starting/resetting a run, copy the selected unlocked location from persistent progression into the new `RunState`.

## Save migration

Existing saves must not crash.

For existing saves:

* preserve their current dwelling as the current run location;
* determine which previous locations should count as unlocked;
* migrate safely to the new profile representation;
* do not silently wipe meta unlocks or achievements.

Add/advance save version as needed.

## Acceptance criteria

* A fresh profile starts in Bedroom.
* Starting a run sets the run location from persistent progression.
* The location cannot change through normal Market purchases.
* Restarting a run retains permanently unlocked locations.
* Old saves load without errors.

---

# Phase 2 — Remove Dwelling Purchases From The Market

## Objective

Locations are chapters, not economic purchases.

Current dwelling upgrades such as:

* `upgrade.garage`
* `upgrade.office_unit`
* `upgrade.warehouse`
* `upgrade.datacentre_campus`
* `upgrade.private_power_grid`
* `upgrade.moon_facility`

must no longer be offered as normal Market purchases.

Do not necessarily delete their definitions immediately if doing so makes migration difficult.

Prefer one of:

1. mark them as legacy/non-market content; or
2. remove them from the normal Market eligibility path.

Remove the progression dependency where higher hardware effectively requires purchasing all previous premises during the same run.

Hardware should instead be gated by the run's fixed location tier.

For example:

* GPU Rack requires Garage or better.
* Compute Cluster requires Office or better.
* Garage Data Centre requires Warehouse or better.
* Compute Warehouse requires Data Centre Campus or better.
* Industrial Campus requires Private Power Grid or better.

Existing `requires_dwelling` semantics can probably still be reused for this.

## Important

Do not remove hardware upgrades, cooling upgrades, components or workflow upgrades.

Those remain the primary economic progression **inside** a run.

## Acceptance criteria

* Garage/Office/Warehouse/etc. never appear as normal purchasable Market cards.
* A Bedroom run cannot buy its way into Garage.
* Hardware inappropriate to the selected location remains unavailable.
* Hardware appropriate to the selected location is still purchased normally.

---

# Phase 3 — Make Location Stats Derived And Fix Cooling

## Objective

A location should provide environmental constraints rather than permanently mutating aggregate cooling.

Currently moving premises adds the new dwelling's cooling to the existing `compute.cooling`.

That can accidentally accumulate:

Bedroom + Garage + Office + Warehouse cooling.

Replace this with a derived cooling model.

Conceptually:

```text
total_cooling =
    location_base_cooling
    + installed_cooling
    + perk/effect modifiers
```

The currently selected location should contribute exactly one environmental cooling value.

Consider storing separate values:

```text
compute.location_cooling
compute.installed_cooling
compute.cooling
```

or otherwise provide a reliable recalculation method.

`compute.cooling` should ultimately be derived rather than being vulnerable to repeated additions caused by moving/reloading/purchasing.

Apply the same principle where useful to:

* hardware slots;
* location rent;
* environmental capacity;
* future power limits.

## Acceptance criteria

For a Warehouse run:

```text
base environmental cooling = warehouse cooling
```

not:

```text
bedroom + garage + office + warehouse
```

Buying and selling cooling equipment changes installed cooling correctly.

Save/load does not duplicate cooling.

Restarting/recalculating does not change cooling unexpectedly.

---

# Phase 4 — Replace The Three-Rung Ascension Ladder With One Run Boss

## Objective

Ascension becomes the visible objective of each run rather than an in-run three-tier progression ladder.

The current `AscensionSystem` has:

* `FINAL_TIER`
* `highest_tier_completed`
* `current_rung`
* `complete_rung`
* `pending_picks`
* tier filtering

These concepts should be removed or simplified.

## New model

Each location identifies one or more Ascension Contracts valid for that location.

For the first implementation, use one primary contract per location.

Suggested mapping:

```text
Bedroom
    → First Scale-Up / introductory equivalent

Garage
    → Million Token Operator

Office Unit
    → stronger scaling contract

Warehouse
    → Data Centre Magnate

Data Centre Campus
    → National Backbone

Private Power Grid
    → The Monopoly

Moon Facility
    → The Final Prompt
```

Exact names/numbers can be adjusted later.

The existing alternate finale concepts:

* The Singularity
* The Archive
* The Simulation
* The Ad Machine

should be retained for later post-game/alternate victory modes rather than deleted.

## Ascension qualification

Qualification should be based on useful run milestones such as:

```text
minimum cumulative income
minimum peak/sustained throughput
minimum round
possibly reputation or another location-specific condition
```

Infrastructure tier should usually NOT be a qualification objective anymore because the location itself already establishes the infrastructure chapter.

## Ascension flow

```text
not qualified
→ qualified
→ player explicitly commits
→ Final Burn
→ success or failure
```

Success means:

```text
run victory
location completed
next location unlocked
meta rewards granted
```

There is no Tier 1 success followed by Tier 2 in the same run.

## Failure

Failing the Ascension Contract should have an explicit rule.

Prefer for now:

* failed Ascension ends the run;

or, if the current game already strongly supports recovery:

* failed Ascension returns to the run with a meaningful penalty.

Pick one clear rule and test it consistently.

Do not leave ambiguous half-reset Ascension state.

## Acceptance criteria

* Every run has exactly one current Ascension target.
* No `1 / 3`, `2 / 3`, `3 / 3` ladder remains in the primary run.
* Completing Ascension wins the run.
* Winning unlocks the next location.
* A new run starts fresh economically in that newly available location.

---

# Phase 5 — Make Ascension The Visible Run Goal

## Objective

The player should understand from Round 1 what they are trying to build toward.

Add a persistent Ascension/qualification summary to the main game UI.

Example:

```text
GARAGE ASCENSION

Million Token Operator
Burn: 50B

QUALIFICATION

Revenue       $82k / $100k
Peak Compute  31M / 40M
Reputation    22 / 25
Available     Round 4

2 / 4 requirements met
```

Once qualified:

```text
ASCENSION READY
```

and offer a clear action to inspect/commit.

Do not hide the entire endgame behind a surprise Job Board state.

Qualification should update live when relevant values change.

The UI must get these values from `AscensionSystem`/simulation state rather than reimplementing qualification rules.

## Acceptance criteria

At any point in a run, the player can answer:

1. What is my boss contract?
2. What do I still need to qualify?
3. How close am I?
4. What happens when I commit?

---

# Phase 6 — Add Rig Safety Forecasting

## Objective

Prevent the Market from presenting catastrophically unsafe hardware as if it were an ordinary upgrade.

Do NOT prohibit reckless builds.

Warn accurately.

## Add a compute/thermal projection API

Create a simulation-side function that can evaluate the rig **as if an upgrade were purchased**, without mutating real state.

For a hardware/cooling purchase return approximately:

```text
token_rate_after
power_draw_after
cooling_after
heat_gain_per_prompt
heat_removed_per_prompt
net_heat_per_prompt
predicted_heat_ratio_after_one_prompt
thermal_status
power_cost_after
```

Suggested statuses:

```text
SAFE
HOT
DANGEROUS
LETHAL
```

The thresholds should come from actual heat rules, not duplicated magic numbers in UI.

## Market presentation

Hardware cards should expose meaningful consequences.

Example:

```text
GPU Rack
+50M throughput
+2,000 power draw

THERMAL FORECAST
Current cooling: 570
Heat after one burn: 112%

🔥 LETHAL CONFIGURATION
Recommended: Immersion Cooling Rig
```

Allow the purchase.

For dangerous/lethal configurations change the action language, e.g.:

```text
BUY ANYWAY
```

Potentially require one extra confirmation only for immediately lethal configurations.

Avoid repeated confirmation spam for merely suboptimal builds.

## Important

The projection must account for:

* current dwelling cooling;
* all existing hardware;
* installed cooling;
* upgrade effects;
* current heat where relevant;
* perks/modifiers where reasonably deterministic.

Do not build the forecast entirely inside Market UI.

## Acceptance criteria

* A GPU rack that would cause immediate fire is visibly identified before purchase.
* Adding adequate cooling changes its forecast to safe.
* Forecast values match the following real burn closely enough to be trusted.
* Players may intentionally buy an unsafe configuration.

---

# Phase 7 — Contract Risk Forecast

## Objective

Make choosing contracts a meaningful decision rather than selecting the largest payout.

Extend Job Board information with a simulation-derived estimate.

Where feasible show:

```text
estimated prompts to complete
estimated heat exposure
estimated running/power/cloud cost
deadline margin
known quality risk
projected profit
overall risk
```

Example:

```text
Government Migration
Reward: $43M

Estimated:
3 prompts
94% peak heat
$1.2M operating cost
2 prompts deadline margin

Risk: HIGH
```

Do not promise exact outcomes where random events/perks can change them.

Label estimates appropriately.

Reuse the same underlying compute model used by real execution wherever possible.

## Acceptance criteria

Contract selection lets the player reason about whether their current build can survive the job.

Reward is no longer the only meaningful visible comparison between contracts.

---

# Phase 8 — Give Each Location A Mechanical Identity

Do this after the structural refactor works.

Avoid making locations merely:

```text
more slots
more cooling
higher numbers
```

Each chapter should introduce or emphasise one constraint.

Suggested identities:

### Bedroom

Tutorial/optimisation.

* tiny floor space;
* cheap overhead;
* desktops/components;
* basic cloud;
* teach contracts, workflow and upgrades.

Question:

**How much can I squeeze out of almost nothing?**

### Garage

Heat chapter.

* GPU racks;
* immersion cooling;
* much higher power draw;
* thermal forecasting becomes essential.

Question:

**How hard dare I run this thing?**

### Office Unit

Operations chapter.

* compute clusters;
* multiple jobs/workflows;
* reliability and workflow design become more important.

Question:

**Can I run a real operation instead of one enormous PC?**

### Warehouse

Industrial scaling.

* serious cooling plants;
* high fixed costs;
* large contracts;
* infrastructure efficiency.

Question:

**Can revenue grow faster than the monster I've built?**

### Data Centre Campus

Power/reliability.

Introduce stronger grid/load constraints and major operational risk.

### Private Power Grid

Extreme scaling.

Player effectively builds infrastructure rather than buying PCs.

### Moon Facility

Final rule-breaking chapter.

Use strange late-game mechanics and alternate Ascension endings.

---

# Phase 9 — Campaign / Location Selection Screen

After more than one location is unlocked, starting a run should present the available environments.

Each card should show approximately:

```text
GARAGE

Unlocked ✓

4 machine slots
Base cooling: 120
Rent: $1,400

Focus:
HEAT & GPU SCALING

Boss:
Million Token Operator
```

Locked locations should show their unlock condition:

```text
OFFICE UNIT

LOCKED

Beat Garage Ascension
```

The user should be able to replay previously completed locations.

Do not force them always to play the highest unlocked one.

---

# Phase 10 — Meta Rewards

Do not overbuild this initially.

Location unlock itself is already a meaningful permanent reward.

First version:

Winning a location grants:

1. next location;
2. a small set of newly available content;
3. optional achievement/meta reward.

Later, Ascension victories can unlock rule-changing content such as:

* new workflow modules;
* new perks;
* alternate bosses;
* founder backgrounds;
* challenge modifiers;
* strange rules like Heat Recycler.

Avoid permanent flat bonuses such as:

```text
+20% starting throughput
+25% income
```

where possible.

Prefer permanent **new choices**, not permanent raw power.

---

# Phase 11 — 12-Round Structure

Keep the 12-round run for now.

Give the clock a clear role.

Suggested pacing:

```text
Rounds 1–3
Establish the build.

Rounds 4–7
Scale and begin meeting Ascension qualification.

Rounds 8–10
Ascension should be realistically attemptable.

Rounds 11–12
Final scramble.
```

The game should communicate urgency as Round 12 approaches.

Default rule:

If Round 12 ends and Ascension has not been completed, the run is lost.

Existing overtime behaviour can optionally remain as a special mechanic, perk or expensive desperation mode, but it should not make the twelve-round limit meaningless.

---

# Phase 12 — Automated Tests

Add headless tests before broad balance work.

At minimum cover:

## Location progression

* fresh profile only has Bedroom;
* Bedroom victory unlocks Garage;
* Garage victory unlocks Office;
* losing a run does not unlock a location;
* replaying an already-cleared location behaves correctly.

## Fixed locations

* Market cannot purchase dwelling upgrades;
* current run location remains unchanged throughout a normal run;
* hardware dwelling requirements use the selected location correctly.

## Cooling

* environmental cooling is included once;
* buying cooling increases cooling by the correct amount;
* selling cooling removes the correct amount;
* save/load does not duplicate environmental cooling.

## Thermal forecast

* forecast of known unsafe GPU-rack configuration is dangerous/lethal;
* adding matching cooling changes forecast;
* predicted one-prompt heat matches real simulation.

## Ascension

* qualification is deterministic;
* qualification exposes individual unmet conditions;
* player cannot commit before qualifying;
* completion ends the run;
* completion unlocks the next location;
* no legacy in-run rung progression remains.

## Save migration

* representative old save loads successfully;
* old dwelling state does not cause invalid campaign state;
* existing meta unlocks survive migration.

---

# Recommended Implementation Order

Do not attempt every phase in a single Cursor pass.

Use this order:

### PR / Task 1 — Progression state

* persistent location unlocks;
* selected starting location;
* migration;
* fixed run location.

### PR / Task 2 — Remove dwelling purchases

* Market filtering;
* location-based hardware gating;
* tests.

### PR / Task 3 — Cooling derivation + thermal bug fixes

* separate location cooling from installed cooling;
* make recalculation deterministic;
* tests.

### PR / Task 4 — Ascension simplification

* one boss per location;
* remove rung ladder;
* victory unlocks next location;
* tests.

### PR / Task 5 — Ascension UI

* permanent qualification tracker;
* clear commit flow;
* clear victory/unlock screen.

### PR / Task 6 — Hardware safety forecast

* simulation-side projection;
* Market warnings;
* BUY ANYWAY behaviour;
* tests.

### PR / Task 7 — Contract forecast

* completion/cost/heat estimates;
* Job Board UI.

### PR / Task 8 — Location identity and balance pass

Only now adjust:

* costs;
* cooling values;
* hardware curves;
* contract rewards;
* Ascension requirements;
* location-specific mechanics.

---

# Non-goals For This Refactor

Do not simultaneously:

* redesign every UI screen;
* rebalance every job;
* rewrite the effect system;
* reintroduce cloud or advertising economies;
* replace the workflow system;
* introduce a giant skill tree;
* add dozens of permanent stat upgrades;
* build all seven locations' unique mechanics at once.

The purpose of this refactor is to establish one understandable progression spine.

---

# Final Design Rule

When evaluating any future progression feature, ask which layer it belongs to:

### Inside the current run

Purchased with cash.

Examples:

* hardware
* cooling
* workflows
* temporary perks

### Win condition

Ascension.

One major target that the current rig is being built to defeat.

### Between runs

Permanent unlocks.

Examples:

* new locations
* new hardware families
* new perks/modules
* alternate bosses
* challenge rules

A feature should normally belong to **one** of those layers.

Do not make the same item simultaneously function as economic upgrade, chapter unlock, qualification requirement and meta-progression reward.

That separation is the core of this refactor.
