# Data safety inventory (#29)

Audit date: 2026-09-02. Re-run this before answering Play Console if any SDK is added.

## What the shipping binary does

| Data | Collected? | Notes |
|------|------------|-------|
| Name, email, account | No | No login |
| Location | No | |
| Photos / files | No | |
| Audio | No | Local SFX only |
| Device IDs | No | |
| Diagnostics / crash | No | No Crashlytics / Sentry / Firebase |
| Analytics | No | `analytics_enabled` is false in release overlay |
| Advertising ID | No | No ads |
| Network | No game backend | Web build only uses `JavaScriptBridge` to resume AudioContext |

## On-device storage

- `user://savegame.json` — current run (local)
- `user://profile.json` — meta unlocks and settings (local)
- Android backup: `user_data_backup/allow=false` on the export preset

## Declaration to file

Play Data safety: **No data collected**, provided this inventory still matches the uploaded AAB and its included Godot/Android OS libraries.

If a crash or analytics SDK is added later, update this file, the privacy policy, and the Play form in the same change.
