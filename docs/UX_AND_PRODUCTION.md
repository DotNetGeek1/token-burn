# Token Burn — UX and Production Plan

## 1. Visual direction

Use a **2D user interface with a small orthographic 2.5D office diorama**.

Avoid full 3D for the first version. The main gameplay is card selection, economic balancing, and combination building. Full 3D would add modelling, animation, camera, lighting, optimisation, and navigation work without strengthening the core loop.

### Art style

- Clean, information-dense cards
- Dark corporate-tech background
- Bright displays and warning indicators
- Chunky icons
- Simple low-poly props
- Limited but expressive animation
- Increasing visual clutter as the company scales

Reusable office props:

- Desk
- Laptop
- PC tower
- Server rack
- Portable air conditioner
- Cable bundles
- Coffee cups
- Fire extinguisher
- Landlord notices
- Cloud-provider hologram

## 2. Platform direction

- Design for mobile from the beginning.
- Use portrait orientation as the primary layout.
- Support desktop and web builds for testing.
- Consider tablet and landscape layouts after the portrait UX is stable.

## 3. Main navigation

Recommended bottom navigation:

```text
Office | Jobs | Build | Market | Menu
```

## 4. Operations screen

```text
┌─────────────────────────────────┐
│ TOKEN BURN              Month 3 │
│ $12,450    8.2 BT/s     Rep 37  │
├─────────────────────────────────┤
│                                 │
│       2.5D OFFICE VIEW          │
│                                 │
│   laptop       server rack      │
│      heat shimmer / cables      │
│                                 │
├─────────────────────────────────┤
│ ACTIVE JOB                      │
│ Build a “Simple” Marketplace    │
│ █████████████░░░  78%           │
│                                 │
│ Tokens     428 BT / 550 BT      │
│ Quality    73 / 80              │
│ Deadline   2.4 days             │
│ Heat       ████████░░ 81%       │
│                                 │
│ [BOOST]       [CLOUD BURST]      │
├─────────────────────────────────┤
│ Office  Jobs  Build  Market  ☰  │
└─────────────────────────────────┘
```

The diorama occupies roughly one-third of the screen and provides visual feedback without displacing the simulation data.

## 5. Job board

```text
┌─────────────────────────────────┐
│ JOB BOARD             Demand 4  │
│ Ad Spend: $340/day       [Edit] │
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
├─────────────────────────────────┤
│ Office  Jobs  Build  Market  ☰  │
└─────────────────────────────────┘
```

Cards scroll vertically. Critical contract information remains visible without opening a detail screen.

## 6. Build screen

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
│ │ RECURSIVE  │  │ FREE TRIAL │  │
│ │ INTERN     │  │            │  │
│ │ Every 5th  │  │ Cloud free │  │
│ │ agent +1   │  │ for 3 jobs │  │
│ └────────────┘  └────────────┘  │
├─────────────────────────────────┤
│ CURRENT SYNERGIES               │
│ ⚡ Reckless Scaling             │
│ Recursive Intern + Free Trial   │
│                                 │
│ Token rate              ×4.8    │
│ Cloud liability        $32.4K   │
├─────────────────────────────────┤
│ Office  Jobs  Build  Market  ☰  │
└─────────────────────────────────┘
```

Rules:

- Use short perk text.
- Use icons for categories and trigger types.
- Tap a card to open a bottom sheet containing exact rules and calculations.
- Show named synergies when recognised.

## 7. Post-job upgrade choice

```text
┌─────────────────────────────────┐
│ CONTRACT COMPLETE               │
│ Earned $7,450 • Burned 2.1 TT   │
├─────────────────────────────────┤
│ CHOOSE YOUR NEXT MISTAKE        │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ NEW GPU                     │ │
│ │ +35% local token rate       │ │
│ │ +400 W power draw           │ │
│ │                    $3,200   │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ RENT THE GARAGE             │ │
│ │ +3 hardware slots           │ │
│ │ Rent becomes $1,400/month   │ │
│ │                    $2,000   │ │
│ └─────────────────────────────┘ │
│                                 │
│ ┌─────────────────────────────┐ │
│ │ MYSTERIOUS CLOUD CREDITS    │ │
│ │ Free compute for 2 jobs     │ │
│ │ Something is clearly wrong  │ │
│ │                       FREE  │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

This screen should deliver the strongest roguelike decision moment in the core loop.

## 8. Mobile UX rules

- Reference viewport: approximately 1080 × 1920.
- Use responsive containers and safe-area margins.
- Minimum touch target: 44–48 logical pixels.
- No essential hover interactions.
- Use large numerical typography.
- Avoid more than two primary buttons on one row.
- Convert tooltips into tap-to-expand bottom sheets.
- Keep core navigation within thumb reach.
- Autosave after every decision.
- Pause or throttle simulation when backgrounded.
- Let players skip or accelerate number animations.
- Do not render token particles proportional to token count.

## 9. First vertical slice

Target one complete 10–15 minute run containing:

- One dwelling
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
- Complex cloud-provider submenus
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

- Portrait responsive UI
- Office diorama
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
