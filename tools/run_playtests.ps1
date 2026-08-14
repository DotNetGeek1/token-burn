# Token Burn UI playtests.
#
# Headless is the default: layout, font, and nav audits work. Hover
# reachability is skipped by the driver because gui_get_hovered_control is
# null under Godot's headless display server (confirmed by the layout spike).
#
# Pass -Windowed or --windowed as the first argument to drop --headless and
# use --rendering-driver dummy instead, so hover/hit-testing works.
#
# Extra args are forwarded to Godot, e.g.:
#   ./tools/run_playtests.ps1 -- --scale=8
#   ./tools/run_playtests.ps1 -Windowed -- --shots --scale=8
#
# Fails if Godot's exit code is non-zero or the log contains SCRIPT ERROR.
# Godot does not fail a test when a UI callback throws.

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$buildDir = Join-Path $repoRoot "build"
$logPath = Join-Path $buildDir "playtests.log"

$godotCmd = Get-Command godot -ErrorAction SilentlyContinue
if (-not $godotCmd) {
    Write-Host "godot not found on PATH."
    exit 1
}

$windowed = $false
$forward = @()
if ($args.Count -gt 0 -and ($args[0] -eq "-Windowed" -or $args[0] -eq "--windowed")) {
    $windowed = $true
    if ($args.Count -gt 1) {
        $forward = @($args[1..($args.Count - 1)])
    }
} else {
    $forward = @($args)
}

if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}

$godotArgs = @()
if ($windowed) {
    $godotArgs += "--rendering-driver", "dummy"
} else {
    $godotArgs += "--headless"
}
$godotArgs += "--path", $repoRoot, "res://tests/run_playtests.tscn"
if ($forward.Count -gt 0) {
    $godotArgs += $forward
}

$ErrorActionPreference = "Continue"
& $godotCmd.Source @godotArgs 2>&1 | ForEach-Object { "$_" } | Tee-Object -FilePath $logPath
$exitCode = $LASTEXITCODE
if ($null -eq $exitCode) {
    $exitCode = 1
}

$sawScriptError = $false
if (Test-Path $logPath) {
    $sawScriptError = [bool](Select-String -Path $logPath -Pattern "SCRIPT ERROR" -SimpleMatch -Quiet)
}

Write-Host ""
Write-Host "Playtests: exit=$exitCode SCRIPT ERROR=$(if ($sawScriptError) { 'yes' } else { 'no' })"

if ($exitCode -ne 0 -or $sawScriptError) {
    if ($exitCode -ne 0) {
        exit $exitCode
    }
    exit 1
}
exit 0
