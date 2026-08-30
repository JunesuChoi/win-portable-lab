[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root)

$ErrorActionPreference = 'Stop'
$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\')
$toolsRoot = Join-Path $resolvedRoot 'tools'
$resolvedToolsRoot = (Resolve-Path -LiteralPath $toolsRoot).Path.TrimEnd('\')
$catalogDocument = Get-Content -LiteralPath (Join-Path $resolvedRoot 'catalog\tools.json') -Raw | ConvertFrom-Json
$catalog = @()
for ($index = 0; $index -lt $catalogDocument.Count; $index++) { $catalog += $catalogDocument[$index] }

foreach ($tool in $catalog) {
    if ([string]::IsNullOrWhiteSpace([string]$tool.purposeFolder)) { throw "Missing purposeFolder for '$($tool.id)'." }
    $source = Join-Path $resolvedToolsRoot $tool.id
    $purposeRoot = Join-Path $resolvedToolsRoot $tool.purposeFolder
    $destination = Join-Path $purposeRoot $tool.id

    $normalizedPurpose = [IO.Path]::GetFullPath($purposeRoot).TrimEnd('\')
    $normalizedDestination = [IO.Path]::GetFullPath($destination).TrimEnd('\')
    if (-not $normalizedPurpose.StartsWith($resolvedToolsRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Purpose path escaped tools root: $normalizedPurpose" }
    if (-not $normalizedDestination.StartsWith($normalizedPurpose + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Tool path escaped purpose folder: $normalizedDestination" }

    New-Item -ItemType Directory -Path $purposeRoot -Force | Out-Null
    if (Test-Path -LiteralPath $source) {
        if (Test-Path -LiteralPath $destination) { throw "Both source and destination exist for '$($tool.id)'." }
        Move-Item -LiteralPath $source -Destination $destination
        Write-Host "Moved $($tool.id) -> $($tool.purposeFolder)"
    }
}

$manifests = @(Get-ChildItem -LiteralPath $resolvedToolsRoot -Filter 'INSTALL-MANIFEST.json' -File -Recurse)
foreach ($manifestFile in $manifests) {
    $manifest = Get-Content -LiteralPath $manifestFile.FullName -Raw | ConvertFrom-Json
    $tool = @($catalog | Where-Object { $_.id -eq $manifest.id }) | Select-Object -First 1
    if (-not $tool) { throw "Manifest has unknown tool id '$($manifest.id)'." }
    $oldPrefix = "tools\$($manifest.id)\"
    $newPrefix = "tools\$($tool.purposeFolder)\$($manifest.id)\"
    foreach ($exe in @($manifest.executables)) {
        if ([string]$exe.path -like "$oldPrefix*") {
            $exe.path = $newPrefix + ([string]$exe.path).Substring($oldPrefix.Length)
        }
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestFile.FullName -Encoding utf8
}

Write-Host "Purpose layout ready. Tools: $($catalog.Count); manifests updated: $($manifests.Count)" -ForegroundColor Green
