[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Vendor,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeDeployTest,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Join-ArgList {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    return ($Arguments | ForEach-Object {
            if ($_ -match '[\s"]') {
                '"' + ($_ -replace '"', '\"') + '"'
            }
            else {
                $_
            }
        }) -join ' '
}

function Invoke-SmokeCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$HostExecutable,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $false)]
        [string[]]$MustContain = @(),

        [Parameter(Mandatory = $false)]
        [string[]]$MustContainAny = @(),

        [Parameter(Mandatory = $false)]
        [int]$ExpectedExitCode = 0
    )

    Write-Host "[TEST] $Name"

    $rawOutput = & $HostExecutable @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($null -eq $exitCode) {
        $exitCode = 0
    }

    $outputText = ($rawOutput | Out-String).TrimEnd()
    $missing = [System.Collections.Generic.List[string]]::new()

    foreach ($needle in $MustContain) {
        if ($outputText -notlike "*$needle*") {
            $missing.Add($needle)
        }
    }

    if ($MustContainAny.Count -gt 0) {
        $matchedAny = $false
        foreach ($candidate in $MustContainAny) {
            if ($outputText -like "*$candidate*") {
                $matchedAny = $true
                break
            }
        }

        if (-not $matchedAny) {
            $missing.Add('One of: ' + ($MustContainAny -join ' | '))
        }
    }

    $passed = ($exitCode -eq $ExpectedExitCode) -and ($missing.Count -eq 0)

    if ($passed) {
        Write-Host "[PASS] $Name"
    }
    else {
        Write-Host "[FAIL] $Name"
    }

    [pscustomobject]@{
        Name = $Name
        Passed = $passed
        Skipped = $false
        ExitCode = $exitCode
        ExpectedExitCode = $ExpectedExitCode
        MissingExpectedOutput = @($missing)
        Command = "$HostExecutable $(Join-ArgList -Arguments $Arguments)"
        Output = $outputText
    }
}

$root = Resolve-RootPath
$hostExe = Resolve-HostExecutable
$isAdmin = Test-IsAdministrator

$outputRoot = if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    Join-Path -Path $root -ChildPath 'TestOutput'
}
else {
    $OutputDirectory
}

if (-not (Test-Path -Path $outputRoot)) {
    New-Item -Path $outputRoot -ItemType Directory -Force | Out-Null
}

$comboPath = Join-Path -Path $root -ChildPath 'Run-Windows11Debloat-Combo.ps1'
$mainPath = Join-Path -Path $root -ChildPath 'Windows11Debloat.ps1'
$ninjaPath = Join-Path -Path $root -ChildPath 'wrappers\NinjaOne-Run-Windows11Debloat.ps1'
$ateraPath = Join-Path -Path $root -ChildPath 'wrappers\Atera-Run-Windows11Debloat.ps1'
$action1Path = Join-Path -Path $root -ChildPath 'wrappers\Action1-Run-Windows11Debloat.ps1'

$requiredFiles = @($comboPath, $mainPath, $ninjaPath, $ateraPath, $action1Path)
foreach ($filePath in $requiredFiles) {
    if (-not (Test-Path -Path $filePath)) {
        throw "Required file not found: $filePath"
    }
}

$vendorArgs = if ([string]::IsNullOrWhiteSpace($Vendor)) {
    @('-AutoDetect')
}
else {
    @('-Vendor', $Vendor)
}

$wrapperVendorArgs = if ([string]::IsNullOrWhiteSpace($Vendor)) {
    @()
}
else {
    @('-Vendor', $Vendor)
}

$results = [System.Collections.Generic.List[object]]::new()

$comboTestArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $comboPath, '-Stage', 'Test', '-CleanupScope', 'Device', '-IncludeCommon') + $vendorArgs
$ninjaTestArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ninjaPath, '-Stage', 'Test', '-CleanupScope', 'User') + $wrapperVendorArgs
$ateraTestArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ateraPath, '-Stage', 'Test', '-CleanupScope', 'User') + $wrapperVendorArgs
$action1TestArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $action1Path, '-Stage', 'Test', '-CleanupScope', 'User') + $wrapperVendorArgs
$whatIfArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $mainPath, '-IncludeCommon', '-CleanupScope', 'Device', '-WhatIf') + $vendorArgs

$results.Add((Invoke-SmokeCase -Name 'Combo Stage Test (Device)' -HostExecutable $hostExe -Arguments $comboTestArgs -MustContain @('Stage: Test', 'Exit code: 0') -MustContainAny @('Dry-run summary:', 'Helpdesk mode requested without elevation.')))

$results.Add((Invoke-SmokeCase -Name 'NinjaOne Wrapper Stage Test (User)' -HostExecutable $hostExe -Arguments $ninjaTestArgs -MustContain @('Running NinjaOne wrapper', 'Stage: Test', 'Exit code: 0') -MustContainAny @('Dry-run summary:', 'Helpdesk mode requested without elevation.')))

$results.Add((Invoke-SmokeCase -Name 'Atera Wrapper Stage Test (User)' -HostExecutable $hostExe -Arguments $ateraTestArgs -MustContain @('Running Atera wrapper', 'Stage: Test', 'Exit code: 0') -MustContainAny @('Dry-run summary:', 'Helpdesk mode requested without elevation.')))

$results.Add((Invoke-SmokeCase -Name 'Action1 Wrapper Stage Test (User)' -HostExecutable $hostExe -Arguments $action1TestArgs -MustContain @('Running Action1 wrapper', 'Stage: Test', 'Exit code: 0') -MustContainAny @('Dry-run summary:', 'Helpdesk mode requested without elevation.')))

if ($isAdmin) {
    $results.Add((Invoke-SmokeCase -Name 'WhatIf Messaging Polish' -HostExecutable $hostExe -Arguments $whatIfArgs -MustContain @('[WhatIf] Would start transcript logging to:', '[WhatIf] Would write pre-change snapshot to:', '[WhatIf] Would update marker registry key:')))
}
else {
    Write-Host '[SKIP] WhatIf Messaging Polish (requires Administrator session)'
    $results.Add([pscustomobject]@{
            Name = 'WhatIf Messaging Polish'
            Passed = $true
            Skipped = $true
            ExitCode = 0
            ExpectedExitCode = 0
            MissingExpectedOutput = @()
            Command = "$hostExe $(Join-ArgList -Arguments $whatIfArgs)"
            Output = 'Skipped because current session is not elevated. Run as Administrator to validate WhatIf marker/snapshot wording.'
        })
}

if ($IncludeDeployTest) {
    $comboDeployArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $comboPath, '-Stage', 'Deploy', '-CleanupScope', 'Device', '-IncludeCommon') + $vendorArgs
    $results.Add((Invoke-SmokeCase -Name 'Combo Stage Deploy (Device)' -HostExecutable $hostExe -Arguments $comboDeployArgs -MustContain @('Stage: Deploy', 'Pre-change snapshot written to:', 'Updated marker registry key:', 'Exit code: 0')))
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$summaryPath = Join-Path -Path $outputRoot -ChildPath "SmokeTest-Summary-$timestamp.log"
$jsonPath = Join-Path -Path $outputRoot -ChildPath "SmokeTest-Summary-$timestamp.json"

$passCount = @($results | Where-Object { $_.Passed -and -not $_.Skipped }).Count
$skipCount = @($results | Where-Object { $_.Skipped }).Count
$failCount = @($results | Where-Object { -not $_.Passed }).Count

$summaryLines = [System.Collections.Generic.List[string]]::new()
$summaryLines.Add('==============================')
$summaryLines.Add('Windows11Debloat Smoke Tests')
$summaryLines.Add('==============================')
$summaryLines.Add('')
$summaryLines.Add("Timestamp: $((Get-Date).ToString('s'))")
$summaryLines.Add("Total: $($results.Count)")
$summaryLines.Add("Passed: $passCount")
$summaryLines.Add("Skipped: $skipCount")
$summaryLines.Add("Failed: $failCount")
$summaryLines.Add('')

foreach ($result in $results) {
    $statusLabel = if ($result.Skipped) { 'SKIP' } elseif ($result.Passed) { 'PASS' } else { 'FAIL' }
    $summaryLines.Add("[$statusLabel] $($result.Name) (Exit: $($result.ExitCode), Expected: $($result.ExpectedExitCode))")

    if ($result.MissingExpectedOutput.Count -gt 0) {
        $summaryLines.Add('  Missing expected output:')
        foreach ($missing in $result.MissingExpectedOutput) {
            $summaryLines.Add("    - $missing")
        }
    }

    $summaryLines.Add("  Command: $($result.Command)")
    $summaryLines.Add('')
}

$summaryLines | Set-Content -Path $summaryPath -Encoding UTF8
$results | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8

Write-Host "[INFO] Smoke test summary written to: $summaryPath"
Write-Host "[INFO] Smoke test JSON written to: $jsonPath"
Write-Host "[INFO] Passed: $passCount / $($results.Count)"
Write-Host "[INFO] Skipped: $skipCount"

if ($failCount -gt 0) {
    exit 1
}

exit 0
