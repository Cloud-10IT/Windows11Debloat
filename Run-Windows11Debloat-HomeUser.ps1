# =============================================================================
# Run-Windows11Debloat-HomeUser.ps1
#
# PURPOSE
#   One-click home user launcher for Windows11Debloat.
#   - Runs a full debloat in Deploy mode (all scopes)
#   - Auto-detects the device vendor
#   - Registers a scheduled task that re-runs automatically after every
#     Windows Update, so bloatware that Microsoft or OEMs re-install gets
#     cleaned up without any user action
#
# USAGE
#   Right-click > Run with PowerShell (as Administrator)
#   OR double-click Run-Windows11Debloat-HomeUser.cmd
#
# WHAT IT DOES
#   1. Runs the full debloat on first launch (device + user scope)
#   2. Registers the Windows11Debloat-AfterWindowsUpdate scheduled task
#   3. The task fires ~30 minutes after Windows Update completes,
#      silently cleans up any re-installed apps, then exits
#
# NO CONFIGURATION NEEDED — sensible defaults are pre-set below.
#   If you want to change the delay before the post-update rerun,
#   edit ScheduleDelayMinutes below.
# =============================================================================

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------
# OPTIONAL — edit these if you want to customise behaviour
# -----------------------------------------------------------------------
$HomeDefaults = @{
    Stage                 = 'Deploy'
    CleanupScope          = 'All'          # Device + User in one pass
    AutoDetect            = $true          # auto-detects Dell / Lenovo / HP / etc.
    IncludeCommon         = $true          # removes common cross-vendor bloat too
    EnableScheduledRerun  = $true          # register the AfterWindowsUpdate task
    ScheduleTriggerMode   = 'AfterWindowsUpdate' # fire after Windows patches, not on a fixed date
    ScheduleDelayMinutes  = 30             # wait 30 min after update completion before rerunning
}
# -----------------------------------------------------------------------

function Resolve-RootPath {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) { return $PSScriptRoot }
    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) { return Split-Path -Path $PSCommandPath -Parent }
    return (Get-Location).Path
}

function Find-PowerShell {
    $pwshPath = Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7\pwsh.exe'
    if (Test-Path -Path $pwshPath) { return $pwshPath }
    $psPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -Path $psPath) { return $psPath }
    throw 'Cannot find pwsh.exe or powershell.exe.'
}

$root      = Resolve-RootPath
$comboPath = Join-Path -Path $root -ChildPath 'Run-Windows11Debloat-Combo.ps1'
$psExe     = Find-PowerShell

if (-not (Test-Path -Path $comboPath)) {
    Write-Error "Run-Windows11Debloat-Combo.ps1 not found at '$comboPath'. Make sure all files are in the same folder."
    exit 1
}

Write-Host ''
Write-Host '======================================================='
Write-Host '  Windows 11 Debloat — Home User Launcher'
Write-Host '======================================================='
Write-Host ''
Write-Host '[INFO] Settings:'
Write-Host "[INFO]   Stage:                 $($HomeDefaults.Stage)"
Write-Host "[INFO]   CleanupScope:          $($HomeDefaults.CleanupScope)"
Write-Host "[INFO]   AutoDetect:            $($HomeDefaults.AutoDetect)"
Write-Host "[INFO]   IncludeCommon:         $($HomeDefaults.IncludeCommon)"
Write-Host "[INFO]   EnableScheduledRerun:  $($HomeDefaults.EnableScheduledRerun)"
Write-Host "[INFO]   ScheduleTriggerMode:   $($HomeDefaults.ScheduleTriggerMode)"
Write-Host "[INFO]   ScheduleDelayMinutes:  $($HomeDefaults.ScheduleDelayMinutes)"
Write-Host ''

$comboArgs = [System.Collections.Generic.List[string]]::new()
$comboArgs.Add('-NoProfile')
$comboArgs.Add('-ExecutionPolicy')
$comboArgs.Add('Bypass')
$comboArgs.Add('-File')
$comboArgs.Add($comboPath)
$comboArgs.Add('-Stage')
$comboArgs.Add($HomeDefaults.Stage)
$comboArgs.Add('-CleanupScope')
$comboArgs.Add($HomeDefaults.CleanupScope)
$comboArgs.Add('-AutoDetect')
$comboArgs.Add('-IncludeCommon')
$comboArgs.Add('-EnableScheduledRerun')
$comboArgs.Add('-ScheduleTriggerMode')
$comboArgs.Add($HomeDefaults.ScheduleTriggerMode)
$comboArgs.Add('-ScheduleDelayMinutes')
$comboArgs.Add([string]$HomeDefaults.ScheduleDelayMinutes)

Write-Host '[INFO] Starting debloat...'
Write-Host ''

& $psExe @comboArgs
$exitCode = $LASTEXITCODE
if ($null -eq $exitCode) { $exitCode = 0 }

Write-Host ''
if ($exitCode -eq 0) {
    Write-Host '[SUCCESS] Debloat complete.'
    Write-Host '[INFO] A scheduled task (Windows11Debloat-AfterWindowsUpdate) has been registered.'
    Write-Host '[INFO] It will run automatically ~30 minutes after future Windows Updates.'
}
else {
    Write-Host "[WARN] Debloat finished with exit code $exitCode. Check the log in C:\ProgramData\Windows11Debloat\Logs\"
}

Write-Host ''
Write-Host 'Press any key to close...'
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
exit $exitCode
