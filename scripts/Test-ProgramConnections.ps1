[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [Parameter(Mandatory)][string]$Path,
    [ValidateSet('ko','en','auto')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Language = Resolve-WplLanguage -Root $Root -Requested $Language
$failures = @()
$document = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
$launcherDocument = Get-Content -LiteralPath (Join-Path $Root 'config\tool-launchers.json') -Raw | ConvertFrom-Json
$launchers = @()
for ($index = 0; $index -lt $launcherDocument.Count; $index++) { $launchers += $launcherDocument[$index] }
$toolsRoot = [IO.Path]::GetFullPath((Join-Path $Root 'tools')).TrimEnd('\')

if ($document.kind -ne 'WinPortableLab-recommended-program-connections') { $failures += 'Invalid connection-plan kind.' }
if ($document.recommendationOnly -ne $true) { $failures += 'recommendationOnly must be true.' }
if ($document.autoLaunchAllowed -ne $false) { $failures += 'autoLaunchAllowed must be false.' }

foreach ($program in @($document.programs)) {
    $launcher = @($launchers | Where-Object { $_.id -eq $program.id }) | Select-Object -First 1
    if (-not $launcher) { $failures += "Unknown launcher id: $($program.id)"; continue }
    if ($program.catalogId -ne $launcher.catalogId) { $failures += "Catalog mismatch: $($program.id)" }
    if ($program.launchable) {
        if ([string]::IsNullOrWhiteSpace([string]$program.executable) -or -not (Test-Path -LiteralPath $program.executable)) { $failures += "Missing linked executable: $($program.id)"; continue }
        $resolvedExecutable = [IO.Path]::GetFullPath([string]$program.executable)
        if (-not $resolvedExecutable.StartsWith($toolsRoot + '\',[StringComparison]::OrdinalIgnoreCase)) { $failures += "Executable escaped tools root: $($program.id)" }
        if ([IO.Path]::GetExtension($resolvedExecutable) -ine '.exe') { $failures += "Linked program is not an executable: $($program.id)" }
    }
    if ([string]$program.risk -notmatch '^read-only' -and $program.command -and [string]$program.command -notmatch '-AcknowledgeRisk') { $failures += "Risk acknowledgement missing from command: $($program.id)" }
}

if ($failures.Count) { $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }; exit 1 }
Write-Host (Get-WplText -Key ProgramPlanValidationPassed -Language $Language -ArgumentList @(@($document.programs).Count)) -ForegroundColor Green
exit 0
