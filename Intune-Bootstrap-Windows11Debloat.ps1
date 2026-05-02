[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
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

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message"
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
