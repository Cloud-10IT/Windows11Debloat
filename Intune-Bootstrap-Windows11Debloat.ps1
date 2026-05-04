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
    [switch]$EnableScheduledRerun,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$ScheduleIntervalDays = 30,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 240)]
    [int]$ScheduleDelayMinutes = 45,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Interval', 'AfterWindowsUpdate', 'IntervalAndAfterWindowsUpdate', 'MonthlyDayOfWeek', 'MonthlyFixedDay')]
    [string]$ScheduleTriggerMode = 'IntervalAndAfterWindowsUpdate',

    [Parameter(Mandatory = $false)]
    [switch]$HasIntuneRemediationsLicense,

    [Parameter(Mandatory = $false)]
    [switch]$AlsoRunAfterWindowsUpdate,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 28)]
    [int]$ScheduleDayOfMonth = 15,

    [Parameter(Mandatory = $false)]
    [ValidateSet('1', '2', '3', '4', 'Last')]
    [string]$ScheduleWeekOfMonth = '2',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')]
    [string]$ScheduleDayOfWeek = 'Wednesday'
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

    # --- Fallback scheduling (only when Intune Remediations licensing is not used) ---
    EnableScheduledRerun         = $false              # $true to create a local scheduled task fallback after a successful Deploy run
    ScheduleIntervalDays         = 30                  # Interval trigger cadence in days
    ScheduleDelayMinutes         = 45                  # Delay after registration time and after Windows Update event completion
    ScheduleTriggerMode          = 'IntervalAndAfterWindowsUpdate' # Interval, AfterWindowsUpdate, IntervalAndAfterWindowsUpdate, MonthlyDayOfWeek, MonthlyFixedDay
    HasIntuneRemediationsLicense = $false             # $true when you will use licensed Intune Remediations instead of local scheduled tasks
    AlsoRunAfterWindowsUpdate    = $false              # $true to also register the Windows Update event trigger alongside a monthly trigger
    ScheduleDayOfMonth           = 15                  # Day of month for MonthlyFixedDay trigger (1-28)
    ScheduleWeekOfMonth          = '2'                 # Week of month for MonthlyDayOfWeek trigger: '1','2','3','4','Last'
    ScheduleDayOfWeek            = 'Wednesday'         # Day of week for MonthlyDayOfWeek trigger: Monday-Sunday
}

if (-not $PSBoundParameters.ContainsKey('PackageZipUrl')) { $PackageZipUrl = $IntuneDefaults.PackageZipUrl }
if (-not $PSBoundParameters.ContainsKey('PackageZipSha256')) { $PackageZipSha256 = $IntuneDefaults.PackageZipSha256 }
if (-not $PSBoundParameters.ContainsKey('InstallRoot')) { $InstallRoot = $IntuneDefaults.InstallRoot }
if (-not $PSBoundParameters.ContainsKey('Stage')) { $Stage = $IntuneDefaults.Stage }
if (-not $PSBoundParameters.ContainsKey('CleanupScope')) { $CleanupScope = $IntuneDefaults.CleanupScope }
if (-not $PSBoundParameters.ContainsKey('Vendor')) { $Vendor = $IntuneDefaults.Vendor }
if (-not $PSBoundParameters.ContainsKey('AutoDetect')) { $AutoDetect = $IntuneDefaults.AutoDetect }
if (-not $PSBoundParameters.ContainsKey('IncludeCommon')) { $IncludeCommon = $IntuneDefaults.IncludeCommon }
if (-not $PSBoundParameters.ContainsKey('EnableScheduledRerun')) { $EnableScheduledRerun = $IntuneDefaults.EnableScheduledRerun }
if (-not $PSBoundParameters.ContainsKey('ScheduleIntervalDays')) { $ScheduleIntervalDays = $IntuneDefaults.ScheduleIntervalDays }
if (-not $PSBoundParameters.ContainsKey('ScheduleDelayMinutes')) { $ScheduleDelayMinutes = $IntuneDefaults.ScheduleDelayMinutes }
if (-not $PSBoundParameters.ContainsKey('ScheduleTriggerMode')) { $ScheduleTriggerMode = $IntuneDefaults.ScheduleTriggerMode }
if (-not $PSBoundParameters.ContainsKey('HasIntuneRemediationsLicense')) { $HasIntuneRemediationsLicense = $IntuneDefaults.HasIntuneRemediationsLicense }
if (-not $PSBoundParameters.ContainsKey('AlsoRunAfterWindowsUpdate')) { $AlsoRunAfterWindowsUpdate = $IntuneDefaults.AlsoRunAfterWindowsUpdate }
if (-not $PSBoundParameters.ContainsKey('ScheduleDayOfMonth')) { $ScheduleDayOfMonth = $IntuneDefaults.ScheduleDayOfMonth }
if (-not $PSBoundParameters.ContainsKey('ScheduleWeekOfMonth')) { $ScheduleWeekOfMonth = $IntuneDefaults.ScheduleWeekOfMonth }
if (-not $PSBoundParameters.ContainsKey('ScheduleDayOfWeek')) { $ScheduleDayOfWeek = $IntuneDefaults.ScheduleDayOfWeek }

if ([string]::IsNullOrWhiteSpace($PackageZipUrl) -or $PackageZipUrl -like 'https://your-storage.example.com/*') {
    throw "PackageZipUrl is not configured. Edit Intune-Bootstrap-Windows11Debloat.ps1 and set a real package URL before uploading to Intune."
}

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

function Set-NetworkDefaults {
    try {
        $desired = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        if ([Enum]::GetNames([Net.SecurityProtocolType]) -contains 'Tls13') {
            $desired = $desired -bor [Net.SecurityProtocolType]::Tls13
        }

        [Net.ServicePointManager]::SecurityProtocol = $desired
        Write-Info "SecurityProtocol configured as: $([Net.ServicePointManager]::SecurityProtocol)"
    }
    catch {
        Write-Info "Unable to set SecurityProtocol explicitly: $($_.Exception.Message)"
    }

    try {
        $proxy = [System.Net.WebRequest]::DefaultWebProxy
        if ($null -ne $proxy) {
            $proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        }
    }
    catch {
        Write-Info "Unable to set default proxy credentials: $($_.Exception.Message)"
    }
}

function Invoke-DownloadFile {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile,
        [int]$MaxAttempts = 3,
        [int]$RetryDelaySeconds = 5
    )

    $lastError = $null

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            if (Test-Path -Path $OutFile) {
                Remove-Item -Path $OutFile -Force -ErrorAction SilentlyContinue
            }

            Write-Info "Download attempt $attempt/$MaxAttempts via Invoke-WebRequest"
            Invoke-WebRequest -Uri $Uri -OutFile $OutFile -UseBasicParsing -ErrorAction Stop

            if (-not (Test-Path -Path $OutFile)) {
                throw 'Download completed but output file does not exist.'
            }

            if ((Get-Item -Path $OutFile).Length -le 0) {
                throw 'Download completed but output file is empty.'
            }

            return
        }
        catch {
            $lastError = $_
            Write-Info "Invoke-WebRequest attempt $attempt failed: $($_.Exception.Message)"

            try {
                if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
                    if (Test-Path -Path $OutFile) {
                        Remove-Item -Path $OutFile -Force -ErrorAction SilentlyContinue
                    }

                    Write-Info "Download attempt $attempt/$MaxAttempts via Start-BitsTransfer"
                    Start-BitsTransfer -Source $Uri -Destination $OutFile -ErrorAction Stop

                    if (-not (Test-Path -Path $OutFile)) {
                        throw 'BITS completed but output file does not exist.'
                    }

                    if ((Get-Item -Path $OutFile).Length -le 0) {
                        throw 'BITS completed but output file is empty.'
                    }

                    return
                }
            }
            catch {
                $lastError = $_
                Write-Info "Start-BitsTransfer attempt $attempt failed: $($_.Exception.Message)"
            }

            if ($attempt -lt $MaxAttempts) {
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }

    throw "Failed to download package from '$Uri' after $MaxAttempts attempts. Last error: $($lastError.Exception.Message)"
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
Write-Info "  EnableScheduledRerun: $([bool]$EnableScheduledRerun)"
Write-Info "  ScheduleIntervalDays: $ScheduleIntervalDays"
Write-Info "  ScheduleDelayMinutes: $ScheduleDelayMinutes"
Write-Info "  ScheduleTriggerMode: $ScheduleTriggerMode"
Write-Info "  HasIntuneRemediationsLicense: $([bool]$HasIntuneRemediationsLicense)"
Write-Info "  AlsoRunAfterWindowsUpdate: $([bool]$AlsoRunAfterWindowsUpdate)"
Write-Info "  ScheduleWeekOfMonth: $ScheduleWeekOfMonth"
Write-Info "  ScheduleDayOfWeek: $ScheduleDayOfWeek"
Write-Info "  ScheduleDayOfMonth: $ScheduleDayOfMonth"

New-Item -Path $tempRoot -ItemType Directory -Force | Out-Null
New-Item -Path $extractPath -ItemType Directory -Force | Out-Null

try {
    Set-NetworkDefaults
    Write-Info "Downloading package zip from: $PackageZipUrl"
    Invoke-DownloadFile -Uri $PackageZipUrl -OutFile $zipPath

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

    if ($HasIntuneRemediationsLicense) {
        $comboArgs.Add('-HasIntuneRemediationsLicense')
    }
    elseif ($EnableScheduledRerun) {
        $comboArgs.Add('-EnableScheduledRerun')
        $comboArgs.Add('-ScheduleIntervalDays')
        $comboArgs.Add([string]$ScheduleIntervalDays)
        $comboArgs.Add('-ScheduleDelayMinutes')
        $comboArgs.Add([string]$ScheduleDelayMinutes)
        $comboArgs.Add('-ScheduleTriggerMode')
        $comboArgs.Add($ScheduleTriggerMode)
        if ($AlsoRunAfterWindowsUpdate) {
            $comboArgs.Add('-AlsoRunAfterWindowsUpdate')
        }
        if ($ScheduleTriggerMode -eq 'MonthlyFixedDay') {
            $comboArgs.Add('-ScheduleDayOfMonth')
            $comboArgs.Add([string]$ScheduleDayOfMonth)
        }
        if ($ScheduleTriggerMode -eq 'MonthlyDayOfWeek') {
            $comboArgs.Add('-ScheduleWeekOfMonth')
            $comboArgs.Add($ScheduleWeekOfMonth)
            $comboArgs.Add('-ScheduleDayOfWeek')
            $comboArgs.Add($ScheduleDayOfWeek)
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
