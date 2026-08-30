[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root,[string]$JournalId,[switch]$MarkResumed)

$ErrorActionPreference='Stop'
$journalRoot=Join-Path $Root 'sessions\reboot-journal'
$journalFile=if($JournalId){Join-Path $journalRoot "$JournalId.json"}else{Get-ChildItem -LiteralPath $journalRoot -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName}
if(-not $journalFile -or -not (Test-Path -LiteralPath $journalFile)){throw 'No reboot journal was found.'}
$journal=Get-Content -LiteralPath $journalFile -Raw | ConvertFrom-Json
if($MarkResumed){
    $journal.state='resumed'
    $journal | Add-Member -NotePropertyName resumedAt -NotePropertyValue (Get-Date).ToString('o') -Force
    $journal | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $journalFile -Encoding utf8
}
$journal | Format-List journalId,workflow,nextAction,guidePath,state,createdAt,resumedAt
