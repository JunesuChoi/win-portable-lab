[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Root,
    [ValidateSet('ko','en','auto')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Language = Resolve-WplLanguage -Root $Root -Requested $Language
$failures = [System.Collections.Generic.List[string]]::new()

function Add-Failure([string]$Message) {
    $failures.Add($Message)
}

function Test-PowerShellSourceEncoding([string]$Path) {
    $bytes=[IO.File]::ReadAllBytes($Path)
    $hasUtf8Bom=$bytes.Length-ge3-and$bytes[0]-eq0xEF-and$bytes[1]-eq0xBB-and$bytes[2]-eq0xBF
    try {
        $utf8=New-Object Text.UTF8Encoding($false,$true)
        $text=$utf8.GetString($bytes)
    }
    catch {
        Add-Failure "PowerShell source is not valid UTF-8: $Path"
        return
    }
    if($text-match'[^\x00-\x7F]'-and-not$hasUtf8Bom){
        Add-Failure "Non-ASCII PowerShell source requires a UTF-8 BOM for Windows PowerShell 5.1: $Path"
    }
    if($text-match'\uFFFD|\uC9A8|\u00C3|\u00C2\u00B7'){
        Add-Failure "Possible mojibake detected in PowerShell source: $Path"
    }
}

$catalogPath = Join-Path $Root 'catalog\tools.json'
# Runtime directories are not tracked in git, so validation creates them before
# asserting on their contents. Otherwise a fresh clone fails on absent output
# folders that the console would have created on first run anyway.
Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force
[void](Initialize-WplRuntimeDirectory -Root $Root)
try {
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
}
catch {
    Add-Failure "Invalid tool catalog: $($_.Exception.Message)"
    $catalog = @()
}

$required = @('id', 'name', 'category', 'purposeFolder', 'distribution', 'homepage', 'risk')
foreach ($tool in @($catalog)) {
    foreach ($field in $required) {
        if (-not $tool.PSObject.Properties.Name.Contains($field) -or [string]::IsNullOrWhiteSpace([string]$tool.$field)) {
            Add-Failure "Tool '$($tool.id)' is missing '$field'."
        }
    }
    if ($tool.homepage -notmatch '^https://') {
        Add-Failure "Tool '$($tool.id)' must use an HTTPS homepage."
    }
    if ($tool.purposeFolder -notmatch '^\d{2}-[A-Za-z0-9-]+$') {
        Add-Failure "Tool '$($tool.id)' has invalid purposeFolder '$($tool.purposeFolder)'."
    }
    if ($tool.distribution -eq 'bundled' -and -not (Test-Path -LiteralPath (Join-Path $Root "tools\$($tool.purposeFolder)\$($tool.id)"))) {
        Add-Failure "Bundled tool '$($tool.id)' has no tools directory."
    }
}

$definitionDirectory = Join-Path $Root 'manifests\tools'
try {
    Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force
    $definitions = @(Get-WplPackageDefinitions -Root $Root)
    if ($definitions.Count -eq 0) { Add-Failure 'No tool package definitions were found.' }
    $duplicates = @($definitions | Group-Object packageId | Where-Object Count -gt 1)
    if ($duplicates.Count) { Add-Failure "Duplicate package ids: $($duplicates.Name -join ', ')" }
    foreach ($definition in $definitions) {
        foreach ($field in @('packageId','catalogId','displayName','version','package','source','risk','redistribution','update')) {
            if (-not $definition.PSObject.Properties.Name.Contains($field) -or $null -eq $definition.$field) {
                Add-Failure "Package definition '$($definition.packageId)' is missing '$field'."
            }
        }
        if ($definition.catalogId -notin @($catalog.id)) { Add-Failure "Package '$($definition.packageId)' references unknown catalog id '$($definition.catalogId)'." }
        if ($definition.package.kind -notin @('zip','7z-sfx','exe','user-supplied')) { Add-Failure "Package '$($definition.packageId)' has invalid package kind." }
        $userSupplied = $definition.package.kind -eq 'user-supplied'
        if ($userSupplied -and $definition.source.trust -ne 'user-supplied-official') { Add-Failure "User-supplied package '$($definition.packageId)' must declare user-supplied-official trust." }
        if (-not $userSupplied -and [string]$definition.source.sha256 -notmatch '^[A-Fa-f0-9]{64}$') { Add-Failure "Package '$($definition.packageId)' must pin a SHA-256 hash." }
        if ([string]$definition.source.url -notmatch '^https://') {
            $httpException = $definition.source.url -match '^http://' -and $definition.source.trust -match 'signed-and-hash-pinned'
            if (-not $httpException) { Add-Failure "Package '$($definition.packageId)' uses an unsafe source URL." }
        }
        foreach ($riskField in @('highLoad','writesData','requiresAdmin','requiresReboot')) {
            if (-not $definition.risk.PSObject.Properties.Name.Contains($riskField) -or $definition.risk.$riskField -isnot [bool]) {
                Add-Failure "Package '$($definition.packageId)' has invalid risk field '$riskField'."
            }
        }
        if ($definition.update.strategy -notin @('github-release','rolling','manual')) { Add-Failure "Package '$($definition.packageId)' has invalid update strategy." }
    }
}
catch { Add-Failure "Invalid package definitions: $($_.Exception.Message)" }

$settingsPath = Join-Path $Root 'config\settings.json'
try {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if ($settings.language -notin @('ko','en')) { Add-Failure "config/settings.json language must be ko or en." }
    if (-not $settings.recommendationOnly) { Add-Failure "recommendationOnly must remain true." }
}
catch { Add-Failure "Invalid language settings: $($_.Exception.Message)" }

$launcherPath = Join-Path $Root 'config\tool-launchers.json'
try {
    $launcherDocument = Get-Content -LiteralPath $launcherPath -Raw | ConvertFrom-Json
    $launchers = @()
    for ($launcherIndex = 0; $launcherIndex -lt $launcherDocument.Count; $launcherIndex++) { $launchers += $launcherDocument[$launcherIndex] }
    $duplicateLaunchers = @($launchers | Group-Object id | Where-Object Count -gt 1)
    if ($duplicateLaunchers.Count) { Add-Failure "Duplicate launcher ids: $($duplicateLaunchers.Name -join ', ')" }
    foreach ($launcher in $launchers) {
        foreach ($field in @('id','catalogId','risk','launchMode')) {
            if ([string]::IsNullOrWhiteSpace([string]$launcher.$field)) { Add-Failure "Launcher '$($launcher.id)' is missing '$field'." }
        }
        if ($launcher.catalogId -notin @($catalog.id)) { Add-Failure "Launcher '$($launcher.id)' references unknown catalog id '$($launcher.catalogId)'." }
        if ($launcher.launchMode -ne 'external-boot' -and [string]::IsNullOrWhiteSpace([string]$launcher.pattern)) { Add-Failure "Launcher '$($launcher.id)' has no executable pattern." }
    }
}
catch { Add-Failure "Invalid launcher configuration: $($_.Exception.Message)" }

if ($launchers.Count -gt 0 -and $definitions.Count -gt 0) {
    foreach ($catalogTool in @($catalog)) {
        if ($catalogTool.id -notin @($definitions.catalogId)) { Add-Failure "Catalog tool '$($catalogTool.id)' has no package definition." }
        if ($catalogTool.id -notin @($launchers.catalogId)) { Add-Failure "Catalog tool '$($catalogTool.id)' has no launcher." }
    }
    foreach ($definition in @($definitions)) {
        if ($definition.catalogId -notin @($launchers.catalogId)) { Add-Failure "Package '$($definition.packageId)' has no launcher for catalog id '$($definition.catalogId)'." }
    }
}

Get-ChildItem -LiteralPath (Join-Path $Root 'scripts') -Filter '*.ps1' | ForEach-Object {
    Test-PowerShellSourceEncoding $_.FullName
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Add-Failure "PowerShell parse error in '$($_.Name)': $($parseError.Message)" }
}

Get-ChildItem -LiteralPath (Join-Path $Root 'src') -Include '*.ps1','*.psm1' -File -Recurse | ForEach-Object {
    Test-PowerShellSourceEncoding $_.FullName
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Add-Failure "PowerShell parse error in '$($_.Name)': $($parseError.Message)" }
}

Get-ChildItem -LiteralPath (Join-Path $Root 'tests') -Filter '*.ps1' -File -Recurse | ForEach-Object {
    Test-PowerShellSourceEncoding $_.FullName
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Add-Failure "PowerShell parse error in '$($_.Name)': $($parseError.Message)" }
}

$rootScript = Join-Path $Root 'WinPortableLab.ps1'
Test-PowerShellSourceEncoding $rootScript
$rootTokens = $null
$rootParseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($rootScript, [ref]$rootTokens, [ref]$rootParseErrors)
foreach ($parseError in @($rootParseErrors)) { Add-Failure "PowerShell parse error in 'WinPortableLab.ps1': $($parseError.Message)" }

foreach ($relativeDoc in @('docs\ko\README.md','docs\en\README.md','docs\ko\SETTING_GUIDE.md','docs\en\SETTING_GUIDE.md')) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $relativeDoc))) { Add-Failure "Missing KO/EN guide: $relativeDoc" }
}

$localizationPath = Join-Path $Root 'scripts\WinPortableLab.Localization.ps1'
try {
    $localizationSource = Get-Content -LiteralPath $localizationPath -Raw
    $declaredLocalizationKeys = @([regex]::Matches($localizationSource,'(?m)^\s*([A-Za-z][A-Za-z0-9]*)=@\{') | ForEach-Object { $_.Groups[1].Value })
    $pairedLocalizationEntries = @([regex]::Matches($localizationSource,'(?m)^\s*([A-Za-z][A-Za-z0-9]*)=@\{ko=(.+);en=(.+)\}\s*$'))
    if ($declaredLocalizationKeys.Count -eq 0) { Add-Failure 'No localization keys were detected.' }
    if ($pairedLocalizationEntries.Count -ne $declaredLocalizationKeys.Count) { Add-Failure 'Every localization key must contain non-empty KO and EN text on its canonical entry line.' }
    foreach ($entry in $pairedLocalizationEntries) {
        $key = $entry.Groups[1].Value
        $ko = $entry.Groups[2].Value
        $en = $entry.Groups[3].Value
        if ([string]::IsNullOrWhiteSpace($ko) -or [string]::IsNullOrWhiteSpace($en)) { Add-Failure "Localization key '$key' has an empty KO or EN value." }
        $koArguments = @([regex]::Matches($ko,'\{\d+\}') | ForEach-Object Value | Sort-Object -Unique)
        $enArguments = @([regex]::Matches($en,'\{\d+\}') | ForEach-Object Value | Sort-Object -Unique)
        if (($koArguments -join ',') -ne ($enArguments -join ',')) { Add-Failure "Localization key '$key' has mismatched KO/EN format placeholders." }
    }
    $productionSources = @($rootScript) + @(Get-ChildItem -LiteralPath (Join-Path $Root 'scripts') -Filter '*.ps1' -File | Where-Object Name -ne 'WinPortableLab.Localization.ps1' | ForEach-Object FullName) + @(Get-ChildItem -LiteralPath (Join-Path $Root 'src') -Include '*.ps1','*.psm1' -File -Recurse | ForEach-Object FullName)
    foreach ($productionPath in $productionSources) {
        $productionSource = Get-Content -LiteralPath $productionPath -Raw
        foreach ($match in [regex]::Matches($productionSource,'Get-WplText\s+-Key\s+([A-Za-z][A-Za-z0-9]*)')) {
            if ($match.Groups[1].Value -notin $declaredLocalizationKeys) { Add-Failure "Undefined localization key '$($match.Groups[1].Value)' in '$([IO.Path]::GetFileName($productionPath))'." }
        }
    }
}
catch { Add-Failure "Invalid localization contract: $($_.Exception.Message)" }

$ids = @($catalog | ForEach-Object id)
Get-ChildItem -LiteralPath (Join-Path $Root 'profiles') -Filter '*.json' | ForEach-Object {
    try {
        $profile = Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json
        foreach ($toolId in @($profile.tools)) {
            if ($toolId -notin $ids) {
                Add-Failure "Profile '$($_.Name)' references unknown tool '$toolId'."
            }
            elseif ($toolId -notin @($launchers.catalogId)) {
                Add-Failure "Profile '$($_.Name)' has no launcher for tool '$toolId'."
            }
        }
        $profileLaunchers = @($launchers | Where-Object { $_.catalogId -in @($profile.tools) })
        if (@($profileLaunchers | Where-Object { [string]$_.risk -notmatch '^read-only' }).Count -gt 0 -and $profile.requiresConfirmation -ne $true) {
            Add-Failure "Profile '$($_.Name)' contains risky tools but requiresConfirmation is not true."
        }
    }
    catch {
        Add-Failure "Invalid profile '$($_.Name)': $($_.Exception.Message)"
    }
}

if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}

Write-Host (Get-WplText -Key RepositoryValidationPassed -Language $Language -ArgumentList @(@($catalog).Count)) -ForegroundColor Green
exit 0
