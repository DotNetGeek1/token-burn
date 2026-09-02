# Token Burn — Perk Draft + Module Market Implementation Brief

**Target repo:** `DotNetGeek1/token-burn`  
**Reviewed baseline:** `b01fd1d22fb9158eef37fc2bc6cd806cc45a010c`  
**Purpose:** Change how perks and modules are acquired.  
**Important:** This is a **separate task** from the 120-module expansion. Do not redesign or rebalance the module catalogue in this task.

---

# 1. Goal

Replace the current mixed end-of-round angel draft:

> choose 1 free item from a mixture of perks and modules

with two clearly separated acquisition systems:

1. **Perks = free strategic identity choices**
   - At the end of an eligible round, show **3 perks**.
   - Player may take **1 perk** or decline all three.
   - Modules never appear here.
   - Perk offers are not purchasable.
   - Remove the paid angel/perk reroll for now.

2. **Modules = purchasable equipment**
   - Modules are sold from the existing **Market** venue.
   - Market carries a limited random stock of modules.
   - Module stock is naturally refreshed at the start of each new round.
   - Player may purchase **multiple modules** from the current stock if they can afford them.
   - Player may pay to reroll/restock the module shelf during the current round.
   - Reroll cost escalates during the round and resets on the next natural restock.

This should make the economy part of deck-building:

> Jobs generate capital → capital buys modules → modules build workflows → perks define how the build bends the rules.

---

# 2. Design principles

These are requirements, not suggestions.

## 2.1 Perks and modules have different jobs

**Perks**
- scarce
- free
- strategic
- define build identity
- usually affect the whole company/run/workflow philosophy

**Modules**
- equipment
- numerous
- bought with cash
- assembled into workflows
- can be benched/replaced
- should compete economically with hardware purchases

Do not merge these acquisition systems again.

## 2.2 Do not give the player perfect control

The module market remains random.

However, stock generation should retain the current tag-affinity behaviour so a build that already contains `test`, `bugs`, `heat`, `recursion`, etc. is *more likely* to see relevant modules.

This is a bias, not a guarantee.

## 2.3 The market must create real economic decisions

The player should often have to choose between:
- buying a useful module,
- buying/upgrading hardware,
- keeping enough money for bills,
- saving for a better future purchase,
- paying for a reroll.

Do not make modules trivially cheap.

## 2.4 Do not automatically refill purchased slots

When a module is bought:
- grant it to the player,
- remove it from market stock,
- leave that shelf slot empty for the rest of the current stock cycle.

A paid reroll may refill the shelf.

A natural next-round restock refills the shelf.

This prevents one market visit from becoming an unlimited module fountain.

---

# 3. Scope boundary with the module expansion task

Another task may already be editing:
- `content/modules/modules.json`
- `definitions/module_definition.gd`
- module unlock requirements
- achievements
- content validation

**Do not edit `content/modules/modules.json` for this feature.**

Module prices should therefore be calculated by the market system from rarity/economy data rather than adding a price field to every module.

If the module expansion task adds new eligibility fields such as:
- `min_victories`
- `min_hard_victories`
- additional achievement gates

the market must honour the final shared eligibility logic.

Do not duplicate unlock rules inside `MarketService`.

Prefer a single reusable module-eligibility helper in `ContentDatabase`.

---

# 4. Existing architecture to reuse

The current project already has the correct seams.

## Current relevant files

### `core/run_lifecycle.gd`
Currently:
- generates the mixed angel offers,
- allows perk/module acceptance,
- owns angel reroll state/cost,
- opens the angel phase after round settlement.

### `core/content_database.gd`
Currently:
- owns perk/module unlock checks,
- applies location/difficulty gates in the mixed angel pool,
- owns rarity weights,
- owns tag-affinity weighting.

### `core/market_service.gd`
Already exists as the dedicated purchase/sale service.

Extend this service for module stock, prices, buying and rerolling.

Do **not** create a second `ModuleShopSystem`.

### `ui/venues/venue_market.gd`
Already renders the physical Market venue and current hardware/services shelves.

Add a module counter/shelf here.

### `ui/screens/angel_investors.gd`
Currently renders the mixed free perk/module draft and paid reroll.

Change it to a perk-only choice.

### `core/simulation.gd`
Keep Simulation as the façade exposed to UI/tests.

New market actions should be thin wrappers around `MarketService`.

---

# 5. New round flow

The intended player flow is:

```text
ROUND WORK
    ↓
CONTRACT / ROUND SETTLEMENT
    ↓
BILLS + EVENTS + COOLING
    ↓
ROUND NUMBER ADVANCES
    ↓
MODULE MARKET NATURALLY RESTOCKS
    ↓
IF ANGEL ELIGIBLE:
    SHOW 3 FREE PERKS
    TAKE 1 OR DECLINE
    ↓
ROUND PREP / VENUE
    ↓
PLAYER MAY VISIT MARKET
    - buy zero, one or several modules
    - buy hardware
    - reroll module shelf
    - leave and start work
```

The module market should also contain stock on round 1 of a fresh run.

A chapter/location transition should generate stock appropriate to the new location.

---

# 6. Perk-only angel draft

## 6.1 Offer generation

Change the angel offer pool so it contains **perks only**.

When there are enough eligible perks:
- produce 3 distinct perk offers.

Eligibility must respect:
- already collected perks,
- incompatible/undraftable perks,
- achievement locks,
- any meta victory locks introduced by the module-expansion work,
- difficulty,
- location tier,
- existing rarity weighting,
- existing tag affinity.

If fewer than 3 valid perks exist, show as many as exist.

If no valid perks exist:
- do not wedge the game in `ANGEL_ROUND`;
- automatically continue to round prep.

## 6.2 Player actions

Allowed:
- take exactly one perk,
- decline all three.

Not allowed:
- buy a perk,
- take a module,
- reroll the perk table.

Keep the existing auto-equip behaviour:
- collect the perk,
- equip it automatically if capacity/compatibility allows,
- otherwise retain it in the perk inventory using current rules.

## 6.3 Statistics

Keep existing meanings:

- `angel_offers_taken` increments when a perk is accepted.
- `angel_offers_declined` increments when the entire perk offer is declined.

A module purchase must **not** increment either angel statistic.

## 6.4 Remove angel reroll

The current angel reroll belongs to the old mixed-draft acquisition system.

Remove it from the player-facing flow.

Update:
- `RunLifecycle.angel_reroll_cost`
- `RunLifecycle.can_reroll_angel`
- `RunLifecycle.reroll_angel_offers`
- corresponding Simulation façade methods
- `ui/screens/angel_investors.gd`
- tests/balance helpers that assume angel rerolls exist

It is acceptable to leave deprecated wrappers temporarily if removing them would create unnecessary migration churn, but:
- UI must not expose them,
- normal gameplay must not use them,
- new tests should target module-market rerolls instead.

---

# 7. Module market state

Store transient shop state inside the run.

Recommended structure:

```gdscript
run_state.business["module_market"] = {
    "stock": [],
    "location": "",
    "round": 0,
    "sequence": 0,
    "rerolls": 0,
}
```

## Fields

### `stock`
Array of module IDs currently available to buy.

### `location`
The dwelling/location where this stock was generated.

Required because chapter transitions reset the round number.

### `round`
Round number where this stock was generated.

### `sequence`
Monotonic stock-generation sequence for deterministic RNG.

### `rerolls`
Number of paid rerolls used since the latest natural restock.

Resets to 0 on natural restock.

## Compatibility

Old saves will not contain this dictionary.

Create it lazily with sane defaults.

A save-version bump is not required solely for this dictionary if lazy initialisation is reliable and tested.

---

# 8. Module market stock size

Use location tier.

Initial values:

| Location | Tier | Module slots |
|---|---:|---:|
| Bedroom | 0 | 3 |
| Garage | 1 | 4 |
| Office Unit | 2 | 4 |
| Warehouse | 3 | 5 |
| Datacentre Campus | 4 | 5 |
| Private Power Grid | 5 | 6 |
| Moon Facility | 6 | 6 |

Put these values in balance data, not scattered through UI code.

Suggested addition to:

`content/balance/economy.json`

```json
"module_market": {
  "slots_by_location_tier": [3, 4, 4, 5, 5, 6, 6],
  "rarity_price_rent_mult": {
    "common": 0.25,
    "uncommon": 0.50,
    "rare": 1.25,
    "legendary": 3.50
  },
  "reroll_rent_mult": 0.15,
  "reroll_job_reward_mult": 0.05,
  "reroll_growth": 2.0
}
```

These are first-pass balance values, not sacred constants.

---

# 9. Stock generation

Add a dedicated ContentDatabase API, for example:

```gdscript
func draw_market_modules(
    rng: DeterministicRng,
    run_state: RunState,
    count: int,
    owned_tags: Array = [],
    blocked_ids: Array = []
) -> Array[ModuleDefinition]
```

Do not use the old generic mixed angel offer list.

## Eligible market modules

A candidate must:
- be unlocked,
- be allowed on current difficulty,
- satisfy current location-tier rules,
- not already be owned,
- not be explicitly blocked for this draw.

If the module-expansion work adds further gates, market stock must automatically respect them.

## Weighting

Use:
1. normal rarity weight,
2. module `draft_weight`,
3. current tag affinity.

The existing build tuning already has:
- `draft_tag_affinity`
- `draft_tag_affinity_cap`

Reuse them.

## Immediate reroll duplicate avoidance

A paid reroll should normally feel like a new shelf.

When rerolling:
- block the current non-owned stock IDs during the first draw attempt.

If this prevents the market from filling because the eligible pool is too small:
- perform a fallback draw that allows previous-stock cards to reappear.

Do not leave the shelf artificially half empty if valid modules exist.

---

# 10. Natural restock

Add to `MarketService` something equivalent to:

```gdscript
static func ensure_module_stock(sim: Node) -> void
static func restock_modules(sim: Node, paid_reroll: bool = false) -> void
```

## Natural restock conditions

Generate fresh stock when:
- no stock state exists,
- current location differs from stored location,
- current round differs from stored round.

Natural restock:
- fills to the location slot count,
- increments `sequence`,
- resets `rerolls` to 0,
- stores current location/round,
- autosaves through the existing run lifecycle.

## Timing

Call the stock ensure/restock during new-round setup, after:
- current location is known,
- current round number is known.

`RunLifecycle._begin_round()` is the appropriate seam.

This automatically covers:
- first round of a run,
- normal next rounds,
- chapter/location transitions.

Do not regenerate stock every time the player opens the Market screen.

Opening/closing the venue must not change the shelf.

---

# 11. Module prices

Do not add a required `price` field to each module in this task.

Use economy-relative prices calculated by `MarketService`.

Suggested API:

```gdscript
static func module_price(sim: Node, module_id: String) -> float
```

## First-pass formula

```text
price = round_rent × rarity_multiplier
```

Rarity multipliers from balance:

```text
common      0.25 × rent
uncommon    0.50 × rent
rare        1.25 × rent
legendary   3.50 × rent
```

Use a small sensible floor if needed so early-game prices never collapse to zero.

The purpose is to make:
- common modules cheap tactical purchases,
- uncommons meaningful,
- rares compete with upgrades,
- legendaries serious investments.

Do not use rarity as a guarantee that a card is better; this is acquisition pressure, not a power score.

A later balance pass can add per-module price overrides if required.

That is deliberately outside this implementation to avoid editing the module catalogue while the 120-card expansion is underway.

---

# 12. Buying modules

Add MarketService methods similar to:

```gdscript
static func module_stock(sim: Node) -> Array
static func can_buy_module(sim: Node, module_id: String) -> bool
static func buy_module(sim: Node, module_id: String) -> bool
```

Expose thin wrappers from `Simulation`.

## Purchase requirements

Purchase succeeds only when:
- Market is open,
- module ID exists in current market stock,
- module still exists in ContentDatabase,
- module is not already owned,
- module is still eligible/unlocked,
- player has enough cash.

Use the existing `EconomySystem.purchase(...)` pattern.

Suggested ledger reason:

```text
module_market:<module_id>
```

## Purchase result

On success:
1. deduct cash,
2. grant module through `BoardSystem.grant_module`,
3. remove module ID from current stock,
4. do **not** refill the slot,
5. emit existing `EVENT_MODULE_ACQUIRED`,
6. evaluate achievement tick if appropriate,
7. autosave,
8. refresh Market/build/workflow UI.

Do not auto-place the module into a workflow.

It arrives on the bench/inventory using current module ownership behaviour.

## Multiple purchases

Do not close the market after buying one module.

If the player can afford every card on the shelf, they may buy every card.

That is intentional.

---

# 13. Market reroll

Move paid reroll pressure from the angel table to the module market.

Recommended API:

```gdscript
static func module_reroll_cost(sim: Node) -> float
static func can_reroll_modules(sim: Node) -> bool
static func reroll_modules(sim: Node) -> bool
```

## Cost formula

Use economy-relative cost:

```text
base = max(
    round_rent × 0.15,
    location_base_job_reward × 0.05
)

cost = base × (2.0 ^ rerolls_this_round)
```

Use values from `economy.json`.

Example behaviour:
- first reroll is tempting,
- second is meaningful,
- third starts to hurt,
- repeated fishing becomes expensive.

## Successful reroll

On success:
1. charge cash,
2. increment `rerolls`,
3. increment stock generation sequence if useful for deterministic RNG,
4. redraw the shelf to full capacity,
5. exclude already-owned modules,
6. attempt to avoid immediately repeating the old shelf,
7. keep current location/round stamp,
8. autosave.

A paid reroll does not affect perk offers.

## Natural reset

On the next natural round restock:
- reroll count becomes 0.

---

# 14. Market open phases

Current `MarketService.market_open()` includes `ANGEL_ROUND`, and buying hardware while angels are open closes the draft.

That behaviour should change.

The perk offer is now an explicit mandatory/declinable strategic decision before normal round prep.

Recommended market-open phases:

```text
ROUND_END
ROUND_PREP
```

Do **not** allow purchases during `ANGEL_ROUND`.

Remove this old behaviour from `MarketService.buy_upgrade()`:

> shopping past the angels closes their draft

Hardware shopping should not implicitly spend/close the perk choice.

After the player takes or declines the perk:
- `after_angel_round()` moves back to the normal market-open phase.

---

# 15. Market UI

Extend:

`ui/venues/venue_market.gd`

The existing Market venue should remain one coherent shop.

Do not make a separate module-shop scene.

## 15.1 Add a module counter

Add a counter key, for example:

```gdscript
const MODULES := "modules"
```

The Market counter list should include:

```text
MODULES
HARDWARE / COMPONENT / SERVICES groups...
INSTALLED
```

Putting modules first is reasonable because they will be checked frequently.

## 15.2 Module tiles

For each stocked module show:

- module name,
- module badge as the headline figure where useful,
- rarity/category,
- concise module description,
- price,
- availability,
- module/category icon,
- `BUY` action.

Suggested tile information:

```text
REGRESSION SUITE
REPAIR ×1.4
UNCOMMON · TEST / QUALITY / BUGS

If bugs were created and all were fixed,
×1.4 QUALITY.

£220                         IN STOCK
[ BUY ]
```

Do not force all tags into the tile if it becomes unreadable on mobile.

## 15.3 Empty purchased slots

If the player has bought part of the shelf, the list simply becomes shorter.

Add a board note such as:

```text
NEXT FREE RESTOCK: ROUND 5
```

## 15.4 Reroll control

The module shelf must expose the current reroll cost.

Use either:
- a dedicated row/button under the module shelf, or
- a synthetic final VenueBoard entry such as `RESTOCK MODULE SHELF`.

Do not hide reroll behind a detail modal.

It should show:
- current price,
- enabled/disabled based on affordability and market phase,
- current reroll number if useful.

Example:

```text
RESTOCK MODULE SHELF        £60
REROLL #1
[ REROLL ]
```

After use:

```text
RESTOCK MODULE SHELF        £120
REROLL #2
[ REROLL ]
```

## 15.5 Wallet / bills

Keep the existing Market index values:
- Wallet,
- Safe to spend,
- Due at round end.

Module purchases should use the same financial framing as hardware purchases.

The player may still spend money that makes the next bill dangerous, as long as they actually possess the cash.

Warn; do not prohibit reckless play.

---

# 16. Angel UI

Update:

`ui/screens/angel_investors.gd`

## Required changes

### Header
Change wording from generic mixed offer language to perk language.

Example:

```text
<INVESTOR>: PICK ONE PERK FREE
```

Keep the useful:
- perk capacity,
- bank,
- bills

summary.

Pipeline fullness is less important now because no modules are being handed out here.

### Cards
Every card is now a perk.

Therefore:
- remove module kind chip paths,
- remove module bench warning,
- use perk icon/path only,
- detail subtitle is always `Free perk`,
- action remains `TAKE IT`.

### Actions
Keep:

```text
TAKE NOTHING
```

Remove:

```text
REROLL — £...
```

### Behaviour
The overlay remains non-dismissible except by:
- taking one perk,
- explicitly declining all.

---

# 17. Content and achievement wording

Achievement-gated modules currently conceptually say that earning the achievement puts the module into the angel draft pool.

That is no longer true.

Update comments/player-facing wording where necessary so module rewards mean:

> This module is now unlocked and can appear in the Market.

Search for wording such as:
- `angel draft pool`
- `angel draft`
- `free module`
- `joins the draft`
- module rewards described as being handed out by angels

Do not change achievement conditions or which modules they unlock unless required by the separate module-expansion task.

Starting modules granted by permanent meta unlocks remain starting modules and do not need to be bought.

---

# 18. Statistics compatibility

The current statistic is called:

```text
modules_drafted
```

It is already used by run/lifetime achievement infrastructure.

For this feature, preserve compatibility rather than performing a broad statistics migration.

When a module is successfully purchased:
- increment `modules_drafted` as the existing legacy “modules acquired” counter.

Add/update comments so future code does not assume it literally came from a draft.

Do not increment it on:
- market reroll,
- merely seeing a module,
- starting module grants,
unless that was already existing behaviour.

A future cleanup may rename it to `modules_acquired`, but that is outside this task.

---

# 19. Save compatibility

## 19.1 Existing saves with no module-market state

Must load successfully.

On first round setup/market access:
- lazily create state,
- generate stock for current round/location.

## 19.2 Existing saves parked on an old mixed angel draft

Current saves may contain pending choices where `type == "module"`.

Update pending-choice migration/normalisation.

Desired behaviour:
1. preserve valid pending perk choices,
2. discard pending module choices,
3. if the game is in `ANGEL_ROUND` and no valid perk choice remains, redraw a fresh perk-only offer table,
4. do not grant the removed module for free,
5. do not wedge the phase.

## 19.3 Existing angel reroll state

Old `draft_state.rerolls` can be ignored once the perk reroll is removed.

Do not accidentally reuse it as module-market reroll state.

Module market has its own `rerolls` counter.

---

# 20. Determinism

The simulation uses derived deterministic RNG streams.

Market stock must remain deterministic across:
- save/load,
- UI refresh,
- repeated venue opens.

Suggested RNG identity:

```text
module_market.<location>.<round>.sequence.<sequence>.reroll.<rerolls>
```

Exact spelling does not matter; stability does.

Opening the Market must never consume RNG.

Only:
- natural restock,
- paid reroll

may change the module shelf.

---

# 21. Suggested implementation API

This is guidance; exact signatures may follow existing style.

## `core/content_database.gd`

Add/refactor:

```gdscript
func draw_angel_perks(
    rng: DeterministicRng,
    run_state: RunState,
    count: int,
    owned_tags: Array = [],
    blocked_ids: Array = []
) -> Array

func draw_market_modules(
    rng: DeterministicRng,
    run_state: RunState,
    count: int,
    owned_tags: Array = [],
    blocked_ids: Array = []
) -> Array[ModuleDefinition]
```

Prefer shared private helpers for:
- perk eligibility,
- module eligibility,
- rarity/tag weighting.

Do not have Angel and Market implement subtly different unlock rules.

## `core/market_service.gd`

Add:

```gdscript
static func ensure_module_stock(sim: Node) -> void
static func module_stock(sim: Node) -> Array
static func module_stock_size(sim: Node) -> int
static func module_price(sim: Node, module_id: String) -> float

static func can_buy_module(sim: Node, module_id: String) -> bool
static func buy_module(sim: Node, module_id: String) -> bool

static func module_reroll_cost(sim: Node) -> float
static func can_reroll_modules(sim: Node) -> bool
static func reroll_modules(sim: Node) -> bool
```

Keep purchase logic here, not in the venue.

## `core/simulation.gd`

Expose thin façade wrappers:

```gdscript
func module_market_stock() -> Array
func module_market_price(module_id: String) -> float
func can_buy_module(module_id: String) -> bool
func buy_module(module_id: String) -> bool
func module_market_reroll_cost() -> float
func can_reroll_module_market() -> bool
func reroll_module_market() -> bool
```

## `core/run_lifecycle.gd`

Responsibilities after change:
- schedule perk-only angel table,
- accept/decline perk,
- ensure MarketService naturally restocks during round begin.

Remove module acquisition from angel flow.

---

# 22. Files expected to change

Core expected set:

```text
core/run_lifecycle.gd
core/content_database.gd
core/market_service.gd
core/simulation.gd
content/balance/economy.json
ui/screens/angel_investors.gd
ui/venues/venue_market.gd
```

Likely tests:

```text
tests/simulation_tests/test_achievements.gd
tests/simulation_tests/test_balance_sweeps.gd
tests/simulation_tests/<new module market test file>.gd
tests/batch_runner.gd
tests/run_tests.gd
```

Potential wording/comment updates:

```text
systems/achievement_system.gd
ui/venues/venue_achievements.gd
ui/common/achievement_splash.gd
docs/GAME_DESIGN.md
```

Avoid editing:

```text
content/modules/modules.json
```

unless resolving an unavoidable integration conflict from the other task.

---

# 23. Test requirements

Add focused simulation tests.

## Perk draft

### Test: angel offers are perk-only
Generate many round-end tables.

Assert:
- every offer has `type == "perk"`.

### Test: three perks offered where pool permits
Fresh eligible pool should return 3 distinct perks.

### Test: taking perk closes draft
Accept one.

Assert:
- perk owned,
- angel taken stat +1,
- pending choices cleared,
- phase leaves Angel Round.

### Test: decline still works
Assert:
- nothing acquired,
- decline stat +1,
- phase continues.

### Test: angel reroll unavailable
UI/service path should no longer allow rerolling perk choices.

### Test: no eligible perks cannot wedge
Force all perks blocked/owned.

Assert:
- no Angel Round deadlock.

---

# 24. Module market tests

## Stock generation

### Test: first round has stock
Start fresh run.

Assert:
- stock generated,
- Bedroom capacity = 3.

### Test: stock size scales by location
Check each location tier against configured slot count.

### Test: stock respects unlocks
Locked achievement module must not appear.

After unlock:
- it becomes eligible for later stock/reroll.

### Test: stock respects location tier
Module above current tier does not appear early.

### Test: stock respects difficulty
Difficulty-specific modules follow existing rules.

### Test: stock excludes owned modules
Owned module never appears for sale.

### Test: tag affinity still bends stock
Use repeated deterministic samples/balance helper rather than asserting one exact random draw.

---

# 25. Restock tests

### Test: opening Market does not reroll
Record stock.

Open/refresh venue repeatedly.

Assert stock unchanged.

### Test: save/load preserves stock
Generate stock, save, load.

Assert:
- same IDs,
- same reroll count,
- same round/location stamp.

### Test: next round naturally restocks
Advance round.

Assert:
- stock cycle advances,
- rerolls reset to 0.

### Test: chapter transition restocks
Move from one location to the next where round resets.

Assert:
- location stamp changes,
- correct new slot count,
- eligible higher-tier modules can now enter pool.

---

# 26. Purchase tests

### Test: purchase deducts cash
Record cash.

Buy stocked module.

Assert:
- cash reduced by quoted module price.

### Test: purchase grants module
Assert module exists in player module inventory after purchase.

### Test: purchase removes shelf item
Assert purchased ID no longer in stock.

### Test: purchase does not auto-refill
Stock length is one smaller after purchase.

### Test: can buy several in one round
Give enough cash.

Buy 2+ separate shelf modules.

Assert all are owned.

### Test: cannot buy absent module
Known module not currently in stock must be rejected.

### Test: cannot buy owned module
Reject duplicate.

### Test: cannot buy without cash
Reject and leave state unchanged.

### Test: purchase emits module acquired event
Preserve existing downstream behaviour.

### Test: compatibility stat
`modules_drafted` increments once on successful purchase.

---

# 27. Reroll tests

### Test: first reroll has expected cost band
Mirror the spirit of the existing angel reroll balance test.

Do not assert one hardcoded pound value unless necessary.

### Test: reroll charges cash
Cash falls exactly by quoted cost.

### Test: reroll escalation
Cost increases by configured growth after each paid reroll.

### Test: natural round reset
Next round's first reroll returns to base cost.

### Test: reroll fills empty purchased slots
Buy one module, reroll.

Assert shelf returns to location capacity if pool permits.

### Test: reroll avoids old stock when possible
With a sufficiently large eligible pool, no immediate old-stock duplicate should appear.

### Test: small pool fallback works
With a tiny eligible pool, reroll still fills as much as possible rather than failing because all old IDs were blocked.

---

# 28. Market phase tests

Current MarketService permits shopping during `ANGEL_ROUND`.

Change and test this.

### Test: market closed during perk decision
During Angel Round:
- hardware purchase rejected,
- module purchase rejected,
- module reroll rejected.

### Test: market reopens after take/decline
After closing perk offer:
- normal market operations available in Round Prep.

Do not let shopping implicitly close/spend the perk draft.

---

# 29. Batch runner / automated simulation

The batch runner currently knows how to consume a mixed Angel table.

Update it.

## Angel phase policy

During `ANGEL_ROUND`:
- choose an eligible perk according to existing/simple policy,
- otherwise decline.

Never look for a module in `pending_choices`.

## Round-prep market policy

Automated runs need some way to acquire modules or all balance simulations will accidentally become “starter modules only”.

Add a deterministic basic shopper.

Recommended simple policy:
1. inspect module market stock,
2. score cards by owned-tag overlap,
3. only consider affordable modules,
4. prefer purchases that stay inside `bills_outlook().spendable`,
5. buy at most one module per round in the generic runner unless a specific test says otherwise,
6. do not automatically reroll in the baseline policy.

This is for simulation quality, not a player-facing AI.

---

# 30. UI acceptance criteria

## Angel screen
- shows only perks,
- usually 3 choices,
- each card clearly says it is free,
- no module chip/path,
- no module bench warning,
- no perk reroll button,
- TAKE NOTHING remains,
- cannot dismiss by tapping outside.

## Market screen
- contains a clearly reachable MODULES counter,
- shows current random stock,
- prices are visible without opening a secondary modal,
- BUY is reachable on mobile,
- bought cards leave stock,
- reroll cost is visible,
- reroll action is reachable,
- wallet / safe-to-spend / bills remain visible,
- hardware/service buying continues to work exactly as before.

---

# 31. Not in scope

Do not implement these in this task:

- the 59/120 module catalogue,
- perk catalogue expansion,
- new module effect primitives,
- module-specific price tuning,
- selling modules back to the market,
- module upgrades/levels,
- limited-time discounts,
- shopkeeper NPC systems,
- market events,
- black-market perks,
- changing perk-offer frequency away from once per eligible round,
- changing perk capacity,
- a full shop HOLD/reserve system.

A single-card HOLD/reserve feature is a good future addition, but it is deliberately not required here. Get the core perk-vs-market acquisition loop working first.

---

# 32. Future-friendly extension: HOLD / reserve

Do **not** block the architecture from adding this later.

Future behaviour could be:

- player marks one stocked module as HOLD,
- held module survives natural restock and paid reroll,
- buying/releasing it clears the hold,
- only one held card at a time.

Do not implement it as part of this change unless explicitly requested later.

---

# 33. Acceptance checklist

The feature is complete when all of the following are true:

- [ ] End-of-round angel table contains perks only.
- [ ] Three distinct perks appear where the eligible pool permits.
- [ ] Player can take one or decline.
- [ ] Perk reroll is removed from normal gameplay.
- [ ] Modules never appear as free angel rewards.
- [ ] Existing Market venue has a MODULES shelf/counter.
- [ ] Round 1 begins with module stock.
- [ ] Module stock naturally refreshes exactly once per new round.
- [ ] Module stock refreshes correctly on location transitions.
- [ ] Market stock respects unlock/location/difficulty rules.
- [ ] Market stock retains tag-affinity weighting.
- [ ] Player can buy multiple stocked modules in one round.
- [ ] Buying deducts cash and grants the module.
- [ ] Bought modules leave an empty shelf slot until restock/reroll.
- [ ] Paid market reroll redraws module stock.
- [ ] Reroll cost escalates during a round.
- [ ] Natural restock resets reroll cost.
- [ ] Hardware buying continues to work.
- [ ] Market cannot be used to bypass/close the unresolved perk choice.
- [ ] Old saves with mixed pending angel choices do not wedge.
- [ ] Market stock survives save/load unchanged.
- [ ] Batch runner can still acquire modules.
- [ ] Existing module unlock achievements now mean “eligible to appear in Market”.
- [ ] No module catalogue content from the separate 120-card task is accidentally overwritten.
- [ ] Full automated test suite passes.

---

# 34. Implementation order

Recommended order for Cursor:

## Phase 1 — Data and domain logic
1. Add `module_market` balance tuning to `economy.json`.
2. Add shared module/perk eligibility helpers if needed.
3. Add perk-only ContentDatabase draw.
4. Add market-module draw.
5. Add MarketService state/stock/price/buy/reroll APIs.
6. Add Simulation façade wrappers.

## Phase 2 — Lifecycle
7. Natural module restock in round begin.
8. Convert angel generation to perk-only.
9. Remove module acceptance from normal angel flow.
10. Remove player-facing angel reroll.
11. Restrict Market during `ANGEL_ROUND`.
12. Add old-save pending-choice normalisation.

## Phase 3 — UI
13. Simplify angel screen to perk-only.
14. Add MODULES counter/shelf to existing Market.
15. Add BUY module actions.
16. Add visible market REROLL action/cost.

## Phase 4 — Simulation/tests
17. Add focused module market tests.
18. Replace angel reroll tests with market reroll tests.
19. Update batch runner perk selection.
20. Add deterministic market shopping behaviour to batch runner.
21. Run full suite and repair regressions.

## Phase 5 — Copy/docs
22. Replace “module joins angel draft” wording with “module can appear in Market”.
23. Update relevant game-design documentation.

---

# 35. Final design summary

After this change, the acquisition hierarchy should be easy for the player to understand:

```text
PERKS
Free.
One strategic choice.
End-of-round investor offer.
Defines what kind of company/build this run is becoming.

MODULES
Bought with cash.
Random market stock.
Multiple purchases allowed.
Restocks every round.
Paid rerolls available.
Defines the actual workflow machinery.

HARDWARE
Bought with cash from the same Market.
Competes directly with modules for capital.
Defines the physical capacity of the rig.
```

That separation is the goal of this task.

Do not solve it by making the new Market another free draft.
