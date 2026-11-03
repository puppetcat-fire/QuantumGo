<#
.SYNOPSIS
  Runs the two-process online flow test for the application shell.

.DESCRIPTION
  Starts a headless host (tests/ui_shell/online_host.gd), then a headless guest
  (tests/ui_shell/online_client.gd). Both drive the real shell UI: create/join a
  room, play a match, record the result, leave and check the leaderboard.

  Asserts the two things that are easiest to get wrong:
    * exactly one leaderboard record per match,
    * Session.leave() really tears the session down on return.

.EXAMPLE
  pwsh -File tests/ui_shell/run_online_flow.ps1
#>
param(
    [string]$Godot = "",
    [int]$StartDelaySeconds = 3,
    [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = "Stop"

$scriptDir = $PSScriptRoot
$project = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
$workspace = (Resolve-Path (Join-Path $project "..")).Path
$godotUser = Join-Path $workspace ".godot-user"

if ([string]::IsNullOrEmpty($Godot)) {
    $Godot = Join-Path $workspace "tools\godot\godot_console.exe"
}
if (-not (Test-Path $Godot)) {
    Write-Error "Godot binary not found: $Godot (pass -Godot <path>)"
    exit 2
}

# Godot crashes with signal 11 without a writable user profile.
$env:APPDATA = Join-Path $godotUser "Roaming"
$env:LOCALAPPDATA = Join-Path $godotUser "Local"

# Some Windows environments carry both `NO_PROXY` and `no_proxy`; Start-Process
# copies the environment into a case-sensitive dictionary and throws on the
# duplicate ("Item has already been added"). Drop one variant for this run.
function Remove-DuplicateEnvironmentKeys {
    $seen = @{}
    foreach ($name in @([Environment]::GetEnvironmentVariables().Keys)) {
        $lower = $name.ToString().ToLowerInvariant()
        if ($seen.ContainsKey($lower)) {
            [Environment]::SetEnvironmentVariable($name.ToString(), $null)
        }
        else {
            $seen[$lower] = $true
        }
    }
}
Remove-DuplicateEnvironmentKeys

$logDir = Join-Path $env:TEMP "qg-online-flow"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
$hostOut = Join-Path $logDir "host.out.txt"
$hostErr = Join-Path $logDir "host.err.txt"
$clientOut = Join-Path $logDir "client.out.txt"
$clientErr = Join-Path $logDir "client.err.txt"

function Start-GodotScript([string]$ScriptPath, [string]$OutFile, [string]$ErrFile) {
    $arguments = @("--headless", "--path", $project, "--script", $ScriptPath)
    return Start-Process -FilePath $Godot -ArgumentList $arguments -PassThru -NoNewWindow `
        -RedirectStandardOutput $OutFile -RedirectStandardError $ErrFile
}

# With redirected output, .NET only settles ExitCode after a blocking WaitForExit().
function Get-ProcessExitCode([System.Diagnostics.Process]$Process) {
    if ($null -eq $Process) { return $null }
    try {
        $Process.WaitForExit()
        return $Process.ExitCode
    }
    catch {
        return $null
    }
}

$hostProcess = $null
$clientProcess = $null
$hostCode = $null
$clientCode = $null

try {
    Write-Host "starting host ..."
    $hostProcess = Start-GodotScript "res://tests/ui_shell/online_host.gd" $hostOut $hostErr
    Start-Sleep -Seconds $StartDelaySeconds

    Write-Host "starting client ..."
    $clientProcess = Start-GodotScript "res://tests/ui_shell/online_client.gd" $clientOut $clientErr

    $hostExited = $hostProcess.WaitForExit($TimeoutSeconds * 1000)
    $clientExited = $clientProcess.WaitForExit($TimeoutSeconds * 1000)

    if (-not $hostExited) {
        Write-Host "host timed out, killing it"
        Stop-Process -Id $hostProcess.Id -Force -ErrorAction SilentlyContinue
    }
    if (-not $clientExited) {
        Write-Host "client timed out, killing it"
        Stop-Process -Id $clientProcess.Id -Force -ErrorAction SilentlyContinue
    }

    $hostProcess.Refresh()
    $clientProcess.Refresh()
    if ($hostExited) { $hostCode = Get-ProcessExitCode $hostProcess }
    if ($clientExited) { $clientCode = Get-ProcessExitCode $clientProcess }
}
finally {
    foreach ($process in @($hostProcess, $clientProcess)) {
        if ($null -ne $process) {
            try {
                if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue }
            }
            catch { }
        }
    }
}

Write-Host ""
Write-Host "===== HOST ====="
if (Test-Path $hostOut) { Get-Content $hostOut -Encoding UTF8 | Where-Object { $_ -match "HOST (PASS|FAIL)|HOST SUMMARY" } | ForEach-Object { Write-Host $_ } }
if (Test-Path $hostErr) { Get-Content $hostErr -Encoding UTF8 | Where-Object { $_ -match "HOST (PASS|FAIL)" } | ForEach-Object { Write-Host $_ } }

Write-Host ""
Write-Host "===== CLIENT ====="
if (Test-Path $clientOut) { Get-Content $clientOut -Encoding UTF8 | Where-Object { $_ -match "CLIENT (PASS|FAIL)|CLIENT SUMMARY" } | ForEach-Object { Write-Host $_ } }
if (Test-Path $clientErr) { Get-Content $clientErr -Encoding UTF8 | Where-Object { $_ -match "CLIENT (PASS|FAIL)" } | ForEach-Object { Write-Host $_ } }

$hostFails = 0
$clientFails = 0
$hostSummary = ""
$clientSummary = ""
if (Test-Path $hostOut) { $hostSummary = (Get-Content $hostOut -Encoding UTF8 | Where-Object { $_ -match "HOST SUMMARY" } | Select-Object -Last 1) }
if (Test-Path $clientOut) { $clientSummary = (Get-Content $clientOut -Encoding UTF8 | Where-Object { $_ -match "CLIENT SUMMARY" } | Select-Object -Last 1) }

$failPattern = "  (HOST|CLIENT) FAIL  "
$failLines = @()
foreach ($file in @($hostOut, $hostErr, $clientOut, $clientErr)) {
    if (Test-Path $file) {
        $failLines += Get-Content $file -Encoding UTF8 | Where-Object { $_ -match $failPattern }
    }
}
if ($hostSummary -match "(\d+) failures") { $hostFails = [int]$Matches[1] }
if ($clientSummary -match "(\d+) failures") { $clientFails = [int]$Matches[1] }

Write-Host ""
Write-Host "host exit code   : $(if ($null -eq $hostCode) { 'unknown' } else { $hostCode })"
Write-Host "client exit code : $(if ($null -eq $clientCode) { 'unknown' } else { $clientCode })"
Write-Host "host summary     : $hostSummary"
Write-Host "client summary   : $clientSummary"
Write-Host "failed checks    : $($failLines.Count)"

$exitCodesKnown = ($null -ne $hostCode) -and ($null -ne $clientCode)
$exitOk = $true
if ($exitCodesKnown) {
    $exitOk = ($hostCode -eq 0) -and ($clientCode -eq 0)
}
$ok = $exitOk -and
      ($hostFails -eq 0) -and ($clientFails -eq 0) -and
      (-not [string]::IsNullOrEmpty($hostSummary)) -and
      (-not [string]::IsNullOrEmpty($clientSummary))

if ($ok) {
    Write-Host "ONLINE FLOW PASS"
    exit 0
}

Write-Host "ONLINE FLOW FAIL"
Write-Host "logs: $logDir"
exit 1
