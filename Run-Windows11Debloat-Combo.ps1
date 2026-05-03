[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Test', 'Deploy')]
    [string]$Stage = 'Test',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Device', 'User', 'All')]
    [string]$CleanupScope = 'Device',

    [Parameter(Mandatory = $false)]
    [string]$Vendor,

    [Parameter(Mandatory = $false)]
    [switch]$AutoDetect,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeCommon,

    [Parameter(Mandatory = $false)]
    [switch]$UseIntuneMode,

    [Parameter(Mandatory = $false)]
    [string]$ProfilesPath,

    [Parameter(Mandatory = $false)]
    [string]$ScriptPath

    ,
    [Parameter(Mandatory = $false)]
    [switch]$RecordTicketResult,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Jira', 'Atera', 'NinjaRMM', 'NinjaOne', 'ServiceNow', 'Freshservice', 'Zendesk', 'ManageEngineSDP', 'ConnectWiseManage', 'AutotaskPSA', 'HaloITSM', 'Other')]
    [string]$TicketSystem,

    [Parameter(Mandatory = $false)]
    [string]$TicketNotifyEmail,

    [Parameter(Mandatory = $false)]
    [string]$TicketRing,

    [Parameter(Mandatory = $false)]
    [string]$TicketingConfigPath,

    [Parameter(Mandatory = $false)]
    [switch]$EnableScheduledRerun,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$ScheduleIntervalDays = 30,

    [Parameter(Mandatory = $false)]
    [ValidateRange(0, 240)]
    [int]$ScheduleDelayMinutes = 45,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Interval', 'AfterWindowsUpdate', 'IntervalAndAfterWindowsUpdate', 'MonthlyDayOfWeek', 'MonthlyFixedDay')]
    [string]$ScheduleTriggerMode = 'IntervalAndAfterWindowsUpdate',

    [Parameter(Mandatory = $false)]
    [switch]$HasIntuneRemediationsLicense,

    [Parameter(Mandatory = $false)]
    [switch]$SkipScheduleRegistration,

    [Parameter(Mandatory = $false)]
    [switch]$AlsoRunAfterWindowsUpdate,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 28)]
    [int]$ScheduleDayOfMonth = 15,

    [Parameter(Mandatory = $false)]
    [ValidateSet('1', '2', '3', '4', 'Last')]
    [string]$ScheduleWeekOfMonth = '2',

    [Parameter(Mandatory = $false)]
    [ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')]
    [string]$ScheduleDayOfWeek = 'Wednesday'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ============================================================================
# EDIT BEFORE UPLOAD TO RMM
# Set defaults below when this file is uploaded directly in an RMM script job
# (NinjaOne, Atera, Action1, ConnectWise, or any RMM that cannot pass arguments).
# ============================================================================
$RmmDefaults = @{
    # --- Deployment options ---
    Stage              = 'Test'                        # 'Test' (pilot/dry-run) or 'Deploy' (production)
    CleanupScope       = 'Device'                      # 'Device', 'User', or 'All'
    Vendor             = ''                            # Example: 'Dell' — leave blank when AutoDetect = $true
    AutoDetect         = $true                         # $true to auto-detect vendor from WMI
    IncludeCommon      = $true                         # $true to also remove common cross-vendor bloat
    UseIntuneMode      = $false                        # $false for RMM; $true only if Intune staging behaviour is needed
    ProfilesPath       = ''                            # Example: 'C:\ProgramData\Windows11Debloat\vendor-profiles.json'
    ScriptPath         = ''                            # Example: 'C:\ProgramData\Windows11Debloat\Windows11Debloat.ps1'

    # --- Ticketing (agnostic) ---
    # Set RecordTicketResult = $true and choose any supported TicketSystem.
    # Supported values: Jira, ServiceNow, Freshservice, Zendesk, Atera,
    #                   NinjaOne, NinjaRMM, ManageEngineSDP, ConnectWiseManage,
    #                   AutotaskPSA, HaloITSM, Other
    RecordTicketResult  = $false                       # $true to create a ticket/event after each run
    TicketSystem        = ''                           # Example: 'ServiceNow'
    TicketNotifyEmail   = ''                           # Example: 'helpdesk@contoso.com'
    TicketRing          = ''                           # Example: 'Ring1'
    TicketingConfigPath = ''                           # Example: 'C:\ProgramData\Windows11Debloat\ticketing-config.json'
    EnableScheduledRerun        = $false               # $true to create a local fallback scheduled task for recurring reruns
    ScheduleIntervalDays        = 30                  # How often the fallback interval task runs
    ScheduleDelayMinutes        = 45                  # Delay before the first interval run and after Windows Update events
    ScheduleTriggerMode         = 'IntervalAndAfterWindowsUpdate' # Interval, AfterWindowsUpdate, or both
    HasIntuneRemediationsLicense = $false             # $true when licensed Intune Remediations will be used instead of local tasks
    AlsoRunAfterWindowsUpdate    = $false              # $true to also register the Windows Update event trigger alongside a monthly trigger
    ScheduleDayOfMonth           = 15                  # Day of month for MonthlyFixedDay trigger (1-28)
    ScheduleWeekOfMonth          = '2'                 # Week of month for MonthlyDayOfWeek trigger: '1','2','3','4','Last'
    ScheduleDayOfWeek            = 'Wednesday'         # Day of week for MonthlyDayOfWeek trigger: Monday-Sunday
    # Note: Jira REST API credentials are configured via Ticketing-Setup.ps1 -Action Setup
    # or set in ticketing-config.json. No Jira fields are needed here unless you use
    # Intune-Bootstrap-Windows11Debloat.ps1 which passes them directly.
}

if (-not $PSBoundParameters.ContainsKey('Stage')) { $Stage = $RmmDefaults.Stage }
if (-not $PSBoundParameters.ContainsKey('CleanupScope')) { $CleanupScope = $RmmDefaults.CleanupScope }
if (-not $PSBoundParameters.ContainsKey('Vendor')) { $Vendor = $RmmDefaults.Vendor }
if (-not $PSBoundParameters.ContainsKey('AutoDetect')) { $AutoDetect = $RmmDefaults.AutoDetect }
if (-not $PSBoundParameters.ContainsKey('IncludeCommon')) { $IncludeCommon = $RmmDefaults.IncludeCommon }
if (-not $PSBoundParameters.ContainsKey('UseIntuneMode')) { $UseIntuneMode = $RmmDefaults.UseIntuneMode }
if (-not $PSBoundParameters.ContainsKey('ProfilesPath')) { $ProfilesPath = $RmmDefaults.ProfilesPath }
if (-not $PSBoundParameters.ContainsKey('ScriptPath')) { $ScriptPath = $RmmDefaults.ScriptPath }
if (-not $PSBoundParameters.ContainsKey('RecordTicketResult')) { $RecordTicketResult = $RmmDefaults.RecordTicketResult }
if (-not $PSBoundParameters.ContainsKey('TicketSystem')) { $TicketSystem = $RmmDefaults.TicketSystem }
if (-not $PSBoundParameters.ContainsKey('TicketNotifyEmail')) { $TicketNotifyEmail = $RmmDefaults.TicketNotifyEmail }
if (-not $PSBoundParameters.ContainsKey('TicketRing')) { $TicketRing = $RmmDefaults.TicketRing }
if (-not $PSBoundParameters.ContainsKey('TicketingConfigPath')) { $TicketingConfigPath = $RmmDefaults.TicketingConfigPath }
if (-not $PSBoundParameters.ContainsKey('EnableScheduledRerun')) { $EnableScheduledRerun = $RmmDefaults.EnableScheduledRerun }
if (-not $PSBoundParameters.ContainsKey('ScheduleIntervalDays')) { $ScheduleIntervalDays = $RmmDefaults.ScheduleIntervalDays }
if (-not $PSBoundParameters.ContainsKey('ScheduleDelayMinutes')) { $ScheduleDelayMinutes = $RmmDefaults.ScheduleDelayMinutes }
if (-not $PSBoundParameters.ContainsKey('ScheduleTriggerMode')) { $ScheduleTriggerMode = $RmmDefaults.ScheduleTriggerMode }
if (-not $PSBoundParameters.ContainsKey('HasIntuneRemediationsLicense')) { $HasIntuneRemediationsLicense = $RmmDefaults.HasIntuneRemediationsLicense }
if (-not $PSBoundParameters.ContainsKey('AlsoRunAfterWindowsUpdate')) { $AlsoRunAfterWindowsUpdate = $RmmDefaults.AlsoRunAfterWindowsUpdate }
if (-not $PSBoundParameters.ContainsKey('ScheduleDayOfMonth')) { $ScheduleDayOfMonth = $RmmDefaults.ScheduleDayOfMonth }
if (-not $PSBoundParameters.ContainsKey('ScheduleWeekOfMonth')) { $ScheduleWeekOfMonth = $RmmDefaults.ScheduleWeekOfMonth }
if (-not $PSBoundParameters.ContainsKey('ScheduleDayOfWeek')) { $ScheduleDayOfWeek = $RmmDefaults.ScheduleDayOfWeek }

function Resolve-RootPath {
    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        return $PSScriptRoot
    }

    if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
        return Split-Path -Path $PSCommandPath -Parent
    }

    return (Get-Location).Path
}

function Resolve-HostExecutable {
    if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) {
        return 'pwsh.exe'
    }

    if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
        return 'powershell.exe'
    }

    throw 'Unable to find pwsh.exe or powershell.exe in PATH.'
}

function Format-ArgumentForPreview {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($Value -match '[\s"]') {
        return '"' + ($Value -replace '"', '\"') + '"'
    }

    return $Value
}

function Invoke-TicketResultRecording {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [int]$DebloatExitCode,

        [Parameter(Mandatory = $true)]
        [string]$RunStage,

        [Parameter(Mandatory = $true)]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$DebloatCommand
    )

    $ticketScriptPath = Join-Path -Path $RootPath -ChildPath 'Ticketing-Setup.ps1'
    if (-not (Test-Path -Path $ticketScriptPath)) {
        Write-Host "[WARN] Ticket result recording requested, but ticket helper was not found at '$ticketScriptPath'."
        return
    }

    $status = if ($DebloatExitCode -eq 0) { 'Success' } else { 'Failure' }
    $deviceName = $env:COMPUTERNAME
    if ([string]::IsNullOrWhiteSpace($deviceName)) {
        $deviceName = 'UnknownDevice'
    }

    $summary = "Windows11Debloat $status - $deviceName - Stage:$RunStage Scope:$Scope Exit:$DebloatExitCode"
    $description = "Command: $DebloatCommand"

    $ticketParams = @{
        Action = 'CreateTicket'
        Summary = $summary
        Description = $description
        DeviceName = $deviceName
        Stage = $RunStage
        CleanupScope = $Scope
        ExitCode = $DebloatExitCode
    }

    if (-not [string]::IsNullOrWhiteSpace($TicketRing)) {
        $ticketParams.Ring = $TicketRing
    }

    if (-not [string]::IsNullOrWhiteSpace($TicketSystem)) {
        $ticketParams.SystemName = $TicketSystem
    }

    if (-not [string]::IsNullOrWhiteSpace($TicketNotifyEmail)) {
        $ticketParams.NotifyEmail = $TicketNotifyEmail
    }

    if (-not [string]::IsNullOrWhiteSpace($TicketingConfigPath)) {
        $ticketParams.ConfigPath = $TicketingConfigPath
    }

    try {
        & $ticketScriptPath @ticketParams
        Write-Host '[INFO] Ticket result recording completed.'
    }
    catch {
        Write-Host "[WARN] Ticket result recording failed. $($_.Exception.Message)"
    }
}

function Get-RecurringTaskDefinitions {
    return @(
        @{ Name = 'Windows11Debloat-Recurring'; Kind = 'Interval' },
        @{ Name = 'Windows11Debloat-AfterWindowsUpdate'; Kind = 'AfterWindowsUpdate' },
        @{ Name = 'Windows11Debloat-MonthlyDayOfWeek'; Kind = 'MonthlyDayOfWeek' },
        @{ Name = 'Windows11Debloat-MonthlyFixedDay'; Kind = 'MonthlyFixedDay' }
    )
}

function Remove-RecurringTasks {
    foreach ($taskDefinition in (Get-RecurringTaskDefinitions)) {
        $taskName = $taskDefinition.Name
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($null -ne $task) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
            Write-Host "[INFO] Removed scheduled task: $taskName"
        }
    }
}

function Get-TaskHostExecutable {
    $powershellPath = Join-Path -Path $env:WINDIR -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (Test-Path -Path $powershellPath) {
        return $powershellPath
    }

    return 'powershell.exe'
}

function Convert-ArgumentListToCommandLine {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.List[string]]$Arguments
    )

    return (($Arguments | ForEach-Object { Format-ArgumentForPreview -Value $_ }) -join ' ')
}

function Get-ComboTaskArguments {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ComboPath,

        [Parameter(Mandatory = $true)]
        [string]$RunStage,

        [Parameter(Mandatory = $true)]
        [string]$Scope,

        [Parameter(Mandatory = $false)]
        [string]$ResolvedVendor,

        [Parameter(Mandatory = $true)]
        [bool]$UseAutoDetect,

        [Parameter(Mandatory = $true)]
        [bool]$UseCommonProfile,

        [Parameter(Mandatory = $true)]
        [bool]$IsIntuneMode,

        [Parameter(Mandatory = $false)]
        [string]$ResolvedProfilesPath,

        [Parameter(Mandatory = $true)]
        [bool]$ShouldRecordTicketResult,

        [Parameter(Mandatory = $false)]
        [string]$ResolvedTicketSystem,

        [Parameter(Mandatory = $false)]
        [string]$ResolvedTicketNotifyEmail,

        [Parameter(Mandatory = $false)]
        [string]$ResolvedTicketRing,

        [Parameter(Mandatory = $false)]
        [string]$ResolvedTicketingConfigPath
    )

    $taskArgs = [System.Collections.Generic.List[string]]::new()
    $taskArgs.Add('-NoProfile')
    $taskArgs.Add('-ExecutionPolicy')
    $taskArgs.Add('Bypass')
    $taskArgs.Add('-File')
    $taskArgs.Add($ComboPath)
    $taskArgs.Add('-Stage')
    $taskArgs.Add($RunStage)
    $taskArgs.Add('-CleanupScope')
    $taskArgs.Add($Scope)

    if ($UseAutoDetect -or [string]::IsNullOrWhiteSpace($ResolvedVendor)) {
        $taskArgs.Add('-AutoDetect')
    }
    else {
        $taskArgs.Add('-Vendor')
        $taskArgs.Add($ResolvedVendor)
    }

    if ($UseCommonProfile) {
        $taskArgs.Add('-IncludeCommon')
    }

    if ($IsIntuneMode) {
        $taskArgs.Add('-UseIntuneMode')
    }

    if (-not [string]::IsNullOrWhiteSpace($ResolvedProfilesPath)) {
        $taskArgs.Add('-ProfilesPath')
        $taskArgs.Add($ResolvedProfilesPath)
    }

    if ($ShouldRecordTicketResult) {
        $taskArgs.Add('-RecordTicketResult')
        if (-not [string]::IsNullOrWhiteSpace($ResolvedTicketSystem)) {
            $taskArgs.Add('-TicketSystem')
            $taskArgs.Add($ResolvedTicketSystem)
        }
        if (-not [string]::IsNullOrWhiteSpace($ResolvedTicketNotifyEmail)) {
            $taskArgs.Add('-TicketNotifyEmail')
            $taskArgs.Add($ResolvedTicketNotifyEmail)
        }
        if (-not [string]::IsNullOrWhiteSpace($ResolvedTicketRing)) {
            $taskArgs.Add('-TicketRing')
            $taskArgs.Add($ResolvedTicketRing)
        }
        if (-not [string]::IsNullOrWhiteSpace($ResolvedTicketingConfigPath)) {
            $taskArgs.Add('-TicketingConfigPath')
            $taskArgs.Add($ResolvedTicketingConfigPath)
        }
    }

    $taskArgs.Add('-SkipScheduleRegistration')
    return $taskArgs
}

function Register-IntervalRecurringTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskName,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string]$Arguments,

        [Parameter(Mandatory = $true)]
        [int]$IntervalDays,

        [Parameter(Mandatory = $true)]
        [int]$DelayMinutes
    )

    $startAt = (Get-Date).AddMinutes([Math]::Max($DelayMinutes, 1))
    $trigger = New-ScheduledTaskTrigger -Daily -DaysInterval $IntervalDays -At $startAt
    $action = New-ScheduledTaskAction -Execute $Command -Argument $Arguments
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest

    Register-ScheduledTask -TaskName $TaskName -Trigger $trigger -Action $action -Settings $settings -Principal $principal -Force | Out-Null
    Write-Host "[INFO] Registered interval scheduled task: $TaskName (every $IntervalDays day(s))"
}

function Register-WindowsUpdateRecurringTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TaskName,

        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string]$Arguments,

        [Parameter(Mandatory = $true)]
        [int]$DelayMinutes
    )

    $subscription = @'
<QueryList>
  <Query Id="0" Path="System">
    <Select Path="System">*[System[Provider[@Name='Microsoft-Windows-WindowsUpdateClient'] and (EventID=19 or EventID=43 or EventID=44)]]</Select>
  </Query>
</QueryList>
'@

    $escapedCommand = [System.Security.SecurityElement]::Escape($Command)
    $escapedArguments = [System.Security.SecurityElement]::Escape($Arguments)
    $escapedSubscription = [System.Security.SecurityElement]::Escape($subscription.Trim())
        $delayElement = if ($DelayMinutes -gt 0) {
                "      <Delay>PT${DelayMinutes}M</Delay>`r`n"
        }
        else {
                ''
        }

        $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
    <RegistrationInfo>
        <Description>Runs Windows11Debloat after Windows Update completion events.</Description>
    </RegistrationInfo>
    <Triggers>
        <EventTrigger>
$delayElement      <Enabled>true</Enabled>
            <Subscription>$escapedSubscription</Subscription>
        </EventTrigger>
    </Triggers>
    <Principals>
        <Principal id="Author">
            <UserId>S-1-5-18</UserId>
            <LogonType>ServiceAccount</LogonType>
            <RunLevel>HighestAvailable</RunLevel>
        </Principal>
    </Principals>
    <Settings>
        <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
        <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
        <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
        <AllowHardTerminate>true</AllowHardTerminate>
        <StartWhenAvailable>true</StartWhenAvailable>
        <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
        <IdleSettings>
            <StopOnIdleEnd>false</StopOnIdleEnd>
            <RestartOnIdle>false</RestartOnIdle>
        </IdleSettings>
        <AllowStartOnDemand>true</AllowStartOnDemand>
        <Enabled>true</Enabled>
        <Hidden>false</Hidden>
        <RunOnlyIfIdle>false</RunOnlyIfIdle>
        <WakeToRun>false</WakeToRun>
        <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
        <Priority>7</Priority>
    </Settings>
    <Actions Context="Author">
        <Exec>
            <Command>$escapedCommand</Command>
            <Arguments>$escapedArguments</Arguments>
        </Exec>
    </Actions>
</Task>
"@

        $tempXmlPath = Join-Path -Path $env:TEMP -ChildPath ("Windows11Debloat-ScheduledTask-" + [Guid]::NewGuid().ToString('N') + '.xml')

        try {
                Set-Content -Path $tempXmlPath -Value $taskXml -Encoding Unicode
                & schtasks.exe /Create /TN $TaskName /XML $tempXmlPath /F | Out-Null
                if ($LASTEXITCODE -ne 0) {
                        throw "schtasks.exe returned exit code $LASTEXITCODE while creating '$TaskName'."
                }

                Write-Host "[INFO] Registered Windows Update scheduled task: $TaskName"
        }
        finally {
                if (Test-Path -Path $tempXmlPath) {
                        Remove-Item -Path $tempXmlPath -Force -ErrorAction SilentlyContinue
        }
        }
}

function Register-MonthlyDayOfWeekRecurringTask {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [Parameter(Mandatory = $true)][int]$DelayMinutes,
        [Parameter(Mandatory = $true)][ValidateSet('1','2','3','4','Last')][string]$WeekOfMonth,
        [Parameter(Mandatory = $true)][ValidateSet('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')][string]$DayOfWeek
    )

    $weekXml          = if ($WeekOfMonth -eq 'Last') { '<Last />' } else { "<Week>$WeekOfMonth</Week>" }
    $dayXml           = "<$DayOfWeek />"
    $escapedCommand   = [System.Security.SecurityElement]::Escape($Command)
    $escapedArguments = [System.Security.SecurityElement]::Escape($Arguments)
    $startBoundary    = Get-Date -Format 'yyyy-MM-ddT09:00:00'
    $delayElement     = if ($DelayMinutes -gt 0) { "      <Delay>PT${DelayMinutes}M</Delay>`r`n" } else { '' }

    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
    <RegistrationInfo>
        <Description>Runs Windows11Debloat on the $WeekOfMonth $DayOfWeek of every month.</Description>
    </RegistrationInfo>
    <Triggers>
        <CalendarTrigger>
$delayElement            <StartBoundary>$startBoundary</StartBoundary>
            <Enabled>true</Enabled>
            <ScheduleByMonthDayOfWeek>
                <Weeks>$weekXml</Weeks>
                <DaysOfWeek>$dayXml</DaysOfWeek>
                <Months>
                    <January /><February /><March /><April /><May /><June />
                    <July /><August /><September /><October /><November /><December />
                </Months>
            </ScheduleByMonthDayOfWeek>
        </CalendarTrigger>
    </Triggers>
    <Principals>
        <Principal id="Author">
            <UserId>S-1-5-18</UserId>
            <LogonType>ServiceAccount</LogonType>
            <RunLevel>HighestAvailable</RunLevel>
        </Principal>
    </Principals>
    <Settings>
        <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
        <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
        <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
        <AllowHardTerminate>true</AllowHardTerminate>
        <StartWhenAvailable>true</StartWhenAvailable>
        <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
        <IdleSettings>
            <StopOnIdleEnd>false</StopOnIdleEnd>
            <RestartOnIdle>false</RestartOnIdle>
        </IdleSettings>
        <AllowStartOnDemand>true</AllowStartOnDemand>
        <Enabled>true</Enabled>
        <Hidden>false</Hidden>
        <RunOnlyIfIdle>false</RunOnlyIfIdle>
        <WakeToRun>false</WakeToRun>
        <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
        <Priority>7</Priority>
    </Settings>
    <Actions Context="Author">
        <Exec>
            <Command>$escapedCommand</Command>
            <Arguments>$escapedArguments</Arguments>
        </Exec>
    </Actions>
</Task>
"@

    $tempXmlPath = Join-Path -Path $env:TEMP -ChildPath ("Windows11Debloat-ScheduledTask-" + [Guid]::NewGuid().ToString('N') + '.xml')
    try {
        Set-Content -Path $tempXmlPath -Value $taskXml -Encoding Unicode
        & schtasks.exe /Create /TN $TaskName /XML $tempXmlPath /F | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "schtasks.exe returned exit code $LASTEXITCODE while creating '$TaskName'."
        }
        Write-Host "[INFO] Registered monthly day-of-week scheduled task: $TaskName (week $WeekOfMonth, $DayOfWeek)"
    }
    finally {
        if (Test-Path -Path $tempXmlPath) {
            Remove-Item -Path $tempXmlPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Register-MonthlyFixedDayRecurringTask {
    param(
        [Parameter(Mandatory = $true)][string]$TaskName,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$Arguments,
        [Parameter(Mandatory = $true)][int]$DelayMinutes,
        [Parameter(Mandatory = $true)][ValidateRange(1, 28)][int]$DayOfMonth
    )

    $escapedCommand   = [System.Security.SecurityElement]::Escape($Command)
    $escapedArguments = [System.Security.SecurityElement]::Escape($Arguments)
    $startBoundary    = Get-Date -Format 'yyyy-MM-ddT09:00:00'
    $delayElement     = if ($DelayMinutes -gt 0) { "      <Delay>PT${DelayMinutes}M</Delay>`r`n" } else { '' }

    $taskXml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
    <RegistrationInfo>
        <Description>Runs Windows11Debloat on day $DayOfMonth of every month.</Description>
    </RegistrationInfo>
    <Triggers>
        <CalendarTrigger>
$delayElement            <StartBoundary>$startBoundary</StartBoundary>
            <Enabled>true</Enabled>
            <ScheduleByMonth>
                <DaysOfMonth><Day>$DayOfMonth</Day></DaysOfMonth>
                <Months>
                    <January /><February /><March /><April /><May /><June />
                    <July /><August /><September /><October /><November /><December />
                </Months>
            </ScheduleByMonth>
        </CalendarTrigger>
    </Triggers>
    <Principals>
        <Principal id="Author">
            <UserId>S-1-5-18</UserId>
            <LogonType>ServiceAccount</LogonType>
            <RunLevel>HighestAvailable</RunLevel>
        </Principal>
    </Principals>
    <Settings>
        <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
        <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
        <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
        <AllowHardTerminate>true</AllowHardTerminate>
        <StartWhenAvailable>true</StartWhenAvailable>
        <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
        <IdleSettings>
            <StopOnIdleEnd>false</StopOnIdleEnd>
            <RestartOnIdle>false</RestartOnIdle>
        </IdleSettings>
        <AllowStartOnDemand>true</AllowStartOnDemand>
        <Enabled>true</Enabled>
        <Hidden>false</Hidden>
        <RunOnlyIfIdle>false</RunOnlyIfIdle>
        <WakeToRun>false</WakeToRun>
        <ExecutionTimeLimit>PT2H</ExecutionTimeLimit>
        <Priority>7</Priority>
    </Settings>
    <Actions Context="Author">
        <Exec>
            <Command>$escapedCommand</Command>
            <Arguments>$escapedArguments</Arguments>
        </Exec>
    </Actions>
</Task>
"@

    $tempXmlPath = Join-Path -Path $env:TEMP -ChildPath ("Windows11Debloat-ScheduledTask-" + [Guid]::NewGuid().ToString('N') + '.xml')
    try {
        Set-Content -Path $tempXmlPath -Value $taskXml -Encoding Unicode
        & schtasks.exe /Create /TN $TaskName /XML $tempXmlPath /F | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "schtasks.exe returned exit code $LASTEXITCODE while creating '$TaskName'."
        }
        Write-Host "[INFO] Registered monthly fixed-day scheduled task: $TaskName (day $DayOfMonth)"
    }
    finally {
        if (Test-Path -Path $tempXmlPath) {
            Remove-Item -Path $tempXmlPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Register-RecurringTasksIfNeeded {
        param(
                [Parameter(Mandatory = $true)]
                [string]$ComboPath,

                [Parameter(Mandatory = $true)]
                [string]$RunStage,

                [Parameter(Mandatory = $true)]
                [string]$Scope,

                [Parameter(Mandatory = $false)]
                [string]$ResolvedVendor,

                [Parameter(Mandatory = $true)]
                [bool]$UseAutoDetect,

                [Parameter(Mandatory = $true)]
                [bool]$UseCommonProfile,

                [Parameter(Mandatory = $true)]
                [bool]$IsIntuneMode,

                [Parameter(Mandatory = $false)]
                [string]$ResolvedProfilesPath,

            [Parameter(Mandatory = $true)]
            [bool]$ShouldRecordTicketResult,

                [Parameter(Mandatory = $false)]
                [string]$ResolvedTicketSystem,

                [Parameter(Mandatory = $false)]
                [string]$ResolvedTicketNotifyEmail,

                [Parameter(Mandatory = $false)]
                [string]$ResolvedTicketRing,

            [Parameter(Mandatory = $false)]
            [string]$ResolvedTicketingConfigPath
            )

        if ($SkipScheduleRegistration) {
                Write-Host '[INFO] Schedule registration skipped for this run.'
                return
        }

        if ($HasIntuneRemediationsLicense) {
                Remove-RecurringTasks
                Write-Host '[INFO] Intune Remediations license enabled. Local fallback scheduled tasks are not used.'
                return
        }

        if (-not $EnableScheduledRerun) {
                return
        }

        if ($RunStage -ne 'Deploy') {
                Write-Host '[WARN] Scheduled rerun registration is only applied for Stage=Deploy. Skipping for Test stage.'
                return
        }

        $taskHostExecutable = Get-TaskHostExecutable
        $taskArguments = Get-ComboTaskArguments -ComboPath $ComboPath -RunStage $RunStage -Scope $Scope -ResolvedVendor $ResolvedVendor -UseAutoDetect $UseAutoDetect -UseCommonProfile $UseCommonProfile -IsIntuneMode $IsIntuneMode -ResolvedProfilesPath $ResolvedProfilesPath -ShouldRecordTicketResult $ShouldRecordTicketResult -ResolvedTicketSystem $ResolvedTicketSystem -ResolvedTicketNotifyEmail $ResolvedTicketNotifyEmail -ResolvedTicketRing $ResolvedTicketRing -ResolvedTicketingConfigPath $ResolvedTicketingConfigPath
        $taskArgumentLine = Convert-ArgumentListToCommandLine -Arguments $taskArguments

        Remove-RecurringTasks

        if ($ScheduleTriggerMode -in @('Interval', 'IntervalAndAfterWindowsUpdate')) {
                Register-IntervalRecurringTask -TaskName 'Windows11Debloat-Recurring' -Command $taskHostExecutable -Arguments $taskArgumentLine -IntervalDays $ScheduleIntervalDays -DelayMinutes $ScheduleDelayMinutes
        }

        if ($ScheduleTriggerMode -in @('AfterWindowsUpdate', 'IntervalAndAfterWindowsUpdate') -or
            ($ScheduleTriggerMode -in @('MonthlyDayOfWeek', 'MonthlyFixedDay') -and $AlsoRunAfterWindowsUpdate)) {
                Register-WindowsUpdateRecurringTask -TaskName 'Windows11Debloat-AfterWindowsUpdate' -Command $taskHostExecutable -Arguments $taskArgumentLine -DelayMinutes $ScheduleDelayMinutes
        }

        if ($ScheduleTriggerMode -eq 'MonthlyDayOfWeek') {
                Register-MonthlyDayOfWeekRecurringTask -TaskName 'Windows11Debloat-MonthlyDayOfWeek' -Command $taskHostExecutable -Arguments $taskArgumentLine -DelayMinutes $ScheduleDelayMinutes -WeekOfMonth $ScheduleWeekOfMonth -DayOfWeek $ScheduleDayOfWeek
        }

        if ($ScheduleTriggerMode -eq 'MonthlyFixedDay') {
                Register-MonthlyFixedDayRecurringTask -TaskName 'Windows11Debloat-MonthlyFixedDay' -Command $taskHostExecutable -Arguments $taskArgumentLine -DelayMinutes $ScheduleDelayMinutes -DayOfMonth $ScheduleDayOfMonth
        }
}

$root = Resolve-RootPath
$resolvedScriptPath = if ([string]::IsNullOrWhiteSpace($ScriptPath)) {
    Join-Path -Path $root -ChildPath 'Windows11Debloat.ps1'
}
else {
    $ScriptPath
}

if (-not (Test-Path -Path $resolvedScriptPath)) {
    throw "Debloat script not found at '$resolvedScriptPath'."
}

$argList = [System.Collections.Generic.List[string]]::new()
$argList.Add('-NoProfile')
$argList.Add('-ExecutionPolicy')
$argList.Add('Bypass')
$argList.Add('-File')
$argList.Add($resolvedScriptPath)

if ($AutoDetect -or [string]::IsNullOrWhiteSpace($Vendor)) {
    $argList.Add('-AutoDetect')
}
else {
    $argList.Add('-Vendor')
    $argList.Add($Vendor)
}

if ($IncludeCommon -or -not $PSBoundParameters.ContainsKey('IncludeCommon')) {
    $argList.Add('-IncludeCommon')
}

$argList.Add('-CleanupScope')
$argList.Add($CleanupScope)

if (-not [string]::IsNullOrWhiteSpace($ProfilesPath)) {
    $argList.Add('-ProfilesPath')
    $argList.Add($ProfilesPath)
}

if ($UseIntuneMode) {
    $argList.Add('-IntuneMode')
}

if ($Stage -eq 'Test') {
    $argList.Add('-HelpdeskMode')
    $argList.Add('-DryRun')
    $argList.Add('-QuietDryRun')
}
else {
    $argList.Add('-HelpdeskMode')
}

$hostExecutable = Resolve-HostExecutable
$commandPreview = $hostExecutable + ' ' + (($argList | ForEach-Object { Format-ArgumentForPreview -Value $_ }) -join ' ')
$comboTaskPath = if (-not [string]::IsNullOrWhiteSpace($PSCommandPath)) { $PSCommandPath } else { Join-Path -Path $root -ChildPath 'Run-Windows11Debloat-Combo.ps1' }

if ($Stage -eq 'Test' -and -not $RecordTicketResult -and -not [string]::IsNullOrWhiteSpace($TicketNotifyEmail)) {
    $RecordTicketResult = $true
    Write-Host '[INFO] Test stage detected with TicketNotifyEmail configured. Enabling RecordTicketResult automatically.'
}

Write-Host '[INFO] Effective combo settings:'
Write-Host "[INFO]   Stage: $Stage"
Write-Host "[INFO]   CleanupScope: $CleanupScope"
Write-Host "[INFO]   VendorMode: $(if ($AutoDetect -or [string]::IsNullOrWhiteSpace($Vendor)) { 'AutoDetect' } else { 'Vendor' })"
Write-Host "[INFO]   Vendor: $(if ([string]::IsNullOrWhiteSpace($Vendor)) { '<not-set>' } else { $Vendor })"
Write-Host "[INFO]   IncludeCommon: $([bool]$IncludeCommon)"
Write-Host "[INFO]   UseIntuneMode: $([bool]$UseIntuneMode)"
Write-Host "[INFO]   ProfilesPath: $(if ([string]::IsNullOrWhiteSpace($ProfilesPath)) { '<default>' } else { $ProfilesPath })"
Write-Host "[INFO]   ScriptPath: $resolvedScriptPath"
Write-Host "[INFO]   RecordTicketResult: $([bool]$RecordTicketResult)"
Write-Host "[INFO]   TicketSystem: $(if ([string]::IsNullOrWhiteSpace($TicketSystem)) { '<not-set>' } else { $TicketSystem })"
Write-Host "[INFO]   TicketNotifyEmail: $(if ([string]::IsNullOrWhiteSpace($TicketNotifyEmail)) { '<not-set>' } else { $TicketNotifyEmail })"
Write-Host "[INFO]   TicketRing: $(if ([string]::IsNullOrWhiteSpace($TicketRing)) { '<not-set>' } else { $TicketRing })"
Write-Host "[INFO]   TicketingConfigPath: $(if ([string]::IsNullOrWhiteSpace($TicketingConfigPath)) { '<default>' } else { $TicketingConfigPath })"
Write-Host "[INFO]   EnableScheduledRerun: $([bool]$EnableScheduledRerun)"
Write-Host "[INFO]   ScheduleIntervalDays: $ScheduleIntervalDays"
Write-Host "[INFO]   ScheduleDelayMinutes: $ScheduleDelayMinutes"
Write-Host "[INFO]   ScheduleTriggerMode: $ScheduleTriggerMode"
Write-Host "[INFO]   HasIntuneRemediationsLicense: $([bool]$HasIntuneRemediationsLicense)"
Write-Host "[INFO]   AlsoRunAfterWindowsUpdate: $([bool]$AlsoRunAfterWindowsUpdate)"
Write-Host "[INFO]   ScheduleWeekOfMonth: $ScheduleWeekOfMonth"
Write-Host "[INFO]   ScheduleDayOfWeek: $ScheduleDayOfWeek"
Write-Host "[INFO]   ScheduleDayOfMonth: $ScheduleDayOfMonth"
Write-Host "[INFO] Stage: $Stage"
Write-Host "[INFO] Command: $commandPreview"

if (-not $SkipScheduleRegistration -and $HasIntuneRemediationsLicense) {
    Register-RecurringTasksIfNeeded -ComboPath $comboTaskPath -RunStage $Stage -Scope $CleanupScope -ResolvedVendor $Vendor -UseAutoDetect ([bool]$AutoDetect -or [string]::IsNullOrWhiteSpace($Vendor)) -UseCommonProfile ([bool]$IncludeCommon -or -not $PSBoundParameters.ContainsKey('IncludeCommon')) -IsIntuneMode ([bool]$UseIntuneMode) -ResolvedProfilesPath $ProfilesPath -ShouldRecordTicketResult ([bool]$RecordTicketResult) -ResolvedTicketSystem $TicketSystem -ResolvedTicketNotifyEmail $TicketNotifyEmail -ResolvedTicketRing $TicketRing -ResolvedTicketingConfigPath $TicketingConfigPath
}

& $hostExecutable @argList
$exitCode = $LASTEXITCODE

if ($null -eq $exitCode) {
    $exitCode = 0
}

if ($RecordTicketResult) {
    Invoke-TicketResultRecording -RootPath $root -DebloatExitCode $exitCode -RunStage $Stage -Scope $CleanupScope -DebloatCommand $commandPreview
}

if ($exitCode -eq 0 -and -not $HasIntuneRemediationsLicense) {
    Register-RecurringTasksIfNeeded -ComboPath $comboTaskPath -RunStage $Stage -Scope $CleanupScope -ResolvedVendor $Vendor -UseAutoDetect ([bool]$AutoDetect -or [string]::IsNullOrWhiteSpace($Vendor)) -UseCommonProfile ([bool]$IncludeCommon -or -not $PSBoundParameters.ContainsKey('IncludeCommon')) -IsIntuneMode ([bool]$UseIntuneMode) -ResolvedProfilesPath $ProfilesPath -ShouldRecordTicketResult ([bool]$RecordTicketResult) -ResolvedTicketSystem $TicketSystem -ResolvedTicketNotifyEmail $TicketNotifyEmail -ResolvedTicketRing $TicketRing -ResolvedTicketingConfigPath $TicketingConfigPath
}

Write-Host "[INFO] Exit code: $exitCode"
exit $exitCode
