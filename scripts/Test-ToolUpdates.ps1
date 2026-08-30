[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [string[]]$Id,
    [switch]$Online
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force
$definitions = @(Get-WplPackageDefinitions -Root $Root)
if ($Id) {
    $wanted = @($Id | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() })
    $definitions = @($definitions | Where-Object { $_.packageId -in $wanted -or $_.catalogId -in $wanted })
}

$results = foreach ($definition in $definitions) {
    $latest = $null
    $status = if ($definition.update.strategy -eq 'manual') { 'manual-check-required' } elseif (-not $Online) { 'online-check-not-requested' } else { 'check-unavailable' }
    $detail = ''
    if ($Online -and $definition.update.strategy -eq 'github-release' -and $definition.source.url -match '^https://github\.com/([^/]+)/([^/]+)/releases/') {
        try {
            $release = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/{1}/releases/latest" -f $Matches[1],$Matches[2]) -Headers @{Accept='application/vnd.github+json';'User-Agent'='WinPortableLab'}
            $latest = [string]$release.tag_name
            $status = if ($latest.TrimStart('v','V') -eq ([string]$definition.version).TrimStart('v','V')) { 'current' } else { 'update-candidate' }
            $detail = [string]$release.html_url
        }
        catch { $status = 'check-failed'; $detail = $_.Exception.Message }
    }
    elseif ($Online -and $definition.update.strategy -eq 'rolling') {
        $status = 'rolling-source-hash-review-required'
        $detail = 'Rolling packages require download, hash comparison, and maintainer approval.'
    }
    [pscustomobject]@{
        packageId=$definition.packageId; installedVersion=$definition.version; latestVersion=$latest
        strategy=$definition.update.strategy; status=$status; detail=$detail
    }
}

$output = Join-Path $Root ('reports\tool-update-check-{0}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path (Split-Path $output -Parent) -Force | Out-Null
$results | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $output -Encoding utf8
$results | Format-Table -AutoSize
Write-Host "Report: $output"
