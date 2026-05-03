# Ticketing & ITSM Integration — Windows11Debloat

Guidance for integrating debloat run results with Jira, Atera, NinjaOne, ServiceNow, and other ITSM platforms.

→ Back to [README.md](README.md)  
→ Deployment instructions: [DEPLOY.md](DEPLOY.md)

---

## Contents

- [Recommended ticket types](#recommended-ticket-types)
- [Standard ticket fields to capture](#standard-ticket-fields-to-capture)
- [Jira example](#jira-example)
- [Atera example](#atera-example)
- [Other ITSM systems (quick mapping)](#other-itsm-systems-quick-mapping)
- [Suggested ticket note template](#suggested-ticket-note-template)

---

## Recommended ticket types

1. Change ticket
- Purpose: approve Ring 2 and Ring 3 promotion.
- Created by: endpoint engineering or platform owner.

2. Incident ticket
- Purpose: track failures from non-zero exit codes or user impact.
- Created by: RMM/MDM alert rule or helpdesk.

3. Problem ticket
- Purpose: track repeated failures across devices/vendors.
- Created by: service owner when incident pattern is recurring.

---

## Standard ticket fields to capture

1. Deployment metadata
- Platform (`Intune`, `NinjaOne`, `Atera`, `Action1`, other)
- Stage (`Test` or `Deploy`)
- Cleanup scope (`Device`, `User`, `All`)
- Vendor mode (`AutoDetect` or forced vendor)

2. Outcome metadata
- Exit code
- Marker values from `HKLM:\SOFTWARE\Windows11Debloat`
- Snapshot path (`C:\ProgramData\Windows11Debloat\Logs\Snapshots\PreChange-*.json`)
- Log path (`C:\ProgramData\Windows11Debloat\Logs\`)

3. Approval metadata
- Ring (`Ring 1`, `Ring 2`, `Ring 3`)
- Decision (`Go` or `Hold`)
- Approver and timestamp

---

## Jira example

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

---

## Atera example

Recommended flow:
1. Use automation profile to run script.
2. Create ticket automatically when exit code is non-zero.
3. Attach command output and device identity to ticket.

Suggested Atera ticket tags:
- `windows11debloat`
- `stage-test` or `stage-deploy`
- `scope-device` or `scope-user`
- `vendor-autodetect` or `vendor-forced`

---

## Other ITSM systems (quick mapping)

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

---

## Suggested ticket note template

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
