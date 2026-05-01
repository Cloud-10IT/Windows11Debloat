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
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [switch]$IntuneMode,

    [Parameter(Mandatory = $false)]
    [switch]$HelpdeskMode,

    [Parameter(Mandatory = $false)]
    [ValidateSet('All', 'Device', 'User')]
    [string]$CleanupScope = 'All',

    [Parameter(Mandatory = $false)]
    [string]$MarkerRegistryPath = 'HKLM:\SOFTWARE\Windows11Debloat',

    [Parameter(Mandatory = $false)]
    [string]$LogBasePath = 'C:\Logs',

    [Parameter(Mandatory = $false)]
    [string]$ScriptCacheBasePath = 'C:\'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:BoundParameters = @{} + $PSBoundParameters
$script:TranscriptStarted = $false
$script:WarningCount = 0
$script:ErrorCount = 0
$script:ExitCode = 0
$script:SkipMarkerWrite = $false
$script:RunContext = 'Unknown'
$script:RunMode = 'Standard'
$script:DevicePhaseStatus = 'Pending'
$script:UserPhaseStatus = 'Pending'
$script:ResolvedVendor = $Vendor
$script:ResolvedCleanupScope = $CleanupScope
$script:ExitCodes = @{
    Success = 0
    ElevationRequired = 10
    InvalidConfiguration = 11
    DetectionFailed = 12
    RuntimeFailure = 20
}

function Convert-BoundParametersToArgumentList {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$BoundParameters,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    $argumentList = [System.Collections.Generic.List[string]]::new()
    $argumentList.Add('-NoProfile')
    $argumentList.Add('-ExecutionPolicy')
    $argumentList.Add('Bypass')
    $argumentList.Add('-File')
    $argumentList.Add($ScriptPath)

    foreach ($entry in $BoundParameters.GetEnumerator()) {
        if ($entry.Value -is [switch]) {
            if ($entry.Value.IsPresent) {
                $argumentList.Add("-$($entry.Key)")
            }
            continue
        }

        if ($entry.Value -is [bool]) {
            if ($entry.Value) {
                $argumentList.Add("-$($entry.Key)")
            }
            continue
        }

        if ($null -ne $entry.Value) {
            $argumentList.Add("-$($entry.Key)")
            $argumentList.Add([string]$entry.Value)
        }
    }

    return $argumentList.ToArray()
}

function Start-ElevatedSelf {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$BoundParameters,

        [Parameter(Mandatory = $true)]
        [string]$ScriptPath
    )

    $hostCommand = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
        'pwsh.exe'
    }
    elseif (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
        'powershell.exe'
    }
    else {
        throw 'Unable to find pwsh.exe or powershell.exe for elevation.'
    }

    $argumentList = Convert-BoundParametersToArgumentList -BoundParameters $BoundParameters -ScriptPath $ScriptPath
    Start-Process -FilePath $hostCommand -ArgumentList $argumentList -Verb RunAs | Out-Null
}

function Start-RunTranscript {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModeName,

        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $logRoot = Get-LogRootPath -BasePath $BasePath
    if (-not (Test-Path -Path $logRoot)) {
        New-Item -Path $logRoot -ItemType Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $safeModeName = ($ModeName -replace '[^a-zA-Z0-9_-]', '-')
    $logPath = Join-Path -Path $logRoot -ChildPath "$safeModeName-$timestamp.log"

    Start-Transcript -Path $logPath -Force | Out-Null
    $script:TranscriptStarted = $true
    Write-Status -Message "Transcript logging to: $logPath" -Level 'Info'
}

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-LogRootPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath
    )

    $domainName = $null

    try {
        $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($computerSystem.PartOfDomain -and -not [string]::IsNullOrWhiteSpace($computerSystem.Domain)) {
            $domainName = [string]$computerSystem.Domain
        }
    }
    catch {
    }

    if ([string]::IsNullOrWhiteSpace($domainName) -and -not [string]::IsNullOrWhiteSpace($env:USERDOMAIN)) {
        $domainName = $env:USERDOMAIN
    }

    if ([string]::IsNullOrWhiteSpace($domainName) -or $domainName -eq $env:COMPUTERNAME -or $domainName -eq 'WORKGROUP') {
        $domainName = 'Default'
    }

    $safeDomainName = $domainName -replace '[\\/:*?"<>|]', '-'
    return (Join-Path -Path $BasePath -ChildPath $safeDomainName)
}

function Get-DomainScopedPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $false)]
        [string]$ChildPath = ''
    )

    $domainRoot = Get-LogRootPath -BasePath $BasePath
    if ([string]::IsNullOrWhiteSpace($ChildPath)) {
        return $domainRoot
    }

    return (Join-Path -Path $domainRoot -ChildPath $ChildPath)
}

function Test-IsSystemContext {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    return $currentIdentity.User.Value -eq 'S-1-5-18'
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
        'Warn' { $script:WarningCount++ }
        'Error' { $script:ErrorCount++ }
    }

    switch ($Level) {
        'Info'    { Write-Host "[INFO] $Message" -ForegroundColor Cyan }
        'Warn'    { Write-Host "[WARN] $Message" -ForegroundColor Yellow }
        'Error'   { Write-Host "[ERROR] $Message" -ForegroundColor Red }
        'Success' { Write-Host "[OK] $Message" -ForegroundColor Green }
    }
}

function Copy-HelpdeskArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,

        [Parameter(Mandatory = $true)]
        [string]$DestinationRoot
    )

    $artifactNames = @(
        'Windows11Debloat.ps1',
        'vendor-profiles.json',
        'Run-Windows11Debloat-Helpdesk.cmd',
        'README.md'
    )

    if (-not (Test-Path -Path $DestinationRoot)) {
        New-Item -Path $DestinationRoot -ItemType Directory -Force | Out-Null
    }

    foreach ($artifactName in $artifactNames) {
        $sourcePath = Join-Path -Path $SourceRoot -ChildPath $artifactName
        if (-not (Test-Path -Path $sourcePath)) {
            Write-Status -Message "Staging skipped for missing artifact: $sourcePath" -Level 'Warn'
            continue
        }

        $destinationPath = Join-Path -Path $DestinationRoot -ChildPath $artifactName
        Copy-Item -Path $sourcePath -Destination $destinationPath -Force
    }

    Write-Status -Message "Staged helpdesk artifacts to: $DestinationRoot" -Level 'Success'
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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Ids
    )

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Status -Message 'winget is not available. Skipping winget package removals.' -Level 'Warn'
        if ($script:IsSystemContext) {
            Write-Status -Message 'This is common in Intune/SYSTEM context on a new machine. Appx removals can still proceed, but winget-managed removals may need a user-context pass later.' -Level 'Info'
        }
        return
    }

    foreach ($id in $Ids) {
        try {
            $removed = $false

            if ($PSCmdlet.ShouldProcess($id, 'winget uninstall by id')) {
                winget uninstall --id $id --exact --silent --accept-source-agreements | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $removed = $true
                }
            }

            if (-not $removed -and $PSCmdlet.ShouldProcess($id, 'winget uninstall by name')) {
                winget uninstall --name $id --exact --silent --accept-source-agreements | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    $removed = $true
                }
            }

            if ($removed) {
                Write-Status -Message "Removed winget package: $id" -Level 'Success'
            }
            else {
                Write-Status -Message "winget package not found or not removed: $id" -Level 'Warn'
            }
        }
        catch {
            Write-Status -Message "Failed winget uninstall '$id'. $($_.Exception.Message)" -Level 'Warn'
        }
    }
}

function Disable-ServicesSafe {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
    Uninstall-WingetPackages -Ids @('Copilot')
}

function Invoke-OneDriveCorpCleanup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    $odfbPresent = $false
    $oneDriveAccountSearchRoots = @(
        'HKCU:\Software\Microsoft\OneDrive\Accounts',
        'Registry::HKEY_USERS\*\Software\Microsoft\OneDrive\Accounts\*'
    )

    foreach ($accountPath in $oneDriveAccountSearchRoots) {
        try {
            $matchingKeys = Get-Item -Path $accountPath -ErrorAction SilentlyContinue
            foreach ($key in $matchingKeys) {
                if ($key.PSChildName -like 'Business*') {
                    $odfbPresent = $true
                    break
                }
            }
        }
        catch {
            Write-Status -Message "Failed to read OneDrive Accounts registry from '$accountPath'. $($_.Exception.Message)" -Level 'Warn'
        }

        if ($odfbPresent) {
            break
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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
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

function Write-DetectionMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [int]$ExitCode,

        [Parameter(Mandatory = $true)]
        [string]$VendorName,

        [Parameter(Mandatory = $true)]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$RunMode,

        [Parameter(Mandatory = $true)]
        [string]$RunContext
    )

    try {
        if (-not (Test-Path -Path $Path)) {
            New-Item -Path $Path -Force | Out-Null
        }

        $values = @(
            @{ Name = 'LastRunUtc'; Value = (Get-Date).ToUniversalTime().ToString('o'); Type = 'String' },
            @{ Name = 'LastRunStatus'; Value = $Status; Type = 'String' },
            @{ Name = 'LastExitCode'; Value = $ExitCode; Type = 'DWord' },
            @{ Name = 'LastVendor'; Value = $VendorName; Type = 'String' },
            @{ Name = 'CleanupScope'; Value = $Scope; Type = 'String' },
            @{ Name = 'RunMode'; Value = $RunMode; Type = 'String' },
            @{ Name = 'RunContext'; Value = $RunContext; Type = 'String' },
            @{ Name = 'WarningCount'; Value = $script:WarningCount; Type = 'DWord' },
            @{ Name = 'ErrorCount'; Value = $script:ErrorCount; Type = 'DWord' },
            @{ Name = 'DevicePhaseStatus'; Value = $script:DevicePhaseStatus; Type = 'String' },
            @{ Name = 'UserPhaseStatus'; Value = $script:UserPhaseStatus; Type = 'String' },
            @{ Name = 'DryRun'; Value = [int]$DryRun.IsPresent; Type = 'DWord' }
        )

        foreach ($value in $values) {
            New-ItemProperty -Path $Path -Name $value.Name -Value $value.Value -PropertyType $value.Type -Force | Out-Null
        }

        Write-Status -Message "Updated marker registry key: $Path" -Level 'Info'
    }
    catch {
        Write-Status -Message "Failed to update marker registry key '$Path'. $($_.Exception.Message)" -Level 'Warn'
    }
}

function Resolve-ExitCode {
    param(
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception
    )

    $message = $Exception.Message

    if ($Exception -is [System.UnauthorizedAccessException] -or $message -like '*must be run as Administrator*') {
        return $script:ExitCodes.ElevationRequired
    }

    if ($message -like 'Vendor profile file not found:*' -or
        $message -like 'Failed to parse vendor profile file*' -or
        $message -like 'No vendor profiles found*' -or
        $message -like 'No profile found for vendor*') {
        return $script:ExitCodes.InvalidConfiguration
    }

    if ($message -like 'AutoDetect could not*') {
        return $script:ExitCodes.DetectionFailed
    }

    return $script:ExitCodes.RuntimeFailure
}

function Invoke-DeviceContextCleanup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $false)]
        [object]$CommonProfile,

        [Parameter(Mandatory = $true)]
        [object]$SelectedProfile,

        [Parameter(Mandatory = $true)]
        [bool]$IncludeCommonProfile
    )

    Write-Status -Message 'Starting device-context cleanup phase.' -Level 'Info'

    if ($IncludeCommonProfile -and $null -ne $CommonProfile) {
        Remove-AppxByName -Names (Get-StringListProperty -InputObject $CommonProfile -PropertyName 'AppxPackages')
        Disable-ServicesSafe -ServiceNames (Get-StringListProperty -InputObject $CommonProfile -PropertyName 'DisableServices')
        Disable-ScheduledTasksSafe -TaskPaths (Get-StringListProperty -InputObject $CommonProfile -PropertyName 'DisableScheduledTasks')
        Set-RegistryTweaks -Tweaks (Get-ArrayProperty -InputObject $CommonProfile -PropertyName 'RegistryTweaks')

        if (Get-BoolProperty -InputObject $CommonProfile -PropertyName 'DisableHibernation' -DefaultValue $false) {
            Set-HibernationState -Enabled $false
        }
    }

    Remove-AppxByName -Names (Get-StringListProperty -InputObject $SelectedProfile -PropertyName 'AppxPackages')
    Disable-ServicesSafe -ServiceNames (Get-StringListProperty -InputObject $SelectedProfile -PropertyName 'Services')
    Disable-ScheduledTasksSafe -TaskPaths (Get-StringListProperty -InputObject $SelectedProfile -PropertyName 'ScheduledTasks')

    $script:DevicePhaseStatus = 'Completed'
    Write-Status -Message 'Completed device-context cleanup phase.' -Level 'Success'
}

function Invoke-UserContextCleanup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory = $false)]
        [object]$CommonProfile,

        [Parameter(Mandatory = $true)]
        [object]$SelectedProfile,

        [Parameter(Mandatory = $true)]
        [bool]$IncludeCommonProfile
    )

    Write-Status -Message 'Starting user-context cleanup phase.' -Level 'Info'

    if ($script:IsSystemContext) {
        Write-Status -Message 'Running in SYSTEM context. User-context cleanup may be limited until a user signs in.' -Level 'Warn'
    }

    if ($IncludeCommonProfile -and $null -ne $CommonProfile) {
        Uninstall-WingetPackages -Ids (Get-StringListProperty -InputObject $CommonProfile -PropertyName 'WingetPackages')

        if (Get-BoolProperty -InputObject $CommonProfile -PropertyName 'RemoveCopilotIfM365Present' -DefaultValue $false) {
            Invoke-ConditionalCopilotRemoval
        }

        if (Get-BoolProperty -InputObject $CommonProfile -PropertyName 'RemoveConsumerOneDriveIfBusinessPresent' -DefaultValue $false) {
            Invoke-OneDriveCorpCleanup
        }
    }

    Uninstall-WingetPackages -Ids (Get-StringListProperty -InputObject $SelectedProfile -PropertyName 'WingetPackages')

    $script:UserPhaseStatus = 'Completed'
    Write-Status -Message 'Completed user-context cleanup phase.' -Level 'Success'
}

function Invoke-Main {
    if (-not (Test-IsAdministrator)) {
        if ($HelpdeskMode -and -not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
            Write-Host '[INFO] Helpdesk mode requested without elevation. Relaunching as Administrator...'
            $script:SkipMarkerWrite = $true
            Start-ElevatedSelf -BoundParameters $script:BoundParameters -ScriptPath $PSCommandPath
            return
        }

        throw 'This script must be run as Administrator.'
    }

    $isSystemContext = Test-IsSystemContext
    $script:IsSystemContext = $isSystemContext
    $script:RunContext = if ($isSystemContext) { 'System' } else { 'UserAdmin' }

    if ($IntuneMode) {
        $script:RunMode = 'Intune'
        $ConfirmPreference = 'None'
        $ProgressPreference = 'SilentlyContinue'
        if (-not $script:BoundParameters.ContainsKey('CleanupScope')) {
            $CleanupScope = 'Device'
        }
        Write-Status -Message 'Intune mode enabled. Running non-interactively for device provisioning.' -Level 'Info'

        if (-not $isSystemContext) {
            Write-Status -Message 'Intune mode is intended for SYSTEM context, but the current session is not running as SYSTEM.' -Level 'Warn'
        }

        if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
            $scriptCachePath = Get-DomainScopedPath -BasePath $ScriptCacheBasePath -ChildPath 'Scripts'
            Copy-HelpdeskArtifacts -SourceRoot $PSScriptRoot -DestinationRoot $scriptCachePath
        }
    }
    elseif ($HelpdeskMode) {
        $script:RunMode = 'Helpdesk'
        if (-not $script:BoundParameters.ContainsKey('AutoDetect') -and -not $script:BoundParameters.ContainsKey('Vendor')) {
            $AutoDetect = $true
        }

        if (-not $script:BoundParameters.ContainsKey('IncludeCommon')) {
            $IncludeCommon = $true
        }

        $ConfirmPreference = 'None'
        Write-Status -Message 'Helpdesk mode enabled. Defaulting to quick standalone remediation behavior.' -Level 'Info'
    }

    Start-RunTranscript -ModeName $script:RunMode -BasePath $LogBasePath

    if ($isSystemContext) {
        Write-Status -Message 'Detected SYSTEM context. Per-user cleanup may be limited on a brand-new machine until a user signs in.' -Level 'Info'
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

    $script:ResolvedVendor = $Vendor
    $script:ResolvedCleanupScope = $CleanupScope

    $selectedProfile = $profiles.PSObject.Properties[$Vendor].Value

    if (-not $selectedProfile) {
        throw "No profile found for vendor '$Vendor'."
    }

    if ($DryRun) {
        $WhatIfPreference = $true
        Write-Status -Message 'Dry run enabled. No changes will be applied.' -Level 'Warn'
    }

    Write-Status -Message "Starting debloat profile for vendor: $Vendor" -Level 'Info'

    $commonProfile = $null
    if ($IncludeCommon) {
        $commonProfile = $profiles.PSObject.Properties['Common'].Value

        if ($null -eq $commonProfile) {
            Write-Status -Message 'Common profile not found in vendor profile file. Skipping common actions.' -Level 'Warn'
        }
        else {
            Write-Status -Message 'Applying common debloat profile.' -Level 'Info'
        }
    }

    switch ($CleanupScope) {
        'Device' {
            $script:UserPhaseStatus = 'Skipped'
            Invoke-DeviceContextCleanup -CommonProfile $commonProfile -SelectedProfile $selectedProfile -IncludeCommonProfile $IncludeCommon
        }
        'User' {
            $script:DevicePhaseStatus = 'Skipped'
            Invoke-UserContextCleanup -CommonProfile $commonProfile -SelectedProfile $selectedProfile -IncludeCommonProfile $IncludeCommon
        }
        default {
            Invoke-DeviceContextCleanup -CommonProfile $commonProfile -SelectedProfile $selectedProfile -IncludeCommonProfile $IncludeCommon
            Invoke-UserContextCleanup -CommonProfile $commonProfile -SelectedProfile $selectedProfile -IncludeCommonProfile $IncludeCommon
        }
    }

    Write-Status -Message 'Debloat routine complete. A restart is recommended.' -Level 'Success'
}

try {
    Invoke-Main
    $script:ExitCode = $script:ExitCodes.Success
}
catch {
    Write-Status -Message $_.Exception.Message -Level 'Error'
    $script:ExitCode = Resolve-ExitCode -Exception $_.Exception
}
finally {
    if (-not $script:SkipMarkerWrite) {
        $runStatus = if ($script:ExitCode -eq $script:ExitCodes.Success) { 'Success' } else { 'Failed' }
        Write-DetectionMarker -Path $MarkerRegistryPath -Status $runStatus -ExitCode $script:ExitCode -VendorName $script:ResolvedVendor -Scope $script:ResolvedCleanupScope -RunMode $script:RunMode -RunContext $script:RunContext
    }

    if ($script:TranscriptStarted) {
        try {
            Stop-Transcript | Out-Null
        }
        catch {
        }
    }

    exit $script:ExitCode
}