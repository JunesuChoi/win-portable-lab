[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [string]$OutputPath,
    [switch]$IncludeRedistributableArchives
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force
if (-not $OutputPath) { $OutputPath = Join-Path $Root ('offline-packs\WinPortableLab-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')) }
New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null

foreach ($name in @('WinPortableLab.ps1','Start.cmd','README.md','SECURITY.md','CONTRIBUTING.md','CHANGELOG.md','THIRD_PARTY_NOTICES.md')) {
    Copy-Item -LiteralPath (Join-Path $Root $name) -Destination $OutputPath -Force
}
foreach ($directory in @('catalog','config','docs','profiles','scripts','src','manifests')) {
    Copy-Item -LiteralPath (Join-Path $Root $directory) -Destination $OutputPath -Recurse -Force
}
foreach ($runtime in @('tools','downloads','reports','recommendations','sessions','logs')) {
    New-Item -ItemType Directory -Path (Join-Path $OutputPath $runtime) -Force | Out-Null
}

$lock = [System.Collections.Generic.List[object]]::new()
foreach ($definition in @(Get-WplPackageDefinitions -Root $Root)) {
    $archive = Join-Path $Root ('downloads\{0}' -f $definition.package.fileName)
    $entry = [ordered]@{
        packageId=$definition.packageId; catalogId=$definition.catalogId; version=$definition.version
        redistributable=[bool]$definition.redistribution.allowed; included=$false; status='not-requested'
        sha256=$definition.source.sha256
    }
    if ($definition.package.kind -eq 'user-supplied') { $entry.status='operator-supplied-no-archive' }
    elseif ($IncludeRedistributableArchives) {
        if (-not $definition.redistribution.allowed) { $entry.status='restricted-by-license' }
        elseif (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { $entry.status='cache-missing' }
        else {
            $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
            if ($actual -ne $definition.source.sha256) { $entry.status='hash-mismatch' }
            else {
                Copy-Item -LiteralPath $archive -Destination (Join-Path $OutputPath 'downloads') -Force
                $entry.included=$true; $entry.status='included-and-verified'
            }
        }
    }
    $lock.Add([pscustomobject]$entry)
}
$lockPath = Join-Path $OutputPath 'OFFLINE-PACK-LOCK.json'
[ordered]@{schemaVersion=1;createdAt=(Get-Date).ToString('o');archivesRequested=[bool]$IncludeRedistributableArchives;packages=$lock} |
    ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $lockPath -Encoding utf8
Write-Host "Offline pack: $OutputPath"
Write-Host "Lock file: $lockPath"
