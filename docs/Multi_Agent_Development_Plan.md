# Token Burn — Multi-Agent Development Plan

## 1. Working Model

The project should be divided into independent workstreams with explicit ownership.

Each agent should receive:

* A clearly defined subsystem.
* A limited directory or file scope.
* Stable interfaces it may consume.
* Explicit interfaces it is responsible for providing.
* Acceptance criteria.
* A small set of tests.
* A list of files it must not modify.

The core rule is:

> Agents may depend on contracts, but should not depend on another agent’s internal implementation.

Avoid assigning agents vague tasks such as:

* “Improve the economy.”
* “Work on the UI.”
* “Add more content.”

Those tasks cause overlapping edits and inconsistent assumptions.

Instead assign bounded tasks such as:

* “Implement the job reward calculation service behind `IRewardCalculator`.”
* “Build the mobile job-selection screen using mock job data.”
* “Create 30 job definitions conforming to the existing job schema.”

---

# 2. Recommended Repository Structure

```text
token-burn/
├── docs/
│   ├── architecture/
│   ├── systems/
│   ├── content/
│   ├── decisions/
│   └── agent-tasks/
│
├── core/
│   ├── simulation/
│   ├── events/
│   ├── effects/
│   ├── state/
│   ├── rng/
│   └── validation/
│
├── systems/
│   ├── jobs/
│   ├── economy/
│   ├── compute/
│   ├── heat/
│   ├── demand/
│   ├── progression/
│   ├── upgrades/
│   └── events/
│
├── content/
│   ├── jobs/
│   ├── perks/
│   ├── hardware/
│   ├── dwellings/
│   ├── random_events/
│   └── balance/
│
├── ui/
│   ├── shell/
│   ├── operations/
│   ├── job_board/
│   ├── build_screen/
│   ├── upgrades/
│   ├── results/
│   ├── settings/
│   └── components/
│
├── presentation/
│   ├── office/
│   ├── animations/
│   ├── particles/
│   ├── audio/
│   └── visual_effects/
│
├── platform/
│   ├── save/
│   ├── analytics/
│   ├── mobile/
│   ├── localisation/
│   └── accessibility/
│
├── tools/
│   ├── content_validator/
│   ├── balance_simulator/
│   ├── debug_console/
│   └── importers/
│
└── tests/
    ├── unit/
    ├── integration/
    ├── simulation/
    └── content/
```

The directory structure should act as a social boundary. Agents should own folders, not scattered files throughout the codebase.

---

# 3. Foundation Contracts

Before assigning feature work, define the contracts every subsystem uses.

These should be implemented first and changed rarely.

## 3.1 Game State Contract

```text
RunState
JobState
EconomyState
ComputeState
DemandState
ProgressionState
InventoryState
StatisticsState
```

All state mutation should occur through systems or transactions. UI should not directly modify state.

## 3.2 Event Contract

```text
GameEvent
EventContext
EventResult
EventPriority
EventPhase
```

Suggested phases:

```text
BASE
ADDITIVE
MULTIPLICATIVE
CONVERSION
CAPS
TRIGGERS
FINALISE
```

## 3.3 Effect Contract

```text
EffectDefinition
EffectOperation
EffectTarget
EffectCondition
EffectResolver
EffectExecutionResult
```

## 3.4 Content Contract

```text
JobDefinition
PerkDefinition
HardwareDefinition
DwellingDefinition
RandomEventDefinition
UpgradeDefinition
BalanceProfile
```

## 3.5 Service Contracts

```text
ISaveService
IRandomService
IContentRepository
IEventBus
IEffectResolver
ISimulationClock
IAnalyticsService
IAudioService
```

Mock implementations should be provided so UI and content agents can work before the real systems are finished.

---

# 4. Workstreams

## Workstream A — Core Simulation

### Ownership

```text
core/simulation/
core/state/
core/rng/
```

### Responsibilities

* Authoritative run state.
* Simulation tick or turn progression.
* Deterministic execution.
* State snapshots.
* Transaction processing.
* Pause, resume and simulation speed.
* Headless simulation support.

### Interfaces provided

```text
start_run()
advance_simulation()
apply_transaction()
get_state_snapshot()
restore_state_snapshot()
```

### Must not own

* UI rendering.
* Job balance values.
* Perk content.
* Save-file implementation.
* Audio or visual effects.

### Acceptance criteria

* Same seed and inputs produce the same outcome.
* Simulation can run without UI.
* State mutation is traceable.
* Invalid state changes fail cleanly.
* 1,000 simulation steps can run without memory growth.

---

## Workstream B — Event and Effect Engine

### Ownership

```text
core/events/
core/effects/
core/validation/
```

### Responsibilities

* Event dispatch.
* Trigger ordering.
* Effect execution.
* Conditions and comparisons.
* Stacking behaviour.
* Recursion safeguards.
* Effect trace generation.
* Content validation.

### Interfaces provided

```text
emit_event()
resolve_effects()
evaluate_condition()
generate_effect_trace()
validate_effect_definition()
```

### Must not own

* Individual perks.
* Individual jobs.
* UI display logic.
* Economy balancing.

### Acceptance criteria

* Effects execute in deterministic order.
* Circular effect chains terminate safely.
* Invalid targets are reported clearly.
* Every calculation can produce a human-readable trace.
* Effect definitions can be added without modifying resolver code.

---

## Workstream C — Job System

### Ownership

```text
systems/jobs/
```

### Responsibilities

* Job offers.
* Job requirements.
* Accepting and rejecting jobs.
* Progress calculation.
* Quality requirements.
* Deadlines.
* Completion and failure.
* Job complications.
* Reward requests sent to the economy system.

### Interfaces consumed

```text
IEventBus
IEffectResolver
IRandomService
IContentRepository
```

### Interfaces provided

```text
generate_job_offers()
accept_job()
advance_job()
complete_job()
fail_job()
```

### Must not own

* Cash mutation.
* Advertising spend.
* Job-board UI.
* Job content files.

### Acceptance criteria

* Jobs can be resolved headlessly.
* Job progress responds to compute output.
* Jobs fail correctly when deadlines expire.
* Complications are deterministic under a fixed seed.
* Reward calculations use the shared event pipeline.

---

## Workstream D — Economy System

### Ownership

```text
systems/economy/
```

### Responsibilities

* Cash.
* Income.
* Recurring expenses.
* Rent.
* Cloud bills.
* Power bills.
* Debt.
* Purchases.
* Bankruptcy.
* Reward settlement.

### Interfaces provided

```text
can_afford()
purchase()
credit()
debit()
calculate_monthly_costs()
settle_job_reward()
process_bills()
```

### Must not own

* Job progression.
* Hardware effects.
* Shop UI.
* Upgrade content.

### Acceptance criteria

* All money movements create ledger entries.
* Negative balances follow explicit debt rules.
* Bills are deterministic.
* Purchases are atomic.
* Economy state can be reconstructed from the transaction log.

---

## Workstream E — Compute, Power and Heat

### Ownership

```text
systems/compute/
systems/heat/
```

### Responsibilities

* Local compute.
* Cloud compute.
* Token throughput.
* Power consumption.
* Cooling.
* Heat generation.
* Thermal throttling.
* Hardware failure risk.
* Capacity limits.

### Interfaces provided

```text
calculate_token_output()
calculate_power_draw()
calculate_heat()
apply_throttling()
get_capacity()
```

### Must not own

* Hardware store UI.
* Hardware content values.
* Cash deductions.
* Office graphics.

### Acceptance criteria

* Throughput calculation produces an effect trace.
* Heat and cooling interact predictably.
* Capacity limits are enforced.
* Cloud compute can be added independently of local hardware.
* Extreme values do not generate invalid numbers.

---

## Workstream F — Demand, Advertising and Reputation

### Ownership

```text
systems/demand/
```

### Responsibilities

* Job demand.
* Advertising spend.
* Lead generation.
* Reputation.
* Job rarity.
* Client quality.
* Sector unlocks.
* Offer refresh rates.

### Interfaces provided

```text
calculate_demand()
generate_leads()
update_reputation()
calculate_offer_quality()
```

### Must not own

* Job resolution.
* Economy ledger.
* Job-board presentation.
* Advertising screen layout.

### Acceptance criteria

* Advertising affects lead quantity or quality.
* Reputation affects available contracts.
* Demand curves are configurable.
* Offer generation remains reproducible with fixed seeds.

---

## Workstream G — Progression and Upgrades

### Ownership

```text
systems/progression/
systems/upgrades/
```

### Responsibilities

* Dwelling progression.
* Hardware slots.
* Perk slots.
* Upgrade choices.
* Unlock conditions.
* Meta-progression hooks.
* Run milestones.

### Interfaces provided

```text
get_available_upgrades()
purchase_upgrade()
check_unlocks()
advance_progression()
```

### Must not own

* Upgrade-card UI.
* Upgrade artwork.
* Core effect execution.
* Economy transaction internals.

### Acceptance criteria

* Unlock requirements are content-driven.
* Upgrade choices can be generated from weighted pools.
* Slot limits are enforced.
* Progression data can be tuned without code changes.

---

## Workstream H — Content Pipeline

### Ownership

```text
content/
tools/importers/
tools/content_validator/
```

### Responsibilities

* Content schemas.
* Job definitions.
* Perk definitions.
* Hardware.
* Dwellings.
* Events.
* Balance tables.
* Spreadsheet or CSV import.
* Content IDs and naming rules.
* Validation reports.

### Must not own

* Runtime resolver logic.
* UI scenes.
* Simulation code.

### Acceptance criteria

* Every content entry has a stable ID.
* Duplicate IDs are rejected.
* Broken references are reported.
* Tooltips are generated from live values where possible.
* Content can be added without recompiling gameplay systems.

### Recommended sub-agents

This workstream can itself be divided:

```text
Content Agent 1: jobs
Content Agent 2: perks
Content Agent 3: hardware and dwellings
Content Agent 4: random events
Content Agent 5: balance curves and economy tables
```

These agents should never modify schemas directly. Schema changes go through the architecture owner.

---

## Workstream I — UI Framework and Shared Components

### Ownership

```text
ui/shell/
ui/components/
```

### Responsibilities

* Navigation.
* Screen transitions.
* Shared buttons.
* Cards.
* Tooltips.
* Modal sheets.
* Number formatting.
* Progress bars.
* Responsive layout.
* Safe-area handling.
* Shared visual theme.

### Interfaces provided

```text
navigate_to()
show_modal()
show_tooltip()
format_large_number()
bind_state()
```

### Must not own

* Specific screen business logic.
* Game-state mutation.
* Simulation calculations.

### Acceptance criteria

* Components work at target mobile resolutions.
* No essential hover interactions.
* Text supports large values.
* Shared widgets use consistent spacing and styling.
* Components can render from mock data.

---

## Workstream J — Operations Screen

### Ownership

```text
ui/operations/
```

### Responsibilities

* Main game screen.
* Active job status.
* Token output.
* Heat.
* Cash.
* Reputation.
* Boost controls.
* Office viewport integration.

### Dependencies

* UI framework.
* Read-only simulation state.
* Job-system view models.
* Compute-system view models.

### Must not own

* Compute calculations.
* Job progression.
* Office rendering internals.

### Acceptance criteria

* Screen works with mock state.
* State updates do not require full redraw.
* Major values are readable at phone size.
* Effect breakdowns can be opened from displayed statistics.

---

## Workstream K — Job Board Screen

### Ownership

```text
ui/job_board/
```

### Responsibilities

* Job cards.
* Offer filtering.
* Job details.
* Accept and reject actions.
* Advertising summary.
* Refresh state.

### Must not own

* Job generation.
* Demand calculations.
* Reward calculations.

### Acceptance criteria

* Screen renders mock and live jobs.
* Cards support long descriptions safely.
* Accept actions call the job-system interface only.
* Locked or unaffordable states are clear.

---

## Workstream L — Build and Perk Screen

### Ownership

```text
ui/build_screen/
```

### Responsibilities

* Equipped perks.
* Available slots.
* Synergy display.
* Effect explanations.
* Build statistics.
* Perk details.

### Must not own

* Effect resolution.
* Perk definitions.
* Synergy detection rules.

### Acceptance criteria

* Build state is readable on a mobile screen.
* Perks display generated descriptions.
* Calculation details are inspectable.
* Invalid equipment operations are blocked by the owning system.

---

## Workstream M — Upgrade and Results Screens

### Ownership

```text
ui/upgrades/
ui/results/
```

### Responsibilities

* Post-job summary.
* Upgrade selection.
* Monthly summary.
* Run-end screen.
* Failure screen.
* Reward animations.

### Must not own

* Upgrade generation.
* Reward calculations.
* Progression rules.

### Acceptance criteria

* Upgrade choices use data supplied by progression.
* Results reflect authoritative simulation values.
* Animations can be skipped.
* Every failure state has a valid presentation path.

---

## Workstream N — Office Diorama and Presentation

### Ownership

```text
presentation/office/
presentation/animations/
presentation/visual_effects/
```

### Responsibilities

* 2.5D office scene.
* Hardware placement.
* Dwelling visual progression.
* Heat effects.
* Cable clutter.
* Screen activity.
* Warning indicators.
* Visual reactions to events.

### Interfaces consumed

```text
OfficePresentationState
PresentationEvent
```

### Must not own

* Hardware capacity logic.
* Upgrade rules.
* Heat calculations.
* Game-state mutation.

### Acceptance criteria

* Diorama can render from a presentation snapshot.
* Visual objects are pooled where appropriate.
* Mobile performance remains within target.
* Presentation can be disabled without affecting simulation.

---

## Workstream O — Save, Load and Platform

### Ownership

```text
platform/save/
platform/mobile/
```

### Responsibilities

* Save-file format.
* Autosave.
* Save migration.
* Application suspend/resume.
* Device-safe paths.
* Corruption recovery.
* Mobile lifecycle handling.

### Interfaces provided

```text
save_run()
load_run()
list_saves()
migrate_save()
create_backup()
```

### Must not own

* Game-state structures.
* UI screens.
* Economy logic.

### Acceptance criteria

* Save and load preserve deterministic state.
* Interrupted writes do not destroy the previous save.
* Old save versions can be migrated.
* Autosave works during mobile lifecycle events.

---

## Workstream P — Audio

### Ownership

```text
presentation/audio/
```

### Responsibilities

* UI sounds.
* Job completion feedback.
* Heat warnings.
* Server ambience.
* Music state.
* Audio settings.
* Ducking and mixing.

### Must not own

* Gameplay event logic.
* UI components.
* Simulation timing.

### Acceptance criteria

* Audio responds to presentation events.
* All audio can be disabled.
* Repeated events do not create sound spam.
* Mobile suspend and resume behave correctly.

---

## Workstream Q — Testing and Simulation Tools

### Ownership

```text
tools/balance_simulator/
tools/debug_console/
tests/
```

### Responsibilities

* Unit-test harness.
* Integration tests.
* Headless simulations.
* Combo scanning.
* Performance benchmarks.
* Debug console.
* Effect trace viewer.
* Balance exports.

### Acceptance criteria

* One command runs all tests.
* One command simulates at least 1,000 runs.
* Invalid perk combinations are flagged.
* Infinite trigger chains are detected.
* Results export to CSV or JSON.
* Test failures identify the owning subsystem.

---

# 5. Agent Dependency Order

Agents should not all start simultaneously on undefined foundations.

## Phase 0 — Contracts

Assign one architecture agent to establish:

* Folder structure.
* State schemas.
* Event schemas.
* Effect schemas.
* Service interfaces.
* Naming conventions.
* Test conventions.
* Mock services.

No feature agent should change these contracts without an architecture decision record.

## Phase 1 — Parallel Core Work

Start these together:

```text
Core simulation
Event/effect engine
Job system
Economy system
Compute/heat system
Demand system
Progression system
Save system
UI framework
Content schema and validators
```

Each agent works against agreed interfaces and mocks.

## Phase 2 — Parallel Feature Work

Start after Phase 1 contracts compile:

```text
Operations screen
Job board
Build screen
Upgrade screen
Office diorama
Audio
Initial content packs
Balance simulator
```

## Phase 3 — Integration

Use a dedicated integration agent or human owner to:

* Merge workstreams.
* Fix contract mismatches.
* Run end-to-end tests.
* Resolve scene wiring.
* Validate save compatibility.
* Check mobile performance.

Feature agents should not independently solve integration conflicts by editing other teams’ folders.

## Phase 4 — Balance and Polish

Parallel tasks:

```text
More content
Economy tuning
Perk combo testing
UI polish
Accessibility
Audio polish
Performance
Onboarding
Analytics
Store preparation
```

---

# 6. Branching Strategy

Use one branch per bounded task, not one long-lived branch per agent.

Example:

```text
feat/job-offer-generation
feat/effect-recursion-guards
feat/ui-job-card
content/perks-starter-pack
test/economy-ledger
fix/mobile-safe-area
```

Avoid branches such as:

```text
alex-agent-work
agent-3
ui-improvements
misc-fixes
```

Each branch should contain one coherent change.

## Integration branch model

```text
main
└── develop
    ├── feat/*
    ├── content/*
    ├── test/*
    └── fix/*
```

For a smaller project, merging directly into `main` is also viable if:

* Tests are fast.
* Pull requests are small.
* Feature flags protect incomplete work.
* Main remains playable.

---

# 7. File Ownership Rules

Create a `CODEOWNERS` file or equivalent.

Example:

```text
/core/simulation/           @simulation-owner
/core/effects/              @effects-owner
/systems/jobs/              @jobs-owner
/systems/economy/           @economy-owner
/content/perks/             @content-perks-owner
/ui/components/             @ui-framework-owner
/ui/job_board/              @job-board-owner
/presentation/office/       @office-owner
/platform/save/             @save-owner
```

Agents should not modify code outside their ownership area unless the task explicitly includes that change.

Shared files should be minimised.

High-conflict files to avoid:

```text
main.gd
game_manager.gd
constants.gd
global_state.gd
all_content.json
theme.tres
project.godot
```

Prefer multiple focused files over central registries.

---

# 8. Integration Contracts

Every subsystem should expose a narrow public API.

## Bad

```text
job_system.current_jobs[0].internal_progress +=
compute_system.local_hardware[2].raw_output
```

## Good

```text
job_system.apply_compute_output(job_id, output_packet)
```

## View Models

UI should receive read-only view models:

```text
JobCardViewModel
OperationsViewModel
BuildViewModel
UpgradeChoiceViewModel
RunSummaryViewModel
```

A view model should already contain:

* Display-ready labels.
* Formatted numbers.
* State flags.
* Progress values.
* Content IDs.
* Action availability.

UI agents should not reconstruct gameplay rules.

---

# 9. Message and Event Boundaries

Use domain events for cross-system communication.

Examples:

```text
JobAccepted
JobCompleted
JobFailed
CashChanged
BillProcessed
UpgradePurchased
PerkEquipped
HeatThresholdCrossed
MonthEnded
RunEnded
```

Event payloads should be immutable.

Example:

```json
{
  "event": "JobCompleted",
  "job_id": "job.fintech_auth",
  "reward": 8200,
  "tokens_burned": 1400000000000,
  "quality": 87,
  "completion_time": 3.4
}
```

Do not use the event bus for everything. Direct service calls are better when one subsystem explicitly requests work from another.

Use events for:

* Notifications.
* Reactions.
* Presentation.
* Analytics.
* Optional subscribers.

Use direct calls for:

* Queries.
* Required calculations.
* Purchases.
* State-changing commands.

---

# 10. Agent Task Template

Every agent task should use this format.

## Task

Implement deterministic job-offer generation.

## Owned files

```text
systems/jobs/job_offer_generator.gd
systems/jobs/job_offer_result.gd
tests/unit/jobs/test_job_offer_generator.gd
```

## May read

```text
core/rng/
content/jobs/
systems/demand/interfaces/
```

## Must not modify

```text
core/effects/
systems/economy/
ui/
content/jobs/*.tres
```

## Inputs

```text
JobDefinition[]
DemandSnapshot
ReputationValue
IRandomService
```

## Outputs

```text
JobOffer[]
```

## Behaviour

* Filter jobs by unlock state.
* Weight jobs by reputation and demand.
* Produce a fixed number of offers.
* Do not return duplicate jobs unless explicitly allowed.
* Produce deterministic results for a fixed seed.

## Acceptance criteria

* Same seed produces identical offers.
* Locked jobs are never returned.
* Empty pools return a valid empty result.
* Weighted selection passes statistical smoke tests.
* Unit tests cover minimum, normal and invalid inputs.

## Deliverables

* Implementation.
* Tests.
* One short markdown note describing assumptions.
* No unrelated refactoring.

---

# 11. Pull Request Requirements

Every agent pull request should include:

```text
Purpose
Owned subsystem
Files changed
Interfaces changed
Tests added
Known limitations
Manual test steps
Screenshots for UI changes
Save compatibility impact
```

Reject pull requests that:

* Mix unrelated changes.
* Refactor shared files unnecessarily.
* Add dependencies without justification.
* Introduce hard-coded balance values in logic.
* Modify schemas without an architecture decision.
* Contain no tests for gameplay systems.
* Modify project-wide settings without calling it out.

---

# 12. Architecture Decision Records

Create small records for decisions that affect several agents.

Directory:

```text
docs/decisions/
```

Example:

```text
ADR-001-use-event-phases.md
ADR-002-content-identifiers.md
ADR-003-save-versioning.md
ADR-004-number-representation.md
ADR-005-ui-view-models.md
```

Template:

```text
# Decision

## Context

## Chosen approach

## Alternatives considered

## Consequences

## Migration impact
```

This prevents every new agent from reopening settled architectural questions.

---

# 13. Feature Flags

Incomplete features should be guarded behind flags.

Example:

```text
office_diorama_enabled
random_events_enabled
meta_progression_enabled
analytics_enabled
```

This allows partial systems to merge without breaking the playable build.

Flags should be configuration-driven, not scattered conditional literals.

---

# 14. Recommended Initial Agent Allocation

For the current stage, use approximately eight parallel agents.

## Agent 1 — Architecture and Contracts

* Review current implementation.
* Define public interfaces.
* Establish directory ownership.
* Create architecture decision records.
* Provide mocks.

## Agent 2 — Effect Engine

* Triggers.
* Conditions.
* Ordering.
* Effect traces.
* Recursion safeguards.

## Agent 3 — Job and Demand Systems

* Job generation.
* Job execution.
* Advertising.
* Reputation.
* Offer pools.

## Agent 4 — Economy and Progression

* Cash.
* Bills.
* Rent.
* Purchases.
* Upgrades.
* Dwelling progression.

## Agent 5 — Compute and Heat

* Token throughput.
* Hardware capacity.
* Cloud compute.
* Heat.
* Cooling.
* Throttling.

## Agent 6 — Mobile UI

* Shared components.
* Operations screen.
* Job board.
* Upgrade screen.
* Mobile responsiveness.

This agent should use mocks and avoid gameplay logic.

## Agent 7 — Content

* Starter jobs.
* Starter perks.
* Hardware.
* Dwellings.
* Random events.
* Balance data.

## Agent 8 — Testing and Tooling

* Unit-test infrastructure.
* Headless runs.
* Combo scanner.
* Content validation.
* Debug screen.

A ninth agent can own the office diorama and presentation layer once the state interfaces are stable.

---

# 15. Suggested First Sprint

## Architecture

* Lock state contracts.
* Lock event names.
* Lock content IDs.
* Lock service interfaces.
* Add mocks.

## Gameplay

* One complete job lifecycle.
* Cash and rent.
* Token throughput.
* Heat and throttling.
* Three perks using the generic effect engine.
* Three upgrade choices.

## UI

* Operations screen.
* Job board.
* Upgrade-choice screen.
* Effect trace popup.

## Content

* Ten jobs.
* Ten perks.
* Five hardware items.
* Three dwellings.
* Five events.

## Tools

* Content validation.
* Deterministic simulation test.
* 1,000-run headless simulation.
* Effect-chain recursion test.

## Definition of done

A player can:

1. Start a seeded run.
2. Select a job.
3. Burn tokens.
4. Generate heat.
5. Complete or fail the job.
6. Receive money.
7. Choose an upgrade.
8. Pay rent.
9. Save and resume.
10. Inspect why a number changed.

---

# 16. Integration Risks

## Shared schema churn

Changing `JobDefinition` repeatedly will block several agents.

Mitigation:

* Lock version one early.
* Add fields compatibly.
* Use optional fields with defaults.
* Require an ADR for breaking changes.

## Global singleton abuse

Agents may place unrelated responsibilities in one global manager.

Mitigation:

* Keep public services narrow.
* Prohibit UI logic in global services.
* Prefer dependency injection or service registration.

## Scene-file conflicts

Godot scene and resource files can be painful when several agents edit them.

Mitigation:

* One owner per scene.
* Break large scenes into child scenes.
* Keep scripts separate from scenes.
* Avoid multiple agents editing the root UI shell.

## Content and code drifting apart

Content agents may produce unsupported effects.

Mitigation:

* Machine-readable schemas.
* Validation tools.
* CI checks.
* Generated reference documentation.

## Hidden balance constants

Agents may place magic numbers in code.

Mitigation:

* All tunable values belong in balance profiles or content.
* Tests may contain fixed values.
* Production logic should reference named parameters.

## Save corruption

State contracts may change while save work proceeds.

Mitigation:

* Version every save.
* Separate runtime state from serialised DTOs.
* Add migration tests.
* Preserve known old fixtures.

---

# 17. Rules for Agent Prompts

Each prompt should state:

* The exact subsystem.
* The exact output.
* Owned directories.
* Forbidden directories.
* Required interfaces.
* Required tests.
* Whether schema changes are allowed.
* Whether dependencies may be added.
* The expected report format.

Example instruction:

```text
Implement only the compute throughput subsystem.

You own:
- systems/compute/
- tests/unit/compute/

You may consume:
- IEffectResolver
- IEventBus
- ComputeState
- HardwareDefinition

Do not modify:
- core/effects/
- content/
- ui/
- project settings

All tunable values must come from definitions or balance data.
Add unit tests for base throughput, additive modifiers,
multipliers, caps, thermal throttling and extreme values.

Return:
1. Summary
2. Files changed
3. Tests run
4. Assumptions
5. Remaining risks
```

---

# 18. Definition of System Stability

A subsystem is stable enough for other agents to consume when:

* Its public API is documented.
* It has a mock or reference implementation.
* It has automated tests.
* Error behaviour is defined.
* Its events are documented.
* Its state ownership is explicit.
* Its tunable parameters are externalised.
* It does not require consumers to access internal fields.

---

# 19. Practical Rule of Thumb

Two agents should not modify the same file during the same sprint.

When that cannot be avoided:

* Assign one explicit file owner.
* Other agents provide patches, notes or requested interface changes.
* The owner performs the final integration.

The biggest danger is not weak agents. It is ten capable agents all “helpfully” refactoring `game_manager.gd` at once.
