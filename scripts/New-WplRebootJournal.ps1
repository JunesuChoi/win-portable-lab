[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Workflow,
    [Parameter(Mandatory)][string]$NextAction,
    [string]$GuidePath,
    [switch]$AcknowledgeExternalChange
)

$ErrorActionPreference='Stop'
if(-not $AcknowledgeExternalChange){throw 'Creating a reboot journal requires -AcknowledgeExternalChange. This command never restarts Windows.'}
$journalRoot=Join-Path $Root 'sessions\reboot-journal'
New-Item -ItemType Directory -Path $journalRoot -Force | Out-Null
$id='{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),([guid]::NewGuid().ToString('N').Substring(0,8))
$path=Join-Path $journalRoot "$id.json"
[ordered]@{
    schemaVersion=1;journalId=$id;workflow=$Workflow;nextAction=$NextAction;guidePath=$GuidePath
    createdAt=(Get-Date).ToString('o');state='pending';restartRequestedByTool=$false
    warningKo='이 파일은 재부팅 후 수동 재개 위치만 기록하며 Windows를 재시작하거나 설정을 변경하지 않습니다.'
    warningEn='This file records only a manual post-reboot resume point. It does not restart Windows or change settings.'
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding utf8
Write-Host "Reboot journal created: $path"
