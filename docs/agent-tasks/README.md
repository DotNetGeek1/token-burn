# Agent Tasks

This directory holds bounded task briefs for multi-agent development on Token Burn. Each file describes one agent assignment: owned files, forbidden areas, inputs/outputs, acceptance criteria, and deliverables.

See [Multi_Agent_Development_Plan.md](../Multi_Agent_Development_Plan.md) sections 2, 7, 10, 12, and 13 for the full orchestration model.

## Naming convention

```text
W<wave>-<agent>-<short-name>.md
```

| Prefix | Meaning |
|---|---|
| `W0-*` | Foundation wave — contracts and shared core (must land before parallel feature work) |
| `W1-*` | Wave 1 — parallel core systems against stable interfaces |
| `W2-*` | Wave 2 — scaffolding, integration prep, and cross-cutting tooling |

## Task template

Every agent brief must include these sections (from plan section 10):

### Task

One sentence describing the bounded outcome.

### Owned files

Exact paths the agent may create or modify.

### May read

Dependencies and contracts the agent may consume but not edit.

### Must not modify

High-conflict or out-of-scope paths. Agents must not touch these unless the brief explicitly allows it.

### Inputs

Interfaces, schemas, or data the implementation receives.

### Outputs

Public APIs, events, or artefacts the implementation must provide.

### Behaviour

Bullet list of required behaviour and edge cases.

### Acceptance criteria

Testable conditions that define done.

### Deliverables

Implementation, tests, a short assumptions note, and no unrelated refactoring.

## Workflow

1. Read the wave brief (`W1-wave1-briefs.md`) for assignment and ownership.
2. Open your agent-specific task file when one exists.
3. Check [docs/decisions/](../decisions/) for ADRs that affect your area.
4. Respect [CODEOWNERS](../../CODEOWNERS) — do not edit paths owned by another team.
5. Return a report: summary, files changed, tests run, assumptions, remaining risks.

## Related artefacts

| Artefact | Purpose |
|---|---|
| [CODEOWNERS](../../CODEOWNERS) | Directory ownership for review routing |
| [docs/decisions/](../decisions/) | Architecture decision records (ADRs) |
| [config/feature_flags.json](../../config/feature_flags.json) | Runtime toggles for incomplete features |
