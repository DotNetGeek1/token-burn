# Export Token Burn for the web into site/public/game/.
#
# Requires Godot 4.7.x on PATH with web export templates installed
# (Editor → Manage Export Templates, including the no-threads variant).
#
# Usage (from anywhere):
#   ./tools/export_web.ps1

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$presetsPath = Join-Path $repoRoot "export_presets.cfg"
$webPresetPath = Join-Path $repoRoot "export/web_export_presets.cfg"
$outDir = Join-Path $repoRoot "site/public/game"
$outHtml = Join-Path $outDir "index.html"

$godotCmd = Get-Command godot -ErrorAction SilentlyContinue
if (-not $godotCmd) {
    Write-Host "godot not found on PATH."
    exit 1
}

if (-not (Test-Path $webPresetPath)) {
    Write-Host "Missing $webPresetPath"
    exit 1
}

$webPreset = Get-Content $webPresetPath -Raw
if (-not (Test-Path $presetsPath)) {
    Set-Content -Path $presetsPath -Value $webPreset -NoNewline
    Write-Host "Wrote export_presets.cfg with the Web preset."
} elseif ((Get-Content $presetsPath -Raw) -notmatch 'name="Web"') {
    $indices = [regex]::Matches((Get-Content $presetsPath -Raw), '\[preset\.(\d+)\]') |
        ForEach-Object { [int]$_.Groups[1].Value }
    $next = if ($indices.Count -eq 0) { 0 } else { ($indices | Measure-Object -Maximum).Maximum + 1 }
    $appended = $webPreset -replace 'preset\.0', "preset.$next"
    Add-Content -Path $presetsPath -Value "`n$appended"
    Write-Host "Appended Web preset as preset.$next."
}

New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Write-Host "Exporting Web release to site/public/game/ ..."
& godot --headless --path $repoRoot --export-release Web $outHtml
if ($LASTEXITCODE -ne 0) {
    Write-Host "Godot export failed with exit code $LASTEXITCODE."
    exit $LASTEXITCODE
}

if (-not (Test-Path $outHtml)) {
    Write-Host "Export finished but $outHtml is missing."
    exit 1
}

Write-Host "Web export ready: $outDir"
Get-ChildItem $outDir | Select-Object Name, @{n = "MB"; e = { "{0:N1}" -f ($_.Length / 1MB) } }
