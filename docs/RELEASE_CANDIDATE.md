# Release-candidate checklist (#40)

One command for the automated half:

```powershell
./tools/run_release_candidate.ps1
```

That runs, in order:

1. Headless correctness (`tools/run_tests.sh` / `godot --headless res://tests/run_tests.tscn`)
2. UI playtests with `SCRIPT ERROR` fail (`tools/run_playtests.ps1`)
3. Balance sweep (`godot --headless res://tests/run_balance.tscn -- --runs=20`)
4. Android export (`tools/export_android.ps1`) if Godot Android templates are installed

## Manual smokes (not in the script)

### Fresh install

1. Uninstall any previous `com.tokenburn.game`
2. Install the RC AAB from the Play closed track (or `bundletool` locally)
3. New run → first job → first burn → debrief → bills → angels
4. Visit Jobs, Build, Workflows, Market, Menu
5. Mute sound, kill the process, relaunch — mute still set

### Upgrade install

1. Install the previous playtest APK (`version/code` 12 or older) and make a save
2. Install the RC AAB over it
3. Continue — cash, jobs, phase, unlocks intact
4. Confirm `tests/fixtures/saves` still pass in the headless suite

### Soak (optional)

- Headless: `godot --headless res://tests/run_balance.tscn -- --runs=50`
- Device: three full twelve-round campaigns on one typical phone

See also [ANDROID_DEVICE_MATRIX.md](ANDROID_DEVICE_MATRIX.md) and [ANDROID_RELEASE.md](ANDROID_RELEASE.md).
