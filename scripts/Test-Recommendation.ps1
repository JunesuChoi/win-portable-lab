[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Path,
    [ValidateSet('ko','en','auto')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Language = Resolve-WplLanguage -Root $Root -Requested $Language
$directory = if (Test-Path -LiteralPath $Path -PathType Container) { $Path } else { Split-Path $Path }
$jsonPath = if (Test-Path -LiteralPath $Path -PathType Leaf) { $Path } else { Join-Path $Path 'recommended-settings.json' }
$document = Get-Content -LiteralPath $jsonPath -Raw -Encoding utf8 | ConvertFrom-Json
$failures = @()

if ($document.kind -ne 'WinPortableLab-recommendation-only') { $failures += 'Invalid recommendation kind.' }
if ($document.applyAllowed -ne $false) { $failures += 'applyAllowed must be false.' }
if ($null -ne $document.recommendedSettings.cpu.manualVoltage) { $failures += 'manualVoltage must remain null.' }
if ($null -ne $document.recommendedSettings.cpu.fixedRatio) { $failures += 'fixedRatio must remain null.' }
if ($document.recommendedSettings.storage.rawDiskWrites -ne $false) { $failures += 'rawDiskWrites must be false.' }
if ($document.recommendedSettings.cpu.allowedCalculationErrors -ne 0 -or $document.recommendedSettings.memory.allowedErrors -ne 0) { $failures += 'Allowed error counts must be zero.' }
foreach ($code in @('ko','en')) {
    $guide = Join-Path $directory "recommended-settings.$code.md"
    if (-not (Test-Path -LiteralPath $guide) -or (Get-Item -LiteralPath $guide).Length -lt 100) { $failures += "Missing or empty $code guide." }
}
if ($failures.Count) { $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }; exit 1 }
Write-Host (Get-WplText -Key RecommendationValidationPassed -Language $Language -ArgumentList @($jsonPath)) -ForegroundColor Green
exit 0
