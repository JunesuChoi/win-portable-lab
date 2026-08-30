[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [string[]]$Id,
    [switch]$IncludeHighLoad,
    [switch]$ListOnly,
    [ValidateSet('ko','en','auto')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force
$Language = Resolve-WplLanguage -Root $Root -Requested $Language

function Normalize-Ids([string[]]$Values) {
    if (-not $Values) { return @() }
    @($Values | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
}

function Expand-WplZipArchive([string]$ArchivePath, [string]$DestinationPath) {
    # Expand-Archive rejects entries whose names contain characters that are
    # illegal for the current file system, which some vendor packages include.
    # Extract through the .NET API and skip only the unusable entries.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $invalid = [IO.Path]::GetInvalidFileNameChars()
    $skipped = @()
    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        $root = [IO.Path]::GetFullPath($DestinationPath).TrimEnd('\')
        foreach ($entry in $zip.Entries) {
            if ([string]::IsNullOrEmpty($entry.Name)) { continue }
            $unusable = $false
            foreach ($char in $invalid) { if ($entry.Name.IndexOf($char) -ge 0) { $unusable = $true; break } }
            if ($unusable) { $skipped += $entry.FullName; continue }
            $target = [IO.Path]::GetFullPath((Join-Path $DestinationPath $entry.FullName))
            if (-not $target.StartsWith($root + '\',[StringComparison]::OrdinalIgnoreCase)) { throw "Archive entry escapes the destination: $($entry.FullName)" }
            $parent = Split-Path -Parent $target
            if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$true)
        }
    }
    finally { $zip.Dispose() }
    if ($skipped.Count) { Write-Host ("Skipped {0} archive entries with file-system-illegal names." -f $skipped.Count) -ForegroundColor Yellow }
}

function Download-File([object]$Package, [string]$Destination) {
    $arguments = @('--http1.1','-L','--fail','--retry','3','--connect-timeout','20','--max-time','900','-sS')
    if ($Package.source.form) {
        $body = (($Package.source.form.PSObject.Properties | ForEach-Object {
            '{0}={1}' -f [uri]::EscapeDataString([string]$_.Name), [uri]::EscapeDataString([string]$_.Value)
        }) -join '&')
        $arguments += @('-d',$body)
    }
    if ($Package.source.referer) { $arguments += @('-e',[string]$Package.source.referer) }
    $arguments += @('-A','Mozilla/5.0 (Windows NT 10.0; Win64; x64)','-H','Accept: */*')
    $arguments += @('-o',$Destination,'-w','%{url_effective}',[string]$Package.source.url)
    $resolved = & curl.exe @arguments
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Destination)) {
        throw (Get-WplText -Key DownloadFailed -Language $Language -ArgumentList @($Package.source.url))
    }
    [string]$resolved
}

$packages = @(Get-WplPackageDefinitions -Root $Root)
$wanted = Normalize-Ids $Id
if ($wanted.Count) {
    $knownIds = @($packages.packageId) + @($packages.catalogId)
    $unknown = @($wanted | Where-Object { $_ -notin $knownIds })
    if ($unknown.Count) { throw (Get-WplText -Key UnknownDownloadId -Language $Language -ArgumentList @($unknown -join ', ')) }
    $packages = @($packages | Where-Object { $_.packageId -in $wanted -or $_.catalogId -in $wanted })
}
if (-not $IncludeHighLoad) { $packages = @($packages | Where-Object { -not $_.risk.highLoad }) }
if ($ListOnly) {
    $packages | Select-Object packageId,catalogId,version,@{n='highLoad';e={$_.risk.highLoad}},@{n='source';e={$_.source.url}} | Format-Table -AutoSize
    return
}

$downloadRoot = Join-Path $Root 'downloads'
New-Item -ItemType Directory -Path $downloadRoot -Force | Out-Null
$catalog = @((Get-Content -LiteralPath (Join-Path $Root 'catalog\tools.json') -Raw | ConvertFrom-Json))
$results = @()

foreach ($package in $packages) {
    $catalogTool = @($catalog | Where-Object { $_.id -eq $package.catalogId }) | Select-Object -First 1
    if (-not $catalogTool -or [string]::IsNullOrWhiteSpace([string]$catalogTool.purposeFolder)) {
        throw "Missing purposeFolder for '$($package.catalogId)'."
    }
    $target = Join-Path $Root ("tools\{0}\{1}\{2}" -f $catalogTool.purposeFolder,$package.catalogId,$package.version)
    $archive = Join-Path $downloadRoot $package.package.fileName
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Write-Host (Get-WplText -Key Downloading -Language $Language -ArgumentList @($package.packageId,$package.version)) -ForegroundColor Cyan
    $resolved = Download-File $package $archive
    $hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if ($package.source.sha256 -and $hash -ne $package.source.sha256) {
        throw (Get-WplText -Key HashMismatch -Language $Language -ArgumentList @($package.packageId,$hash))
    }

    switch ([string]$package.package.kind) {
        'zip' { Expand-WplZipArchive -ArchivePath $archive -DestinationPath $target }
        '7z-sfx' {
            & 7z.exe x $archive ("-o{0}" -f $target) -y | Out-Null
            if ($LASTEXITCODE -ne 0) { throw (Get-WplText -Key ExtractFailed -Language $Language -ArgumentList @($package.packageId)) }
        }
        default { Copy-Item -LiteralPath $archive -Destination (Join-Path $target $package.package.fileName) -Force }
    }

    $executables = @(Get-ChildItem -LiteralPath $target -Filter '*.exe' -File -Recurse -ErrorAction SilentlyContinue)
    $exeInfo = @($executables | ForEach-Object {
        $signature = Get-AuthenticodeSignature -LiteralPath $_.FullName
        [ordered]@{
            path = $_.FullName.Substring($Root.Length).TrimStart('\')
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
            signatureStatus = [string]$signature.Status
            signer = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { $null }
            fileVersion = $_.VersionInfo.FileVersion
        }
    })
    $manifest = [ordered]@{
        id = $package.catalogId
        packageId = $package.packageId
        version = $package.version
        trust = $package.source.trust
        sourceUrl = $package.source.url
        resolvedUrl = $resolved
        downloadedAt = (Get-Date).ToString('o')
        archive = [ordered]@{
            path = $archive.Substring($Root.Length).TrimStart('\')
            bytes = (Get-Item $archive).Length
            sha256 = $hash
            expectedSha256 = $package.source.sha256
        }
        executables = $exeInfo
        highLoad = [bool]$package.risk.highLoad
        executionTested = $false
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $target 'INSTALL-MANIFEST.json') -Encoding utf8
    $results += [pscustomobject]@{Id=$package.packageId;Version=$package.version;Executables=$executables.Count;Sha256=$hash;Path=$target}
}

$results | Format-Table -AutoSize
Write-Host (Get-WplText -Key DownloadSafe -Language $Language) -ForegroundColor Yellow
