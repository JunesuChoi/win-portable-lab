[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [string[]]$Area,
    [int[]]$ProcessId,
    [switch]$Report,
    [switch]$AcknowledgeRisk,
    [switch]$Json,
    [ValidateSet('ko','en','auto')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Root = (Resolve-Path -LiteralPath $Root).Path
$Language = Resolve-WplLanguage -Root $Root -Requested $Language
Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force
Import-Module (Join-Path $Root 'src\WinPortableLab.Memory.psm1') -Force
[void](Initialize-WplRuntimeDirectory -Root $Root)

$logDirectory = Join-Path $Root 'logs'
if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) { New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null }
$logPath = Join-Path $logDirectory ('memory-cleanup-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
$statsPath = Join-Path $logDirectory 'memory-cleanup-stats.json'

function Write-WplMemoryLog([object]$Value) {
    try { $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $logPath -Encoding utf8 } catch { }
}

try {
    # A report is deliberately available to standard users. It captures the
    # plan and current snapshot but does not call a native cleanup entry point.
    if (-not $Report -and -not (Test-WplAdministrator)) {
        throw (Get-WplText -Key MemoryNeedsAdmin -Language $Language)
    }
    $arguments = @{}
    if ($Area) { $arguments.Area = $Area }
    if ($ProcessId) { $arguments.ProcessId = $ProcessId }
    # A real run also appends to the running counters Mem Reduct keeps, so the
    # operator can see the run count and cumulative freed memory between boots.
    $result = Clear-WplSystemMemory @arguments -Report:$Report -AcknowledgeRisk:$AcknowledgeRisk -StatsPath $statsPath
    Write-WplMemoryLog $result

    if ($Json) {
        $result | ConvertTo-Json -Depth 12
        exit 0
    }

    $areaText = @($result.Requested.Areas) -join ', '
    if ($result.ReportOnly) {
        Write-Host (Get-WplText -Key MemoryReportReady -Language $Language -ArgumentList @($areaText)) -ForegroundColor Cyan
    }
    else {
        $completed = @($result.Performed).Count
        $skipped = @($result.Results | Where-Object { $_.Skipped }).Count
        $delta = if ($null -eq $result.DeltaBytes) { '-' } else { '{0:N2} MB' -f ([double]$result.DeltaBytes / 1MB) }
        Write-Host (Get-WplText -Key MemoryCleanupComplete -Language $Language -ArgumentList @($completed,$skipped,$delta)) -ForegroundColor Green
        if ($result.Statistics) {
            $statsText = Get-WplText -Key MemoryStatistics -Language $Language -ArgumentList @([int]$result.Statistics.runCount, ('{0:N2} MB' -f ([double]$result.Statistics.totalFreedBytes / 1MB)), ('{0:N2} MB' -f ([double]$result.Statistics.lastFreedBytes / 1MB)))
            Write-Host $statsText -ForegroundColor DarkCyan
        }
    }
    foreach ($entry in @($result.Results)) {
        $tone = if ($entry.ReportOnly) { 'DarkGray' } elseif ($entry.Success) { 'Green' } elseif ($entry.Skipped) { 'Yellow' } else { 'Red' }
        Write-Host ('[{0}] {1}: {2}' -f $(if($entry.ReportOnly){Get-WplText -Key MemoryPlan -Language $Language}elseif($entry.Success){Get-WplText -Key MemorySucceeded -Language $Language}elseif($entry.Skipped){Get-WplText -Key MemorySkipped -Language $Language}else{Get-WplText -Key MemoryFailed -Language $Language}),$entry.Id,$entry.Message) -ForegroundColor $tone
    }
    Write-Host (Get-WplText -Key MemoryLogWritten -Language $Language -ArgumentList @($logPath)) -ForegroundColor DarkGray
    exit 0
}
catch {
    $message = [string]$_.Exception.Message
    $failure = [pscustomobject][ordered]@{
        Requested = [ordered]@{ Areas = if($Area){@($Area)}else{@('Combined')}; ProcessIds = @($ProcessId) }
        Performed = @()
        ReportOnly = [bool]$Report
        Before = $null
        After = $null
        DeltaBytes = $null
        Results = @([pscustomobject][ordered]@{ Id='Clear-WplSystemMemory'; Success=$false; Skipped=$false; ReportOnly=[bool]$Report; Status=$null; StatusHex=$null; Message=$message; ProcessId=$null })
    }
    Write-WplMemoryLog $failure
    if ($Json) { $failure | ConvertTo-Json -Depth 12 } else { Write-Error (Get-WplText -Key MemoryCliFailed -Language $Language -ArgumentList @($message,$logPath)) }
    exit 1
}
