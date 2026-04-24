<#
.SYNOPSIS
    Dell BIOS Update via DCU CLI - Silent, No Forced Reboot
    Kills competing Dell processes before running dcu-cli.exe
    Stages a registry key for ConfigMgr detection
#>

#region --- Configuration ---
$DCUPath     = "C:\Program Files\Dell\CommandUpdate\dcu-cli.exe"
$LogDir      = "C:\Windows\Temp\Logs\Dell"
$LogFile     = Join-Path $LogDir "DCU_BIOS_Update.log"
$StdOutLog   = Join-Path $LogDir "dcu-cli.stdout.log"
$StdErrLog   = Join-Path $LogDir "dcu-cli.stderr.log"
$RegPath     = "HKLM:\SOFTWARE\Company\DCU" # Replace Company with company name or update reg path to whatever you'd like
$RegName     = "BIOSUpdateStaged"
$DCUArgs     = "/applyUpdates -silent -reboot=disable -updateType=bios,firmware"
#endregion

#region --- Logging ---
function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $entry = "[$timestamp] $Message"
    Write-Output $entry
    Add-Content -Path $LogFile -Value $entry -ErrorAction SilentlyContinue
}
#endregion

#region --- Registry Helpers ---
function Set-BIOSStagedRegKey {
    try {
        if (-not (Test-Path $RegPath)) {
            New-Item -Path $RegPath -Force | Out-Null
        }
        Set-ItemProperty -Path $RegPath -Name $RegName -Value "True" -Type String -Force
        Write-Log "Registry key set: $RegPath\$RegName = True"
    } catch {
        Write-Log "WARNING: Failed to set registry key - $_"
    }
}

function Clear-BIOSStagedRegKey {
    try {
        if (Test-Path $RegPath) {
            Remove-ItemProperty -Path $RegPath -Name $RegName -ErrorAction SilentlyContinue
            Write-Log "Registry key cleared: $RegPath\$RegName"
        }
    } catch {
        Write-Log "WARNING: Failed to clear registry key - $_"
    }
}
#endregion

#region --- BitLocker Suspension ---
function Suspend-BitLockerIfEnabled {
    try {
        $BLStatus = Get-BitLockerVolume -MountPoint "C:" -ErrorAction SilentlyContinue
        if ($BLStatus -and $BLStatus.ProtectionStatus -eq "On") {
            Write-Log "BitLocker detected - suspending for 2 reboot cycle..."
            Suspend-BitLocker -MountPoint "C:" -RebootCount 2 -ErrorAction Stop
            Write-Log "BitLocker suspended successfully."
        } else {
            Write-Log "BitLocker not active on C: - skipping suspension."
        }
    } catch {
        Write-Log "ERROR: Failed to suspend BitLocker - $_"
        exit 1
    }
}
#endregion

#region --- Kill Competing Dell Processes ---
function Stop-DellBackgroundProcesses {
    $DellProcessesToStop = @(
        "Dell.Update.SubAgent",
        "Dell.TechHub",
        "Dell.TechHub.Analytics.SubAgent",
        "Dell.TechHub.DataManager.SubAgent",
        "Dell.TechHub.Instrumentation.SubAgent",
        "Dell.TechHub.Instrumentation.UserProcess",
        "Dell.UCA.Manager",
        "Dell.CoreServices.Client"
    )

    Write-Log "Stopping competing Dell background processes..."
    foreach ($proc in $DellProcessesToStop) {
        $running = Get-Process -Name $proc -ErrorAction SilentlyContinue
        if ($running) {
            Write-Log "Stopping: $proc (PID $($running.Id))"
            Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
        } else {
            Write-Log "Not running: $proc"
        }
    }

    Start-Sleep -Seconds 5
    Write-Log "Dell background processes stopped. Proceeding with dcu-cli.exe..."
}
#endregion

#region --- Restart Dell Services ---
function Start-DellServices {
    Write-Log "Restarting Dell Client Management Service..."
    Start-Service -Name "DellClientManagementService" -ErrorAction SilentlyContinue
    Write-Log "Dell Client Management Service restart attempted."
}
#endregion

#region --- AC Power Check ---
function Test-ACPower {
    try {
        $battery = Get-WmiObject -Class Win32_Battery -ErrorAction SilentlyContinue
        if ($null -eq $battery) {
            Write-Log "No battery detected - assuming desktop/AC powered."
            return $true
        }
        # BatteryStatus 2 = AC power
        if ($battery.BatteryStatus -eq 2) {
            Write-Log "AC power confirmed."
            return $true
        } else {
            Write-Log "Device is on battery power - skipping BIOS update."
            return $false
        }
    } catch {
        Write-Log "WARNING: Could not determine power status - proceeding anyway."
        return $true
    }
}
#endregion

#region --- Main ---

# Ensure log directory exists
if (-not (Test-Path $LogDir)) {
    New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
}

Write-Log "===== Dell BIOS Update Script Started ====="
Write-Log "DCU Path: $DCUPath"
Write-Log "DCU Args: $DCUArgs"

# Verify DCU is installed
if (-not (Test-Path $DCUPath)) {
    Write-Log "ERROR: dcu-cli.exe not found at $DCUPath. Is Dell Command | Update installed?"
    exit 1
}

# AC power check (skip on desktops automatically)
if (-not (Test-ACPower)) {
    exit 0  # Soft exit - retry next time
}

# Suspend BitLocker if active
Suspend-BitLockerIfEnabled

# Kill competing Dell processes
Stop-DellBackgroundProcesses

# Run dcu-cli.exe and capture stdout/stderr
Write-Log "Launching: $DCUPath $DCUArgs"

$Process = Start-Process -FilePath $DCUPath `
    -ArgumentList $DCUArgs `
    -Wait -PassThru -NoNewWindow `
    -RedirectStandardOutput $StdOutLog `
    -RedirectStandardError  $StdErrLog

$ExitCode = $Process.ExitCode
Write-Log "dcu-cli.exe exited with code: $ExitCode"

# Log stdout/stderr content
if (Test-Path $StdOutLog) {
    $stdout = Get-Content $StdOutLog -Raw -ErrorAction SilentlyContinue
    if ($stdout) { Write-Log "STDOUT: $stdout" }
}
if (Test-Path $StdErrLog) {
    $stderr = Get-Content $StdErrLog -Raw -ErrorAction SilentlyContinue
    if ($stderr) { Write-Log "STDERR: $stderr" }
}

# Restart Dell services
Start-DellServices

# Handle exit codes
switch ($ExitCode) {
    0 {
        Write-Log "SUCCESS: No updates found or updates applied successfully (no reboot needed)."
        Clear-BIOSStagedRegKey
        exit 0
    }
    1 {
        Write-Log "SUCCESS: Updates applied - reboot required. Staging registry key."
        Set-BIOSStagedRegKey
        exit 0  # Soft exit - reboot is user-initiated
    }
    2 {
        Write-Log "SUCCESS: Updates downloaded - reboot required to apply."
        Set-BIOSStagedRegKey
        exit 0
    }
    5 {
        Write-Log "INFO: Updates are available but were not applied (reboot pending from previous run?)."
        Set-BIOSStagedRegKey
        exit 0
    }
    107 {
        Write-Log "WARNING: DCU was busy/locked (exit 107) even after stopping background processes. Will retry next run."
        exit 0  # Soft exit so ConfigMgr doesn't mark as failed
    }
    500 {
        Write-Log "ERROR: DCU encountered a general error (exit 500)."
        exit 1
    }
    default {
        Write-Log "WARNING: Unhandled exit code $ExitCode - treating as non-fatal."
        exit 0
    }
}

#endregion
