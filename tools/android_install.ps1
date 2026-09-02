# Build a local-testing APK set from the release/debug AAB and install it.
param(
    [string]$Aab = "",
    [switch]$Launch
)
$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if (-not $Aab) {
    $Aab = Join-Path $repoRoot "build\android\token_burn.aab"
}
if (-not (Test-Path $Aab)) {
    Write-Host "Missing $Aab. Run ./tools/export_android.ps1 first."
    exit 1
}

$adb = Get-Command adb -ErrorAction SilentlyContinue
if (-not $adb) {
    Write-Host "adb not found on PATH."
    exit 1
}

$java = Get-Command java -ErrorAction SilentlyContinue
if (-not $java -and $env:JAVA_HOME) {
    $javaPath = Join-Path $env:JAVA_HOME "bin\java.exe"
    if (Test-Path $javaPath) {
        $java = Get-Command $javaPath
    }
}
if (-not $java) {
    Write-Host "java not found. Install JDK 17 or set JAVA_HOME."
    exit 1
}

$buildDir = Join-Path $repoRoot "build"
if (-not (Test-Path $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir | Out-Null
}
$jar = Join-Path $buildDir "bundletool.jar"
if (-not (Test-Path $jar)) {
    Write-Host "Downloading bundletool..."
    Invoke-WebRequest -Uri "https://github.com/google/bundletool/releases/download/1.18.1/bundletool-all-1.18.1.jar" -OutFile $jar
}

$apks = Join-Path $buildDir "android\token_burn.apks"
$apksDir = Split-Path $apks -Parent
if (-not (Test-Path $apksDir)) {
    New-Item -ItemType Directory -Path $apksDir | Out-Null
}
if (Test-Path $apks) {
    Remove-Item $apks -Force
}

$ks = $env:GODOT_ANDROID_KEYSTORE_DEBUG_PATH
if (-not $ks) {
    $ks = Join-Path $env:APPDATA "Godot\keystores\debug.keystore"
}
$ksPass = $env:GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD
if (-not $ksPass) { $ksPass = "android" }
$ksAlias = $env:GODOT_ANDROID_KEYSTORE_DEBUG_USER
if (-not $ksAlias) { $ksAlias = "androiddebugkey" }

$buildArgs = @(
    "-jar", $jar, "build-apks",
    "--bundle=$Aab",
    "--output=$apks"
)
if (Test-Path $ks) {
    $buildArgs += @(
        "--ks=$ks",
        "--ks-pass=pass:$ksPass",
        "--ks-key-alias=$ksAlias",
        "--key-pass=pass:$ksPass"
    )
} else {
    Write-Host "No debug keystore at $ks; install will fail if the AAB is unsigned."
}

Write-Host "Building APKs from $Aab"
& $java.Source @buildArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Installing onto the connected device"
& $java.Source -jar $jar install-apks --apks=$apks
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($Launch) {
    & $adb.Source shell am start -n com.tokenburn.game/com.godot.game.GodotAppLauncher
}
Write-Host "Installed com.tokenburn.game"
