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

## Run (PowerShell As Administrator)

### Quick standalone helpdesk run

For a technician remediating a machine after Windows Update re-installs apps/features, the preferred approach is to call the locally staged script from your remote support or RMM tool.

Examples:
- TeamViewer
- ConnectWise
- Splashtop

When the device has already been through `IntuneMode`, have the remote tool call the staged local copy from:
- `C:\<domain>\Scripts`
- fallback: `C:\Default\Scripts`

Example remote command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\<domain>\Scripts\Windows11Debloat.ps1" -HelpdeskMode
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
- write a transcript log to `C:\Logs\<domain>` and fall back to `C:\Logs\Default`

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

`IntuneMode` is intended for device-context execution on a newly provisioned corporate machine.

When `IntuneMode` runs, it also stages the helpdesk copy locally to:
- `C:\<domain>\Scripts`
- fallback: `C:\Default\Scripts`

Staged files include the script, vendor profile JSON, helpdesk launcher, and README.

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

## MDM and RMM Setup

Use this section to operationalize deployment in enterprise tooling.

### Ready-to-paste commands

Use these commands directly in script runners, package install commands, or remote execute actions.

| Platform | Where to paste command | Recommended run context | Recommended command |
|---|---|---|---|
| Intune Win32 app | Install command | SYSTEM (64-bit) | `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -IntuneMode` |
| ManageEngine MDM | Script command / deployment command | SYSTEM / Administrator | `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -IntuneMode` |
| Atera | Script body / command field | User remediation after updates | `powershell.exe -ExecutionPolicy Bypass -File "C:\\<domain>\\Scripts\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| NinjaOne | Script body / parameters | User remediation after updates | `powershell.exe -ExecutionPolicy Bypass -File "C:\\<domain>\\Scripts\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Hexnode | Run Script action / policy script command | SYSTEM for baseline, user-focused for reruns | Baseline: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device`<br>Rerun: `powershell.exe -ExecutionPolicy Bypass -File "C:\\<domain>\\Scripts\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Pulseway | Automation workflow script step | SYSTEM for baseline, user-focused for reruns | Baseline: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device`<br>Rerun: `powershell.exe -ExecutionPolicy Bypass -File "C:\\<domain>\\Scripts\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| LogMeIn Resolve | Script execution task | User remediation after updates | `powershell.exe -ExecutionPolicy Bypass -File "C:\\<domain>\\Scripts\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Datto RMM | Component script command | SYSTEM for baseline, user-focused for reruns | Baseline: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device`<br>Rerun: `powershell.exe -ExecutionPolicy Bypass -File "C:\\<domain>\\Scripts\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Auvik | Script task / integration command | User remediation after updates | `powershell.exe -ExecutionPolicy Bypass -File "C:\\<domain>\\Scripts\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Syncro | Script module command | SYSTEM for baseline, user-focused for reruns | Baseline: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device`<br>Rerun: `powershell.exe -ExecutionPolicy Bypass -File "C:\\<domain>\\Scripts\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Action1 | Script deployment command | SYSTEM for baseline, user-focused for reruns | Baseline: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device`<br>Rerun: `powershell.exe -ExecutionPolicy Bypass -File "C:\\<domain>\\Scripts\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Other RMM | Script command field | Baseline: Device, recurring: User | Baseline: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device`<br>Recurring: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope User -HelpdeskMode` |

If your domain-staged path is unavailable, use:

`powershell.exe -ExecutionPolicy Bypass -File "C:\\Default\\Scripts\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User`

```powershell
# Intune initial deployment (device context)
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -IntuneMode

# ManageEngine MDM initial deployment (device context)
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -IntuneMode

# Atera post-update remediation (user-focused cleanup from staged copy)
powershell.exe -ExecutionPolicy Bypass -File "C:\<domain>\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# NinjaOne post-update remediation (user-focused cleanup from staged copy)
powershell.exe -ExecutionPolicy Bypass -File "C:\<domain>\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Hexnode post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\<domain>\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Pulseway post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\<domain>\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# LogMeIn Resolve post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\<domain>\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Datto RMM post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\<domain>\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Auvik post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\<domain>\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Syncro post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\<domain>\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Action1 post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\<domain>\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Fallback when domain path is not available
powershell.exe -ExecutionPolicy Bypass -File "C:\Default\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Generic RMM baseline run (device phase only)
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device

# Generic RMM recurring cleanup after updates (user phase only)
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope User -HelpdeskMode

# Helpdesk local machine quick run (all phases)
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -HelpdeskMode
```

Optional vendor-forced commands (skip AutoDetect):

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -Vendor Dell -IncludeCommon -CleanupScope Device
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -Vendor Lenovo -IncludeCommon -CleanupScope Device
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -Vendor HP -IncludeCommon -CleanupScope Device
```

### Microsoft Intune (Win32 app)

### Recommended schedule

Use this cadence to keep systems clean when updates reintroduce apps.

| Platform | Initial baseline cadence | Recurring remediation cadence | Recommended scope |
|---|---|---|---|
| Intune | During enrollment / Autopilot | Monthly and after feature updates | Baseline: `Device`, Recurring: `User` |
| ManageEngine MDM | During enrollment | Monthly and after feature updates | Baseline: `Device`, Recurring: `User` |
| NinjaOne | On first onboarding policy | Weekly or post-update trigger | Baseline: `Device`, Recurring: `User` |
| Hexnode | During enrollment policy | Monthly or post-update trigger | Baseline: `Device`, Recurring: `User` |
| Pulseway | On new endpoint onboarding | Weekly or monthly | Baseline: `Device`, Recurring: `User` |
| LogMeIn Resolve | On new endpoint onboarding | Weekly or post-update trigger | Baseline: `Device`, Recurring: `User` |
| Datto RMM | During component onboarding | Weekly or monthly | Baseline: `Device`, Recurring: `User` |
| Auvik | During initial automation run | Weekly or monthly | Baseline: `Device`, Recurring: `User` |
| Syncro | During initial policy deployment | Weekly or monthly | Baseline: `Device`, Recurring: `User` |
| Action1 | During initial deployment | Weekly or monthly | Baseline: `Device`, Recurring: `User` |
| Atera | On first onboarding policy | Weekly or post-update trigger | Baseline: `Device`, Recurring: `User` |

Suggested run logic:
1. Baseline run once in device context:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device
```

2. Recurring remediation run in user-focused mode:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\<domain>\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User
```

3. If domain path is unavailable, use fallback:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Default\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User
```

1. Package these files into your `.intunewin` payload:
	- `Windows11Debloat.ps1`
	- `vendor-profiles.json`
	- `Run-Windows11Debloat-Helpdesk.cmd`
	- `README.md`
2. Create a Win32 app in Intune and upload the package.
3. Use install command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -IntuneMode
```

4. Run in 64-bit PowerShell and assign to device groups.
5. Detection rule suggestion (registry):
	- Key: `HKLM\SOFTWARE\Windows11Debloat`
	- Value: `LastRunStatus` equals `Success`
	- Value: `LastExitCode` equals `0`
6. For post-update remediation, run a follow-up script in user context or remote tool with:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\<domain>\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User
```

### ManageEngine MDM

1. Upload the same script bundle used for Intune.
2. Configure script execution as Administrator/SYSTEM on device enrollment.
3. Use command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -IntuneMode
```

4. Use custom compliance/detection with marker key:
	- `HKLM\SOFTWARE\Windows11Debloat\LastRunStatus` = `Success`
	- `HKLM\SOFTWARE\Windows11Debloat\LastExitCode` = `0`

### Atera and NinjaOne (and similar RMM)

Best practice:
- Let Intune/MDM perform initial deployment.
- Use the RMM for fast reruns after updates by calling the staged local script.

Recommended remote command:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\<domain>\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User
```

If the staged path is not present yet, use fallback:

```powershell
powershell.exe -ExecutionPolicy Bypass -File "C:\Default\Scripts\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User
```

### Other RMM software (generic pattern)

1. Run initial baseline as SYSTEM/device context:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device
```

2. Run recurring user cleanup after Windows feature updates:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope User -HelpdeskMode
```

3. Use registry marker key `HKLM:\SOFTWARE\Windows11Debloat` for reporting and success detection.

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
- `IntuneMode` stages a local helpdesk copy under `C:\<domain>\Scripts` so technicians can rerun remediation after updates.
- The script writes a detection marker registry key by default at `HKLM:\SOFTWARE\Windows11Debloat`.
- Marker values include last status, exit code, vendor, cleanup scope, run mode, run context, and phase completion states.
- Default exit codes: `0` success, `10` elevation required, `11` invalid configuration, `12` auto-detect failure, `20` runtime failure.
