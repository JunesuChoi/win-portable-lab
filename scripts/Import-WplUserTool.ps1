[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Id,
    [Parameter(Mandatory)][string]$Path,
    [switch]$ConfirmOwnership,
    [ValidateSet('ko','en','auto')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Language = Resolve-WplLanguage -Root $Root -Requested $Language
Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force

if (-not $ConfirmOwnership) { throw (Get-WplText -Key UserToolImportConfirmRequired -Language $Language) }
$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$source = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
if ([IO.Path]::GetExtension($source) -ine '.exe') { throw (Get-WplText -Key UserPathNotExe -Language $Language -ArgumentList @($source)) }
$launchers = @(Read-WplJsonArray -Path (Join-Path $resolvedRoot 'config\tool-launchers.json'))
$launcher = @($launchers | Where-Object { [string]$_.id -eq $Id.Trim() }) | Select-Object -First 1
if (-not $launcher) { throw (Get-WplText -Key UserPathUnknownId -Language $Language -ArgumentList @($Id,(@($launchers.id) -join ', '))) }
$catalog = @(Read-WplJsonArray -Path (Join-Path $resolvedRoot 'catalog\tools.json'))
$tool = @($catalog | Where-Object { [string]$_.id -eq [string]$launcher.catalogId }) | Select-Object -First 1
if (-not $tool) { throw "Catalog entry missing for '$Id'." }

$toolsRoot = [IO.Path]::GetFullPath((Join-Path $resolvedRoot 'tools')).TrimEnd('\')
$sourceFull = [IO.Path]::GetFullPath($source)
if ($sourceFull.StartsWith($toolsRoot + '\',[StringComparison]::OrdinalIgnoreCase)) {
    throw (Get-WplText -Key UserToolImportAlreadyInside -Language $Language -ArgumentList @($sourceFull))
}
$importId = 'user-import-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$destination = Join-Path $resolvedRoot ("tools\{0}\{1}\{2}" -f $tool.purposeFolder,$tool.id,$importId)
New-Item -ItemType Directory -Path $destination -Force | Out-Null
$sourceDirectory = Split-Path -Parent $sourceFull
# Copy the selected executable's folder so adjacent DLL and configuration
# dependencies accompany a portable tool. The destination is always new.
Get-ChildItem -LiteralPath $sourceDirectory -Force | Copy-Item -Destination $destination -Recurse -Force
$importedExecutable = Join-Path $destination ([IO.Path]::GetFileName($sourceFull))
if (-not (Test-Path -LiteralPath $importedExecutable -PathType Leaf)) { throw "The imported executable was not found: $importedExecutable" }
$signature = Get-AuthenticodeSignature -LiteralPath $importedExecutable
[ordered]@{
    schemaVersion = 1; id = [string]$launcher.id; catalogId = [string]$tool.id
    importedAt = (Get-Date).ToString('o'); originalPath = $sourceFull
    importedExecutable = $importedExecutable.Substring($resolvedRoot.Length).TrimStart('\')
    sourceSha256 = (Get-FileHash -LiteralPath $sourceFull -Algorithm SHA256).Hash
    importedSha256 = (Get-FileHash -LiteralPath $importedExecutable -Algorithm SHA256).Hash
    signatureStatus = [string]$signature.Status
    signer = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
    copyScope = 'selected-executable-parent-directory'; userConfirmedOwnership = $true
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $destination 'USER-IMPORT-MANIFEST.json') -Encoding utf8
& (Join-Path $PSScriptRoot 'Set-WplToolPath.ps1') -Root $resolvedRoot -Action set -Id $launcher.id -Path $importedExecutable -Language $Language
Write-Host (Get-WplText -Key UserToolImportCompleted -Language $Language -ArgumentList @($tool.name,$destination)) -ForegroundColor Green
