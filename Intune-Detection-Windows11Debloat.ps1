# Intune Remediations — Detection Script
# Used in: Devices > Scripts and remediations > Remediations > [your policy] > Detection script
#
# Logic:
#   EXIT 0  = COMPLIANT   (script ran successfully within the last 30 days) — no remediation triggered
#   EXIT 1  = NON-COMPLIANT (never ran, failed, or older than 30 days)      — remediation triggered
#
# Adjust $MaxAgeDays to match your re-run cadence (default: 30 days).

$MarkerPath = 'HKLM:\SOFTWARE\Windows11Debloat'
$MaxAgeDays = 30

try {
    if (-not (Test-Path -Path $MarkerPath)) {
        # Marker key does not exist — script has never run on this device
        exit 1
    }

    $marker = Get-ItemProperty -Path $MarkerPath -ErrorAction Stop

    # Must have completed successfully
    if ($marker.LastRunStatus -ne 'Success' -or $marker.LastExitCode -ne 0) {
        exit 1
    }

    # Must have run within the allowed age window
    if ([string]::IsNullOrWhiteSpace($marker.LastRunUtc)) {
        exit 1
    }

    $lastRun = [datetime]::Parse($marker.LastRunUtc, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
    $ageDays  = ([datetime]::UtcNow - $lastRun).TotalDays

    if ($ageDays -gt $MaxAgeDays) {
        exit 1
    }

    # All checks passed — device is compliant
    exit 0
}
catch {
    # Any unexpected error — treat as non-compliant so remediation runs
    exit 1
}
