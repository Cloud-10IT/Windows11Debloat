[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Setup', 'CreateTicket', 'ShowConfig')]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Jira', 'Atera', 'NinjaRMM', 'NinjaOne', 'ServiceNow', 'Freshservice', 'Zendesk', 'ManageEngineSDP', 'ConnectWiseManage', 'AutotaskPSA', 'HaloITSM', 'Other')]
    [string]$SystemName,

    [Parameter(Mandatory = $false)]
    [string]$NotifyEmail,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [string]$Summary,

    [Parameter(Mandatory = $false)]
    [string]$Description,

    [Parameter(Mandatory = $false)]
    [string]$DeviceName,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Test', 'Deploy')]
    [string]$Stage,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Device', 'User', 'All')]
    [string]$CleanupScope,

    [Parameter(Mandatory = $false)]
    [int]$ExitCode,

    [Parameter(Mandatory = $false)]
    [string]$Ring,

    [Parameter(Mandatory = $false)]
    [string]$JiraBaseUrl,

    [Parameter(Mandatory = $false)]
    [string]$JiraProjectKey,

    [Parameter(Mandatory = $false)]
    [string]$JiraIssueType = 'Incident',

    [Parameter(Mandatory = $false)]
    [string]$JiraUserEmail,

    [Parameter(Mandatory = $false)]
    [string]$JiraApiToken,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RootPath {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return (Split-Path -Path $PSCommandPath -Parent)
    }

    return (Get-Location).Path
}

function Get-ConfigPath {
    param(
        [Parameter(Mandatory = $false)]
        [string]$InputPath
    )

    if (-not [string]::IsNullOrWhiteSpace($InputPath)) {
        return $InputPath
    }

    $root = Resolve-RootPath
    return (Join-Path -Path $root -ChildPath 'ticketing-config.json')
}

function Load-Config {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -Path $Path)) {
        throw "Ticketing config not found: $Path"
    }

    return (Get-Content -Path $Path -Raw | ConvertFrom-Json)
}

function Save-Config {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object]$Config
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -Path $parent)) {
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
    }

    $Config | ConvertTo-Json -Depth 6 | Set-Content -Path $Path -Encoding UTF8
}

function Build-TicketDescription {
    param(
        [Parameter(Mandatory = $false)]
        [string]$BaseDescription,

        [Parameter(Mandatory = $false)]
        [string]$System,

        [Parameter(Mandatory = $false)]
        [string]$Device,

        [Parameter(Mandatory = $false)]
        [string]$TicketStage,

        [Parameter(Mandatory = $false)]
        [string]$Scope,

        [Parameter(Mandatory = $false)]
        [int]$Code,

        [Parameter(Mandatory = $false)]
        [string]$TicketRing,

        [Parameter(Mandatory = $false)]
        [string]$Email
    )

    $lines = [System.Collections.Generic.List[string]]::new()

    if (-not [string]::IsNullOrWhiteSpace($BaseDescription)) {
        $lines.Add($BaseDescription)
        $lines.Add('')
    }

    $lines.Add('Windows11Debloat ticket metadata:')
    $lines.Add("System: $System")
    $lines.Add("Device: $Device")
    $lines.Add("Stage: $TicketStage")
    $lines.Add("CleanupScope: $Scope")
    $lines.Add("ExitCode: $Code")
    $lines.Add("Ring: $TicketRing")
    $lines.Add("NotificationEmail: $Email")
    $lines.Add("TimestampUtc: $((Get-Date).ToUniversalTime().ToString('o'))")

    return ($lines -join [Environment]::NewLine)
}

function Resolve-SystemApiHint {
    param(
        [Parameter(Mandatory = $false)]
        [string]$System
    )

    switch ($System) {
        'Atera' { return 'Use Atera PSA API v3 ticket endpoint or native alert-to-ticket automation.' }
        'NinjaRMM' { return 'Use NinjaOne ticketing API or policy-based alert ticket creation.' }
        'NinjaOne' { return 'Use NinjaOne ticketing API or policy-based alert ticket creation.' }
        'ServiceNow' { return 'Use ServiceNow Table API: /api/now/table/incident (or change_request).' }
        'Freshservice' { return 'Use Freshservice REST API: /api/v2/tickets.' }
        'Zendesk' { return 'Use Zendesk Tickets API: /api/v2/tickets.' }
        'ManageEngineSDP' { return 'Use ServiceDesk Plus API for request/ticket creation.' }
        'ConnectWiseManage' { return 'Use ConnectWise Manage service ticket endpoint.' }
        'AutotaskPSA' { return 'Use Autotask REST API ticket endpoint.' }
        'HaloITSM' { return 'Use HaloITSM API action for incident/ticket creation.' }
        'Other' { return 'Use your platform native ticket API/automation endpoint.' }
        default { return $null }
    }
}

function New-JiraIssue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true)]
        [string]$ProjectKey,

        [Parameter(Mandatory = $true)]
        [string]$IssueType,

        [Parameter(Mandatory = $true)]
        [string]$UserEmail,

        [Parameter(Mandatory = $true)]
        [string]$ApiToken,

        [Parameter(Mandatory = $true)]
        [string]$TicketSummary,

        [Parameter(Mandatory = $true)]
        [string]$TicketDescription,

        [Parameter(Mandatory = $false)]
        [switch]$WhatIfOnly
    )

    $jiraPayload = @{
        fields = @{
            project = @{ key = $ProjectKey }
            summary = $TicketSummary
            issuetype = @{ name = $IssueType }
            description = @{
                type = 'doc'
                version = 1
                content = @(
                    @{
                        type = 'paragraph'
                        content = @(
                            @{
                                type = 'text'
                                text = $TicketDescription
                            }
                        )
                    }
                )
            }
        }
    }

    $uri = "$($BaseUrl.TrimEnd('/'))/rest/api/3/issue"
    $jsonBody = $jiraPayload | ConvertTo-Json -Depth 10

    if ($WhatIfOnly) {
        Write-Host '[INFO] DryRun enabled. Jira payload preview:'
        Write-Host $jsonBody
        return
    }

    $authPlain = "$UserEmail`:$ApiToken"
    $authBytes = [System.Text.Encoding]::ASCII.GetBytes($authPlain)
    $authHeader = [Convert]::ToBase64String($authBytes)

    $headers = @{
        Authorization = "Basic $authHeader"
        Accept = 'application/json'
        'Content-Type' = 'application/json'
    }

    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $jsonBody
    Write-Host "[INFO] Jira ticket created: $($response.key)"
}

$configFilePath = Get-ConfigPath -InputPath $ConfigPath

if ($Action -eq 'Setup') {
    if ([string]::IsNullOrWhiteSpace($SystemName)) {
        throw 'SystemName is required for Setup.'
    }

    $config = [ordered]@{
        SystemName = $SystemName
        NotifyEmail = $NotifyEmail
        Jira = [ordered]@{
            BaseUrl = $JiraBaseUrl
            ProjectKey = $JiraProjectKey
            IssueType = $JiraIssueType
            UserEmail = $JiraUserEmail
            ApiToken = $JiraApiToken
        }
    }

    Save-Config -Path $configFilePath -Config $config
    Write-Host "[INFO] Ticketing config saved: $configFilePath"
    exit 0
}

if ($Action -eq 'ShowConfig') {
    $config = Load-Config -Path $configFilePath
    $safe = [ordered]@{
        SystemName = $config.SystemName
        NotifyEmail = $config.NotifyEmail
        Jira = [ordered]@{
            BaseUrl = $config.Jira.BaseUrl
            ProjectKey = $config.Jira.ProjectKey
            IssueType = $config.Jira.IssueType
            UserEmail = $config.Jira.UserEmail
            ApiToken = if ([string]::IsNullOrWhiteSpace([string]$config.Jira.ApiToken)) { '' } else { '***redacted***' }
        }
    }

    $safe | ConvertTo-Json -Depth 6
    exit 0
}

$config = Load-Config -Path $configFilePath

$effectiveSystem = if (-not [string]::IsNullOrWhiteSpace($SystemName)) { $SystemName } else { [string]$config.SystemName }
$effectiveEmail = if (-not [string]::IsNullOrWhiteSpace($NotifyEmail)) { $NotifyEmail } else { [string]$config.NotifyEmail }
$effectiveSummary = if (-not [string]::IsNullOrWhiteSpace($Summary)) { $Summary } else { 'Windows11Debloat rollout event' }
$effectiveDescription = Build-TicketDescription -BaseDescription $Description -System $effectiveSystem -Device $DeviceName -TicketStage $Stage -Scope $CleanupScope -Code $ExitCode -TicketRing $Ring -Email $effectiveEmail

if ($effectiveSystem -eq 'Jira') {
    $jiraBase = if (-not [string]::IsNullOrWhiteSpace($JiraBaseUrl)) { $JiraBaseUrl } else { [string]$config.Jira.BaseUrl }
    $jiraProject = if (-not [string]::IsNullOrWhiteSpace($JiraProjectKey)) { $JiraProjectKey } else { [string]$config.Jira.ProjectKey }
    $jiraType = if (-not [string]::IsNullOrWhiteSpace($JiraIssueType)) { $JiraIssueType } else { [string]$config.Jira.IssueType }
    $jiraUser = if (-not [string]::IsNullOrWhiteSpace($JiraUserEmail)) { $JiraUserEmail } else { [string]$config.Jira.UserEmail }
    $jiraToken = if (-not [string]::IsNullOrWhiteSpace($JiraApiToken)) { $JiraApiToken } else { [string]$config.Jira.ApiToken }

    if ([string]::IsNullOrWhiteSpace($jiraBase) -or [string]::IsNullOrWhiteSpace($jiraProject) -or [string]::IsNullOrWhiteSpace($jiraUser) -or [string]::IsNullOrWhiteSpace($jiraToken)) {
        throw 'Jira configuration incomplete. Set JiraBaseUrl, JiraProjectKey, JiraUserEmail, and JiraApiToken in Setup or parameters.'
    }

    New-JiraIssue -BaseUrl $jiraBase -ProjectKey $jiraProject -IssueType $jiraType -UserEmail $jiraUser -ApiToken $jiraToken -TicketSummary $effectiveSummary -TicketDescription $effectiveDescription -WhatIfOnly:$DryRun
    exit 0
}

# Non-Jira systems can still use this helper for consistent ticket content.
Write-Host "[INFO] System '$effectiveSystem' selected."
Write-Host '[INFO] Use the following payload content in your RMM/ITSM ticket creation action:'

$genericPayload = [ordered]@{
    SystemName = $effectiveSystem
    NotifyEmail = $effectiveEmail
    Summary = $effectiveSummary
    Description = $effectiveDescription
    Stage = $Stage
    CleanupScope = $CleanupScope
    ExitCode = $ExitCode
    Ring = $Ring
    DeviceName = $DeviceName
    ApiHint = (Resolve-SystemApiHint -System $effectiveSystem)
}

$genericPayload | ConvertTo-Json -Depth 6
exit 0
