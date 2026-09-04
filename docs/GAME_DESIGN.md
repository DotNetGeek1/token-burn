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
7. Take one free perk from the angel table (or decline), then buy modules, hardware and cabinet system tiers in the Market and route contracts through trained workflows.
8. Repeat until the run is won or collapses.

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
- **Reputation:** Opens stretch contracts on the band above the current chapter.
- **Workflow mastery:** Each named pipeline trains run-long OUTPUT, QUALITY, and THERMAL multipliers. Hardware sets the raw token rate; the workflow decides how obscene that output becomes.

Mastery is scored once, the first time a contract's remaining tokens hit zero. Clean and cool are the whole contract's history: bugs created on any burn, and peak heat across every burn. Shipping or polishing after that cannot train the same contract again.

- **OUTPUT** seeds the pipeline's progress multiplier. The number the board shows is `token_mult × progress_mult`. Raw hardware tokens stay raw.
- **QUALITY** multiplies positive pipeline quality only. Penalties and the contract's passive quality share stay additive.
- **THERMAL** divides positive pipeline heat only. Signed cooling stays additive; ambient rig heat is unchanged.

Tag density is the main build glue. Equipped perks and slotted modules count; the bench does not. Named perk pairs remain easter eggs.

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

Early desktops still cap at four copies so the first two chapters teach floor
space. From GPU Rack onward the shop does not invent a MAX_LEVEL: money, floor
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
  chapter change lowers a tier.
- Perk, module, upgrade and meta bonuses stay additive on top of the tier
  value. The tier is the baseline, not the ceiling.
- The sum of the five tiers (5–20) names the cabinet's **generation**:
  Improvised Cabinet, Spliced Rig, Token Furnace, Grid Eater, Impossible
  Engine. The generation is presentation only; nothing reads a number back
  out of it.
- Buying a tier plays an install reveal: the camera pulls back to the
  Maintenance view, the old part flickers out, the new part seats, and the
  stat delta is printed. It is skippable and crossfades under reduced motion.

### Campaign chapters

The seven chapters — Bedroom, Garage, Office Unit, Warehouse, Data Centre
Campus, Private Power Grid, Moon Facility — are where a run is staked, not a
ladder of properties to buy. A run starts in one chapter, beats that chapter's
ascension contract, and the next chapter unlocks for the next run. Nothing in
a run buys the next room.

A chapter sets:

- **Rent** and the investor's **starting cash**.
- The **starting hardware** the room comes with, so contracts are sized to a
  rig the room expects rather than whatever the player happens to own.
- The **starting system tiers**: a fresh Garage run opens with Garage-grade
  systems; a run that had already bought higher keeps what it had.
- The **maximum system tier** the Market will sell: Bedroom and Garage cap at
  tier 2, Office Unit and Warehouse at tier 3, Data Centre Campus onward at
  tier 4. A capped row explains itself (`NEXT CHAPTER UNLOCKS TIER 3`)
  rather than disappearing.

Cabinet systems are infrastructure. Modules and perks remain the strategic
build: the systems decide how much of a pipeline the cabinet can hold and how
hot it may run; the pipeline decides what happens to the tokens.

## 7. Perks

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

A strong initial structure is a twelve-month company run.

Each month contains:

- Job selection
- Production rounds
- Random events
- Upgrade decisions
- Bills
- Performance review

The final month presents a capstone contract. Winning unlocks a higher compute age and more extreme mechanics.

### Pacing contract

- A matched ordinary job takes roughly 4-6 burns on chapter entry and 2-3
  after the chapter's meaningful hardware upgrades.
- A normal fresh chapter targets 5-8 rounds; established permanent progression
  targets 4-7 and the supported veteran profile targets 3-6.
- Permanent power may make deliberately older postings trivial, but every board
  must still advertise work that exercises the installed rig.
- The authoritative thresholds and deterministic profile fixtures live in
  `content/balance/pacing_targets.json`; `tests/run_balance.tscn` plays real
  chapter transitions and reports pacing, heat, purchases and outcomes.

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

Permanent unlocks may include:

- The next campaign chapter, and with it a higher system-tier cap
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
