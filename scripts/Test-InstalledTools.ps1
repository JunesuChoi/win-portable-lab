[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root,[ValidateSet('ko','en','auto')][string]$Language = 'auto')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Language = Resolve-WplLanguage -Root $Root -Requested $Language
$failures = @()
$rows = @()
$manifests = @(Get-ChildItem -LiteralPath (Join-Path $Root 'tools') -Filter 'INSTALL-MANIFEST.json' -File -Recurse)

foreach ($file in $manifests) {
    $manifest = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    $archive = Join-Path $Root $manifest.archive.path
    if (-not (Test-Path -LiteralPath $archive)) {
        $failures += "Missing archive: $($manifest.archive.path)"
        continue
    }
    $archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    if ($archiveHash -ne $manifest.archive.sha256) { $failures += "Archive hash mismatch: $($manifest.id)" }
    foreach ($exe in @($manifest.executables)) {
        $path = Join-Path $Root $exe.path
        if (-not (Test-Path -LiteralPath $path)) { $failures += "Missing executable: $($exe.path)"; continue }
        if ((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $exe.sha256) { $failures += "Executable hash mismatch: $($exe.path)" }
    }
    if ([IO.Path]::GetExtension($archive) -ieq '.zip') {
        & 7z.exe t $archive | Out-Null
        if ($LASTEXITCODE -ne 0) { $failures += "Archive integrity failed: $($manifest.id)" }
    }
    $rows += [pscustomobject]@{Id=$manifest.id;Version=$manifest.version;Trust=$manifest.trust;Executables=@($manifest.executables).Count;ArchiveSha256='OK'}
}

$rows | Sort-Object Id | Format-Table -AutoSize
if ($failures.Count) { $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }; exit 1 }
Write-Host (Get-WplText -Key InstalledValidationPassed -Language $Language -ArgumentList @($manifests.Count)) -ForegroundColor Green
exit 0
