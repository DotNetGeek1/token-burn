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

## Lifecycle smoke (#25 / #37)

Install with `./tools/android_install.ps1 -Launch` from the same debug AAB on each device. Upgrade tests must reuse that debug signing key (`GODOT_ANDROID_KEYSTORE_DEBUG_*`); Android refuses an upgrade signed with a different key.

| Case | Phone | Tablet |
|------|-------|--------|
| Pause / resume during ROUND_PREP | | |
| Pause / resume mid-burn | | |
| Pause / resume on debrief | | |
| Pause / resume on bills | | |
| Pause / resume on angels | | |
| Pause / resume on investor call | | |
| Pause / resume on help | | |
| Pause / resume on run end | | |
| Pause / resume mid venue fade | | |
| System back: desk / jobs / build / workflows / market / menu / legacy / achievements / terms | | |
| System back closes overlay (help, debrief, bills, angels, investor) | | |
| System back steps out of desk lean-in, then venue lean-in | | |
| `adb shell am force-stop com.tokenburn.game` mid-burn, relaunch, Continue | | |
| Upgrade install over previous debug build with a live save | | |

### Results (2026-09-02)

Automated coverage: `tests/playtests/pt_android_lifecycle.gd` (35 passed) and `tests/simulation_tests/test_lifecycle_hooks.gd` (12 passed).

Phone install (2026-09-02): Galaxy S24 Ultra `SM_S9280` / `R5CX420KATZ` received debug AAB `versionCode=13` `versionName=0.7.1` (`targetSdk=36`, `arm64-v8a` split). App launched via `GodotAppLauncher`. Full lifecycle smoke table above is still unfilled. Tablet not connected.

See [RELEASE_CANDIDATE.md](RELEASE_CANDIDATE.md).
