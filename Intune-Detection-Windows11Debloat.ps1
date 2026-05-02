# ============================================================================
# Intune-Detection-Windows11Debloat.ps1
# PURPOSE : Detection script for Intune Remediations — checks whether the
#           debloat has run successfully within the allowed age window.
# EDIT     : Find the EDIT BEFORE UPLOAD block below and adjust values
#            before uploading to Devices > Scripts and remediations > Remediations.
# ============================================================================
#
# Logic:
#   EXIT 0  = COMPLIANT   (script ran successfully within the last 30 days) — no remediation triggered
#   EXIT 1  = NON-COMPLIANT (never ran, failed, or older than 30 days)      — remediation triggered
#
# ============================================================================
# EDIT BEFORE UPLOAD TO INTUNE
# Adjust values below for your detection cadence.
# ============================================================================
# Marker registry path example: 'HKLM:\SOFTWARE\Windows11Debloat'
# MaxAgeDays examples: 30 (monthly), 7 (weekly), 90 (quarterly)

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
