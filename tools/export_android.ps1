# Merge the committed Android preset into export_presets.cfg (without
# clobbering Web) and export an AAB. Signing uses Godot's
# GODOT_ANDROID_KEYSTORE_* environment variables; nothing is written to git.
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outDir = Join-Path $repoRoot "build\android"
$aab = Join-Path $outDir "token_burn.aab"

$godotCmd = Get-Command godot -ErrorAction SilentlyContinue
if (-not $godotCmd) {
    Write-Host "godot not found on PATH."
    exit 1
}

$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command python3 -ErrorAction SilentlyContinue
}
if (-not $python) {
    Write-Host "python not found on PATH."
    exit 1
}

& $python.Source (Join-Path $repoRoot "tools\merge_android_preset.py")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$mode = "debug"
$exportFlag = "--export-debug"
if ($env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH) {
    $mode = "release"
    $exportFlag = "--export-release"
}

Write-Host "Exporting Android $mode AAB to $aab"
$godotArgs = @(
    "--headless",
    "--path", $repoRoot,
    "--install-android-build-template",
    $exportFlag, "Android",
    $aab
)
& $godotCmd.Source @godotArgs
if ($LASTEXITCODE -ne 0) {
    Write-Host "Godot export failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}
if (-not (Test-Path $aab)) {
    Write-Host "Export finished but $aab is missing."
    exit 1
}

$inspect = @(Join-Path $repoRoot "tools\inspect_aab.py", $aab)
if ($env:BUNDLETOOL_JAR) {
    $inspect += @("--bundletool", $env:BUNDLETOOL_JAR)
}
& $python.Source @inspect
exit $LASTEXITCODE
