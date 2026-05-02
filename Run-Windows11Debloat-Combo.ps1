[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Test', 'Deploy')]
    [string]$Stage = 'Test',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Device', 'User', 'All')]
    [string]$CleanupScope = 'Device',

    [Parameter(Mandatory = $false)]
    [string]$Vendor,

    [Parameter(Mandatory = $false)]
    [switch]$AutoDetect,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeCommon,

    [Parameter(Mandatory = $false)]
    [switch]$UseIntuneMode,

    [Parameter(Mandatory = $false)]
    [string]$ProfilesPath,

    [Parameter(Mandatory = $false)]
    [string]$ScriptPath

    ,
    [Parameter(Mandatory = $false)]
    [switch]$RecordTicketResult,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Jira', 'Atera', 'NinjaRMM', 'NinjaOne', 'ServiceNow', 'Freshservice', 'Zendesk', 'ManageEngineSDP', 'ConnectWiseManage', 'AutotaskPSA', 'HaloITSM', 'Other')]
    [string]$TicketSystem,

    [Parameter(Mandatory = $false)]
    [string]$TicketNotifyEmail,

    [Parameter(Mandatory = $false)]
    [string]$TicketRing,

    [Parameter(Mandatory = $false)]
    [string]$TicketingConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# EDIT BEFORE UPLOAD TO RMM
# Set defaults below when this file is uploaded directly in an RMM script job
# (NinjaOne, Atera, Action1, ConnectWise, or any RMM that cannot pass arguments).
# ============================================================================
$RmmDefaults = @{
    # --- Deployment options ---
    Stage              = 'Test'                        # 'Test' (pilot/dry-run) or 'Deploy' (production)
    CleanupScope       = 'Device'                      # 'Device', 'User', or 'All'
    Vendor             = ''                            # Example: 'Dell' — leave blank when AutoDetect = $true
    AutoDetect         = $true                         # $true to auto-detect vendor from WMI
    IncludeCommon      = $true                         # $true to also remove common cross-vendor bloat
    UseIntuneMode      = $false                        # $false for RMM; $true only if Intune staging behaviour is needed
    ProfilesPath       = ''                            # Example: 'C:\ProgramData\Windows11Debloat\vendor-profiles.json'
    ScriptPath         = ''                            # Example: 'C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1'

    # --- Ticketing (agnostic) ---
    # Set RecordTicketResult = $true and choose any supported TicketSystem.
    # Supported values: Jira, ServiceNow, Freshservice, Zendesk, Atera,
    #                   NinjaOne, NinjaRMM, ManageEngineSDP, ConnectWiseManage,
    #                   AutotaskPSA, HaloITSM, Other
    RecordTicketResult  = $false                       # $true to create a ticket/event after each run
    TicketSystem        = ''                           # Example: 'ServiceNow'
    TicketNotifyEmail   = ''                           # Example: 'helpdesk@contoso.com'
    TicketRing          = ''                           # Example: 'Ring1'
    TicketingConfigPath = ''                           # Example: 'C:\ProgramData\Windows11Debloat\ticketing-config.json'
    # Note: Jira REST API credentials are configured via Ticketing-Setup.ps1 -Action Setup
    # or set in ticketing-config.json. No Jira fields are needed here unless you use
    # Intune-Bootstrap-Windows11Debloat.ps1 which passes them directly.
}

if (-not $PSBoundParameters.ContainsKey('Stage')) { $Stage = $RmmDefaults.Stage }
if (-not $PSBoundParameters.ContainsKey('CleanupScope')) { $CleanupScope = $RmmDefaults.CleanupScope }
if (-not $PSBoundParameters.ContainsKey('Vendor')) { $Vendor = $RmmDefaults.Vendor }
if (-not $PSBoundParameters.ContainsKey('AutoDetect')) { $AutoDetect = $RmmDefaults.AutoDetect }
if (-not $PSBoundParameters.ContainsKey('IncludeCommon')) { $IncludeCommon = $RmmDefaults.IncludeCommon }
if (-not $PSBoundParameters.ContainsKey('UseIntuneMode')) { $UseIntuneMode = $RmmDefaults.UseIntuneMode }
if (-not $PSBoundParameters.ContainsKey('ProfilesPath')) { $ProfilesPath = $RmmDefaults.ProfilesPath }
if (-not $PSBoundParameters.ContainsKey('ScriptPath')) { $ScriptPath = $RmmDefaults.ScriptPath }
if (-not $PSBoundParameters.ContainsKey('RecordTicketResult')) { $RecordTicketResult = $RmmDefaults.RecordTicketResult }
if (-not $PSBoundParameters.ContainsKey('TicketSystem')) { $TicketSystem = $RmmDefaults.TicketSystem }
if (-not $PSBoundParameters.ContainsKey('TicketNotifyEmail')) { $TicketNotifyEmail = $RmmDefaults.TicketNotifyEmail }
if (-not $PSBoundParameters.ContainsKey('TicketRing')) { $TicketRing = $RmmDefaults.TicketRing }
if (-not $PSBoundParameters.ContainsKey('TicketingConfigPath')) { $TicketingConfigPath = $RmmDefaults.TicketingConfigPath }

function Resolve-RootPath {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return Split-Path -Path $PSCommandPath -Parent
    }

    return (Get-Location).Path
}

function Resolve-HostExecutable {
    if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
        return 'pwsh.exe'
    }

    if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
        return 'powershell.exe'
    }

    throw 'Unable to find pwsh.exe or powershell.exe in PATH.'
}

function Format-ArgumentForPreview {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($Value -match '[\s"]') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }

    return $Value
}

function Invoke-TicketResultRecording {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [int]$DebloatExitCode,

        [Parameter(Mandatory = $true)]
        [string]$RunStage,

        [Parameter(Mandatory = $true)]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$DebloatCommand
    )

    $ticketScriptPath = Join-Path -Path $RootPath -ChildPath 'Ticketing-Setup.ps1'
    if (-not (Test-Path -Path $ticketScriptPath)) {
        Write-Host "[WARN] Ticket result recording requested, but ticket helper was not found at '$ticketScriptPath'."
        return
    }

    $status = if ($DebloatExitCode -eq 0) { 'Success' } else { 'Failure' }
    $deviceName = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($deviceName)) {
        $deviceName = 'UnknownDevice'
    }

    $summary = "Windows11Debloat $status - $deviceName - Stage:$RunStage Scope:$Scope Exit:$DebloatExitCode"
    $description = "Command: $DebloatCommand"

    $ticketParams = @{
        Action = 'CreateTicket'
        Summary = $summary
        Description = $description
        DeviceName = $deviceName
        Stage = $RunStage
        CleanupScope = $Scope
        ExitCode = $DebloatExitCode
    }

    if (-not [string]::IsNullOrWhiteSpace($TicketRing)) {
        $ticketParams.Ring = $TicketRing
    }

    if (-not [string]::IsNullOrWhiteSpace($TicketSystem)) {
        $ticketParams.SystemName = $TicketSystem
    }

    if (-not [string]::IsNullOrWhiteSpace($TicketNotifyEmail)) {
        $ticketParams.NotifyEmail = $TicketNotifyEmail
    }

    if (-not [string]::IsNullOrWhiteSpace($TicketingConfigPath)) {
        $ticketParams.ConfigPath = $TicketingConfigPath
    }

    try {
        & $ticketScriptPath @ticketParams
        Write-Host '[INFO] Ticket result recording completed.'
    }
    catch {
        Write-Host "[WARN] Ticket result recording failed. $($_.Exception.Message)"
    }
}

$root = Resolve-RootPath
$resolvedScriptPath = if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    Join-Path -Path $root -ChildPath 'Windows11Debloat.ps1'
}
else {
    $ScriptPath
}

if (-not (Test-Path -Path $resolvedScriptPath)) {
    throw "Debloat script not found at '$resolvedScriptPath'."
}

$argList = [System.Collections.Generic.List[string]]::new()
$argList.Add('-NoProfile')
$argList.Add('-ExecutionPolicy')
$argList.Add('Bypass')
$argList.Add('-File')
$argList.Add($resolvedScriptPath)

if ($AutoDetect -or [string]::IsNullOrWhiteSpace($Vendor)) {
    $argList.Add('-AutoDetect')
}
else {
    $argList.Add('-Vendor')
    $argList.Add($Vendor)
}

if ($IncludeCommon -or -not $PSBoundParameters.ContainsKey('IncludeCommon')) {
    $argList.Add('-IncludeCommon')
}

$argList.Add('-CleanupScope')
$argList.Add($CleanupScope)

if (-not [string]::IsNullOrWhiteSpace($ProfilesPath)) {
    $argList.Add('-ProfilesPath')
    $argList.Add($ProfilesPath)
}

if ($UseIntuneMode) {
    $argList.Add('-IntuneMode')
}

if ($Stage -eq 'Test') {
    $argList.Add('-HelpdeskMode')
    $argList.Add('-DryRun')
    $argList.Add('-QuietDryRun')
}
else {
    $argList.Add('-HelpdeskMode')
}

$hostExecutable = Resolve-HostExecutable
$commandPreview = $hostExecutable + ' ' + (($argList | ForEach-Object { Format-ArgumentForPreview -Value $_ }) -join ' ')
Write-Host '[INFO] Effective combo settings:'
Write-Host "[INFO]   Stage: $Stage"
Write-Host "[INFO]   CleanupScope: $CleanupScope"
Write-Host "[INFO]   VendorMode: $(if ($AutoDetect -or [string]::IsNullOrWhiteSpace($Vendor)) { 'AutoDetect' } else { 'Vendor' })"
Write-Host "[INFO]   Vendor: $(if ([string]::IsNullOrWhiteSpace($Vendor)) { '<not-set>' } else { $Vendor })"
Write-Host "[INFO]   IncludeCommon: $([bool]$IncludeCommon)"
Write-Host "[INFO]   UseIntuneMode: $([bool]$UseIntuneMode)"
Write-Host "[INFO]   ProfilesPath: $(if ([string]::IsNullOrWhiteSpace($ProfilesPath)) { '<default>' } else { $ProfilesPath })"
Write-Host "[INFO]   ScriptPath: $resolvedScriptPath"
Write-Host "[INFO]   RecordTicketResult: $([bool]$RecordTicketResult)"
Write-Host "[INFO]   TicketSystem: $(if ([string]::IsNullOrWhiteSpace($TicketSystem)) { '<not-set>' } else { $TicketSystem })"
Write-Host "[INFO]   TicketNotifyEmail: $(if ([string]::IsNullOrWhiteSpace($TicketNotifyEmail)) { '<not-set>' } else { $TicketNotifyEmail })"
Write-Host "[INFO]   TicketRing: $(if ([string]::IsNullOrWhiteSpace($TicketRing)) { '<not-set>' } else { $TicketRing })"
Write-Host "[INFO]   TicketingConfigPath: $(if ([string]::IsNullOrWhiteSpace($TicketingConfigPath)) { '<default>' } else { $TicketingConfigPath })"
Write-Host "[INFO] Stage: $Stage"
Write-Host "[INFO] Command: $commandPreview"

& $hostExecutable @argList
$exitCode = $LASTEXITCODE

if ($null -eq $exitCode) {
    $exitCode = 0
}

if ($RecordTicketResult) {
    Invoke-TicketResultRecording -RootPath $root -DebloatExitCode $exitCode -RunStage $Stage -Scope $CleanupScope -DebloatCommand $commandPreview
}

Write-Host "[INFO] Exit code: $exitCode"
exit $exitCode
