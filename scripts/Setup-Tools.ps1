[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Root,

    [string[]]$Id,

    [switch]$OpenSourcePages,
    [ValidateSet('ko','en','auto')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Language = Resolve-WplLanguage -Root $Root -Requested $Language
$catalogPath = Join-Path $Root 'catalog\tools.json'
$catalogDocument = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$catalog = @()
for ($index = 0; $index -lt $catalogDocument.Count; $index++) {
    $catalog += $catalogDocument[$index]
}
Write-Verbose "Loaded $($catalog.Count) catalog entries."

if ($Id) {
    $selectedIds = @(
        $Id |
            ForEach-Object { $_ -split ',' } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
    )
    Write-Verbose "Selected ids: $($selectedIds -join ', ')"
    $unknown = @($selectedIds | Where-Object { $_ -notin @($catalog.id) })
    if ($unknown.Count -gt 0) {
        throw (Get-WplText -Key UnknownToolId -Language $Language -ArgumentList @($unknown -join ', '))
    }
    $catalog = @($catalog | Where-Object { $selectedIds -contains [string]$_.id })
    Write-Verbose "Matched $($catalog.Count) catalog entries."
}

foreach ($tool in $catalog) {
    if ([string]::IsNullOrWhiteSpace([string]$tool.purposeFolder)) { throw "Missing purposeFolder for '$($tool.id)'." }
    $toolDirectory = Join-Path $Root "tools\$($tool.purposeFolder)\$($tool.id)"
    New-Item -ItemType Directory -Path $toolDirectory -Force | Out-Null

    $sourceRecord = [ordered]@{
        id = $tool.id
        name = $tool.name
        distribution = $tool.distribution
        officialSource = $tool.homepage
        license = $tool.license
        risk = $tool.risk
        automation = $tool.automation
        notes = $tool.notes
        preparedAt = (Get-Date).ToString('o')
    }
    $sourceRecord | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $toolDirectory 'SOURCE.json') -Encoding utf8

    $executables = @(Get-ChildItem -LiteralPath $toolDirectory -Filter '*.exe' -File -Recurse -ErrorAction SilentlyContinue)
    [pscustomobject]@{
        Id = $tool.id
        Distribution = $tool.distribution
        Executables = $executables.Count
        Directory = $toolDirectory
    }

    if ($OpenSourcePages) {
        Start-Process $tool.homepage
    }
}

Write-Host (Get-WplText -Key NoBinaryDownloaded -Language $Language) -ForegroundColor Yellow
Write-Host (Get-WplText -Key SetupHint -Language $Language)
