# 03 — Layout and responsive specification

## Principle

Build a responsive game board wearing cabinet artwork. Do not fit the whole UI to a 16:9 photograph.

Current reviewed geometry gives the CRT only `0.494 × 0.385` of the plate (about 19% of total area). v2 targets roughly 70–75% of width and 55–60% of height for the playable CRT.

## Region profiles

The exact starter values are in `data/cabinet_regions_v2.json`.

### Wide: aspect ≥ 1.65

- Single-row 10-bay backplane.
- Slim right telemetry rail.
- Abort lever on the left edge.
- CRT target: about 72% × 58%.
- Decorative edges may crop using cover behavior.

### Compact landscape: 1.35 ≤ aspect < 1.65

- CRT remains dominant.
- Backplane becomes 5×2.
- Telemetry becomes a narrower stack or two-column strip.
- Lever and commit control remain at least 48 logical pixels.

### Tablet / near-square: aspect < 1.35

- Landscape orientation is still expected.
- Backplane stays 5×2.
- Telemetry becomes a horizontal strip under the CRT if the side rail would reduce readable width.
- Decorative side wings disappear before interactive areas shrink.

## Required targets

- 1600×900 desktop
- 1280×720 design baseline
- 1024×768 landscape tablet
- 960×540 compact landscape
- 854×480 minimum supported landscape

Respect display safe areas and add at least 16 logical pixels of interactive inset after safe-area calculation.

## Sizing rules

- Minimum tap target: 48×48 logical pixels; 44×44 is the absolute fallback at 854×480.
- Main body copy: target 16 px at 1280×720, never below 12 px.
- Critical values and commit label: target 22–30 px at baseline.
- Contract/module rows must not depend on hover.
- Long lists scroll inside the CRT; the cabinet itself does not scroll.
- The dock may paginate only when workflow capacity exceeds ten. Ten stages must be visible without paging at supported wide sizes.

## Godot structure

Suggested scene hierarchy:

```text
BurnCabinet
├── Backdrop
├── CabinetFrame (decorative, cover/crop)
├── SafeArea
│   ├── OperationGrid
│   │   ├── AbortRail
│   │   ├── MainColumn
│   │   │   ├── CrtFrame
│   │   │   │   └── CabinetScreen
│   │   │   ├── CommandDeck
│   │   │   └── WorkflowBackplane
│   │   └── TelemetryRail
│   └── MaintenanceLayer
└── OverlayRoot
```

Use containers for coarse layout and profile data for breakpoint-specific ratios. Art assets decorate those containers. Fractional regions are acceptable inside a self-contained component, but not as a single global plate map.

## CRT content behavior

- Tabs occupy a compact row inside the CRT bezel.
- The tab body uses the remaining CRT rectangle with no decorative inset larger than 2%.
- Selection detail and consequence remain visible together on every committing screen.
- Burn Feed can temporarily replace or overlay telemetry during the burn, then collapses.

## Dock behavior

- Backplane header owns workflow selectors 1–4 and the active-workflow name.
- Bay grid is computed from available width and profile.
- Locked bays use physical shutters and are non-focusable.
- Focus order follows workflow order, not scene-tree accident.
- Drag/drop is optional convenience; tap-to-arm then tap-bay must fully work on touch.

