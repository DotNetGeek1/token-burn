# Android release build

## Toolchain

| Piece | Version |
|-------|---------|
| Godot | **4.7.1** (export templates required) |
| JDK | **17** (Temurin). Godot 4.7 Gradle is happiest on 17. |
| Android SDK | platform **36**, build-tools **36.0.0** |
| NDK | the copy shipped inside the Godot 4.7 Android export templates |

The local Android Studio JBR is currently **21**. If a Gradle export fails with a toolchain mismatch, set Editor Settings → Export → Android → **Java SDK Path** to a JDK 17 install, or set `JAVA_HOME` to that install before `./tools/export_android.ps1`.

`ANDROID_HOME` on this machine is `C:\Users\AlexGriffiths\AppData\Local\Android\Sdk`.

## Why Gradle + AAB

The playtest preset exported an APK with empty `min_sdk` / `target_sdk` and no Gradle project. Google Play needs an AAB whose merged manifest has `targetSdkVersion=36` and 16 KB-aligned native libraries. Godot 4.7 defaults to those values **when Gradle build is enabled**.

Committed template: [`export/android_export_presets.cfg`](../export/android_export_presets.cfg)

- `gradle_build/use_gradle_build=true`
- `gradle_build/export_format=1` (AAB)
- `min_sdk=24` (Android 7.0)
- `target_sdk=36` (Android 16)
- `architectures/arm64-v8a=true` only
- `package/unique_name=com.tokenburn.game`

`export_presets.cfg` stays gitignored. `tools/export_android.ps1` / `tools/export_android.sh` merge the Android template into it and **do not** clobber a local Web preset.

```powershell
./tools/export_android.ps1
```

Debug AAB unless `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` is set. The script installs the Android build template, then runs `tools/inspect_aab.py`.

## Keystore (do not commit)

Godot 4.7 reads these environment variables and they override the export dialog:

| Env | Purpose |
|-----|---------|
| `GODOT_ANDROID_KEYSTORE_DEBUG_PATH` | Absolute path to a debug `.keystore` |
| `GODOT_ANDROID_KEYSTORE_DEBUG_USER` | Debug alias (`androiddebugkey`) |
| `GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD` | Debug store/key password |
| `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` | Absolute path to the Play upload keystore |
| `GODOT_ANDROID_KEYSTORE_RELEASE_USER` | Release alias |
| `GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD` | Release store/key password |

Create a release keystore once and keep it off git:

```bash
keytool -genkey -v -keystore token-burn-release.keystore -alias token-burn -keyalg RSA -keysize 2048 -validity 10000
```

### GitHub secrets (signed tag builds)

The `aab-release` job in [`.github/workflows/android.yml`](../.github/workflows/android.yml) is inert until these exist:

1. `ANDROID_KEYSTORE_BASE64` — `base64 -w0 token-burn-release.keystore`
2. `ANDROID_KEY_ALIAS` — e.g. `token-burn`
3. `ANDROID_KEYSTORE_PASSWORD`

PRs and `main` always produce a **debug** AAB artifact (`token_burn-debug.aab`) signed with a throwaway debug keystore. Tags `v*` produce a signed release AAB and attach it to the GitHub Release **only** when the secrets are present.

## Versioning

- `version/name` — player-facing, e.g. `0.7.1` then `1.0.0`
- `version/code` — integer, **must increase** every Play upload (template starts at **13**)

Bump **all three** together:

1. `version/code` in [`export/android_export_presets.cfg`](../export/android_export_presets.cfg)
2. `version/name` in the same file
3. `application/config/version` in [`project.godot`](../project.godot)

`tests/architecture_tests/test_android_preset.gd` fails if the names diverge or the code drops back to the last playtest APK (12).

## First export checklist

1. JDK 17 and Android SDK 36 installed; Godot Android export templates installed
2. `./tools/export_android.ps1` (or the CI debug job)
3. `python tools/inspect_aab.py build/android/token_burn.aab --bundletool path/to/bundletool.jar`
4. Confirm `targetSdkVersion=36`, `arm64-v8a`, 16 KB `PT_LOAD` alignment
5. `./tools/android_install.ps1` onto a device, or upload to the closed testing track (#45)

## Secrets

No keystore, Play service account JSON, or signing passwords belong in git.
