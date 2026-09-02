# Token Burn release-candidate command (#40).
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Set-Location $repoRoot

function Invoke-Step([string]$Name, [scriptblock]$Body) {
    Write-Host ""
    Write-Host "=== $Name ==="
    & $Body
    if ($LASTEXITCODE -ne 0) {
        Write-Host "RC failed at: $Name (exit $LASTEXITCODE)"
        exit $LASTEXITCODE
    }
}

$godotCmd = Get-Command godot -ErrorAction SilentlyContinue
if (-not $godotCmd) {
    Write-Host "godot not found on PATH."
    exit 1
}

Invoke-Step "Headless correctness" {
    & $godotCmd.Source --headless --path $repoRoot res://tests/run_tests.tscn
}

Invoke-Step "UI playtests" {
    & (Join-Path $repoRoot "tools\run_playtests.ps1")
}

Invoke-Step "Balance sweep (20 runs)" {
    & $godotCmd.Source --headless --path $repoRoot res://tests/run_balance.tscn -- --runs=20
}

Write-Host ""
Write-Host "=== Android export (optional if templates missing) ==="
& (Join-Path $repoRoot "tools\export_android.ps1")
if ($LASTEXITCODE -ne 0) {
    Write-Host "Android export skipped or failed. Install Android build templates and retry."
}

Write-Host ""
Write-Host "RC automated steps finished. Complete the manual smokes in docs/RELEASE_CANDIDATE.md."
exit 0
