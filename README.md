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
