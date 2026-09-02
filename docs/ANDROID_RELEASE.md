# Android release build

Godot **4.7.1**, JDK **17**, Android SDK **36**, NDK as shipped with Godot 4.7 templates.

## Why Gradle + AAB

The playtest preset exported an APK with empty `min_sdk` / `target_sdk` and no Gradle project. Google Play needs an AAB whose merged manifest has `targetSdkVersion=36` and 16 KB-aligned native libraries. Godot 4.7 defaults to those values **when Gradle build is enabled**.

Committed template: [`export/android_export_presets.cfg`](../export/android_export_presets.cfg)

- `gradle_build/use_gradle_build=true`
- `gradle_build/export_format=1` (AAB)
- `min_sdk=24` (Android 7.0)
- `target_sdk=36` (Android 16)
- `architectures/arm64-v8a=true` only
- `package/unique_name=com.tokenburn.game`

`export_presets.cfg` stays gitignored. Copy the template locally:

```powershell
Copy-Item export/android_export_presets.cfg export_presets.cfg
```

Or `./tools/export_android.ps1` (unsigned debug AAB unless keystore env vars are set).

## Keystore (do not commit)

```bash
keytool -genkey -v -keystore token-burn-release.keystore -alias token-burn -keyalg RSA -keysize 2048 -validity 10000
```

Local / CI injection:

| Env | Purpose |
|-----|---------|
| `TOKEN_BURN_KEYSTORE` | Path to `.keystore` |
| `TOKEN_BURN_KEYSTORE_PASSWORD` | Store password |
| `TOKEN_BURN_KEY_ALIAS` | `token-burn` |
| `TOKEN_BURN_KEY_PASSWORD` | Key password |

Godot reads these from Editor Settings or the export dialog. CI should write them into the runner's Godot editor settings or pass `--export-release Android` after `godot --headless --import` with a generated `editor_settings`.

## Versioning

- `version/name` — player-facing, e.g. `0.7.1` then `1.0.0`
- `version/code` — integer, **must increase** every Play upload (template starts at **13**)

Bump both in `export/android_export_presets.cfg` and `application/config/version` in `project.godot`.

## First export checklist

1. Install Android build template: Project → Install Android Build Template
2. Confirm `android/build/config.gradle` has `compileSdk` / `targetSdk` 36
3. Export AAB to `build/android/token_burn.aab`
4. Inspect with Android Studio APK Analyzer: `android:targetSdkVersion="36"`, `arm64-v8a`, 16 KB zip alignment on `.so` files
5. Upload to the closed testing track (#45)

## Secrets

No keystore, Play service account JSON, or signing passwords belong in git.
