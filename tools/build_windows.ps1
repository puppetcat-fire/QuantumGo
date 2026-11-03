## Builds a runnable Windows folder for Quantum Go.
##
##   powershell -ExecutionPolicy Bypass -File tools/build_windows.ps1
##
## Two modes:
##
##   -pack  (default, works everywhere)  exports the game as a .pck and ships the
##          Godot editor binary as the runtime. The launch option must be
##          `QuantumGo.exe --main-pack QuantumGo.pck`. This is an interim
##          distributor: it runs today without export templates, at the cost of a
##          ~170 MB executable.
##
##   -Full  produces a normal standalone .exe with the engine embedded. It needs
##          the Godot 4.6.1 export templates installed in the editor
##          (Editor -> Manage Export Templates -> Download).
##
## This file is deliberately ASCII-only: Windows PowerShell 5.1 reads .ps1 files
## as ANSI unless they carry a UTF-8 BOM, and non-ASCII literals break parsing.
## User-facing Chinese text lives in docs/BUILD_README_CN.txt and is copied in.
param(
    [switch]$Full,
    [switch]$SkipPck,
    [string]$GodotPath = "",
    [string]$OutDir = ""
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $OutDir = Join-Path $projectRoot 'build\windows'
}

# Keep Godot away from the real user profile, matching the test harnesses.
$env:APPDATA = Join-Path (Split-Path -Parent $projectRoot) '.godot-user\Roaming'
$env:LOCALAPPDATA = Join-Path (Split-Path -Parent $projectRoot) '.godot-user\Local'
New-Item -ItemType Directory -Force -Path $env:APPDATA, $env:LOCALAPPDATA | Out-Null

function Resolve-Godot {
    if (-not [string]::IsNullOrWhiteSpace($GodotPath) -and (Test-Path $GodotPath)) {
        return (Resolve-Path $GodotPath).Path
    }
    if (-not [string]::IsNullOrWhiteSpace($env:QG_GODOT) -and (Test-Path $env:QG_GODOT)) {
        return (Resolve-Path $env:QG_GODOT).Path
    }
    $toolRoot = Join-Path (Split-Path -Parent $projectRoot) 'tools\godot'
    $candidates = @(
        (Join-Path $toolRoot 'godot_console.exe'),
        (Join-Path $toolRoot 'godot.exe'),
        (Join-Path $toolRoot 'Godot_v4.6.1-stable_win64_console.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    throw "Godot binary not found. Pass -GodotPath <path to godot_console.exe>."
}

function Resolve-EditorBinary([string]$consolePath) {
    # The console build is a thin wrapper around the windowed engine binary; the
    # runtime we ship has to be the windowed one.
    $directory = Split-Path -Parent $consolePath
    foreach ($name in @('godot.exe', 'Godot_v4.6.1-stable_win64.exe')) {
        $candidate = Join-Path $directory $name
        if (Test-Path $candidate) { return (Resolve-Path $candidate).Path }
    }
    throw "Windowed Godot binary not found next to $consolePath"
}

$godot = Resolve-Godot
Write-Host "Godot : $godot"
Write-Host "Output: $OutDir"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not $SkipPck) {
    $pck = Join-Path $OutDir 'QuantumGo.pck'
    Write-Host "Exporting PCK ..."
    & $godot --headless --path $projectRoot --export-pack "Windows Desktop" $pck | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $pck)) {
        throw "PCK export failed (exit $LASTEXITCODE)"
    }
    Write-Host ("  {0} ({1:N1} MB)" -f $pck, ((Get-Item $pck).Length / 1MB))
}

if ($Full) {
    $exe = Join-Path $OutDir 'QuantumGo.exe'
    Write-Host "Exporting full executable (needs export templates) ..."
    & $godot --headless --path $projectRoot --export-release "Windows Desktop" $exe | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path $exe)) {
        throw "Full export failed. Install the Godot 4.6.1 export templates first (Editor -> Manage Export Templates -> Download)."
    }
    Write-Host ("  {0} ({1:N1} MB)" -f $exe, ((Get-Item $exe).Length / 1MB))
    Copy-Item (Join-Path $projectRoot 'docs\BUILD_README_FULL.txt') (Join-Path $OutDir 'README.txt') -Force
} else {
    $editor = Resolve-EditorBinary $godot
    $runtime = Join-Path $OutDir 'QuantumGo.exe'
    try {
        Copy-Item $editor $runtime -Force -ErrorAction Stop
        Write-Host ("  runtime {0} ({1:N0} MB)" -f $runtime, ((Get-Item $runtime).Length / 1MB))
    } catch {
        # The engine binary never changes between builds; if the game is running
        # Windows locks it. Keep the existing copy instead of failing the build.
        Write-Warning "Could not refresh $runtime (is the game running?). Keeping the existing copy."
    }

    $launcher = Join-Path $OutDir 'play.cmd'
    $launcherLines = @(
        '@echo off',
        'cd /d "%~dp0"',
        'echo.',
        'echo   Quantum Go',
        'echo   Starting up - the game window appears in about 5-10 seconds.',
        'echo   This console window stays open until you close the game.',
        'echo.',
        'start /wait "" "%~dp0QuantumGo.exe" --main-pack "%~dp0QuantumGo.pck" --log-file "%~dp0launch.log"',
        'set code=%errorlevel%',
        'echo.',
        'if "%code%"=="0" (',
        '    echo   Game closed normally.',
        ') else (',
        '    echo   Game exited with code %code%.',
        ')',
        'if exist "%~dp0launch.log" (',
        '    echo.',
        '    echo   ---- last lines of launch.log ----',
        '    powershell -NoProfile -Command "Get-Content -LiteralPath ''%~dp0launch.log'' -Tail 25 -ErrorAction SilentlyContinue"',
        ')',
        'echo.',
        'pause'
    )
    Set-Content -Path $launcher -Value $launcherLines -Encoding ASCII
    # GodotSteam reads this file from next to the executable. 480 is Spacewar,
    # Valve's public test app; replace it with the real AppID when shipping.
    Set-Content -Path (Join-Path $OutDir 'steam_appid.txt') -Value '480' -Encoding ASCII
    Copy-Item (Join-Path $projectRoot 'docs\BUILD_README_PACK.txt') (Join-Path $OutDir 'README.txt') -Force
}

Write-Host "Done."
Get-ChildItem $OutDir | Select-Object Name, @{n='MB';e={[math]::Round($_.Length/1MB,2)}} | Format-Table -AutoSize

# Godot prints a harmless certificate-store warning on stderr in this
# environment; it must not turn a successful build into a failure exit code.
exit 0
