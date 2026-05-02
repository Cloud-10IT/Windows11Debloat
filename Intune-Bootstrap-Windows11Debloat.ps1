# ============================================================================
# Intune-Bootstrap-Windows11Debloat.ps1
# PURPOSE : Single-file Intune bootstrap — downloads the full package zip,
#           stages all scripts locally, then runs the debloat combo.
# EDIT     : Find the EDIT BEFORE UPLOAD block below and set your values
#            before uploading to Devices > Scripts and remediations.
# ============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$PackageZipUrl,

    [Parameter(Mandatory = $false)]
    [string]$PackageZipSha256,

    [Parameter(Mandatory = $false)]
    [string]$InstallRoot = 'C:\ProgramData\Windows11Debloat',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Test', 'Deploy')]
    [string]$Stage = 'Deploy',

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
    [switch]$RecordTicketResult,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Jira', 'Atera', 'NinjaRMM', 'NinjaOne', 'ServiceNow', 'Freshservice', 'Zendesk', 'ManageEngineSDP', 'ConnectWiseManage', 'AutotaskPSA', 'HaloITSM', 'Other')]
    [string]$TicketSystem,

    [Parameter(Mandatory = $false)]
    [string]$TicketNotifyEmail,

    [Parameter(Mandatory = $false)]
    [string]$TicketRing,

    [Parameter(Mandatory = $false)]
    [string]$JiraBaseUrl,

    [Parameter(Mandatory = $false)]
    [string]$JiraProjectKey,

    [Parameter(Mandatory = $false)]
    [string]$JiraIssueType = 'Incident',

    [Parameter(Mandatory = $false)]
    [string]$JiraUserEmail,

    [Parameter(Mandatory = $false)]
    [string]$JiraApiToken
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# EDIT BEFORE UPLOAD TO INTUNE
# Set defaults below for admins who upload this file directly in:
# Devices > Scripts and remediations > Platform scripts
#
# Intune Assignments do not pass script arguments. These defaults are used when
# parameters are not explicitly passed on the command line.
# ============================================================================
$IntuneDefaults = @{
    # --- Package source ---
    PackageZipUrl      = 'https://your-storage.example.com/Windows11Debloat.zip' # Example: 'https://contoso.blob.core.windows.net/deploy/Windows11Debloat.zip?<sas-token>'
    PackageZipSha256   = ''                            # Example: '6E3B1B2B8E8A3F0D...' (leave blank to skip hash check)
    InstallRoot        = 'C:\ProgramData\Windows11Debloat' # Example: 'C:\ProgramData\Windows11Debloat'

    # --- Deployment options ---
    Stage              = 'Deploy'                      # 'Test' (pilot/dry-run) or 'Deploy' (production)
    CleanupScope       = 'Device'                      # 'Device', 'User', or 'All'
    Vendor             = ''                            # Example: 'Dell' — leave blank when AutoDetect = $true
    AutoDetect         = $true                         # $true to auto-detect vendor from WMI
    IncludeCommon      = $true                         # $true to also remove common cross-vendor bloat

    # --- Ticketing (agnostic) ---
    # Set RecordTicketResult = $true and choose any supported TicketSystem.
    # Supported values: Jira, ServiceNow, Freshservice, Zendesk, Atera,
    #                   NinjaOne, NinjaRMM, ManageEngineSDP, ConnectWiseManage,
    #                   AutotaskPSA, HaloITSM, Other
    RecordTicketResult = $false                        # $true to create a ticket/event after each run
    TicketSystem       = ''                            # Example: 'ServiceNow'
    TicketNotifyEmail  = ''                            # Example: 'helpdesk@contoso.com'
    TicketRing         = ''                            # Example: 'Ring1'

    # --- Jira-specific (only used when TicketSystem = 'Jira') ---
    JiraBaseUrl        = ''                            # Example: 'https://contoso.atlassian.net'
    JiraProjectKey     = ''                            # Example: 'ITOPS'
    JiraIssueType      = 'Incident'                    # Example: 'Incident'
    JiraUserEmail      = ''                            # Example: 'jira-bot@contoso.com'
    JiraApiToken       = ''                            # Example: 'ATATTxxxxxxxxxxxxxxxx'
}

if (-not $PSBoundParameters.ContainsKey('PackageZipUrl')) { $PackageZipUrl = $IntuneDefaults.PackageZipUrl }
if (-not $PSBoundParameters.ContainsKey('PackageZipSha256')) { $PackageZipSha256 = $IntuneDefaults.PackageZipSha256 }
if (-not $PSBoundParameters.ContainsKey('InstallRoot')) { $InstallRoot = $IntuneDefaults.InstallRoot }
if (-not $PSBoundParameters.ContainsKey('Stage')) { $Stage = $IntuneDefaults.Stage }
if (-not $PSBoundParameters.ContainsKey('CleanupScope')) { $CleanupScope = $IntuneDefaults.CleanupScope }
if (-not $PSBoundParameters.ContainsKey('Vendor')) { $Vendor = $IntuneDefaults.Vendor }
if (-not $PSBoundParameters.ContainsKey('AutoDetect')) { $AutoDetect = $IntuneDefaults.AutoDetect }
if (-not $PSBoundParameters.ContainsKey('IncludeCommon')) { $IncludeCommon = $IntuneDefaults.IncludeCommon }
if (-not $PSBoundParameters.ContainsKey('RecordTicketResult')) { $RecordTicketResult = $IntuneDefaults.RecordTicketResult }
if (-not $PSBoundParameters.ContainsKey('TicketSystem')) { $TicketSystem = $IntuneDefaults.TicketSystem }
if (-not $PSBoundParameters.ContainsKey('TicketNotifyEmail')) { $TicketNotifyEmail = $IntuneDefaults.TicketNotifyEmail }
if (-not $PSBoundParameters.ContainsKey('TicketRing')) { $TicketRing = $IntuneDefaults.TicketRing }
if (-not $PSBoundParameters.ContainsKey('JiraBaseUrl')) { $JiraBaseUrl = $IntuneDefaults.JiraBaseUrl }
if (-not $PSBoundParameters.ContainsKey('JiraProjectKey')) { $JiraProjectKey = $IntuneDefaults.JiraProjectKey }
if (-not $PSBoundParameters.ContainsKey('JiraIssueType')) { $JiraIssueType = $IntuneDefaults.JiraIssueType }
if (-not $PSBoundParameters.ContainsKey('JiraUserEmail')) { $JiraUserEmail = $IntuneDefaults.JiraUserEmail }
if (-not $PSBoundParameters.ContainsKey('JiraApiToken')) { $JiraApiToken = $IntuneDefaults.JiraApiToken }

if ([string]::IsNullOrWhiteSpace($PackageZipUrl) -or $PackageZipUrl -like 'https://your-storage.example.com/*') {
    throw "PackageZipUrl is not configured. Edit Intune-Bootstrap-Windows11Debloat.ps1 and set a real package URL before uploading to Intune."
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
}

function Get-MaskedValue {
    param(
        [string]$Value,
        [int]$RevealStart = 4,
        [int]$RevealEnd = 2
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return '<not-set>'
    }

    if ($Value.Length -le ($RevealStart + $RevealEnd)) {
        return ('*' * $Value.Length)
    }

    return ($Value.Substring(0, $RevealStart) + ('*' * ($Value.Length - $RevealStart - $RevealEnd)) + $Value.Substring($Value.Length - $RevealEnd))
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

function New-CleanDirectory {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (Test-Path -Path $Path) {
        Remove-Item -Path $Path -Recurse -Force -ErrorAction Stop
    }

    New-Item -Path $Path -ItemType Directory -Force | Out-Null
}

$hostExe = Resolve-HostExecutable
$tempRoot = Join-Path -Path $env:TEMP -ChildPath ('Windows11DebloatBootstrap-' + [Guid]::NewGuid().ToString('N'))
$zipPath = Join-Path -Path $tempRoot -ChildPath 'Windows11Debloat.zip'
$extractPath = Join-Path -Path $tempRoot -ChildPath 'extract'
$resolvedMode = if ($AutoDetect -or [string]::IsNullOrWhiteSpace($Vendor)) { 'AutoDetect' } else { 'Vendor' }

Write-Info 'Effective bootstrap settings:'
Write-Info "  PackageZipUrl: $PackageZipUrl"
Write-Info "  PackageZipSha256: $(if ([string]::IsNullOrWhiteSpace($PackageZipSha256)) { '<not-set>' } else { '<provided>' })"
Write-Info "  InstallRoot: $InstallRoot"
Write-Info "  Stage: $Stage"
Write-Info "  CleanupScope: $CleanupScope"
Write-Info "  VendorMode: $resolvedMode"
Write-Info "  Vendor: $(if ([string]::IsNullOrWhiteSpace($Vendor)) { '<not-set>' } else { $Vendor })"
Write-Info "  AutoDetect: $([bool]$AutoDetect)"
Write-Info "  IncludeCommon: $([bool]$IncludeCommon)"
Write-Info "  RecordTicketResult: $([bool]$RecordTicketResult)"
Write-Info "  TicketSystem: $(if ([string]::IsNullOrWhiteSpace($TicketSystem)) { '<not-set>' } else { $TicketSystem })"
Write-Info "  TicketNotifyEmail: $(if ([string]::IsNullOrWhiteSpace($TicketNotifyEmail)) { '<not-set>' } else { $TicketNotifyEmail })"
Write-Info "  TicketRing: $(if ([string]::IsNullOrWhiteSpace($TicketRing)) { '<not-set>' } else { $TicketRing })"
Write-Info "  JiraBaseUrl: $(if ([string]::IsNullOrWhiteSpace($JiraBaseUrl)) { '<not-set>' } else { $JiraBaseUrl })"
Write-Info "  JiraProjectKey: $(if ([string]::IsNullOrWhiteSpace($JiraProjectKey)) { '<not-set>' } else { $JiraProjectKey })"
Write-Info "  JiraIssueType: $(if ([string]::IsNullOrWhiteSpace($JiraIssueType)) { '<not-set>' } else { $JiraIssueType })"
Write-Info "  JiraUserEmail: $(if ([string]::IsNullOrWhiteSpace($JiraUserEmail)) { '<not-set>' } else { $JiraUserEmail })"
Write-Info "  JiraApiToken: $(Get-MaskedValue -Value $JiraApiToken)"

New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
New-Item -Path $extractPath -ItemType Directory -Force | Out-Null

try {
    Write-Info "Downloading package zip from: $PackageZipUrl"
    Invoke-WebRequest -Uri $PackageZipUrl -OutFile $zipPath -UseBasicParsing

    if (-not [string]::IsNullOrWhiteSpace($PackageZipSha256)) {
        Write-Info 'Validating downloaded package SHA-256 hash'
        $expectedHash = $PackageZipSha256.Trim().ToUpperInvariant()
        $actualHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()

        if ($actualHash -ne $expectedHash) {
            throw "Package hash mismatch. Expected '$expectedHash', actual '$actualHash'."
        }

        Write-Info 'Package SHA-256 validation passed'
    }

    Write-Info 'Extracting package'
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    $comboScript = Get-ChildItem -Path $extractPath -Recurse -Filter 'Run-Windows11Debloat-Combo.ps1' -File | Select-Object -First 1
    if ($null -eq $comboScript) {
        throw 'Run-Windows11Debloat-Combo.ps1 not found in downloaded package.'
    }

    $packageRoot = Split-Path -Path $comboScript.FullName -Parent

    Write-Info "Staging package to: $InstallRoot"
    New-CleanDirectory -Path $InstallRoot
    Copy-Item -Path (Join-Path -Path $packageRoot -ChildPath '*') -Destination $InstallRoot -Recurse -Force

    $ticketingSetupPath = Join-Path -Path $InstallRoot -ChildPath 'Ticketing-Setup.ps1'
    if ($RecordTicketResult -and (Test-Path -Path $ticketingSetupPath)) {
        $setupParams = @{
            Action = 'Setup'
        }

        if (-not [string]::IsNullOrWhiteSpace($TicketSystem)) { $setupParams.SystemName = $TicketSystem }
        if (-not [string]::IsNullOrWhiteSpace($TicketNotifyEmail)) { $setupParams.NotifyEmail = $TicketNotifyEmail }
        if (-not [string]::IsNullOrWhiteSpace($JiraBaseUrl)) { $setupParams.JiraBaseUrl = $JiraBaseUrl }
        if (-not [string]::IsNullOrWhiteSpace($JiraProjectKey)) { $setupParams.JiraProjectKey = $JiraProjectKey }
        if (-not [string]::IsNullOrWhiteSpace($JiraIssueType)) { $setupParams.JiraIssueType = $JiraIssueType }
        if (-not [string]::IsNullOrWhiteSpace($JiraUserEmail)) { $setupParams.JiraUserEmail = $JiraUserEmail }
        if (-not [string]::IsNullOrWhiteSpace($JiraApiToken)) { $setupParams.JiraApiToken = $JiraApiToken }

        if ($setupParams.ContainsKey('SystemName')) {
            Write-Info 'Configuring ticketing settings'
            & $ticketingSetupPath @setupParams
        }
        else {
            Write-Info 'Ticket recording requested but no TicketSystem provided; skipping ticket setup.'
        }
    }

    $comboPath = Join-Path -Path $InstallRoot -ChildPath 'Run-Windows11Debloat-Combo.ps1'
    if (-not (Test-Path -Path $comboPath)) {
        throw "Combo script not found at '$comboPath' after staging."
    }

    $comboArgs = [System.Collections.Generic.List[string]]::new()
    $comboArgs.Add('-NoProfile')
    $comboArgs.Add('-ExecutionPolicy')
    $comboArgs.Add('Bypass')
    $comboArgs.Add('-File')
    $comboArgs.Add($comboPath)
    $comboArgs.Add('-Stage')
    $comboArgs.Add($Stage)
    $comboArgs.Add('-CleanupScope')
    $comboArgs.Add($CleanupScope)
    $comboArgs.Add('-UseIntuneMode')

    if ($AutoDetect -or [string]::IsNullOrWhiteSpace($Vendor)) {
        $comboArgs.Add('-AutoDetect')
    }
    else {
        $comboArgs.Add('-Vendor')
        $comboArgs.Add($Vendor)
    }

    if ($IncludeCommon -or -not $PSBoundParameters.ContainsKey('IncludeCommon')) {
        $comboArgs.Add('-IncludeCommon')
    }

    if ($RecordTicketResult) {
        $comboArgs.Add('-RecordTicketResult')
        if (-not [string]::IsNullOrWhiteSpace($TicketSystem)) {
            $comboArgs.Add('-TicketSystem')
            $comboArgs.Add($TicketSystem)
        }
        if (-not [string]::IsNullOrWhiteSpace($TicketNotifyEmail)) {
            $comboArgs.Add('-TicketNotifyEmail')
            $comboArgs.Add($TicketNotifyEmail)
        }
        if (-not [string]::IsNullOrWhiteSpace($TicketRing)) {
            $comboArgs.Add('-TicketRing')
            $comboArgs.Add($TicketRing)
        }
    }

    Write-Info 'Running debloat combo script from staged package'
    & $hostExe @comboArgs
    $exitCode = $LASTEXITCODE

    if ($null -eq $exitCode) {
        $exitCode = 0
    }

    Write-Info "Bootstrap complete. Exit code: $exitCode"
    exit $exitCode
}
finally {
    if (Test-Path -Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
