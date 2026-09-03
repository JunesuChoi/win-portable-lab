[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [ValidateSet('preview','apply')][string]$Action = 'preview',
    [switch]$ConfirmCleanup
)

$ErrorActionPreference = 'Stop'
$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$policyPath = Join-Path $resolvedRoot 'config\retention-policy.json'
if (-not (Test-Path -LiteralPath $policyPath)) { throw "Retention policy not found: $policyPath" }
$policy = Get-Content -LiteralPath $policyPath -Raw -Encoding utf8 | ConvertFrom-Json
$now = Get-Date
$candidates = [Collections.Generic.List[object]]::new()

function Add-WplRetentionCandidate([string]$Path,[string]$Category,[string]$Reason) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $files = @(Get-ChildItem -LiteralPath $Path -File -Recurse -Force -ErrorAction SilentlyContinue)
    $candidates.Add([pscustomobject]@{
        path = $Path
        category = $Category
        reason = $Reason
        fileCount = $files.Count
        bytes = [int64](($files | Measure-Object Length -Sum).Sum)
        lastWriteTime = (Get-Item -LiteralPath $Path).LastWriteTime.ToString('o')
    })
}

function Add-WplExpiredRunDirectories([string]$Relative,[object]$Rule) {
    $base = Join-Path $resolvedRoot $Relative
    if (-not (Test-Path -LiteralPath $base -PathType Container)) { return }
    $cutoff = $now.AddDays(-[int]$Rule.maxAgeDays)
    $runs = @(Get-ChildItem -LiteralPath $base -Directory -Force | Sort-Object LastWriteTime -Descending)
    for ($index = 0; $index -lt $runs.Count; $index++) {
        $run = $runs[$index]
        if (Test-Path -LiteralPath (Join-Path $run.FullName $policy.preserveMarkerFile)) { continue }
        if ($index -ge [int]$Rule.minimumNewestToKeep -and $run.LastWriteTime -lt $cutoff) {
            Add-WplRetentionCandidate -Path $run.FullName -Category $Relative -Reason ("older-than-{0}-days-and-outside-newest-{1}" -f $Rule.maxAgeDays,$Rule.minimumNewestToKeep)
        }
    }
}

function Add-WplExpiredLooseFiles([string]$Relative,[object]$Rule) {
    $base = Join-Path $resolvedRoot $Relative
    if (-not (Test-Path -LiteralPath $base -PathType Container)) { return }
    $cutoff = $now.AddDays(-[int]$Rule.maxAgeDays)
    Get-ChildItem -LiteralPath $base -File -Force | Where-Object { $_.LastWriteTime -lt $cutoff } | ForEach-Object {
        Add-WplRetentionCandidate -Path $_.FullName -Category $Relative -Reason ("older-than-{0}-days-loose-file" -f $Rule.maxAgeDays)
    }
}

Add-WplExpiredRunDirectories -Relative 'reports' -Rule $policy.reportAndRecommendation
Add-WplExpiredRunDirectories -Relative 'recommendations' -Rule $policy.reportAndRecommendation
Add-WplExpiredRunDirectories -Relative 'sessions' -Rule $policy.sessions
Add-WplExpiredLooseFiles -Relative 'reports' -Rule $policy.reportAndRecommendation
Add-WplExpiredLooseFiles -Relative 'recommendations' -Rule $policy.reportAndRecommendation
Add-WplExpiredLooseFiles -Relative 'sessions' -Rule $policy.sessions

$logs = Join-Path $resolvedRoot 'logs'
if (Test-Path -LiteralPath $logs -PathType Container) {
    $backups = @(Get-ChildItem -LiteralPath $logs -Directory -Filter 'self-update-backup-*' -Force | Sort-Object LastWriteTime -Descending)
    for ($index = [int]$policy.logs.keepSelfUpdateBackups; $index -lt $backups.Count; $index++) {
        Add-WplRetentionCandidate -Path $backups[$index].FullName -Category 'logs' -Reason ("outside-newest-{0}-self-update-backups" -f $policy.logs.keepSelfUpdateBackups)
    }
    $cutoff = $now.AddDays(-[int]$policy.logs.maxAgeDays)
    Get-ChildItem -LiteralPath $logs -File -Recurse -Force | Where-Object {
        $relative = $_.FullName.Substring($logs.Length).TrimStart('\')
        $inBackup = $relative -match '^self-update-backup-'
        $protected = @($policy.logs.alwaysKeepNamePatterns | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        $keep = $false
        foreach ($pattern in $protected) { if ($_.Name -like [string]$pattern) { $keep = $true; break } }
        (-not $inBackup) -and (-not $keep) -and $_.LastWriteTime -lt $cutoff
    } | ForEach-Object {
        Add-WplRetentionCandidate -Path $_.FullName -Category 'logs' -Reason ("older-than-{0}-days" -f $policy.logs.maxAgeDays)
    }
}

$summary = [ordered]@{
    schemaVersion = 1
    action = $Action
    generatedAt = $now.ToString('o')
    policyPath = $policyPath
    candidateCount = $candidates.Count
    candidateBytes = [int64](($candidates | Measure-Object bytes -Sum).Sum)
    candidates = @($candidates)
}
if ($Action -eq 'apply') {
    if (-not $ConfirmCleanup) { throw 'Cleanup requires -ConfirmCleanup after reviewing preview output.' }
    foreach ($candidate in $candidates) {
        $target = (Resolve-Path -LiteralPath $candidate.path).Path
        $allowed = @('reports','recommendations','sessions','logs') | ForEach-Object { Join-Path $resolvedRoot $_ }
        if (-not (@($allowed | Where-Object { $target.StartsWith($_,[StringComparison]::OrdinalIgnoreCase) }).Count)) { throw "Refusing cleanup outside runtime output: $target" }
        Remove-Item -LiteralPath $target -Recurse -Force
    }
    $summary.action = 'applied'
}
[pscustomobject]$summary | ConvertTo-Json -Depth 5 -Compress
