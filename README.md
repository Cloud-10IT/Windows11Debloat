# Windows11Debloat

Windows 11 debloat script with external vendor profiles.

Current profiles include:
- Dell (default, intended for Dell XPS)
- Lenovo
- HP
- Acer
- ASUS
- MSI
- Samsung
- Microsoft
- Razer
- Huawei
- LG
- Gigabyte
- Fujitsu
- Panasonic
- Dynabook
- VAIO
- Framework

The script is profile-based so you can add more vendors easily.

Five additional vendors now include starter entries: Acer, ASUS, MSI, Samsung, and Razer.

All other newly added vendors still use safe empty lists by default, so you can populate each profile with the exact packages/services/tasks for your environment.

## File

- `Windows11Debloat.ps1`
- `vendor-profiles.json`

## What It Does

- Removes vendor and consumer Appx packages
- Attempts to uninstall vendor tools via winget
- Disables selected vendor/background services
- Disables selected scheduled tasks
- Applies a small set of safe registry tweaks (only when common profile is included)
- Disables hibernation (when enabled in Common profile)
- Disables SSD-often-unneeded services in Common profile (SysMain and Windows Search indexing service)
- Exports a pre-change safety snapshot on non-dry runs to `C:\ProgramData\Windows11Debloat\Logs\Snapshots`

## Run (PowerShell As Administrator)

<details>
<summary><strong>Expand quick navigation</strong></summary>

- [Combo pilot-to-RMM workflow](#combo-pilot-to-rmm-workflow)
- [RMM direct commands](#rmm-direct-commands)
- [Smoke test harness](#one-command-smoke-test-harness)
- [Quick standalone helpdesk run](#quick-standalone-helpdesk-run)
- [Vendor profiles](#dell-xps-profile)
- [Cleanup scope / Dry run](#cleanup-scope-split)
- [Enterprise deployment guide (Intune, MDM, RMM, Go/No-Go)](DEPLOY.md)

</details>

### Combo pilot-to-RMM workflow

Use one launcher for both pre-deployment validation and production rollout:

```powershell
# Pilot test in an environment (safe, no changes)
.\Run-Windows11Debloat-Combo.ps1 -Stage Test -AutoDetect -CleanupScope Device

# Promote to deployment from the same command pattern
.\Run-Windows11Debloat-Combo.ps1 -Stage Deploy -AutoDetect -CleanupScope Device
```

How to use in RMM:
- Pilot ring: run `-Stage Test` first and validate summary/log output.
- Production ring: switch only `-Stage Deploy` and keep the same vendor/scope arguments.
- Recurring post-update cleanup: set `-CleanupScope User` for user-context reruns.
- Test stage now writes restore artifacts to `C:\ProgramData\Windows11Debloat\Logs\RestorePlans`:
	- `RemovedApps-<vendor>-<timestamp>.json` (manifest of appx/winget targets)
	- `Restore-RemovedApps-<vendor>-<timestamp>.ps1` (best-effort reinstall helper)

### RMM direct commands

Use the combo launcher directly from each platform.

```powershell
# NinjaOne pilot test (safe preview)
powershell.exe -ExecutionPolicy Bypass -File .\Run-Windows11Debloat-Combo.ps1 -Stage Test -AutoDetect -IncludeCommon -CleanupScope User

# NinjaOne production deploy
powershell.exe -ExecutionPolicy Bypass -File .\Run-Windows11Debloat-Combo.ps1 -Stage Deploy -AutoDetect -IncludeCommon -CleanupScope User

# Atera pilot test (safe preview)
powershell.exe -ExecutionPolicy Bypass -File .\Run-Windows11Debloat-Combo.ps1 -Stage Test -AutoDetect -IncludeCommon -CleanupScope User

# Atera production deploy
powershell.exe -ExecutionPolicy Bypass -File .\Run-Windows11Debloat-Combo.ps1 -Stage Deploy -AutoDetect -IncludeCommon -CleanupScope User

# Action1 pilot test (safe preview)
powershell.exe -ExecutionPolicy Bypass -File .\Run-Windows11Debloat-Combo.ps1 -Stage Test -AutoDetect -IncludeCommon -CleanupScope User

# Action1 production deploy
powershell.exe -ExecutionPolicy Bypass -File .\Run-Windows11Debloat-Combo.ps1 -Stage Deploy -AutoDetect -IncludeCommon -CleanupScope User
```

Optional vendor force example:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Run-Windows11Debloat-Combo.ps1 -Stage Deploy -Vendor Dell -IncludeCommon -CleanupScope Device
```


### One-command smoke test harness

Run a safe validation pass (Test stage and WhatIf checks only):

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Run-SmokeTests.ps1
```

Run smoke tests for a specific vendor:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Run-SmokeTests.ps1 -Vendor Dell
```

Include a real deploy test in the same run (pilot device only):

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Run-SmokeTests.ps1 -IncludeDeployTest
```

Outputs are written to `TestOutput` as both `.log` and `.json` summary files.
If the session is not elevated, the harness will mark the WhatIf wording check as `SKIP` and continue.

> For full enterprise rollout guidance and ring sign-off, see the sub-guides:
> - [DEPLOY.md](DEPLOY.md) — Go/No-Go checklist, Intune bootstrap, Remediations blade, MDM and RMM setup

### Quick standalone helpdesk run

For a technician remediating a machine after Windows Update re-installs apps/features, the preferred approach is to call the locally staged script from your remote support or RMM tool.

Examples:
- TeamViewer
- ConnectWise
- Splashtop

When the device has already been through `IntuneMode`, have the remote tool call the staged local copy from `C:\ProgramData\Windows11Debloat\`.

Example remote command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1" -HelpdeskMode
```

If you are working directly on the machine, use the standalone helpdesk launcher:

```powershell
.\Run-Windows11Debloat-Helpdesk.cmd
```

Or run the script directly:

```powershell
.\Windows11Debloat.ps1 -HelpdeskMode
```

`HelpdeskMode` is intended for fast manual remediation and will:
- relaunch elevated if needed
- default to `-AutoDetect` when no vendor is specified
- default to `-IncludeCommon` when not specified
- suppress confirmation prompts for faster execution
- write a transcript log to `C:\ProgramData\Windows11Debloat\Logs`

### Dell XPS profile

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\Windows11Debloat.ps1 -Vendor Dell -IncludeCommon
```

### Lenovo profile

```powershell
.\Windows11Debloat.ps1 -Vendor Lenovo -IncludeCommon
```

### HP profile

```powershell
.\Windows11Debloat.ps1 -Vendor HP -IncludeCommon
```

### Auto-detect vendor from system manufacturer

```powershell
.\Windows11Debloat.ps1 -AutoDetect -IncludeCommon
```

### Intune / Autopilot device provisioning

```powershell
.\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -IntuneMode
```

`IntuneMode` runs as SYSTEM on a newly provisioned corporate machine and stages all scripts to `C:\ProgramData\Windows11Debloat\`.

For full Intune setup including bootstrap, Remediations blade, upload-time parameter checklist, and MDM/RMM deployment: see **[DEPLOY.md](DEPLOY.md)**.

---

### Cleanup scope split

You can split cleanup into device-context and user-context phases:

```powershell
.\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device
.\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope User
.\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope All
```

Scope behavior:
- `Device`: Appx removal, services, scheduled tasks, registry tweaks, hibernation
- `User`: winget removals, Copilot cleanup, OneDrive consumer cleanup
- `All`: runs both phases

`IntuneMode` defaults to `-CleanupScope Device` unless you explicitly override it.

If auto-detection cannot map your manufacturer, the script will stop and show available vendor profiles.

Auto-detect alias matching is configured in `ManufacturerAliases` inside `vendor-profiles.json`.

### Use a custom profile file

```powershell
.\Windows11Debloat.ps1 -Vendor Dell -IncludeCommon -ProfilesPath .\vendor-profiles.json
```

### Dry run (no changes)

```powershell
.\Windows11Debloat.ps1 -Vendor Dell -IncludeCommon -DryRun
```

Auto-detect with dry run:

```powershell
.\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -DryRun
```

Quiet dry run (summary only):

```powershell
.\Windows11Debloat.ps1 -DryRun -HelpdeskMode -QuietDryRun
```

## MDM and RMM Setup

For platform-specific deployment commands, cadence recommendations, and ready-to-paste script commands for all RMM tools, see **[DEPLOY.md](DEPLOY.md)**.

## Add Another Vendor

Edit `vendor-profiles.json` and add a new top-level object next to `Dell`, `Lenovo`, and `HP`:

- `AppxPackages`: Appx package name patterns
- `WingetPackages`: winget IDs
- `Services`: service names
- `ScheduledTasks`: full task paths

No script changes are required. The script reads any vendor name present in `vendor-profiles.json`.

If you want AutoDetect support for that vendor, also add aliases under `ManufacturerAliases`.

Example for adding Acer:

```json
"Acer": {
	"AppxPackages": ["AcerIncorporated.AcerCareCenter"],
	"WingetPackages": ["Acer.AcerCareCenter"],
	"Services": ["AcerQuickAccessService"],
	"ScheduledTasks": ["\\Acer\\Acer Update Task"]
}
```

Then append your vendor alias entry inside the existing `ManufacturerAliases` object:

```json
"ManufacturerAliases": {
  "Acer": ["Acer", "Acer Incorporated"]
}
```

## Notes

- Always test with `-DryRun` first.
- Starter entries are conservative defaults. Validate against your exact model image before running without `-DryRun`.
- Hibernation and Common service tweaks are profile-driven in `vendor-profiles.json` and can be turned on/off there.
- Package names differ between models and regions. Adjust profile lists as needed.
- Some enterprise environments may re-install OEM software via policy or management tooling.
- `HelpdeskMode` is best for rerunning cleanup after feature updates or Store re-installs on an already deployed device.
- `IntuneMode` is best for new-machine deployment under SYSTEM context.
- On fresh Intune devices, some `winget` or per-user removals may need a later user-context remediation pass.
- `IntuneMode` stages a local helpdesk copy under `C:\ProgramData\Windows11Debloat\` so technicians can rerun remediation after updates.
- The script writes a detection marker registry key by default at `HKLM:\SOFTWARE\Windows11Debloat`.
- Marker values include last status, exit code, vendor, cleanup scope, run mode, run context, and phase completion states.
- Default exit codes: `0` success, `10` elevation required, `11` invalid configuration, `12` auto-detect failure, `20` runtime failure.
