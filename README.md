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
- To send ticket/email notifications during Test stage, pass `-TicketNotifyEmail`; combo will auto-enable `-RecordTicketResult` for that run.

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

Ticket-enabled direct command example:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\Run-Windows11Debloat-Combo.ps1 -Stage Deploy -AutoDetect -IncludeCommon -CleanupScope User -RecordTicketResult -TicketSystem NinjaOne -TicketRing Ring2 -TicketNotifyEmail helpdesk@contoso.com
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

### Go/No-Go checklist before broad rollout

Use this gate before moving from pilot to broad RMM deployment.

1. Elevation behavior validated
- Confirm one non-admin run relaunches correctly.
- Confirm one admin run completes without relaunch.

2. Pilot deploy validated on real devices
- Run `-Stage Deploy` on 1-3 pilot endpoints.
- Confirm expected app/service/task changes and no critical business tools removed.

3. Snapshot and marker verification completed
- Confirm pre-change snapshot file exists under `C:\ProgramData\Windows11Debloat\Logs\Snapshots`.
- Confirm marker key updates under `HKLM:\SOFTWARE\Windows11Debloat`.

4. Context coverage validated
- Test at least one SYSTEM-context run (RMM/MDM style).
- Test at least one user-admin run.

5. Vendor detection sanity checks passed
- Validate `-AutoDetect` on at least one Dell, Lenovo, and HP endpoint.
- Confirm unmapped manufacturer behavior is clear and actionable.

6. Logging and exit-code handling verified in RMM
- Confirm script output is captured in job logs.
- Confirm non-zero exit codes trigger alerting or remediation workflows.

7. Ring rollout plan confirmed
- Ring 1: `-Stage Test` only.
- Ring 2: `-Stage Deploy` for limited subset.
- Ring 3: Broad deployment after log and ticket review.

Go decision:
- Proceed only when all checks above are green.
- If any check fails, hold rollout and remediate before broad deployment.

#### Sign-off template (change ticket)

1. Change ID: ______
2. Platform: Intune / NinjaOne / Atera / Action1 / Other
3. Ring: Pilot / Broad
4. Devices tested: ______
5. Success rate: ______%
6. Critical issues found: Yes / No
7. Snapshot and marker verification: Pass / Fail
8. Exit-code monitoring configured: Yes / No
9. Decision: Go / Hold
10. Approved by: ______
11. Approval date/time: ______

#### Minimum evidence required for sign-off

1. Pilot execution evidence
- At least 2 successful pilot run logs from different devices.
- At least 1 successful `-Stage Test` and 1 successful `-Stage Deploy` result.

2. State verification evidence
- At least 1 marker verification capture (`HKLM:\SOFTWARE\Windows11Debloat`).
- At least 1 pre-change snapshot file confirmed in `C:\ProgramData\Windows11Debloat\Logs\Snapshots`.

3. Outcome quality evidence
- No critical-severity helpdesk incidents attributed to the rollout during pilot window.
- Documented success rate for pilot devices (target recommendation: >= 95%).

4. Monitoring evidence
- Non-zero exit code alerting confirmed in the target platform.
- Named owner on-call for rollback/remediation during first broad wave.

#### How sign-off works in Intune

1. Create ringed device groups (Ring 1 pilot, Ring 2 limited, Ring 3 broad).
2. Assign `-Stage Test` to Ring 1 and review logs, exit codes, and tickets.
3. Complete sign-off template and record decision in your change ticket.
4. Promote to `-Stage Deploy` for Ring 2 only after sign-off.
5. Promote to Ring 3 after Ring 2 is stable and re-signed off.

#### How sign-off works in other RMM tools

1. Create two jobs/components: Test job (`-Stage Test`) and Deploy job (`-Stage Deploy`).
2. Run Test job on pilot tags/groups and review outcomes.
3. Complete sign-off template and approve the deploy wave.
4. Run Deploy job on next ring.
5. Keep recurring user cleanup job scheduled with `-CleanupScope User` after update windows.

### Ticketing system guidance (Jira, Atera, and others)

Use this section to standardize change evidence and rollout communication across ticketing platforms.

#### Recommended ticket types

1. Change ticket
- Purpose: approve Ring 2 and Ring 3 promotion.
- Created by: endpoint engineering or platform owner.

2. Incident ticket
- Purpose: track failures from non-zero exit codes or user impact.
- Created by: RMM/MDM alert rule or helpdesk.

3. Problem ticket
- Purpose: track repeated failures across devices/vendors.
- Created by: service owner when incident pattern is recurring.

#### Standard ticket fields to capture

1. Deployment metadata
- Platform (`Intune`, `NinjaOne`, `Atera`, `Action1`, other)
- Stage (`Test` or `Deploy`)
- Cleanup scope (`Device`, `User`, `All`)
- Vendor mode (`AutoDetect` or forced vendor)

2. Outcome metadata
- Exit code
- Marker values from `HKLM:\SOFTWARE\Windows11Debloat`
- Snapshot path (`C:\Logs\<domain>\Snapshots\PreChange-*.json`)
- Log path (`C:\Logs\<domain>\*.log`)

3. Approval metadata
- Ring (`Ring 1`, `Ring 2`, `Ring 3`)
- Decision (`Go` or `Hold`)
- Approver and timestamp

#### Jira example

Recommended issue flow:
1. `Change` issue for rollout approval and ring progression.
2. Linked `Incident` issues for failures.
3. Linked `Problem` issue if failure pattern repeats.

Suggested custom fields in Jira:
- `DeploymentStage`
- `CleanupScope`
- `ExitCode`
- `MarkerStatus`
- `SnapshotPath`
- `Ring`

Jira REST ticket creation example:

```powershell
$jiraBody = @{
	fields = @{
		project = @{ key = 'ITOPS' }
		summary = 'Windows11Debloat failure on endpoint'
		issuetype = @{ name = 'Incident' }
		description = @{
			type = 'doc'
			version = 1
			content = @(
				@{
					type = 'paragraph'
					content = @(
						@{ type = 'text'; text = 'ExitCode: 10, Stage: Deploy, Scope: User, Device: LAPTOP-1234' }
					)
				}
			)
		}
	}
}

$pair = 'admin@contoso.com:YOUR_JIRA_API_TOKEN'
$auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes($pair))

Invoke-RestMethod -Method Post `
	-Uri 'https://yourtenant.atlassian.net/rest/api/3/issue' `
	-Headers @{ Authorization = "Basic $auth"; Accept = 'application/json'; 'Content-Type' = 'application/json' } `
	-Body ($jiraBody | ConvertTo-Json -Depth 10)
```

Ticketing setup helper script:
- `Ticketing-Setup.ps1` lets you set ticketing system name and notification email once, then create tickets consistently.
- Supported systems: `Jira`, `Atera`, `NinjaRMM`, `NinjaOne`, `ServiceNow`, `Freshservice`, `Zendesk`, `ManageEngineSDP`, `ConnectWiseManage`, `AutotaskPSA`, `HaloITSM`, `Other`.

Ticket wrapper script is available under `wrappers\ticketing\`:
- `Create-TicketEvent.ps1` (single entrypoint for all supported systems via `-SystemName`)

Setup examples:

```powershell
# Jira setup
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Ticketing-Setup.ps1 -Action Setup -SystemName Jira -NotifyEmail helpdesk@contoso.com -JiraBaseUrl https://yourtenant.atlassian.net -JiraProjectKey ITOPS -JiraIssueType Incident -JiraUserEmail admin@contoso.com -JiraApiToken YOUR_JIRA_API_TOKEN

# Atera setup
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Ticketing-Setup.ps1 -Action Setup -SystemName Atera -NotifyEmail helpdesk@contoso.com

# NinjaRMM setup
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Ticketing-Setup.ps1 -Action Setup -SystemName NinjaRMM -NotifyEmail helpdesk@contoso.com

# ServiceNow setup
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Ticketing-Setup.ps1 -Action Setup -SystemName ServiceNow -NotifyEmail helpdesk@contoso.com
```

Create ticket/event examples:

```powershell
# Single entrypoint (recommended)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\wrappers\ticketing\Create-TicketEvent.ps1 -SystemName ServiceNow -Summary "Windows11Debloat event" -DeviceName LAPTOP-1234 -Stage Deploy -CleanupScope User -ExitCode 10 -Ring Ring2

# Jira issue creation
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Ticketing-Setup.ps1 -Action CreateTicket -Summary "Windows11Debloat failed on LAPTOP-1234" -Description "Automated deployment failure" -DeviceName LAPTOP-1234 -Stage Deploy -CleanupScope User -ExitCode 10 -Ring Ring2

# Atera/NinjaRMM payload generation for your native ticket action
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Ticketing-Setup.ps1 -Action CreateTicket -SystemName Atera -Summary "Windows11Debloat event" -DeviceName LAPTOP-1234 -Stage Test -CleanupScope Device -ExitCode 0 -Ring Ring1

# Example wrapper usage (HaloITSM)
pwsh -NoProfile -ExecutionPolicy Bypass -File .\wrappers\ticketing\Create-TicketEvent.ps1 -SystemName HaloITSM -Summary "Windows11Debloat event" -DeviceName LAPTOP-1234 -Stage Deploy -CleanupScope User -ExitCode 10 -Ring Ring2
```

Single-command Intune deployment with ticket result recording:

```powershell
# Recommended first step: save ticketing settings once
pwsh -NoProfile -ExecutionPolicy Bypass -File .\Ticketing-Setup.ps1 -Action Setup -SystemName Jira -NotifyEmail helpdesk@contoso.com -JiraBaseUrl https://yourtenant.atlassian.net -JiraProjectKey ITOPS -JiraIssueType Incident -JiraUserEmail admin@contoso.com -JiraApiToken YOUR_JIRA_API_TOKEN

# Single Intune command: run debloat and record result ticket/event
powershell.exe -ExecutionPolicy Bypass -File .\Run-Windows11Debloat-Combo.ps1 -Stage Deploy -AutoDetect -IncludeCommon -CleanupScope Device -UseIntuneMode -RecordTicketResult -TicketSystem Jira -TicketRing Ring2
```

Notes:
- `-RecordTicketResult` records success/failure details after the debloat run.
- `-TicketSystem` supports `Jira`, `Atera`, `NinjaRMM`, `NinjaOne`, `ServiceNow`, `Freshservice`, `Zendesk`, `ManageEngineSDP`, `ConnectWiseManage`, `AutotaskPSA`, `HaloITSM`, or `Other`.
- For Jira, a ticket is created directly when Jira settings are configured.
- For non-Jira systems, the helper outputs a normalized payload you can pass into that platform's native ticket creation action.

#### Atera example

Recommended flow:
1. Use automation profile to run script.
2. Create ticket automatically when exit code is non-zero.
3. Attach command output and device identity to ticket.

Suggested Atera ticket tags:
- `windows11debloat`
- `stage-test` or `stage-deploy`
- `scope-device` or `scope-user`
- `vendor-autodetect` or `vendor-forced`

#### Other ITSM systems (quick mapping)

1. ServiceNow
- Use `Change Request` for rollout gates.
- Auto-create `Incident` on failed jobs.
- Store marker and snapshot paths in work notes.

2. Freshservice
- Use `Change` for ring approvals.
- Use `Incident` for endpoint failures.
- Add rollout metadata in custom fields.

3. Zendesk
- Use a dedicated form for endpoint remediation incidents.
- Include stage, scope, exit code, and device name.

4. ManageEngine ServiceDesk Plus
- Use `Change` + `Incident` linkage.
- Capture run evidence in resolution/worklog sections.

5. ConnectWise Manage / Autotask PSA / HaloITSM
- Use one change ticket per wave and auto-create incidents from RMM alerts.
- Require go/no-go evidence fields before approval status change.

#### Suggested ticket note template

```text
Windows11Debloat rollout update
Platform: <Intune/NinjaOne/Atera/Action1/...>
Stage: <Test/Deploy>
Scope: <Device/User/All>
Vendor mode: <AutoDetect/Vendor:X>
Device count: <n>
Success count: <n>
Failure count: <n>
Exit code summary: <codes>
Marker key status: <value>
Snapshot sample path: <path>
Decision: <Go/Hold>
Approved by: <name>
Timestamp: <UTC>
```

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

`IntuneMode` is intended for device-context execution on a newly provisioned corporate machine.

When `IntuneMode` runs, it also stages the helpdesk copy locally to `C:\ProgramData\Windows11Debloat\`.

Staged files include the script, vendor profile JSON, helpdesk launcher, and README.

### Upload-time parameter checklist (Intune + RMM)

Before uploading scripts into any RMM or Intune policy, edit these files first:

| File | Upload target | What to edit before upload |
|---|---|---|
| `Intune-Bootstrap-Windows11Debloat.ps1` | Intune Platform scripts | `$IntuneDefaults` block (URL, hash, stage, scope, vendor mode, ticket settings) |
| `Intune-Detection-Windows11Debloat.ps1` | Intune Remediations (Detection) | `$MaxAgeDays` and optional `$MarkerPath` |
| `Intune-Remediation-Windows11Debloat.ps1` | Intune Remediations (Remediation) | `$IntuneRemediationDefaults` block (URL, stage, scope, vendor mode, ticket + Jira settings) |
| `Run-Windows11Debloat-Combo.ps1` | NinjaOne/Atera/Action1/other RMM script jobs | `$RmmDefaults` block (stage, scope, vendor mode, ticket settings) |

All four scripts now print effective runtime settings in logs so helpdesk can confirm exactly what policy values were used.

### Intune single-file bootstrap mode — upload one file, all scripts auto-created on device

#### Fast Intune quick start (recommended)

Use this path if you want the simplest setup for admins and helpdesk teams.

1. Edit `Intune-Bootstrap-Windows11Debloat.ps1`.
	Set these fields in the `EDIT BEFORE UPLOAD TO INTUNE` block:
	- `PackageZipUrl` = your hosted zip URL
	- `PackageZipSha256` = your SHA-256 hash if you want integrity verification
	- `Stage` = `Test` for pilot or `Deploy` for production
	- `HasIntuneRemediationsLicense` = `$true` if you will use licensed Intune Remediations for recurring runs
	- `EnableScheduledRerun` = `$true` only when you do **not** have Remediations licensing and want a local fallback scheduled task
	- `ScheduleTriggerMode` = trigger type: `Interval`, `AfterWindowsUpdate`, `IntervalAndAfterWindowsUpdate`, `MonthlyDayOfWeek`, or `MonthlyFixedDay`
	- `ScheduleIntervalDays`, `ScheduleDelayMinutes` = cadence/delay settings for interval-based triggers
	- `ScheduleWeekOfMonth`, `ScheduleDayOfWeek` = required when using `MonthlyDayOfWeek` (e.g. `'2'`, `'Wednesday'` = 2nd Wednesday)
	- `ScheduleDayOfMonth` = required when using `MonthlyFixedDay` (e.g. `15` = 15th of each month)
	- `AlsoRunAfterWindowsUpdate` = `$true` to also register the Windows Update event trigger alongside any monthly trigger
2. In Intune, go to **Devices > Scripts and remediations > Platform scripts > Add**.
3. Upload `Intune-Bootstrap-Windows11Debloat.ps1` with these settings:
	- Run this script using the logged on credentials: **No**
	- Enforce script signature check: **No**
	- Run script in 64-bit PowerShell Host: **Yes**
4. Assign to a pilot device group first, then expand to production groups.
5. After run, all script files are auto-created under `C:\ProgramData\Windows11Debloat`.

Helpdesk path after deployment:
- `C:\ProgramData\Windows11Debloat\Run-Windows11Debloat-Helpdesk.cmd`

Answer to the common question "does uploading one Intune script create the rest of the files?":
- **Yes**. The bootstrap downloads and stages the full package, so technicians can remote in and run from `C:\ProgramData\Windows11Debloat`.

Upload only **`Intune-Bootstrap-Windows11Debloat.ps1`** to Intune.
When the policy runs on a device, the script downloads your hosted zip, extracts all repository files,
and stages them to `C:\ProgramData\Windows11Debloat` automatically — no manual file copy is needed.

#### Step 1 — Host the package zip

Zip the contents of this repository and upload it to an accessible location:

- Azure Blob Storage with a SAS URL (recommended for security)
- Internal web server or SharePoint direct-download URL
- GitHub Releases asset URL

Note the final URL — you will embed it as `-PackageZipUrl` before uploading to Intune.
Optional but strongly recommended: generate a SHA-256 hash for integrity verification:

```powershell
Get-FileHash .\Windows11Debloat.zip -Algorithm SHA256
```

#### Step 2 — Prepare the bootstrap script

Before uploading to Intune, open `Intune-Bootstrap-Windows11Debloat.ps1` and set your
`-PackageZipUrl` (and optionally `-PackageZipSha256`) as the default parameter values,
since Intune Platform scripts do not support passing arguments to uploaded scripts.

Edit these fields before upload:

1. `PackageZipUrl` = required hosted zip URL.
2. `PackageZipSha256` = optional but recommended package hash.
3. `Stage` = `Test` for pilot policy or `Deploy` for production policy.
4. `CleanupScope` = `Device`, `User`, or `All`.
5. `Vendor` or `AutoDetect` = explicit vendor or automatic vendor detection.
6. `IncludeCommon` = enable common cross-vendor cleanup when desired.
7. `RecordTicketResult`, `TicketSystem`, `TicketNotifyEmail`, `TicketRing` = ticketing behavior.
8. `HasIntuneRemediationsLicense` = `$true` when you will use licensed Intune Remediations.
9. `EnableScheduledRerun`, `ScheduleTriggerMode`, `ScheduleIntervalDays`, `ScheduleDelayMinutes` = local fallback scheduling only for unlicensed tenants.
   - For monthly patching schedules: set `ScheduleTriggerMode` to `MonthlyDayOfWeek` or `MonthlyFixedDay`
   - `MonthlyDayOfWeek` also requires `ScheduleWeekOfMonth` (e.g. `'2'`) and `ScheduleDayOfWeek` (e.g. `'Wednesday'`)
   - `MonthlyFixedDay` also requires `ScheduleDayOfMonth` (e.g. `15`)
   - Set `AlsoRunAfterWindowsUpdate = $true` to add the Windows Update event trigger alongside any monthly trigger

If the tenant does **not** have eligible Intune Remediations licensing, you can also enable the
local fallback scheduler in this same defaults block. The fallback supports five trigger modes:

| `ScheduleTriggerMode` | Description |
|---|---|
| `Interval` | Runs every N days (`ScheduleIntervalDays`) |
| `AfterWindowsUpdate` | Runs after Windows Update completion events (IDs 19, 43, 44) |
| `IntervalAndAfterWindowsUpdate` | Both of the above (default) |
| `MonthlyDayOfWeek` | Runs on the Nth weekday of every month — set `ScheduleWeekOfMonth` and `ScheduleDayOfWeek` |
| `MonthlyFixedDay` | Runs on a fixed day of every month — set `ScheduleDayOfMonth` |

For monthly modes, set `AlsoRunAfterWindowsUpdate = $true` to also register the Windows Update event trigger alongside the monthly task.

Common patching patterns:

| Goal | Settings |
|---|---|
| Day after Patch Tuesday | `MonthlyDayOfWeek`, Week `'2'`, Day `'Wednesday'`, `AlsoRunAfterWindowsUpdate = $true` |
| 2nd Sunday sweep | `MonthlyDayOfWeek`, Week `'2'`, Day `'Sunday'` |
| Last Friday of month | `MonthlyDayOfWeek`, Week `'Last'`, Day `'Friday'` |
| Fixed 15th of month | `MonthlyFixedDay`, `ScheduleDayOfMonth = 15` |
| Every 30 days + catch updates | `IntervalAndAfterWindowsUpdate` (default) |

A configurable delay (`ScheduleDelayMinutes`) applies to all trigger types — giving Windows Update or patch installs time to complete before the cleanup runs.

If `HasIntuneRemediationsLicense = $true`, the combo script ignores the fallback scheduler and removes any previously created local tasks.

Important: Intune **Assignments** only chooses target groups. It does **not** pass `-Stage` or any other script arguments.
To use rings (`Test` then `Deploy`), you publish separate script files/policies.

Ring method:
1. Create a pilot copy, for example `Intune-Bootstrap-Windows11Debloat-Test.ps1`, and set `[string]$Stage = 'Test'`.
2. Create a production copy, for example `Intune-Bootstrap-Windows11Debloat-Deploy.ps1`, and set `[string]$Stage = 'Deploy'`.
3. Upload each file as a separate Platform script policy.
4. Assign the `Test` policy to pilot devices and the `Deploy` policy to broad production devices.

Key parameters to configure for your environment:

| Parameter | What to set |
|---|---|
| `-PackageZipUrl` | Your hosted zip URL from Step 1 |
| `-PackageZipSha256` | Your SHA-256 hash (optional, recommended) |
| `-Stage` | Set inside the uploaded script file (`Test` for pilot policy, `Deploy` for production policy) |
| `-AutoDetect` | Include — auto-detects Dell / Lenovo / HP / etc. |
| `-IncludeCommon` | Include — removes common cross-vendor bloatware |
| `-RecordTicketResult` + `-TicketSystem` | Include if you want an ITSM ticket per device run |
| `-HasIntuneRemediationsLicense` | Set to true when you will use licensed Intune Remediations for drift correction |
| `-EnableScheduledRerun` | Set to true only for the unlicensed fallback path |
| `-ScheduleTriggerMode` | `Interval`, `AfterWindowsUpdate`, `IntervalAndAfterWindowsUpdate`, `MonthlyDayOfWeek`, or `MonthlyFixedDay` |
| `-ScheduleIntervalDays` / `-ScheduleDelayMinutes` | Interval cadence and delay before each rerun |
| `-ScheduleWeekOfMonth` / `-ScheduleDayOfWeek` | Required for `MonthlyDayOfWeek` — e.g. `'2'` + `'Wednesday'` = 2nd Wednesday |
| `-ScheduleDayOfMonth` | Required for `MonthlyFixedDay` — e.g. `15` = 15th of each month |
| `-AlsoRunAfterWindowsUpdate` | Adds Windows Update event trigger alongside any monthly trigger |

#### Step 3 — Upload to Devices > Scripts and remediations

Navigate to **Devices > Scripts and remediations > Platform scripts > Add > Windows 10 and later**.

On the **Script settings** tab configure the following:

| Field | Value | Reason |
|---|---|---|
| **Script location** | Upload `Intune-Bootstrap-Windows11Debloat.ps1` | This is the only file Intune needs |
| **Run this script using the logged on credentials** | **No** | Must run as SYSTEM to remove apps, write HKLM, change services |
| **Enforce script signature check** | **No** | Script is not code-signed; Yes would block execution |
| **Run script in 64-bit PowerShell Host** | **Yes** | Required for correct HKLM registry paths and WMI vendor detection |

In **Assignments**, scope each policy to the right device group:
- Assign the script file with `Stage = Test` to pilot devices
- Assign the script file with `Stage = Deploy` to broad production devices

> **Note:** Platform scripts run **once** per device on policy assignment. Use this for initial provisioning.
> For monthly automatic re-runs (drift correction), use the Remediations blade described below.

If you do **not** have eligible Intune Remediations licensing, use the fallback local scheduled task instead by enabling
`EnableScheduledRerun` in `Intune-Bootstrap-Windows11Debloat.ps1`. When enabled, the combo registers tasks based on `ScheduleTriggerMode`:

| Mode | Task registered |
|---|---|
| `Interval` | `Windows11Debloat-Recurring` (every N days) |
| `AfterWindowsUpdate` | `Windows11Debloat-AfterWindowsUpdate` (event trigger) |
| `IntervalAndAfterWindowsUpdate` | Both of the above |
| `MonthlyDayOfWeek` | `Windows11Debloat-MonthlyDayOfWeek` — uses `ScheduleWeekOfMonth` + `ScheduleDayOfWeek` |
| `MonthlyFixedDay` | `Windows11Debloat-MonthlyFixedDay` — uses `ScheduleDayOfMonth` |

Set `AlsoRunAfterWindowsUpdate = $true` with any monthly mode to also register `Windows11Debloat-AfterWindowsUpdate` alongside it.

Helpdesk verification for fallback tasks:

```powershell
Get-ScheduledTask -TaskName 'Windows11Debloat-Recurring',
    'Windows11Debloat-AfterWindowsUpdate',
    'Windows11Debloat-MonthlyDayOfWeek',
    'Windows11Debloat-MonthlyFixedDay' -ErrorAction SilentlyContinue |
	Select-Object TaskName, State, TaskPath
```

Helpdesk cleanup for fallback tasks:

```powershell
foreach ($name in @(
    'Windows11Debloat-Recurring',
    'Windows11Debloat-AfterWindowsUpdate',
    'Windows11Debloat-MonthlyDayOfWeek',
    'Windows11Debloat-MonthlyFixedDay'
)) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
}
```

#### What gets created on the device automatically

When Intune runs the bootstrap, no further helpdesk action is needed:

1. Downloads and verifies the package zip
2. Extracts and stages **all repository files** to `C:\ProgramData\Windows11Debloat\`
3. Configures ticketing if `-RecordTicketResult` is set
4. Runs the debloat combo and writes the result marker to `HKLM:\SOFTWARE\Windows11Debloat`
5. Writes a transcript log to `C:\ProgramData\Windows11Debloat\Logs\`

A helpdesk technician remoting to the device afterwards can find everything here:

| What | Path |
|---|---|
| All scripts | `C:\ProgramData\Windows11Debloat\` |
| Core debloat script | `C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1` |
| One-click helpdesk launcher | `C:\ProgramData\Windows11Debloat\Run-Windows11Debloat-Helpdesk.cmd` |
| Vendor profiles | `C:\ProgramData\Windows11Debloat\vendor-profiles.json` |
| Run logs | `C:\ProgramData\Windows11Debloat\Logs\` |

To re-run from a remote session:

```powershell
cd C:\ProgramData\Windows11Debloat

# One-click re-run (helpdesk mode):
.\Run-Windows11Debloat-Helpdesk.cmd

# Full deploy run:
powershell.exe -ExecutionPolicy Bypass -File .\Run-Windows11Debloat-Combo.ps1 `
    -Stage Deploy -AutoDetect -IncludeCommon -CleanupScope Device -UseIntuneMode
```

---

### Intune monthly re-run — Remediations blade

> **Remediation Scripts — Licensing Statement**
>
> Proactive remediation scripts in Microsoft Intune (including detection and remediation scripts) are
> used only on devices and for users that are licensed with an eligible Windows Enterprise–level
> license. Each user or device benefiting from remediation scripts is assigned one of the required
> licenses: **Microsoft 365 F3, E3, or E5**; or **Windows Enterprise E3 or E5**. Microsoft Intune
> tenant settings are enabled only to support these licensed users and devices.

#### Enable the required Intune tenant setting

Before uploading the Remediations scripts you must confirm licensing in your tenant:

1. In the [Intune admin center](https://intune.microsoft.com), go to **Tenant administration > Windows data**.
2. Toggle **Enable Windows diagnostic data processor configuration** to **On**.
3. Check **I confirm that my tenant owns one of these qualifying licenses** and click **Save**.

> Without this step the Remediations blade will not execute detection/remediation scripts on enrolled devices.

Use **Devices > Scripts and remediations > Remediations** to automatically re-apply the debloat
on a recurring schedule. This catches newly installed bloatware, corrects settings drift,
and optionally creates an ITSM ticket each cycle.

If you are using this licensed Remediations path, keep the bootstrap fallback scheduler disabled.
The remediation run automatically removes all previously created local fallback tasks
(`Windows11Debloat-Recurring`, `Windows11Debloat-AfterWindowsUpdate`, `Windows11Debloat-MonthlyDayOfWeek`, `Windows11Debloat-MonthlyFixedDay`)
so only one recurring mechanism remains active.

Two scripts are provided for this blade:

| File | Role |
|---|---|
| `Intune-Detection-Windows11Debloat.ps1` | Upload as **Detection script** |
| `Intune-Remediation-Windows11Debloat.ps1` | Upload as **Remediation script** |

#### Prepare the remediation script

Open `Intune-Remediation-Windows11Debloat.ps1` and set the variables at the top before uploading:

```powershell
$PackageZipUrl    = 'https://your-storage.example.com/Windows11Debloat.zip'
$PackageZipSha256 = 'YOUR_SHA256_HASH'   # or leave blank to skip verification
```

Edit these fields before upload:

1. `PackageZipUrl` = required hosted zip URL.
2. `PackageZipSha256` = optional but recommended package hash.
3. `Stage` = normally leave as `Deploy`.
4. `CleanupScope` = `Device`, `User`, or `All`.
5. `Vendor` or `AutoDetect` = explicit vendor or automatic vendor detection.
6. `IncludeCommon` = enable common cross-vendor cleanup when desired.
7. `RecordTicketResult`, `TicketSystem`, `TicketNotifyEmail`, `TicketRing`, `TicketingConfigPath` = ticketing behavior.
8. `HasIntuneRemediationsLicense` = leave as `$true` for the licensed Remediations path.

Uncomment the ticketing parameter lines if you want an ITSM ticket per monthly cycle.
`HasIntuneRemediationsLicense` is already set to `$true` in this script and should stay that way for the licensed path.

#### Create the Remediations policy in Intune

Navigate to **Devices > Scripts and remediations > Remediations > Create**.

| Tab | Field | Value |
|---|---|---|
| **Basics** | Name | `Windows 11 Debloat - Monthly` |
| **Settings** | Detection script | Upload `Intune-Detection-Windows11Debloat.ps1` |
| **Settings** | Remediation script | Upload `Intune-Remediation-Windows11Debloat.ps1` |
| **Settings** | Run this script using the logged on credentials | **No** (SYSTEM) |
| **Settings** | Enforce script signature check | **No** |
| **Settings** | Run script in 64-bit PowerShell Host | **Yes** |
| **Assignments** | Schedule | Daily check; remediation triggers only when non-compliant |
| **Assignments** | Groups | Scope to your device groups / rings |

#### How detection works

The detection script reads `HKLM:\SOFTWARE\Windows11Debloat` and exits:

- **Exit 1 (non-compliant — remediation runs)** if:
  - Registry key is missing (script has never run on this device)
  - `LastRunStatus` is not `Success`, or `LastExitCode` is not `0`
  - `LastRunUtc` is older than **30 days**
- **Exit 0 (compliant — no action)** if all checks pass

To change the re-run interval, edit `$MaxAgeDays` in `Intune-Detection-Windows11Debloat.ps1`:

```powershell
$MaxAgeDays = 30   # change to 7 for weekly, 90 for quarterly
```

Edit these detection fields before upload:

1. `MaxAgeDays` = how old a successful run can be before remediation is triggered.
2. `MarkerPath` = leave as default unless you intentionally changed the registry marker location.

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

Use this section to operationalize deployment in enterprise tooling.

### Ready-to-paste commands

Use these commands directly in script runners, package install commands, or remote execute actions.

| Platform | Where to paste command | Recommended run context | Recommended command |
|---|---|---|---|
| Intune Win32 app | Install command | SYSTEM (64-bit) | `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -IntuneMode` |
| ManageEngine MDM | Script command / deployment command | SYSTEM / Administrator | `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -IntuneMode` |
| Atera | Script body / command field | User remediation after updates | `powershell.exe -ExecutionPolicy Bypass -File "C:\\ProgramData\\Windows11Debloat\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| NinjaOne | Script body / parameters | User remediation after updates | `powershell.exe -ExecutionPolicy Bypass -File "C:\\ProgramData\\Windows11Debloat\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Hexnode | Run Script action / policy script command | SYSTEM for baseline, user-focused for reruns | Baseline: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device`<br>Rerun: `powershell.exe -ExecutionPolicy Bypass -File "C:\\ProgramData\\Windows11Debloat\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Pulseway | Automation workflow script step | SYSTEM for baseline, user-focused for reruns | Baseline: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device`<br>Rerun: `powershell.exe -ExecutionPolicy Bypass -File "C:\\ProgramData\\Windows11Debloat\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| LogMeIn Resolve | Script execution task | User remediation after updates | `powershell.exe -ExecutionPolicy Bypass -File "C:\\ProgramData\\Windows11Debloat\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Datto RMM | Component script command | SYSTEM for baseline, user-focused for reruns | Baseline: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device`<br>Rerun: `powershell.exe -ExecutionPolicy Bypass -File "C:\\ProgramData\\Windows11Debloat\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Auvik | Script task / integration command | User remediation after updates | `powershell.exe -ExecutionPolicy Bypass -File "C:\\ProgramData\\Windows11Debloat\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Syncro | Script module command | SYSTEM for baseline, user-focused for reruns | Baseline: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device`<br>Rerun: `powershell.exe -ExecutionPolicy Bypass -File "C:\\ProgramData\\Windows11Debloat\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Action1 | Script deployment command | SYSTEM for baseline, user-focused for reruns | Baseline: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device`<br>Rerun: `powershell.exe -ExecutionPolicy Bypass -File "C:\\ProgramData\\Windows11Debloat\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User` |
| Other RMM | Script command field | Baseline: Device, recurring: User | Baseline: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope Device`<br>Recurring: `powershell.exe -ExecutionPolicy Bypass -File .\\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -CleanupScope User -HelpdeskMode` |

If the staged path is not present yet, use the bootstrap to provision it first, then run:

`powershell.exe -ExecutionPolicy Bypass -File "C:\\ProgramData\\Windows11Debloat\\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User`

```powershell
# Intune initial deployment (device context)
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -IntuneMode

# ManageEngine MDM initial deployment (device context)
powershell.exe -ExecutionPolicy Bypass -File .\Windows11Debloat.ps1 -AutoDetect -IncludeCommon -IntuneMode

# Atera post-update remediation (user-focused cleanup from staged copy)
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# NinjaOne post-update remediation (user-focused cleanup from staged copy)
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Hexnode post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Pulseway post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# LogMeIn Resolve post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Datto RMM post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Auvik post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Syncro post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

# Action1 post-update remediation
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User

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
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User
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
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User
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
powershell.exe -ExecutionPolicy Bypass -File "C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1" -HelpdeskMode -CleanupScope User
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
- `IntuneMode` stages a local helpdesk copy under `C:\ProgramData\Windows11Debloat\` so technicians can rerun remediation after updates.
- The script writes a detection marker registry key by default at `HKLM:\SOFTWARE\Windows11Debloat`.
- Marker values include last status, exit code, vendor, cleanup scope, run mode, run context, and phase completion states.
- Default exit codes: `0` success, `10` elevation required, `11` invalid configuration, `12` auto-detect failure, `20` runtime failure.
