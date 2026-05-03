# ============================================================================
# Intune-Remediation-Windows11Debloat.ps1
# PURPOSE : Remediation script for Intune Remediations — re-downloads the
#           package and re-runs the debloat when the detection script exits 1.
# EDIT     : Find the EDIT BEFORE UPLOAD block below and set your values
#            before uploading to Devices > Scripts and remediations > Remediations.
# ----------------------------------------------------------------------------
# LICENSING — INTUNE REMEDIATIONS
#   Proactive remediation scripts are used only on devices and users licensed
#   with an eligible Windows Enterprise-level license. Each device/user must
#   hold one of: Microsoft 365 F3, E3, or E5; or Windows Enterprise E3 or E5.
#   Intune tenant settings are enabled only for these licensed users/devices.
#
#   Required tenant setting (one-time, per tenant):
#     Intune admin center → Tenant administration → Windows data
#       ☑ Enable Windows diagnostic data processor configuration  (set to On)
#       ☑ I confirm that my tenant owns one of these qualifying licenses
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# EDIT BEFORE UPLOAD TO INTUNE
# Set defaults below before uploading this script in Remediations.
# ============================================================================
$IntuneRemediationDefaults = @{
    # --- Package source ---
    PackageZipUrl      = 'https://your-storage.example.com/Windows11Debloat.zip' # Example: 'https://contoso.blob.core.windows.net/deploy/Windows11Debloat.zip?<sas-token>'
    PackageZipSha256   = ''                            # Example: '6E3B1B2B8E8A3F0D...' (leave blank to skip)
    InstallRoot        = 'C:\ProgramData\Windows11Debloat' # Example: 'C:\ProgramData\Windows11Debloat'

    # --- Deployment options ---
    Stage              = 'Deploy'                      # 'Test' (pilot/dry-run) or 'Deploy' (production)
    CleanupScope       = 'Device'                      # 'Device', 'User', or 'All'
    Vendor             = ''                            # Example: 'Dell' — leave blank when AutoDetect = $true
    AutoDetect         = $true                         # $true to auto-detect vendor from WMI
    IncludeCommon      = $true                         # $true to also remove common cross-vendor bloat
    UseIntuneMode      = $true                         # $true when running in Intune context

    # --- Ticketing (agnostic) ---
    # Set RecordTicketResult = $true and choose any supported TicketSystem.
    # Supported values: Jira, ServiceNow, Freshservice, Zendesk, Atera,
    #                   NinjaOne, NinjaRMM, ManageEngineSDP, ConnectWiseManage,
    #                   AutotaskPSA, HaloITSM, Other
    RecordTicketResult  = $false                       # $true to create a ticket/event after each run
    TicketSystem        = ''                           # Example: 'ServiceNow'
    TicketNotifyEmail   = ''                           # Example: 'helpdesk@contoso.com'
    TicketRing          = ''                           # Example: 'Ring2'
    TicketingConfigPath = ''                           # Example: 'C:\ProgramData\Windows11Debloat\ticketing-config.json'

    # --- Jira-specific (only used when TicketSystem = 'Jira') ---
    JiraBaseUrl        = ''                            # Example: 'https://contoso.atlassian.net'
    JiraProjectKey     = ''                            # Example: 'ITOPS'
    JiraIssueType      = 'Incident'                    # Example: 'Incident'
    JiraUserEmail      = ''                            # Example: 'jira-bot@contoso.com'
    JiraApiToken       = ''                            # Example: 'ATATTxxxxxxxxxxxxxxxx'
    HasIntuneRemediationsLicense = $true              # Remediations is the licensed path; local fallback tasks are removed/ignored
}

$PackageZipUrl = $IntuneRemediationDefaults.PackageZipUrl
$PackageZipSha256 = $IntuneRemediationDefaults.PackageZipSha256
$InstallRoot = $IntuneRemediationDefaults.InstallRoot
$Stage = $IntuneRemediationDefaults.Stage
$CleanupScope = $IntuneRemediationDefaults.CleanupScope
$Vendor = $IntuneRemediationDefaults.Vendor
$AutoDetect = $IntuneRemediationDefaults.AutoDetect
$IncludeCommon = $IntuneRemediationDefaults.IncludeCommon
$UseIntuneMode = $IntuneRemediationDefaults.UseIntuneMode
$RecordTicketResult = $IntuneRemediationDefaults.RecordTicketResult
$TicketSystem = $IntuneRemediationDefaults.TicketSystem
$TicketNotifyEmail = $IntuneRemediationDefaults.TicketNotifyEmail
$TicketRing = $IntuneRemediationDefaults.TicketRing
$TicketingConfigPath = $IntuneRemediationDefaults.TicketingConfigPath
$JiraBaseUrl = $IntuneRemediationDefaults.JiraBaseUrl
$JiraProjectKey = $IntuneRemediationDefaults.JiraProjectKey
$JiraIssueType = $IntuneRemediationDefaults.JiraIssueType
$JiraUserEmail = $IntuneRemediationDefaults.JiraUserEmail
$JiraApiToken = $IntuneRemediationDefaults.JiraApiToken
$HasIntuneRemediationsLicense = $IntuneRemediationDefaults.HasIntuneRemediationsLicense

if ([string]::IsNullOrWhiteSpace($PackageZipUrl) -or $PackageZipUrl -like 'https://your-storage.example.com/*') {
    throw "PackageZipUrl is not configured. Edit Intune-Remediation-Windows11Debloat.ps1 before uploading to Intune."
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

$tempRoot = Join-Path -Path $env:TEMP -ChildPath ('W11DebloatRemediation-' + [Guid]::NewGuid().ToString('N'))
$zipPath = Join-Path -Path $tempRoot -ChildPath 'Windows11Debloat.zip'
$extractPath = Join-Path -Path $tempRoot -ChildPath 'extract'
$hostExe = Resolve-HostExecutable

Write-Info 'Effective remediation settings:'
Write-Info "  PackageZipUrl: $PackageZipUrl"
Write-Info "  PackageZipSha256: $(if ([string]::IsNullOrWhiteSpace($PackageZipSha256)) { '<not-set>' } else { '<provided>' })"
Write-Info "  InstallRoot: $InstallRoot"
Write-Info "  Stage: $Stage"
Write-Info "  CleanupScope: $CleanupScope"
Write-Info "  VendorMode: $(if ($AutoDetect -or [string]::IsNullOrWhiteSpace($Vendor)) { 'AutoDetect' } else { 'Vendor' })"
Write-Info "  Vendor: $(if ([string]::IsNullOrWhiteSpace($Vendor)) { '<not-set>' } else { $Vendor })"
Write-Info "  AutoDetect: $([bool]$AutoDetect)"
Write-Info "  IncludeCommon: $([bool]$IncludeCommon)"
Write-Info "  UseIntuneMode: $([bool]$UseIntuneMode)"
Write-Info "  RecordTicketResult: $([bool]$RecordTicketResult)"
Write-Info "  TicketSystem: $(if ([string]::IsNullOrWhiteSpace($TicketSystem)) { '<not-set>' } else { $TicketSystem })"
Write-Info "  TicketNotifyEmail: $(if ([string]::IsNullOrWhiteSpace($TicketNotifyEmail)) { '<not-set>' } else { $TicketNotifyEmail })"
Write-Info "  TicketRing: $(if ([string]::IsNullOrWhiteSpace($TicketRing)) { '<not-set>' } else { $TicketRing })"
Write-Info "  TicketingConfigPath: $(if ([string]::IsNullOrWhiteSpace($TicketingConfigPath)) { '<default>' } else { $TicketingConfigPath })"
Write-Info "  JiraBaseUrl: $(if ([string]::IsNullOrWhiteSpace($JiraBaseUrl)) { '<not-set>' } else { $JiraBaseUrl })"
Write-Info "  JiraProjectKey: $(if ([string]::IsNullOrWhiteSpace($JiraProjectKey)) { '<not-set>' } else { $JiraProjectKey })"
Write-Info "  JiraIssueType: $(if ([string]::IsNullOrWhiteSpace($JiraIssueType)) { '<not-set>' } else { $JiraIssueType })"
Write-Info "  JiraUserEmail: $(if ([string]::IsNullOrWhiteSpace($JiraUserEmail)) { '<not-set>' } else { $JiraUserEmail })"
Write-Info "  JiraApiToken: $(Get-MaskedValue -Value $JiraApiToken)"
Write-Info "  HasIntuneRemediationsLicense: $([bool]$HasIntuneRemediationsLicense)"

try {
    New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
    New-Item -Path $extractPath -ItemType Directory -Force | Out-Null

    Write-Info "Downloading package from: $PackageZipUrl"
    Invoke-WebRequest -Uri $PackageZipUrl -OutFile $zipPath -UseBasicParsing

    if (-not [string]::IsNullOrWhiteSpace($PackageZipSha256)) {
        Write-Info 'Validating downloaded package SHA-256 hash'
        $expectedHash = $PackageZipSha256.Trim().ToUpperInvariant()
        $actualHash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($actualHash -ne $expectedHash) {
            throw "Package hash mismatch. Expected '$expectedHash', got '$actualHash'."
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
    if (Test-Path -Path $InstallRoot) {
        Remove-Item -Path $InstallRoot -Recurse -Force -ErrorAction Stop
    }
    New-Item -Path $InstallRoot -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path -Path $packageRoot -ChildPath '*') -Destination $InstallRoot -Recurse -Force

    $comboPath = Join-Path -Path $InstallRoot -ChildPath 'Run-Windows11Debloat-Combo.ps1'
    if (-not (Test-Path -Path $comboPath)) {
        throw "Combo script not found at '$comboPath' after staging."
    }

    $ticketingSetupPath = Join-Path -Path $InstallRoot -ChildPath 'Ticketing-Setup.ps1'
    if ($RecordTicketResult -and (Test-Path -Path $ticketingSetupPath)) {
        $setupParams = @{ Action = 'Setup' }

        if (-not [string]::IsNullOrWhiteSpace($TicketSystem)) { $setupParams.SystemName = $TicketSystem }
        if (-not [string]::IsNullOrWhiteSpace($TicketNotifyEmail)) { $setupParams.NotifyEmail = $TicketNotifyEmail }
        if (-not [string]::IsNullOrWhiteSpace($JiraBaseUrl)) { $setupParams.JiraBaseUrl = $JiraBaseUrl }
        if (-not [string]::IsNullOrWhiteSpace($JiraProjectKey)) { $setupParams.JiraProjectKey = $JiraProjectKey }
        if (-not [string]::IsNullOrWhiteSpace($JiraIssueType)) { $setupParams.JiraIssueType = $JiraIssueType }
        if (-not [string]::IsNullOrWhiteSpace($JiraUserEmail)) { $setupParams.JiraUserEmail = $JiraUserEmail }
        if (-not [string]::IsNullOrWhiteSpace($JiraApiToken)) { $setupParams.JiraApiToken = $JiraApiToken }
        if (-not [string]::IsNullOrWhiteSpace($TicketingConfigPath)) { $setupParams.ConfigPath = $TicketingConfigPath }

        if ($setupParams.ContainsKey('SystemName')) {
            Write-Info 'Configuring ticketing settings'
            & $ticketingSetupPath @setupParams
        }
        else {
            Write-Info 'RecordTicketResult enabled but no TicketSystem configured; skipping ticket setup.'
        }
    }

    $argList = [System.Collections.Generic.List[string]]::new()
    $argList.Add('-NoProfile')
    $argList.Add('-ExecutionPolicy')
    $argList.Add('Bypass')
    $argList.Add('-File')
    $argList.Add($comboPath)
    $argList.Add('-Stage')
    $argList.Add($Stage)
    $argList.Add('-CleanupScope')
    $argList.Add($CleanupScope)

    if ($UseIntuneMode) {
        $argList.Add('-UseIntuneMode')
    }

    if ($AutoDetect -or [string]::IsNullOrWhiteSpace($Vendor)) {
        $argList.Add('-AutoDetect')
    }
    else {
        $argList.Add('-Vendor')
        $argList.Add($Vendor)
    }

    if ($IncludeCommon) {
        $argList.Add('-IncludeCommon')
    }

    if ($RecordTicketResult) {
        $argList.Add('-RecordTicketResult')
        if (-not [string]::IsNullOrWhiteSpace($TicketSystem)) {
            $argList.Add('-TicketSystem')
            $argList.Add($TicketSystem)
        }
        if (-not [string]::IsNullOrWhiteSpace($TicketNotifyEmail)) {
            $argList.Add('-TicketNotifyEmail')
            $argList.Add($TicketNotifyEmail)
        }
        if (-not [string]::IsNullOrWhiteSpace($TicketRing)) {
            $argList.Add('-TicketRing')
            $argList.Add($TicketRing)
        }
        if (-not [string]::IsNullOrWhiteSpace($TicketingConfigPath)) {
            $argList.Add('-TicketingConfigPath')
            $argList.Add($TicketingConfigPath)
        }
    }

    if ($HasIntuneRemediationsLicense) {
        $argList.Add('-HasIntuneRemediationsLicense')
    }

    Write-Info 'Running debloat combo'
    & $hostExe @argList

    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) {
        $exitCode = 0
    }

    Write-Info "Combo exited with code: $exitCode"
    exit $exitCode
}
catch {
    Write-Host "[ERROR] Remediation failed: $_"
    exit 1
}
finally {
    if (Test-Path -Path $tempRoot) {
        Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
