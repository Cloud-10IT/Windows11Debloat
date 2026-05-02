# Intune Remediations — Remediation Script
# Used in: Devices > Scripts and remediations > Remediations > [your policy] > Remediation script
#
# This script re-runs the bootstrap to re-download, re-stage, and re-apply the debloat package.
# It is only invoked when the Detection script exits 1 (non-compliant).
#
# REQUIRED: Set $PackageZipUrl to your hosted zip URL before uploading to Intune.
# OPTIONAL: Set $PackageZipSha256 to validate download integrity.
#
# Adjust -Stage, -TicketSystem, -TicketRing, and Jira credentials to match your environment.

$PackageZipUrl   = 'https://your-storage.example.com/Windows11Debloat.zip'
$PackageZipSha256 = ''   # SHA-256 of the zip, or leave blank to skip verification

$InstallRoot = 'C:\ProgramData\Windows11Debloat'

# ── Bootstrap download & execution ────────────────────────────────────────────

$tempRoot   = Join-Path -Path $env:TEMP -ChildPath ('W11DebloatRemediation-' + [Guid]::NewGuid().ToString('N'))
$zipPath    = Join-Path -Path $tempRoot -ChildPath 'Windows11Debloat.zip'
$extractPath = Join-Path -Path $tempRoot -ChildPath 'extract'

try {
    New-Item -Path $tempRoot    -ItemType Directory -Force | Out-Null
    New-Item -Path $extractPath -ItemType Directory -Force | Out-Null

    Write-Host "[INFO] Downloading package from: $PackageZipUrl"
    Invoke-WebRequest -Uri $PackageZipUrl -OutFile $zipPath -UseBasicParsing

    if (-not [string]::IsNullOrWhiteSpace($PackageZipSha256)) {
        $expected = $PackageZipSha256.Trim().ToUpperInvariant()
        $actual   = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToUpperInvariant()
        if ($actual -ne $expected) {
            throw "Package hash mismatch. Expected '$expected', got '$actual'."
        }
        Write-Host '[INFO] SHA-256 validation passed'
    }

    Write-Host '[INFO] Extracting package'
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

    $comboScript = Get-ChildItem -Path $extractPath -Recurse -Filter 'Run-Windows11Debloat-Combo.ps1' -File | Select-Object -First 1
    if ($null -eq $comboScript) {
        throw 'Run-Windows11Debloat-Combo.ps1 not found in downloaded package.'
    }

    $packageRoot = Split-Path -Path $comboScript.FullName -Parent

    Write-Host "[INFO] Staging to $InstallRoot"
    if (Test-Path -Path $InstallRoot) {
        Remove-Item -Path $InstallRoot -Recurse -Force -ErrorAction Stop
    }
    New-Item -Path $InstallRoot -ItemType Directory -Force | Out-Null
    Copy-Item -Path (Join-Path -Path $packageRoot -ChildPath '*') -Destination $InstallRoot -Recurse -Force

    $comboPath = Join-Path -Path $InstallRoot -ChildPath 'Run-Windows11Debloat-Combo.ps1'

    # ── Build argument list ────────────────────────────────────────────────────
    # Customise these arguments to match your deployment requirements.
    # Remove -RecordTicketResult and ticket params if you do not use ticketing.
    $args = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', $comboPath
        '-Stage',        'Deploy'
        '-AutoDetect'
        '-IncludeCommon'
        '-CleanupScope', 'Device'
        '-UseIntuneMode'
        #'-RecordTicketResult'
        #'-TicketSystem',       'Jira'
        #'-TicketNotifyEmail',  'helpdesk@contoso.com'
        #'-TicketRing',         'Ring2'
        #'-JiraBaseUrl',        'https://yourtenant.atlassian.net'
        #'-JiraProjectKey',     'ITOPS'
        #'-JiraIssueType',      'Incident'
        #'-JiraUserEmail',      'admin@contoso.com'
        #'-JiraApiToken',       'YOUR_JIRA_API_TOKEN'
    )

    Write-Host '[INFO] Running debloat combo'
    $hostExe = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
    & $hostExe @args

    $exitCode = $LASTEXITCODE
    Write-Host "[INFO] Combo exited with code: $exitCode"
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
