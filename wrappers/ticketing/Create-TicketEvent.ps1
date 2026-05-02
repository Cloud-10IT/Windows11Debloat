[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Jira', 'Atera', 'NinjaRMM', 'NinjaOne', 'ServiceNow', 'Freshservice', 'Zendesk', 'ManageEngineSDP', 'ConnectWiseManage', 'AutotaskPSA', 'HaloITSM', 'Other')]
    [string]$SystemName,

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
    [string]$NotifyEmail,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [string]$JiraBaseUrl,

    [Parameter(Mandatory = $false)]
    [string]$JiraProjectKey,

    [Parameter(Mandatory = $false)]
    [string]$JiraIssueType,

    [Parameter(Mandatory = $false)]
    [string]$JiraUserEmail,

    [Parameter(Mandatory = $false)]
    [string]$JiraApiToken,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Path (Split-Path -Path $PSScriptRoot -Parent) -Parent
$helperPath = Join-Path -Path $repoRoot -ChildPath 'Ticketing-Setup.ps1'
if (-not (Test-Path -Path $helperPath)) {
    throw "Ticketing helper not found at '$helperPath'."
}

$params = @{
    Action = 'CreateTicket'
    SystemName = $SystemName
}

foreach ($name in @('Summary', 'Description', 'DeviceName', 'Stage', 'CleanupScope', 'ExitCode', 'Ring', 'NotifyEmail', 'ConfigPath')) {
    if ($PSBoundParameters.ContainsKey($name)) {
        $params[$name] = $PSBoundParameters[$name]
    }
}

if ($SystemName -eq 'Jira') {
    foreach ($name in @('JiraBaseUrl', 'JiraProjectKey', 'JiraIssueType', 'JiraUserEmail', 'JiraApiToken')) {
        if ($PSBoundParameters.ContainsKey($name)) {
            $params[$name] = $PSBoundParameters[$name]
        }
    }

    if ($DryRun) {
        $params.DryRun = $true
    }
}

& $helperPath @params
exit $LASTEXITCODE
