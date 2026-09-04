# 04 — Interaction specification

## Core grammar

`Select on CRT → inspect exact consequence → commit with physical control`

The contextual control is intentionally consistent in location and inconsistent only in verb. Its label must exactly describe the pending irreversible action.

## Commit button states

| State | Visual | Input |
| --- | --- | --- |
| Idle | Smoked shutter, low contrast, `SELECT ITEM` | Disabled. |
| Armed | Illuminated red face, exact verb and consequence | Single press. |
| Dangerous | Red/amber hazard frame, `HOLD …` | Hold 650 ms; progress ring/bar. |
| Busy | Mechanically latched, label `WORKING` | Disabled. Never skip. |
| Blocked | Dark face plus plain-language reason | Disabled. |

Extend `CabinetTab.primary_action()` to return:

```gdscript
{
  "label": "BUY",
  "enabled": true,
  "sub": "$480 · leaves $1,120",
  "tone": "normal", # normal | danger
  "confirm": "press", # press | hold
  "hold_seconds": 0.65,
  "pressed": callable
}
```

## Burn rules

- Commit becomes `BURN` only on Run.
- During burn playback it is busy/locked.
- If playback can be skipped, show a small `SKIP` control inside the CRT. Do not overload Commit.
- Abort/kill remains the lever. Require a hold where accidental activation loses work.

## Selection rules

- Only one primary selection per tab.
- Selected state must be visible without color alone: outline, notch, marker or depth change.
- Consequence subtext includes cost, bay, heat delta, reward or other material effect.
- Disabled state explains the blocker: `NEED $240 MORE`, `MARKET CLOSED`, `SELECT A BAY`, `COOL FIRST`.
- Selling is dangerous and uses hold confirmation.

## Maintenance

- System back or the maintenance control zooms out.
- Maintenance controls: Resume, Settings, Help, Records/Achievements, Save & Quit.
- Back/escape from Maintenance resumes operation.
- Maintenance never contains purchases, inventories or a hidden second build screen.
- Selecting a cabinet assembly may show its name/tier/stat as read-only inspection.

## Installation reveal

After a successful cabinet-system upgrade:

1. Lock input.
2. Zoom to Maintenance in 250–350 ms.
3. Replace the old tier asset with a short mechanical/flicker effect.
4. Show `SYSTEM NAME · TIER N` and its stat change for 1.0–1.5 s.
5. Return to the Market selection without losing scroll/selection.

The reveal is skippable from the CRT. It must not delay save persistence.

## Accessibility and input

- Full mouse, keyboard/controller and touch operation.
- Never require hover or drag.
- Visible focus state on every focusable control.
- Do not encode heat/danger with red alone; use text/icon/pattern.
- Respect reduced motion: installation becomes a crossfade; CRT shake and parallax disable.

