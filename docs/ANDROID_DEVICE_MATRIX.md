# Android device / performance matrix (#26)

Run against a Play-delivered or locally installed release AAB. Record pass/fail, not vibes.

## Profiles

| Profile | Viewport (landscape) | Why |
|---------|----------------------|-----|
| Narrow phone | 854 × 480 | Console/handset floor used by playtests |
| Typical 1080p phone | 1920 × 1080 | Supported desktop/phone floor |
| Tall modern phone | ~2400 × 1080 with cutout | Safe area / notch / gesture bar |
| Tablet landscape | 1280 × 800 or 1920 × 1200 | Claimed tablet screenshots |
| Low-spec | 2–3 GB RAM emulator or old arm64 | Memory + frame-time floor |

## Per-profile checks

- UI clipping / overlap on Desk, Jobs, Build, Workflows, Market, Burn Board, overlays
- Touch targets reachable one-handed in landscape
- Burn Board spectacle frame pacing (no multi-second stalls)
- Memory growth across 3+ rounds
- Venue transition latency after fade
- Background / resume mid-burn and mid-overlay (#25 / #37)
- System back matches the visible back action (#20)

## Thresholds (release candidate)

- No clipped primary action
- No blank shell after round-end or resume (`SceneRouter.visible_route_ok()`)
- Venue fade + mount under 1.0s on typical 1080p
- No crash or save corruption after OS kill + relaunch
- Heat/burn spectacle stays playable (no hard lock)

Record results in the RC report produced by `tools/run_release_candidate.ps1`.
