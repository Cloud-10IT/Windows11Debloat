[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string]$Vendor = 'Dell',

    [Parameter(Mandatory = $false)]
    [switch]$AutoDetect,

    [Parameter(Mandatory = $false)]
    [string]$ProfilesPath = (Join-Path -Path $PSScriptRoot -ChildPath 'vendor-profiles.json'),

    [Parameter(Mandatory = $false)]
    [switch]$IncludeCommon,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-Status {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warn', 'Error', 'Success')]
        [string]$Level = 'Info'
    )

    switch ($Level) {
        'Info'    { Write-Host "[INFO] $Message" -ForegroundColor Cyan }
        'Warn'    { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
        'Error'   { Write-Host "[ERROR] $Message" -ForegroundColor Red }
        'Success' { Write-Host "[OK] $Message" -ForegroundColor Green }
    }
}

function Get-VendorProfiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Vendor profile file not found: $Path"
    }

    try {
        $raw = Get-Content -Path $Path -Raw -ErrorAction Stop
        $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Failed to parse vendor profile file '$Path'. $($_.Exception.Message)"
    }

    if (-not $parsed) {
        throw "Vendor profile file '$Path' is empty or invalid."
    }

    return $parsed
}

function Get-StringListProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property -or $null -eq $property.Value) {
        return @()
    }

    if ($property.Value -is [System.Array]) {
        return [string[]]$property.Value
    }

    return @([string]$property.Value)
}

function Get-ArrayProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName
    )

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property -or $null -eq $property.Value) {
        return @()
    }

    if ($property.Value -is [System.Array]) {
        return $property.Value
    }

    return @($property.Value)
}

function Get-BoolProperty {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$PropertyName,

        [Parameter(Mandatory = $false)]
        [bool]$DefaultValue = $false
    )

    $property = $InputObject.PSObject.Properties[$PropertyName]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $DefaultValue
    }

    try {
        return [bool]$property.Value
    }
    catch {
        return $DefaultValue
    }
}

function Get-SystemManufacturer {
    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs -and -not [string]::IsNullOrWhiteSpace($cs.Manufacturer)) {
            return [string]$cs.Manufacturer
        }
    }
    catch {
        Write-Status -Message "Get-CimInstance failed for manufacturer detection. $($_.Exception.Message)" -Level 'Warn'
    }

    try {
        $csLegacy = Get-WmiObject -Class Win32_ComputerSystem -ErrorAction Stop
        if ($csLegacy -and -not [string]::IsNullOrWhiteSpace($csLegacy.Manufacturer)) {
            return [string]$csLegacy.Manufacturer
        }
    }
    catch {
        Write-Status -Message "Get-WmiObject failed for manufacturer detection. $($_.Exception.Message)" -Level 'Warn'
    }

    return $null
}

function Resolve-VendorFromManufacturer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Manufacturer,

        [Parameter(Mandatory = $true)]
        [string[]]$AvailableVendors,

        [Parameter(Mandatory = $false)]
        [object]$ManufacturerAliases
    )

    $normalizedManufacturer = $Manufacturer.Trim().ToLowerInvariant()

    if ($null -ne $ManufacturerAliases) {
        foreach ($vendor in $ManufacturerAliases.PSObject.Properties.Name) {
            $aliasList = Get-StringListProperty -InputObject $ManufacturerAliases -PropertyName $vendor

            foreach ($alias in $aliasList) {
                if ([string]::IsNullOrWhiteSpace($alias)) {
                    continue
                }

                if ($normalizedManufacturer -like "*$($alias.Trim().ToLowerInvariant())*") {
                    if ($AvailableVendors -contains $vendor) {
                        return $vendor
                    }
                }
            }
        }
    }

    foreach ($vendor in $AvailableVendors) {
        foreach ($alias in @($vendor)) {
            if ([string]::IsNullOrWhiteSpace($alias)) {
                continue
            }

            if ($normalizedManufacturer -like "*$($alias.ToLowerInvariant())*") {
                if ($AvailableVendors -contains $vendor) {
                    return $vendor
                }
            }
        }
    }

    return $null
}

function Remove-AppxByName {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Names
    )

    foreach ($name in $Names) {
        try {
            $packages = Get-AppxPackage -AllUsers -Name $name -ErrorAction SilentlyContinue
            if (-not $packages) {
                Write-Status -Message "Appx package not found: $name" -Level 'Warn'
                continue
            }

            foreach ($pkg in $packages) {
                if ($PSCmdlet.ShouldProcess($pkg.PackageFullName, 'Remove-AppxPackage -AllUsers')) {
                    Remove-AppxPackage -Package $pkg.PackageFullName -AllUsers -ErrorAction Stop
                }
            }

            $provisioned = Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like "$name*" }
            foreach ($prov in $provisioned) {
                if ($PSCmdlet.ShouldProcess($prov.PackageName, 'Remove-AppxProvisionedPackage -Online')) {
                    Remove-AppxProvisionedPackage -Online -PackageName $prov.PackageName -ErrorAction Stop | Out-Null
                }
            }

            Write-Status -Message "Removed Appx package pattern: $name" -Level 'Success'
        }
        catch {
            Write-Status -Message "Failed to remove Appx package '$name'. $($_.Exception.Message)" -Level 'Warn'
        }
    }
}

function Uninstall-WingetPackages {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Ids
    )

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Status -Message 'winget is not available. Skipping winget package removals.' -Level 'Warn'
        return
    }

    foreach ($id in $Ids) {
        try {
            if ($PSCmdlet.ShouldProcess($id, 'winget uninstall')) {
                winget uninstall --id $id --silent --accept-source-agreements | Out-Null
            }
            Write-Status -Message "Attempted winget uninstall: $id" -Level 'Info'
        }
        catch {
            Write-Status -Message "Failed winget uninstall '$id'. $($_.Exception.Message)" -Level 'Warn'
        }
    }
}

function Disable-ServicesSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ServiceNames
    )

    foreach ($serviceName in $ServiceNames) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if (-not $service) {
            Write-Status -Message "Service not found: $serviceName" -Level 'Warn'
            continue
        }

        try {
            if ($service.Status -eq 'Running' -and $PSCmdlet.ShouldProcess($serviceName, 'Stop-Service')) {
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
            }

            if ($PSCmdlet.ShouldProcess($serviceName, 'Set-Service StartupType Disabled')) {
                Set-Service -Name $serviceName -StartupType Disabled -ErrorAction Stop
            }

            Write-Status -Message "Disabled service: $serviceName" -Level 'Success'
        }
        catch {
            Write-Status -Message "Failed to disable service '$serviceName'. $($_.Exception.Message)" -Level 'Warn'
        }
    }
}

function Set-HibernationState {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Enabled
    )

    $targetState = if ($Enabled) { 'on' } else { 'off' }

    try {
        if ($PSCmdlet.ShouldProcess("Hibernate ($targetState)", "powercfg /hibernate $targetState")) {
            powercfg /hibernate $targetState | Out-Null
        }

        if ($Enabled) {
            Write-Status -Message 'Hibernation enabled.' -Level 'Success'
        }
        else {
            Write-Status -Message 'Hibernation disabled.' -Level 'Success'
        }
    }
    catch {
        Write-Status -Message "Failed to set hibernation state to '$targetState'. $($_.Exception.Message)" -Level 'Warn'
    }
}

function Invoke-ConditionalCopilotRemoval {
    $m365Key = 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration'
    $m365Present = $false

    if (Test-Path -Path $m365Key) {
        try {
            $productIds = (Get-ItemProperty -Path $m365Key -ErrorAction Stop).ProductReleaseIds
            if ($productIds -match 'O365|Microsoft365|M365') {
                $m365Present = $true
            }
        }
        catch {
            Write-Status -Message "Failed to read Office ClickToRun registry. $($_.Exception.Message)" -Level 'Warn'
        }
    }

    if (-not $m365Present) {
        Write-Status -Message 'Microsoft 365 not detected. Skipping conditional Copilot removal.' -Level 'Info'
        return
    }

    Write-Status -Message 'Microsoft 365 detected. Removing standalone Windows Copilot app.' -Level 'Info'
    Remove-AppxByName -Names @('Microsoft.Windows.Copilot', 'Microsoft.Copilot')
}

function Invoke-OneDriveCorpCleanup {
    $odfbPresent = $false
    $odfbAccountsKey = 'HKCU:\Software\Microsoft\OneDrive\Accounts'

    if (Test-Path -Path $odfbAccountsKey) {
        try {
            $subkeys = Get-ChildItem -Path $odfbAccountsKey -ErrorAction Stop
            foreach ($key in $subkeys) {
                if ($key.PSChildName -like 'Business*') {
                    $odfbPresent = $true
                    break
                }
            }
        }
        catch {
            Write-Status -Message "Failed to read OneDrive Accounts registry. $($_.Exception.Message)" -Level 'Warn'
        }
    }

    if (-not $odfbPresent) {
        Write-Status -Message 'OneDrive for Business not detected. Skipping consumer OneDrive removal.' -Level 'Info'
        return
    }

    Write-Status -Message 'OneDrive for Business detected. Removing consumer OneDrive.' -Level 'Info'

    $oneDriveSetup = Join-Path -Path $env:SystemRoot -ChildPath 'SysWOW64\OneDriveSetup.exe'
    if (-not (Test-Path -Path $oneDriveSetup)) {
        $oneDriveSetup = Join-Path -Path $env:SystemRoot -ChildPath 'System32\OneDriveSetup.exe'
    }

    if (Test-Path -Path $oneDriveSetup) {
        try {
            if ($PSCmdlet.ShouldProcess('Consumer OneDrive', "$oneDriveSetup /uninstall")) {
                & $oneDriveSetup /uninstall | Out-Null
            }
            Write-Status -Message 'Consumer OneDrive uninstall initiated via OneDriveSetup.exe.' -Level 'Success'
        }
        catch {
            Write-Status -Message "OneDriveSetup.exe uninstall failed. $($_.Exception.Message)" -Level 'Warn'
        }
    }
    elseif (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            if ($PSCmdlet.ShouldProcess('Microsoft.OneDrive', 'winget uninstall')) {
                winget uninstall --id 'Microsoft.OneDrive' --silent --accept-source-agreements | Out-Null
            }
            Write-Status -Message 'Consumer OneDrive winget uninstall initiated.' -Level 'Success'
        }
        catch {
            Write-Status -Message "winget uninstall of OneDrive failed. $($_.Exception.Message)" -Level 'Warn'
        }
    }
    else {
        Write-Status -Message 'OneDriveSetup.exe not found and winget unavailable. Manual OneDrive removal required.' -Level 'Warn'
    }
}

function Disable-ScheduledTasksSafe {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$TaskPaths
    )

    foreach ($taskPath in $TaskPaths) {
        $normalized = $taskPath.TrimStart('\\')
        $parts = $normalized -split '\\'

        if ($parts.Count -lt 2) {
            Write-Status -Message "Invalid task path format: $taskPath" -Level 'Warn'
            continue
        }

        $taskName = $parts[-1]
        $taskFolder = '\\' + (($parts[0..($parts.Count - 2)] -join '\\')) + '\\'

        try {
            $task = Get-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -ErrorAction SilentlyContinue
            if (-not $task) {
                Write-Status -Message "Scheduled task not found: $taskPath" -Level 'Warn'
                continue
            }

            if ($PSCmdlet.ShouldProcess($taskPath, 'Disable-ScheduledTask')) {
                Disable-ScheduledTask -TaskPath $taskFolder -TaskName $taskName -ErrorAction Stop | Out-Null
            }

            Write-Status -Message "Disabled scheduled task: $taskPath" -Level 'Success'
        }
        catch {
            Write-Status -Message "Failed to disable task '$taskPath'. $($_.Exception.Message)" -Level 'Warn'
        }
    }
}

function Set-RegistryTweaks {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Tweaks
    )

    foreach ($tweak in $Tweaks) {
        try {
            $path = $tweak.Path
            $name = $tweak.Name
            $type = $tweak.Type
            $value = $tweak.Value

            if (-not (Test-Path -Path $path)) {
                if ($PSCmdlet.ShouldProcess($path, 'New-Item')) {
                    New-Item -Path $path -Force | Out-Null
                }
            }

            if ($PSCmdlet.ShouldProcess("$path\\$name", 'Set-ItemProperty')) {
                New-ItemProperty -Path $path -Name $name -Value $value -PropertyType $type -Force | Out-Null
            }

            Write-Status -Message "Applied registry tweak: $path\\$name" -Level 'Success'
        }
        catch {
            Write-Status -Message "Failed registry tweak '$($tweak.Path)\\$($tweak.Name)'. $($_.Exception.Message)" -Level 'Warn'
        }
    }
}

if (-not (Test-IsAdministrator)) {
    throw 'This script must be run as Administrator.'
}

$profiles = Get-VendorProfiles -Path $ProfilesPath

$metadataKeys = @('Common', 'ManufacturerAliases')

$availableVendors = @(
    $profiles.PSObject.Properties.Name | Where-Object { $metadataKeys -notcontains $_ }
)

$manufacturerAliases = $profiles.PSObject.Properties['ManufacturerAliases'].Value

if ($availableVendors.Count -eq 0) {
    throw "No vendor profiles found in '$ProfilesPath'."
}

if ($AutoDetect) {
    $manufacturer = Get-SystemManufacturer
    if ([string]::IsNullOrWhiteSpace($manufacturer)) {
        throw "AutoDetect could not determine system manufacturer. Use -Vendor with one of: $($availableVendors -join ', ')"
    }

    $detectedVendor = Resolve-VendorFromManufacturer -Manufacturer $manufacturer -AvailableVendors $availableVendors -ManufacturerAliases $manufacturerAliases
    if ([string]::IsNullOrWhiteSpace($detectedVendor)) {
        throw "AutoDetect could not map manufacturer '$manufacturer' to a vendor profile. Available vendors: $($availableVendors -join ', ')"
    }

    $Vendor = $detectedVendor
    Write-Status -Message "AutoDetect selected vendor '$Vendor' from manufacturer '$manufacturer'." -Level 'Info'
}

if ($availableVendors -notcontains $Vendor) {
    $vendorList = $availableVendors -join ', '
    throw "No profile found for vendor '$Vendor'. Available vendors: $vendorList"
}

$selectedProfile = $profiles.PSObject.Properties[$Vendor].Value

if (-not $selectedProfile) {
    throw "No profile found for vendor '$Vendor'."
}

if ($DryRun) {
    $WhatIfPreference = $true
    Write-Status -Message 'Dry run enabled. No changes will be applied.' -Level 'Warn'
}

Write-Status -Message "Starting debloat profile for vendor: $Vendor" -Level 'Info'

if ($IncludeCommon) {
    $commonProfile = $profiles.PSObject.Properties['Common'].Value

    if ($null -eq $commonProfile) {
        Write-Status -Message 'Common profile not found in vendor profile file. Skipping common actions.' -Level 'Warn'
    }
    else {
        Write-Status -Message 'Applying common debloat profile.' -Level 'Info'

        Remove-AppxByName -Names (Get-StringListProperty -InputObject $commonProfile -PropertyName 'AppxPackages')
        Disable-ServicesSafe -ServiceNames (Get-StringListProperty -InputObject $commonProfile -PropertyName 'DisableServices')
        Disable-ScheduledTasksSafe -TaskPaths (Get-StringListProperty -InputObject $commonProfile -PropertyName 'DisableScheduledTasks')
        Set-RegistryTweaks -Tweaks (Get-ArrayProperty -InputObject $commonProfile -PropertyName 'RegistryTweaks')

        if (Get-BoolProperty -InputObject $commonProfile -PropertyName 'DisableHibernation' -DefaultValue $false) {
            Set-HibernationState -Enabled $false
        }

        if (Get-BoolProperty -InputObject $commonProfile -PropertyName 'RemoveCopilotIfM365Present' -DefaultValue $false) {
            Invoke-ConditionalCopilotRemoval
        }

        if (Get-BoolProperty -InputObject $commonProfile -PropertyName 'RemoveConsumerOneDriveIfBusinessPresent' -DefaultValue $false) {
            Invoke-OneDriveCorpCleanup
        }
    }
}

Remove-AppxByName -Names (Get-StringListProperty -InputObject $selectedProfile -PropertyName 'AppxPackages')
Uninstall-WingetPackages -Ids (Get-StringListProperty -InputObject $selectedProfile -PropertyName 'WingetPackages')
Disable-ServicesSafe -ServiceNames (Get-StringListProperty -InputObject $selectedProfile -PropertyName 'Services')
Disable-ScheduledTasksSafe -TaskPaths (Get-StringListProperty -InputObject $selectedProfile -PropertyName 'ScheduledTasks')

Write-Status -Message 'Debloat routine complete. A restart is recommended.' -Level 'Success'