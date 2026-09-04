# Token Burn — UX and Production Plan

## 1. Visual direction

The game is **one machine**: the Burn Cabinet, a front-on, layered 2D
industrial console with a wide CRT in the middle, a telemetry rail beside it,
an abort lever on the left, the command deck under the glass and the workflow
backplane across the bottom.

Avoid full 3D. The main gameplay is card selection, economic balancing, and combination building. Full 3D would add modelling, animation, camera, lighting, optimisation, and navigation work without strengthening the core loop.

### Art style

- Riveted rust-brown steel, scorched edges, amber stencil paint, dark phosphor glass
- Palette: `#EDAD3D` amber, `#6BEB99` phosphor, `#EB4738` red, near-black steel
- Front-on camera, one key light, no numbers or changing labels baked into art
- Clean, information-dense CRT cards inside the bezel
- Chunky, code-drawn state outlines that still read in grayscale
- Limited but expressive animation
- The cabinet itself gets bigger and stranger as its systems are upgraded

Every layer is generated from one shared style preamble and registered in the
`cabinet_v2` block of `presentation/asset_catalog.json`. Art decorates
containers; it never carries geometry.

### Two cameras

- **Operation** — the machine fills the safe area. This is where the run is
  played.
- **Maintenance** — the same machine zoomed out (250–350 ms; a crossfade under
  reduced motion) over the workshop wall, with Resume / Settings / Help /
  Records / Save & Quit down the left and the five system mounts — Compute
  Stack, Cooling Loop, Power Bus, Workflow Backplane, Control Rack — along the
  floor. Mounts are inspected, not operated. System back from the run tab
  opens Maintenance; the player never leaves the cabinet.

### The machine evolves

The visible progression is the cabinet's five systems, each at tier 1–4.
Buying a tier in the Market's SYSTEMS shelf saves, pulls the camera back to
Maintenance, flickers the old part out, seats the new one, prints
`NAME · TIER N` and the stat delta, and returns to the Market selection. The
tier sum names the cabinet's generation on the wall (Improvised Cabinet →
Impossible Engine).

## 2. Platform direction

- Design mobile gameplay for landscape orientation only.
- Support desktop and web gameplay from 1920×1080 upward.
- The cabinet must pass at five viewports: `1600×900`, `1280×720`,
	`1024×768`, `960×540` and `854×480` (`tests/playtests/pt_cabinet_viewports.gd`).
- Portrait is not a release target and must not drive cabinet composition.

Layout comes from `presentation/cabinet_layout_profiles.json`: `wide`
(aspect ≥ 1.65, width ≥ 1100 px, ten bays in a row), `compact` (aspect ≥ 1.35,
five bays × two rows) and `tablet` (aspect < 1.35, telemetry as a strip). See
[Technical Architecture](TECHNICAL_ARCHITECTURE.md#2a-burn-cabinet-shell)
before moving an instrument.

## 3. Main navigation

Everything is a tab on the central CRT:

```text
RUN | CONTRACTS | MODULES | MARKET | PERKS
```

There is no menu tab and no MENU door. Maintenance (the menu, settings,
records) is a camera move, reached by system back (Escape / Android back) from
the run tab; system back from any other tab first returns to the run tab.

## 4. Operation view

```text
┌─┬───────────────────────────────────────────┬────────┐
│A│ RUN  CONTRACTS  MODULES  MARKET  PERKS    │ ×1.84  │
│B│ ┌───────────────────────────────────────┐ │ drum   │
│O│ │  Build a “Simple” Marketplace     78% │ │        │
│R│ │  Tokens 428 BT / 550 BT               │ │ HEAT   │
│T│ │  Quality 73 / 80   Deadline 2.4 days  │ │ ████░░ │
│ │ │  HEAT 81% -> 96%                      │ │        │
│ │ └───────────────────────────────────────┘ │ STATUS │
├─┴───────────────────────────────────────────┤ ledger │
│ [OVERRIDE]   ┃  BURN  ┃   [COOLDOWN]  ●●○  │ feed   │
│              ┃ 7 prompts                    │        │
├─────────────────────────────────────────────┴────────┤
│ 1 2 3 4  HOUSE STYLE                                 │
│ [bay][bay][bay][bay][bay][bay][bay][▒▒][▒▒][▒▒]      │
└──────────────────────────────────────────────────────┘
```

The CRT is at least 65 % of the safe width and 50 % of its height on every
profile. Locked bays wear the shutter and are not focusable; selected, target
and active bays are code-drawn outlines. The Burn Feed collapses to nothing
when idle and overlays the telemetry rail during a burn.

### Commit grammar

One physical button commits everything. The grammar is always the same:

> **select on the CRT → inspect the consequence → commit physically**

- The active tab's `primary_action()` names the verb on the button — BURN,
  ACCEPT, SEAT, EJECT, BUY, REROLL, SELL, FIT, BENCH, UPGRADE — and the
  consequence under it (`$570 · 7 prompts`).
- Nothing picked: the shutter is down (`SELECT ITEM`, `SELECT A BAY`,
  `TAKE A CONTRACT FIRST`).
- Picked but not actionable: dark face and the reason (`NEED $240 MORE`,
  `MARKET CLOSED`, `COOL FIRST`, `NEXT CHAPTER UNLOCKS TIER 3`).
- Destructive actions (SELL, lever pulls) carry the hazard frame and a
  **hold** of 0.65 s with a filling ring; releasing early cancels cleanly.
- During a batch the button reads `WORKING` and does nothing. Skipping the
  playback is a small control inside the CRT, never the commit button.
- Selection and scroll position survive a successful commit.

## 5. Job board

The CONTRACTS tab. Cards sit on the glass; ACCEPT is the commit button.

```text
┌─────────────────────────────────┐
│ JOB BOARD             4 SLOTS   │
│ Contract fit             [VIEW] │
├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │
│ │ URGENT • FINTECH            │ │
│ │ Fix Authentication System   │ │
│ │                             │ │
│ │ Reward          $8,200      │ │
│ │ Tokens          1.4 TT      │ │
│ │ Quality         85          │ │
│ │ Deadline        4 days      │ │
│ │                             │ │
│ │ ⚠ Legacy Code               │ │
│ │ ⚠ Compliance Review         │ │
│ │                [ACCEPT]     │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ “QUICK LANDING PAGE”        │ │
│ │ Reward $900 • 180 BT        │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

Cards scroll vertically. Critical contract information remains visible without opening a detail screen.

## 6. Build screen

The PERKS tab (loadout and synergies) and the MODULES tab (bench, and the
backplane bays under the glass: FIT / BENCH / SEAT / EJECT).

```text
┌─────────────────────────────────┐
│ YOUR BUILD            4 / 5     │
├─────────────────────────────────┤
│ ┌────────────┐  ┌────────────┐  │
│ │ SHIP IT    │  │ QUANTISED  │  │
│ │            │  │ EVERYTHING │  │
│ │ Late jobs  │  │ -50% cost  │  │
│ │ pay 2×     │  │ -8 quality │  │
│ └────────────┘  └────────────┘  │
│                                 │
│ ┌────────────┐  ┌────────────┐  │
│ │ FIRST TRY  │  │ COOL       │  │
│ │            │  │ OPERATOR   │  │
│ │ One-shot   │  │ Cool jobs  │  │
│ │ trains OUT │  │ train T    │  │
│ └────────────┘  └────────────┘  │
├─────────────────────────────────┤
│ CURRENT SYNERGIES               │
│ Recursion Density               │
│ 3 recursion cards active        │
│                                 │
│ House Style  OUT ×1.24          │
│              Q ×1.08 T ×1.16    │
└─────────────────────────────────┘
```

Rules:

- Use short perk text.
- Use icons for categories and trigger types.
- Tap a card to open a detail sheet containing exact rules and calculations.
- Show named synergies when recognised.

## 7. Post-job upgrade choice

The angel table (three perks, take one or decline) is an overlay; everything
paid for is the MARKET tab: the MODULES shelf, the hardware shelves, the
SYSTEMS shelf and the RIG shelf (what is installed, sellable back).

```text
┌─────────────────────────────────┐
│ MARKET   MODULES  HARDWARE …    │
│          SYSTEMS  RIG           │
├─────────────────────────────────┤
│ SYSTEMS                         │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ POWER BUS       TIER 1 → 2  │ │
│ │ Transformer                 │ │
│ │ 2 → 4 HARDWARE SLOTS        │ │
│ │                    $2,800   │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ COOLING LOOP    TIER 1 → 2  │ │
│ │ Radiator                    │ │
│ │ 16 → 97 COOLING ·           │ │
│ │ 100 → 140 HEAT CAP          │ │
│ │                    $2,200   │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ COMPUTE STACK   TIER 2 → 3  │ │
│ │ NEXT CHAPTER UNLOCKS TIER 3 │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
        ┃  UPGRADE  ┃
        ┃  $2,800 · 2 → 4 SLOTS
```

The SYSTEMS shelf shows only each system's **next** tier with its cost and
effect. A row the chapter caps or the player cannot afford stays visible and
says why. Buying one plays the install reveal (section 1) and returns to the
same selection.

Choosing what to buy next should deliver the strongest roguelike decision
moment in the core loop.

## 8. Mobile UX rules

- Reference viewports: the five in section 2, landscape only.
- Use responsive containers and safe-area margins (16 px inset plus the
  display's own insets).
- Minimum touch target: 48 logical pixels; 44 at `854×480`.
- Body copy never drops below 12 px; 16 px is the target at `1280×720`.
- No hover and no drag is ever required. Everything is select then commit.
- Every commit is a press or a hold on one button that keyboard, controller
  and finger reach the same way (`ui_accept` held while focused is a hold).
- Holds cancel cleanly on release, pointer exit, focus loss or window unfocus.
- Reduced motion replaces the camera zoom and the install flicker with
  crossfades and shortens them.
- Use large numerical typography.
- Convert tooltips into tap-to-expand detail sheets.
- Autosave after every decision; save before an install reveal plays.
- Pause or throttle simulation when backgrounded.
- Let players skip or accelerate number animations from the CRT.
- Do not render token particles proportional to token count.

## 9. First vertical slice

Target one complete 10–15 minute run containing:

- One chapter
- Three hardware upgrades
- Twelve jobs
- Fifteen perks
- Five random events
- Cash, tokens, quality, heat, and deadlines
- One month-end rent payment
- One loss condition
- One capstone contract
- Burn Lab debug screen
- Automated simulation of 1,000 runs

## 10. Excluded from the first slice

- Detailed 3D environment
- Staff management
- Multiple currencies
- Investors
- Hosted-compute provider submenus
- Meta-progression
- Online services
- Procedurally generated perk text
- Real code-generation gameplay

## 11. Suggested milestone order

### Milestone 1: Headless simulation

- Run state
- Deterministic random number generator
- Jobs
- Effect resolver
- Basic economy
- Automated tests

### Milestone 2: Playable greybox

- Job board
- Active job screen
- Upgrade selection
- Loss and victory states
- Local save

### Milestone 3: Build system

- Fifteen initial perks
- Synergy display
- Trigger traces
- Guard-limit handling
- Combo scanner

### Milestone 4: Mobile presentation

- Landscape responsive cabinet shell
- Cabinet systems and the maintenance view
- Animation and sound feedback
- Android device build

### Milestone 5: Balance and content

- Burn Lab
- Batch simulations
- Expanded jobs and events
- Difficulty profiles
- Performance tuning

## 12. Success criteria

The vertical slice is successful when:

- A player understands the loop without external explanation.
- At least three distinct build strategies are viable.
- Players can discover combinations that feel unfair in a satisfying way.
- Invalid trigger chains terminate safely.
- A full run works reliably on a mid-range mobile device.
- The game remains enjoyable with placeholder art.
