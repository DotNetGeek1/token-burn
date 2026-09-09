# Token Burn — Game Design Overview

## 1. High concept

You are a reckless vibe coder taking increasingly absurd contracts. Jobs pay cash and reputation, but consume tokens, time, electricity, and compute capacity.

After each job, you reinvest in hardware, the cabinet's own systems, Market modules, and strange rule-changing perks. The goal is to assemble a local build capable of processing ridiculous quantities of tokens without going bankrupt, overheating, missing deadlines, or being evicted.

Everything happens on one machine: the **Burn Cabinet**. Contracts, modules, the Market and the perk rack are tabs on its central CRT; the red commit button under the glass relabels itself to whatever the current tab does; and the cabinet itself visibly grows as its five systems are upgraded.

## 2. Core loop

1. Choose a job.
2. Commit local compute and modifiers.
3. Process the job while managing tokens, time, heat, cost, and quality.
4. Resolve complications such as bugs, scope creep, outages, and revisions.
5. Get paid and gain reputation.
6. Pay rent, electricity, debt, and other overhead.
7. Buy modules, hardware, Infrastructure Tiers and cabinet system tiers in the Market and route contracts through trained workflows. Perks are permanent for the run and are only dealt once per Investor Target: meeting the investor's figure offers a table of perks (take one or decline) before the company can move on.
8. Repeat until the final Investor Target is met (the win) or the company collapses.

## 3. Primary resources

- **Cash:** Used for upgrades, rent, power, and emergency actions.
- **Token throughput:** Tokens processed per second or per turn.
- **Efficiency:** Useful output produced per token.
- **Quality:** Determines whether the delivered work meets the contract.
- **Capacity:** Number and size of jobs that can be processed concurrently.
- **Heat:** Limits sustained local compute.
- **Power:** Determines operating cost and hardware constraints.
- **Space:** Limits hardware, cooling, and staff capacity. Floor slots come from the cabinet's Power Bus tier.
- **Job slots:** How many contracts the installed machines can take at once.
- **Reputation:** Opens stretch contracts on the band above the current Infrastructure Tier.
- **Workflow mastery:** Each named pipeline trains run-long OUTPUT, QUALITY, and THERMAL multipliers. Hardware sets the raw token rate; the workflow decides how obscene that output becomes.

Mastery is scored once, the first time a contract's remaining tokens hit zero. Clean and cool are the whole contract's history: bugs created on any burn, and peak heat across every burn. Shipping or polishing after that cannot train the same contract again.

- **OUTPUT** seeds the pipeline's progress multiplier. The number the board shows is `token_mult × progress_mult`. Raw hardware tokens stay raw.
- **QUALITY** multiplies positive pipeline quality only. Penalties and the contract's passive quality share stay additive.
- **THERMAL** divides positive pipeline heat only. Signed cooling stays additive; ambient rig heat is unchanged.

Tag density is the main build glue. Owned perks (all permanent — there is no perk bench or loadout cap) and slotted modules count; benched modules do not. Named perk pairs remain easter eggs.

## 4. Strategic archetypes

- **Token Cannon:** Solves problems through overwhelming local compute.
- **Prompt Engineer:** Uses fewer tokens with high efficiency.
- **Bare Metal:** Owns the iron and accepts the heat that comes with it.
- **Agent Swarm:** Runs many specialised workers and recursive effects.
- **Consultancy:** Pursues high-quality, high-reputation contracts.

## 5. Jobs

Each job behaves like an encounter and contains:

- Reward
- Token requirement
- Quality threshold
- Deadline
- Context requirement
- Revision risk
- Hidden or visible complications
- Optional stretch goals

Example jobs:

| Job | Reward | Token pressure | Complication |
|---|---:|---:|---|
| Write 40 product descriptions | $250 | Low | Client wants it “more human” |
| Fix a WordPress plugin | $700 | Medium | No documentation |
| Build a dating app MVP | $8,000 | High | Founder changes scope |
| Migrate a bank system | $300,000 | Extreme | Failure can end the run |
| Generate an open-world game | $12 million | Ludicrous | Context grows exponentially |
| Simulate a civilisation | Unknown | Cosmic | The simulation hires you |

Players may eventually bid on contracts, trading a higher chance of winning work against reduced profit margin.

## 6. Upgrade categories

### Hardware

- Used gaming laptop
- Custom desktop
- GPU rack
- Garage data centre
- Compute warehouse
- Industrial campus
- Orbital cooling array

Hardware increases local throughput but raises power, heat, maintenance, and space requirements.

Early desktops still cap at four copies so the first two Infrastructure Tiers
teach floor space. From GPU Rack onward the shop does not invent a MAX_LEVEL: money, floor
slots, electricity, cooling and instability are the limits. A bigger Power Bus
can hold more of the same machine and run more contracts in parallel. When a
rig reaches the next compute era, the board keeps one familiar local posting
and fills the rest from the rig's service tier. Existing postings never resize
from the live token rate.

### Cabinet systems

The machine the player sees is the Burn Cabinet, and the cabinet is built from
five systems. Each is owned at a tier from 1 to 4, bought tier by tier from the
Market's SYSTEMS shelf, and each tier is a visibly different part bolted onto
the same mount (`content/upgrades/cabinet_systems.json`):

| System | What it governs | Tiers |
|---|---|---|
| Compute Stack | Flat base token rate on top of the hardware curves | Exposed Board → GPU Cage → Accelerator Stack → Impossible Core |
| Cooling Loop | Passive cooling and heat capacity (the size of the heat bar) | Desk Fan → Radiator → Liquid Manifold → Phase Cooler |
| Power Bus | Hardware floor slots | Household Lead → Transformer → Busbar Bank → Unstable Core |
| Workflow Backplane | Module bays a pipeline can hold | 3-Bay Rail → 5-Bay Rail → 7-Bay Rail → 10-Bay Rail |
| Control Rack | Saved workflow capacity | Single → Dual → Triple → Quad Selector |

Rules:

- A tier is only ever bought upward. Nothing sells a system back down and no
  Infrastructure purchase lowers a tier.
- Perk, module, upgrade and meta bonuses stay additive on top of the tier
  value. The tier is the baseline, not the ceiling. The Workflow Backplane
  is the one exception: its bay count *is* the safe pipeline capacity, and
  Wide Bus, monitors/desks and meta ranks only widen the overflow allowance
  (stages past safe that cost instability).
- The sum of the five tiers (5–20) names the cabinet's **generation**:
  Improvised Cabinet, Spliced Rig, Token Furnace, Grid Eater, Impossible
  Engine. The generation is presentation only; nothing reads a number back
  out of it.
- Buying a tier plays an install reveal: the camera pulls back to the
  Maintenance view, the old part flickers out, the new part seats, and the
  stat delta is printed. It is skippable and crossfades under reduced motion.

### Infrastructure Tier

The machine's scale is bought, not awarded. The Market's INFRASTRUCTURE row
sells tiers 0 to 6 upward whenever the run can afford the next one
(`content/upgrades/infrastructure.json`; tier 0 is free, tier 1 costs $7,500,
tier 6 $750M). A tier sets, 1:1, what the room of the same index used to
grant:

- The cabinet **scale profile**: base token rate, power draw, work tier,
  cooling and heat capacity, and the cost scale the cabinet tier values are
  multiplied by.
- The **cabinet tier cap** the Market will sell: tier 0 caps cabinet systems
  at tier 2, tiers 1–2 at 3, tiers 3+ at 4. A capped row explains itself
  (`NEEDS INFRASTRUCTURE TIER 3`) rather than disappearing.
- The **cabinet entry tiers** the scale opens with (a system already bought
  higher keeps what it had), permanent **capacity floors**, the board's
  **overflow allowance**, and the **facility cost** the rent is set from.

The room — Bedroom, Garage, Office Unit, Warehouse, Data Centre Campus,
Private Power Grid, Moon Facility — is presentation for the tier: the art the
shell is drawn in and the investor's "new premises" call. Nothing in gameplay
reads a room key for a number.

Cabinet systems sit on top of the Infrastructure Tier. Modules and perks
remain the strategic build: the systems decide how much of a pipeline the
cabinet can hold and how hot it may run; the pipeline decides what happens to
the tokens.

## 7. Perks

Perks are **Run Perks**: the investor deals a table of three (four or five
with Rolodex ranks) each time an Investor Target is met, the player takes one
or declines, and the pick is permanent for the rest of the run — no bench, no
swap, no cap. Perks survive level-ups, Infrastructure purchases and the final
victory (they carry into Deep Burn) and are gone when a new run starts. They
never touch the profile.

Perks should change rules rather than merely increase percentages.

Examples:

- **Ship It:** Jobs completed with less than 5% time remaining pay 2×.
- **Recursive Intern:** Every fifth agent creates another temporary agent.
- **Stack Overflow Tab:** The first bug generated each job is automatically fixed.
- **Quantised Everything:** Halves token cost but reduces quality.
- **Works on My Machine:** Local jobs gain throughput; deployment loses reliability.
- **Technical Debt:** Gain immediate cash; future jobs can spawn extra bugs.
- **Infinite Context:** Removes context limits while making token use grow exponentially.
- **The Wrapper:** Every completed job creates a weaker passive-income copy.
- **Vibe Check:** Skip testing, gain speed, and make quality unpredictable.

## 8. Token escalation

The game should begin with deliberately excessive values:

- First job: millions of tokens
- Early run: billions
- Mid-run: trillions
- Late run: quadrillions and beyond

Large numbers should be paired with comic comparisons:

- Novels equivalent
- Years of human speech
- Copies of Stack Overflow consumed
- React components generated
- Energy equivalent
- “One internet”

## 9. Run structure

A run is one continuous company on one continuous calendar. Each round
contains:

- Job selection
- Production rounds
- Random events
- Upgrade decisions
- Bills
- Performance review

### Investor Targets

Progression inside the run is the investor's ladder
(`content/investor/targets.json`). The run starts at **Investor Level 1** with
target 1 live from the first prompt; each target names a total burn (plus
optional quality, heat, catastrophe and profit conditions) and a deadline of
twelve rounds counted from the round it went live. Meeting it is a level-up:
the perk table is dealt, and on Continue the next target activates on the same
calendar — nothing resets, nothing moves, the terms simply get bigger
(30M tokens at level 1, 25T at level 7). Missing a deadline ends the run.

Level 7, **The Final Prompt**, is marked `final`: meeting it is the win. The
run may then Keep Burning into Deep Burn. Ordinary contracts never advance the
level; only the target does.

### Deep Burn

Deep Burn is the endless mode past the win: voluntary depths that stack
harder work and affixes in exchange for score, with targets generated from
the balance curves off the last authored one. The run carries on for as long
as the company survives; the deepest depth is a profile record.

### Pacing contract

- A matched ordinary job takes roughly 4-6 burns on entering an Infrastructure
  Tier and 2-3 after that tier's meaningful hardware upgrades.
- A normal fresh run targets 5-8 rounds per Investor Target; established
  permanent progression targets 4-7 and the supported veteran profile 3-6.
- Permanent power may make deliberately older postings trivial, but every board
  must still advertise work that exercises the installed rig.
- The authoritative thresholds and deterministic profile fixtures live in
  `content/balance/pacing_targets.json`; `tests/run_balance.tscn` plays real
  campaigns through every tier and reports pacing, heat, purchases and outcomes.

## 10. Failure states

- Bankruptcy
- Eviction
- Hardware fire
- Reputation collapse
- Unpayable debt
- Technical-debt cascade
- Power-grid overload
- Agent rebellion
- Accidental consciousness before invoicing

Hardware fire remains immediate when a committed prompt reaches the Cooling
Loop's heat capacity. Before BURN, including the first click of a queued session, the board
shows current and projected heat (`HEAT 0% -> 118% / FIRE`). This is a warning,
not a confirmation or safety interlock: knowingly committing the burn still
loses the run.

## 11. Meta-progression

Only completing the game — meeting the final Investor Target — banks
**Permanent Unlock** picks (`content/meta/unlocks.json`). Targets cleared on
the way up are level-ups inside the run, not sources of permanent power. A
pick is spent in the debrief on any area still open (rig, cooling, cash,
workflows, board width, Rolodex) and applies to every run from then on;
Run Perks never touch the profile.

Permanent unlocks include:

- New job sectors
- Starting hardware
- New perks
- New client types
- Better credit
- Improved screening
- New founder backgrounds

Possible starting characters:

- Bedroom Hacker
- Ex-Consultant
- ML Researcher
- Crypto Survivor
- Enterprise Architect
- Influencer Founder

## 12. Design test

The first prototype must answer one question:

> Is choosing jobs and combining modifiers fun before expensive presentation and progression systems exist?
