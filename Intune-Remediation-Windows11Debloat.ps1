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
$HasIntuneRemediationsLicense = $IntuneRemediationDefaults.HasIntuneRemediationsLicense

if ([string]::IsNullOrWhiteSpace($PackageZipUrl) -or $PackageZipUrl -like 'https://your-storage.example.com/*') {
    throw "PackageZipUrl is not configured. Edit Intune-Remediation-Windows11Debloat.ps1 before uploading to Intune."
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
