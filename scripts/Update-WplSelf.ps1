[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [ValidateSet('check','apply')][string]$Action = 'check',
    [string]$Repository = 'JunesuChoi/win-portable-lab',
    [string]$Branch = 'main',
    [int]$WaitForProcessId,
    [switch]$Restart
)

# The updater deliberately has no configurable URL.  It only accepts the
# project's canonical GitHub repository, and never touches tools, downloads,
# reports, logs, sessions, or per-machine configuration.
$ErrorActionPreference = 'Stop'
$canonicalRepository = 'JunesuChoi/win-portable-lab'
if ($Repository -ne $canonicalRepository) { throw "Unsupported update repository: $Repository" }
$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$logs = Join-Path $resolvedRoot 'logs'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$statePath = Join-Path $logs 'installed-revision.json'

function Get-WplInstalledRevision {
    $revision = $null
    if (Test-Path -LiteralPath $statePath) {
        try {
            $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
            $revision = [string]$state.commit
            # State written by the first self-updater build used availableCommit.
            # Keep that successful update recognised when upgrading this script.
            if (-not $revision) { $revision = [string]$state.availableCommit }
        } catch { }
    }
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $revision -and $git -and (Test-Path -LiteralPath (Join-Path $resolvedRoot '.git'))) {
        $revision = @(& $git.Source -C $resolvedRoot rev-parse HEAD 2>$null | Select-Object -First 1)[0]
    }
    return $revision
}

function Get-WplRemoteCommit {
    $headers = @{ Accept='application/vnd.github+json'; 'User-Agent'='WinPortableLab-self-update' }
    $commit = Invoke-RestMethod -Uri ("https://api.github.com/repos/{0}/commits/{1}" -f $canonicalRepository,$Branch) -Headers $headers
    if (-not $commit.sha -or ([string]$commit.sha -notmatch '^[0-9a-f]{40}$')) { throw 'GitHub returned an invalid commit identifier.' }
    return [pscustomobject]@{ Commit=[string]$commit.sha; Message=[string]$commit.commit.message; Url=[string]$commit.html_url }
}

function Copy-WplUpdateDirectory([string]$Source,[string]$Destination,[string]$BackupRoot) {
    if (Test-Path -LiteralPath $Destination) {
        Copy-Item -LiteralPath $Destination -Destination (Join-Path $BackupRoot ([IO.Path]::GetFileName($Destination))) -Recurse -Force
    }
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

$remote = Get-WplRemoteCommit
$installed = Get-WplInstalledRevision
$result = [ordered]@{
    schemaVersion = 1
    repository = $canonicalRepository
    branch = $Branch
    commit = $remote.Commit
    installedCommit = $installed
    availableCommit = $remote.Commit
    status = if ($installed -eq $remote.Commit) { 'current' } else { 'update-available' }
    message = $remote.Message
    url = $remote.Url
    updatedAt = $null
    backupPath = $null
}
if ($Action -eq 'check') { [pscustomobject]$result | ConvertTo-Json -Depth 4 -Compress; return }

if ($WaitForProcessId -gt 0) {
    $running = Get-Process -Id $WaitForProcessId -ErrorAction SilentlyContinue
    if ($running) { $running | Wait-Process }
}

# Re-check just before writing: the archive name is the exact SHA seen above.
$archive = Join-Path $logs ('self-update-' + $remote.Commit + '.zip')
$staging = Join-Path $logs ('self-update-staging-' + [guid]::NewGuid().ToString('N'))
$backup = Join-Path $logs ('self-update-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
try {
    Invoke-WebRequest -Uri ("https://codeload.github.com/{0}/zip/{1}" -f $canonicalRepository,$remote.Commit) -OutFile $archive -UseBasicParsing
    Expand-Archive -LiteralPath $archive -DestinationPath $staging -Force
    $sourceRoot = @(Get-ChildItem -LiteralPath $staging -Directory | Select-Object -First 1)[0].FullName
    if (-not $sourceRoot -or -not (Test-Path -LiteralPath (Join-Path $sourceRoot 'WinPortableLab.ps1'))) { throw 'The downloaded update archive has no WinPortableLab root.' }
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($directory in @('.github','bin','catalog','docs','manifests','profiles','scripts','src','tests')) {
        $source = Join-Path $sourceRoot $directory
        if (Test-Path -LiteralPath $source) { Copy-WplUpdateDirectory -Source $source -Destination (Join-Path $resolvedRoot $directory) -BackupRoot $backup }
    }
    foreach ($file in @('.gitignore','CHANGELOG.md','CONTRIBUTING.md','LICENSE','README.md','SECURITY.md','Start.cmd','THIRD_PARTY_NOTICES.md','WinPortableLab.ps1','package.json')) {
        $source = Join-Path $sourceRoot $file
        if (Test-Path -LiteralPath $source) {
            $destination = Join-Path $resolvedRoot $file
            if (Test-Path -LiteralPath $destination) { Copy-Item -LiteralPath $destination -Destination $backup -Force }
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }
    foreach ($configFile in @('tool-launchers.json','stop-conditions.json','retention-policy.json')) {
        $source = Join-Path $sourceRoot ('config\\' + $configFile)
        if (Test-Path -LiteralPath $source) {
            $destination = Join-Path $resolvedRoot ('config\\' + $configFile)
            $backupConfig = Join-Path $backup 'config'
            New-Item -ItemType Directory -Path $backupConfig -Force | Out-Null
            if (Test-Path -LiteralPath $destination) { Copy-Item -LiteralPath $destination -Destination $backupConfig -Force }
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }
    $result.status = 'updated'
    $result.updatedAt = (Get-Date).ToString('o')
    $result.backupPath = $backup
    [pscustomobject]$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding utf8
    if ($Restart) { Start-Process -FilePath (Join-Path $resolvedRoot 'Start.cmd') }
    [pscustomobject]$result | ConvertTo-Json -Depth 4 -Compress
}
finally {
    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue }
    if (Test-Path -LiteralPath $archive) { Remove-Item -LiteralPath $archive -Force -ErrorAction SilentlyContinue }
}
