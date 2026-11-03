#requires -version 5.0
<#
.SYNOPSIS
    Two-process integration test for the Quantum Go ENet transport.

.DESCRIPTION
    Starts real headless Godot processes and checks that they can play a full
    online match through QGSession:

      * host_probe.gd (host, black) + client_probe.gd (guest, white) play a
        scripted 9x9 match (move, move, quantum, move, move, pass, pass,
        resign) and must both end with the same weighted score and move count;
      * a guest process killed hard mid-match must produce a clean
        "opponent left" sequence on the host, not a crash;
      * a client connecting to a port nobody listens on must report a readable
        failure and exit cleanly;
      * hosting on an already occupied port must fail cleanly and recover.

    The script is self-contained: it locates the Godot binary, points Godot at a
    private user-data directory, picks free UDP ports and terminates every
    process it started. It exits 0 when every scenario passes and 1 otherwise.

    Probe processes are asked to die by creating a kill file that they poll;
    this works even when the shell is not allowed to terminate the launcher's
    process tree directly. Every probe also has its own hard watchdog and exits
    on every path.

.PARAMETER GodotPath
    Path to godot_console.exe or godot.exe. Defaults to the QG_GODOT environment
    variable, then <workspace>/tools/godot/godot_console.exe, then godot.exe.

.PARAMETER Port
    First UDP port to use. Defaults to 0, which asks the OS for free ports.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File tests/net/run_net_test.ps1
#>
[CmdletBinding()]
param(
    [string]$GodotPath = "",
    [int]$Port = 0
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Layout
# --------------------------------------------------------------------------

$netDir = $PSScriptRoot
$projectRoot = Split-Path -Parent (Split-Path -Parent $netDir)
$workspaceRoot = Split-Path -Parent $projectRoot

function Resolve-GodotPath {
    param([string]$Candidate)
    if (-not $Candidate) { return '' }
    if (-not (Test-Path -LiteralPath $Candidate)) { return '' }
    return (Resolve-Path -LiteralPath $Candidate).Path
}

$resolved = Resolve-GodotPath $GodotPath
if (-not $resolved) { $resolved = Resolve-GodotPath $env:QG_GODOT }
if (-not $resolved) { $resolved = Resolve-GodotPath (Join-Path $workspaceRoot 'tools\godot\godot_console.exe') }
if (-not $resolved) { $resolved = Resolve-GodotPath (Join-Path $workspaceRoot 'tools\godot\godot.exe') }
if (-not $resolved) {
    Write-Host 'NET TEST FAIL: could not find godot_console.exe. Pass -GodotPath <path> or set QG_GODOT.' -ForegroundColor Red
    exit 1
}
$GodotPath = $resolved

# Godot crashes on this machine (signal 11) unless it gets a private, writable
# user-data directory. Keep it inside the workspace so the test is portable.
$env:APPDATA = Join-Path $workspaceRoot '.godot-user\Roaming'
$env:LOCALAPPDATA = Join-Path $workspaceRoot '.godot-user\Local'
foreach ($dir in @($env:APPDATA, $env:LOCALAPPDATA)) {
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

$logRoot = Join-Path $env:TEMP ('qg-net-test-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

$failures = New-Object System.Collections.ArrayList
$started = New-Object System.Collections.ArrayList
$scenarioCount = 0

# Godot 4.6 prints these on every headless start/shutdown in this environment:
#   - the certificate store warning comes from the TLS backend;
#   - the ObjectDB/resource lines are the engine's own teardown diagnostics and
#     appear for the rules-engine suite too, so they say nothing about the
#     transport. Everything else in stderr is treated as a real failure.
$knownEngineNoise = @(
    'root certificate store',
    'resources still in use at exit',
    'ObjectDB instances leaked at exit'
)

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------

function Add-Failure {
    param([string]$Message)
    Write-Host ('  FAIL: ' + $Message) -ForegroundColor Red
    [void]$failures.Add($Message)
}

function Get-FreeUdpPort {
    $udp = New-Object -TypeName System.Net.Sockets.UdpClient -ArgumentList 0
    try {
        return ([System.Net.IPEndPoint]$udp.Client.LocalEndPoint).Port
    } finally {
        $udp.Close()
    }
}

function Get-ScenarioPort {
    param([int]$Index)
    if ($Port -gt 0) {
        return $Port + $Index
    }
    return Get-FreeUdpPort
}

function Read-Log {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            $text = $reader.ReadToEnd()
            $reader.Dispose()
            return [string]$text
        } finally {
            $stream.Dispose()
        }
    } catch {
        return ''
    }
}

# --------------------------------------------------------------------------
# Probe processes
#
# Launched through cmd.exe so stdout/stderr go straight to log files. The
# probes self-terminate when a kill file appears, so the test does not depend on
# being allowed to kill a process tree (which some sandboxes deny).
# --------------------------------------------------------------------------

function Start-Probe {
    param(
        [string]$ProbeScript,
        [string]$Mode,
        [string]$LogName,
        [int]$ProbePort
    )
    $outPath = Join-Path $logRoot ($LogName + '.out.txt')
    $errPath = Join-Path $logRoot ($LogName + '.err.txt')
    $killPath = Join-Path $logRoot ($LogName + '.kill')
    if (Test-Path -LiteralPath $killPath) { Remove-Item -LiteralPath $killPath -Force }

    $commandLine = '/c ""{0}" --headless --path "{1}" --script {2} -- --port={3} --mode={4} --kill-file="{5}" > "{6}" 2> "{7}""' -f `
        $GodotPath, $projectRoot, $ProbeScript, $ProbePort, $Mode, $killPath, $outPath, $errPath

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $env:ComSpec
    if (-not $psi.FileName -or -not (Test-Path -LiteralPath $psi.FileName)) {
        $psi.FileName = Join-Path $env:SystemRoot 'System32\cmd.exe'
    }
    $psi.Arguments = $commandLine
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = $projectRoot

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    if (-not $process.Start()) {
        throw ('could not start ' + $ProbeScript)
    }
    $probe = [pscustomobject]@{
        Name = $LogName
        Script = $ProbeScript
        Process = $process
        StdOut = $outPath
        StdErr = $errPath
        KillFile = $killPath
        EnginePid = 0
    }
    [void](Resolve-ProbeEnginePid $probe)
    return $probe
}

## The probe prints its own engine PID as its first line. Knowing it lets the
## test terminate the real engine even when the shell may not kill the cmd.exe
## launcher tree.
function Resolve-ProbeEnginePid {
    param($Probe)
    $deadline = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $text = Read-Log $Probe.StdOut
        $match = [regex]::Match($text, 'NET PID (\d+)')
        if ($match.Success) {
            $Probe.EnginePid = [int]$match.Groups[1].Value
            return $Probe.EnginePid
        }
        try {
            if ($Probe.Process.HasExited) { break }
        } catch {
        }
        Start-Sleep -Milliseconds 50
    }
    return 0
}

function Get-ProbeEngineProcess {
    param($Probe)
    if ($null -eq $Probe -or $Probe.EnginePid -le 0) { return $null }
    try {
        $engine = Get-Process -Id $Probe.EnginePid -ErrorAction Stop
        if ($engine.ProcessName -like 'godot*') { return $engine }
    } catch {
    }
    return $null
}

function Stop-Probe {
    param($Probe)
    if ($null -eq $Probe) { return }
    $engine = Get-ProbeEngineProcess $Probe
    if ($null -ne $engine) {
        try {
            $engine.Kill()
            [void]$engine.WaitForExit(3000)
        } catch {
        }
    }
    try {
        if (-not $Probe.Process.HasExited) {
            Set-Content -LiteralPath $Probe.KillFile -Value 'stop' -ErrorAction SilentlyContinue
            [void]$Probe.Process.WaitForExit(8000)
        }
    } catch {
    }
    try {
        if (-not $Probe.Process.HasExited) {
            $Probe.Process.Kill()
            [void]$Probe.Process.WaitForExit(5000)
        }
    } catch {
    }
}

function Wait-ProbeExit {
    param($Probe, [int]$TimeoutSeconds)
    try {
        return $Probe.Process.WaitForExit($TimeoutSeconds * 1000)
    } catch {
        return $false
    }
}

function Wait-LogContains {
    param($Probe, [string[]]$Needles, [int]$TimeoutSeconds)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $text = Read-Log $Probe.StdOut
        foreach ($needle in $Needles) {
            if ($text.Contains($needle)) { return $true }
        }
        try {
            if ($Probe.Process.HasExited) { break }
        } catch {
        }
        Start-Sleep -Milliseconds 100
    }
    $text = Read-Log $Probe.StdOut
    foreach ($needle in $Needles) {
        if ($text.Contains($needle)) { return $true }
    }
    return $false
}

function Get-UnexpectedEngineErrors {
    param([string]$Text, [string[]]$AllowedPatterns)
    $found = New-Object System.Collections.ArrayList
    foreach ($line in ($Text -split '\r?\n')) {
        if ($line -match '^(ERROR:|SCRIPT ERROR:|USER ERROR:)') {
            $allowed = $false
            foreach ($pattern in $AllowedPatterns) {
                if ($line -match $pattern) { $allowed = $true; break }
            }
            if (-not $allowed) { [void]$found.Add($line.Trim()) }
        }
    }
    return $found
}

function Report-Logs {
    param($Probes)
    foreach ($probe in $Probes) {
        if ($null -eq $probe) { continue }
        Write-Host ('--- ' + $probe.Name + ' stdout (' + $probe.StdOut + ') ---')
        Write-Host (Read-Log $probe.StdOut)
        Write-Host ('--- ' + $probe.Name + ' stderr (' + $probe.StdErr + ') ---')
        Write-Host (Read-Log $probe.StdErr)
    }
}

function Assert-ProbePassed {
    param(
        $Probe,
        [string]$PassMarker,
        [string[]]$AllowedErrors,
        [string]$Scenario
    )
    $stdout = Read-Log $Probe.StdOut
    $stderr = Read-Log $Probe.StdErr
    $exited = $false
    $exitCode = $null
    try {
        $exited = $Probe.Process.HasExited
        if ($exited) { $exitCode = $Probe.Process.ExitCode }
    } catch {
        $exited = true
    }

    if (-not $exited) {
        Add-Failure ($Scenario + ': ' + $Probe.Name + ' did not exit in time')
    } elseif ($null -ne $exitCode -and $exitCode -ne 0) {
        Add-Failure ($Scenario + ': ' + $Probe.Name + ' exited with code ' + $exitCode)
    }
    if (-not $stdout.Contains($PassMarker)) {
        Add-Failure ($Scenario + ': ' + $Probe.Name + " did not print '" + $PassMarker + "'")
    }
    foreach ($line in ($stdout -split '\r?\n')) {
        if ($line.StartsWith('NET FAIL')) {
            Add-Failure ($Scenario + ': ' + $line.Trim())
        }
    }

    $allowed = @($knownEngineNoise) + $AllowedErrors
    $unexpected = Get-UnexpectedEngineErrors ($stdout + "`n" + $stderr) $allowed
    foreach ($line in $unexpected) {
        Add-Failure ($Scenario + ': unexpected engine error in ' + $Probe.Name + ': ' + $line)
    }
}

# --------------------------------------------------------------------------
# Scenarios
# --------------------------------------------------------------------------

try {
    Write-Host ('Quantum Go net test | godot: ' + $GodotPath)
    Write-Host ('project: ' + $projectRoot)
    Write-Host ('logs: ' + $logRoot)
    Write-Host ''

    # ----------------------------------------------------------------
    # 1. A full scripted match between two real processes.
    # ----------------------------------------------------------------
    $scenarioCount++
    Write-Host '=== Scenario 1: full match through ENet (host + guest) ==='
    $port = Get-ScenarioPort 0
    $hostProbe = Start-Probe 'res://tests/net/host_probe.gd' 'match' 'match-host' $port
    [void]$started.Add($hostProbe)
    $clientProbe = $null

    if (-not (Wait-LogContains $hostProbe @('NET HOST READY') 25)) {
        Add-Failure 'scenario 1: host never became ready'
        Report-Logs @($hostProbe)
    } else {
        $clientProbe = Start-Probe 'res://tests/net/client_probe.gd' 'match' 'match-client' $port
        [void]$started.Add($clientProbe)

        [void](Wait-ProbeExit $hostProbe 60)
        [void](Wait-ProbeExit $clientProbe 60)

        $scenarioFailures = $failures.Count
        Assert-ProbePassed $hostProbe 'NET PASS host match' @() 'scenario 1'
        Assert-ProbePassed $clientProbe 'NET PASS client match' @() 'scenario 1'

        $hostText = Read-Log $hostProbe.StdOut
        $clientText = Read-Log $clientProbe.StdOut
        $hostScore = [regex]::Match($hostText, 'NET SCORE host black=(-?\d+) white=(-?\d+) moves=(-?\d+) winner=(-?\d+)')
        $clientScore = [regex]::Match($clientText, 'NET SCORE client black=(-?\d+) white=(-?\d+) moves=(-?\d+) winner=(-?\d+)')

        if (-not $hostScore.Success) {
            Add-Failure 'scenario 1: host did not report a final score'
        }
        if (-not $clientScore.Success) {
            Add-Failure 'scenario 1: client did not report a final score'
        }
        if ($hostScore.Success -and $clientScore.Success) {
            $fields = @('black', 'white', 'moves', 'winner')
            for ($i = 1; $i -le 4; $i++) {
                $hostValue = $hostScore.Groups[$i].Value
                $clientValue = $clientScore.Groups[$i].Value
                if ($hostValue -ne $clientValue) {
                    Add-Failure ('scenario 1: score mismatch in ' + $fields[$i - 1] + ': host=' + $hostValue + ' client=' + $clientValue)
                }
            }
            if ($hostScore.Groups[3].Value -ne '7') {
                Add-Failure ('scenario 1: expected 7 moves in the scripted match, got ' + $hostScore.Groups[3].Value)
            }
        }

        if ($failures.Count -gt $scenarioFailures) {
            Report-Logs @($hostProbe, $clientProbe)
        } else {
            Write-Host ('  PASS host/guest scores match: ' + $hostScore.Groups[1].Value + '/' + $hostScore.Groups[2].Value + ', moves=' + $hostScore.Groups[3].Value)
        }
        Stop-Probe $hostProbe
        Stop-Probe $clientProbe
    }

    # ----------------------------------------------------------------
    # 2. Guest killed mid-match: host must stay alive and report it.
    # ----------------------------------------------------------------
    $scenarioCount++
    Write-Host ''
    Write-Host '=== Scenario 2: guest killed mid-match ==='
    $port = Get-ScenarioPort 1
    $disconnectHost = Start-Probe 'res://tests/net/host_probe.gd' 'disconnect' 'disconnect-host' $port
    [void]$started.Add($disconnectHost)
    $disconnectClient = $null

    if (-not (Wait-LogContains $disconnectHost @('NET HOST READY') 25)) {
        Add-Failure 'scenario 2: host never became ready'
        Report-Logs @($disconnectHost)
    } else {
        $disconnectClient = Start-Probe 'res://tests/net/client_probe.gd' 'idle' 'disconnect-client' $port
        [void]$started.Add($disconnectClient)

        if (-not (Wait-LogContains $disconnectHost @('NET DISCONNECT READY') 35)) {
            Add-Failure 'scenario 2: host never reached the mid-match state'
            Report-Logs @($disconnectHost, $disconnectClient)
        } else {
            Start-Sleep -Milliseconds 300
            # Hard kill: the guest gets no chance to say goodbye.
            Stop-Probe $disconnectClient

            $scenarioFailures = $failures.Count
            if (-not (Wait-ProbeExit $disconnectHost 75)) {
                Add-Failure 'scenario 2: host did not react to the killed guest in time'
                Stop-Probe $disconnectHost
            }
            Assert-ProbePassed $disconnectHost 'NET PASS host disconnect' @() 'scenario 2'
            if (-not (Read-Log $disconnectHost.StdOut).Contains('NET SCORE host')) {
                Add-Failure 'scenario 2: host could not score the position after the guest left'
            }
            if ($failures.Count -gt $scenarioFailures) {
                Report-Logs @($disconnectHost, $disconnectClient)
            } else {
                Write-Host '  PASS host reported the guest leaving and stayed consistent'
            }
        }
        Stop-Probe $disconnectHost
        Stop-Probe $disconnectClient
    }

    # ----------------------------------------------------------------
    # 3. Refused connection: readable error, no crash.
    # ----------------------------------------------------------------
    $scenarioCount++
    Write-Host ''
    Write-Host '=== Scenario 3: connection refused ==='
    $port = Get-ScenarioPort 2
    $refusedClient = Start-Probe 'res://tests/net/client_probe.gd' 'refused' 'refused-client' $port
    [void]$started.Add($refusedClient)
    $scenarioFailures = $failures.Count
    if (-not (Wait-ProbeExit $refusedClient 30)) {
        Add-Failure 'scenario 3: client did not give up on the refused connection in time'
        Stop-Probe $refusedClient
    }
    Assert-ProbePassed $refusedClient 'NET PASS client refused' @() 'scenario 3'
    if (-not (Read-Log $refusedClient.StdOut).Contains('NET CLIENT ERROR')) {
        Add-Failure 'scenario 3: client did not report the connection error message'
    }
    if ($failures.Count -gt $scenarioFailures) {
        Report-Logs @($refusedClient)
    } else {
        Write-Host '  PASS client reported a readable connection failure'
    }
    Stop-Probe $refusedClient

    # ----------------------------------------------------------------
    # 4. Port already in use: clean failure, then recovery.
    # ----------------------------------------------------------------
    $scenarioCount++
    Write-Host ''
    Write-Host '=== Scenario 4: port already in use ==='
    $port = Get-ScenarioPort 3
    $busyHost = Start-Probe 'res://tests/net/host_probe.gd' 'port-busy' 'port-busy-host' $port
    [void]$started.Add($busyHost)
    $scenarioFailures = $failures.Count
    if (-not (Wait-ProbeExit $busyHost 30)) {
        Add-Failure 'scenario 4: host did not finish the occupied-port check in time'
        Stop-Probe $busyHost
    }
    # The engine itself logs "Couldn't create an ENet host." when ENet cannot
    # bind; that line is expected here and is the only allowed error.
    Assert-ProbePassed $busyHost 'NET PASS host port-busy' @("Couldn't create an ENet host") 'scenario 4'
    if ($failures.Count -gt $scenarioFailures) {
        Report-Logs @($busyHost)
    } else {
        Write-Host '  PASS occupied port reported cleanly and hosting recovered'
    }
    Stop-Probe $busyHost
} catch {
    Add-Failure ('unexpected driver error: ' + $_.Exception.Message)
} finally {
    foreach ($probe in $started) {
        Stop-Probe $probe
    }
    foreach ($probe in $started) {
        if ($null -ne (Get-ProbeEngineProcess $probe)) {
            Add-Failure ('probe ' + $probe.Name + ' (engine pid ' + $probe.EnginePid + ') is still running')
        }
    }
}

Write-Host ''
if ($failures.Count -eq 0) {
    Write-Host ('NET TEST PASS (' + $scenarioCount + ' scenarios, logs: ' + $logRoot + ')') -ForegroundColor Green
    exit 0
}

foreach ($failure in $failures) {
    Write-Host ('  - ' + $failure) -ForegroundColor Red
}
Write-Host ('NET TEST FAIL (' + $failures.Count + ' failure(s), logs: ' + $logRoot + ')') -ForegroundColor Red
exit 1
