# Copy the committed Android preset and export an AAB.
# Signing secrets come from the environment; they are never written to git.
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$presetSrc = Join-Path $repoRoot "export\android_export_presets.cfg"
$presetDst = Join-Path $repoRoot "export_presets.cfg"
$outDir = Join-Path $repoRoot "build\android"
$godotCmd = Get-Command godot -ErrorAction SilentlyContinue
if (-not $godotCmd) {
    Write-Host "godot not found on PATH."
    exit 1
}
Copy-Item $presetSrc $presetDst -Force
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}
$godotArgs = @(
    "--headless",
    "--path", $repoRoot,
    "--export-release", "Android",
    (Join-Path $outDir "token_burn.aab")
)
& $godotCmd.Source @godotArgs
exit $LASTEXITCODE
