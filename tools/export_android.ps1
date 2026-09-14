# Merge the committed Android preset into export_presets.cfg (without
# clobbering Web) and export an AAB. Signing uses Godot's
# GODOT_ANDROID_KEYSTORE_* environment variables; nothing is written to git.
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$outDir = Join-Path $repoRoot "build\android"
$aab = Join-Path $outDir "token_burn.aab"
$phaseSeconds = @{}

function Stop-PhaseTimer([string]$Name, [Diagnostics.Stopwatch]$Sw) {
    $Sw.Stop()
    $phaseSeconds[$Name] = [math]::Round($Sw.Elapsed.TotalSeconds, 1)
}

function Get-GodotVersionString([string]$GodotExe) {
    $raw = & $GodotExe --version 2>&1 | Select-Object -First 1
    return "$raw".Trim()
}

function Test-AndroidBuildTemplateCurrent([string]$Root, [string]$GodotVersion) {
    $versionFile = Join-Path $Root "android\.build_version"
    if (-not (Test-Path $versionFile)) {
        return $false
    }
    $installed = (Get-Content $versionFile -Raw).Trim()
    if ($installed -eq "") {
        return $false
    }
    return $GodotVersion.StartsWith($installed)
}

function Test-FreshAab([string]$Path, [datetime]$Since) {
    if (-not (Test-Path $Path)) {
        return $false
    }
    return (Get-Item $Path).LastWriteTime -ge $Since
}

function Stop-GodotExportProcesses([System.Diagnostics.Process]$MainProcess) {
    $startMin = if ($MainProcess) { $MainProcess.StartTime.AddSeconds(-2) } else { (Get-Date).AddMinutes(-5) }
    $ids = [System.Collections.Generic.List[int]]::new()
    if ($MainProcess -and -not $MainProcess.HasExited) {
        $ids.Add($MainProcess.Id)
    }
    foreach ($name in @("godot", "godot.console")) {
        Get-Process -Name $name -ErrorAction SilentlyContinue |
            Where-Object { $_.StartTime -ge $startMin } |
            ForEach-Object { $ids.Add($_.Id) }
    }
    foreach ($id in ($ids | Select-Object -Unique)) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-GodotExport(
    [string]$GodotExe,
    [string[]]$GodotArgs,
    [string]$AabPath,
    [datetime]$Started,
    [int]$PostExportGraceSeconds = 20
) {
    $proc = Start-Process -FilePath $GodotExe -ArgumentList $GodotArgs -NoNewWindow -PassThru
    if (-not $proc) {
        throw "Failed to start Godot export process."
    }

    $aabFreshSince = $null
    $pollMs = 500

    while (-not $proc.HasExited) {
        if (Test-FreshAab -Path $AabPath -Since $Started) {
            if ($null -eq $aabFreshSince) {
                $aabFreshSince = Get-Date
            } elseif (((Get-Date) - $aabFreshSince).TotalSeconds -ge $PostExportGraceSeconds) {
                Write-Host "Godot did not exit within ${PostExportGraceSeconds}s after writing the AAB; terminating."
                Stop-GodotExportProcesses -MainProcess $proc
                return -1
            }
        }
        Start-Sleep -Milliseconds $pollMs
    }

    return $proc.ExitCode
}

$totalSw = [Diagnostics.Stopwatch]::StartNew()

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

$mergeSw = [Diagnostics.Stopwatch]::StartNew()
& $python.Source (Join-Path $repoRoot "tools\merge_android_preset.py")
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
Stop-PhaseTimer "merge_preset" $mergeSw

if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Path $outDir | Out-Null
}

$mode = "debug"
$exportFlag = "--export-debug"
if ($env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH) {
    $mode = "release"
    $exportFlag = "--export-release"
}

$godotVersion = Get-GodotVersionString $godotCmd.Source
$installTemplate = -not (Test-AndroidBuildTemplateCurrent -Root $repoRoot -GodotVersion $godotVersion)
if ($installTemplate) {
    Write-Host "Installing Android build template (engine $godotVersion)."
} else {
    Write-Host "Android build template up to date for $godotVersion; skipping reinstall."
}

Write-Host "Exporting Android $mode AAB to $aab"
if (Test-Path $aab) {
    Remove-Item $aab -Force
}
$started = Get-Date
$godotArgs = @(
    "--headless",
    "--path", $repoRoot
)
if ($installTemplate) {
    $godotArgs += "--install-android-build-template"
}
$godotArgs += @($exportFlag, "Android", $aab)

$exportSw = [Diagnostics.Stopwatch]::StartNew()
$godotExit = Invoke-GodotExport -GodotExe $godotCmd.Source -GodotArgs $godotArgs -AabPath $aab -Started $started
Stop-PhaseTimer "godot_export" $exportSw

# Local editor addons can make Godot exit non-zero after a successful export
# (teardown errors). A freshly written AAB is the real signal.
$fresh = Test-FreshAab -Path $aab -Since $started
if (-not $fresh) {
    Write-Host "Godot export failed (exit $godotExit) and no new $aab was written."
    if ($godotExit -ne 0) { exit $godotExit }
    exit 1
}
if ($godotExit -ne 0) {
    Write-Host "Godot exited $godotExit after writing the AAB; continuing (editor addon teardown noise)."
}

$inspectSw = [Diagnostics.Stopwatch]::StartNew()
$inspect = @((Join-Path $repoRoot "tools\inspect_aab.py"), $aab)
if ($env:BUNDLETOOL_JAR) {
    $inspect += @("--bundletool", $env:BUNDLETOOL_JAR)
}
& $python.Source @inspect
$inspectExit = $LASTEXITCODE
Stop-PhaseTimer "inspect_aab" $inspectSw

$totalSw.Stop()
Write-Host ""
Write-Host "Export timing (seconds): merge_preset=$($phaseSeconds['merge_preset']), godot_export=$($phaseSeconds['godot_export']), inspect_aab=$($phaseSeconds['inspect_aab']), total=$([math]::Round($totalSw.Elapsed.TotalSeconds, 1))"

exit $inspectExit
