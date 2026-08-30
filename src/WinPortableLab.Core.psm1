Set-StrictMode -Version Latest

function Read-WplJson {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "JSON file not found: $Path" }
    Get-Content -LiteralPath $Path -Raw -Encoding utf8 | ConvertFrom-Json
}

function Read-WplJsonArray {
    # ConvertFrom-Json on PowerShell 5.1 emits a JSON array as one object, so
    # @(Read-WplJson ...) collapses to a single element. Index explicitly instead.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $document = Read-WplJson -Path $Path
    $items = @()
    if ($null -eq $document) { return $items }
    for ($index = 0; $index -lt @($document).Count; $index++) { $items += $document[$index] }
    return $items
}

function Get-WplRuntimePaths {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    $resolved = (Resolve-Path -LiteralPath $Root).Path
    [pscustomobject]@{
        Root = $resolved
        Tools = Join-Path $resolved 'tools'
        Downloads = Join-Path $resolved 'downloads'
        Reports = Join-Path $resolved 'reports'
        Recommendations = Join-Path $resolved 'recommendations'
        Sessions = Join-Path $resolved 'sessions'
        Logs = Join-Path $resolved 'logs'
        PackageDefinitions = Join-Path $resolved 'manifests\tools'
    }
}

function Get-WplPackageDefinitions {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    $directory = Join-Path $Root 'manifests\tools'
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { throw "Package definition directory not found: $directory" }
    @(
        Get-ChildItem -LiteralPath $directory -Filter '*.json' -File | Sort-Object Name | ForEach-Object {
            $definition = Read-WplJson -Path $_.FullName
            $definition | Add-Member -NotePropertyName definitionPath -NotePropertyValue $_.FullName -Force
            $definition
        }
    )
}

function Test-WplAdministrator {
    [CmdletBinding()]
    param()
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Runtime output directories are created on demand instead of being tracked as
# empty placeholders, so a fresh clone carries only real content. Every entry is
# either gitignored output or the tools tree that Setup-Tools.ps1 populates.
function Initialize-WplRuntimeDirectory {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    $resolved = (Resolve-Path -LiteralPath $Root).Path
    $created = [Collections.Generic.List[string]]::new()
    foreach ($relative in @('tools','reports','recommendations','sessions','logs')) {
        $path = Join-Path $resolved $relative
        if (-not (Test-Path -LiteralPath $path -PathType Container)) {
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            $created.Add($relative)
        }
    }
    return @($created)
}

function Resolve-WplExecutable {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][object]$Launcher)
    # A user-supplied path wins over the bundled tools tree so an operator can
    # point the console at a copy they already own.
    $override = Get-WplToolOverride -Root $Root -LauncherId ([string]$Launcher.id)
    if ($override) { return $override }
    if ([string]::IsNullOrWhiteSpace([string]$Launcher.pattern)) { return $null }
    Get-ChildItem -LiteralPath (Join-Path $Root 'tools') -Filter '*.exe' -File -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $relative = $_.FullName.Substring($Root.Length).TrimStart('\')
            $relative -like "*\$($Launcher.pattern)" -or $_.Name -like $Launcher.pattern
        } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
}

function Get-WplToolOverridePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    Join-Path $Root 'config\user-tool-paths.json'
}

function Read-WplToolOverrides {
    # Returns a hashtable of launcherId -> declared path. Missing or malformed
    # files degrade to an empty map rather than breaking a diagnostic run.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root)
    $map = @{}
    $path = Get-WplToolOverridePath -Root $Root
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $map }
    try { $document = Read-WplJson -Path $path } catch { return $map }
    foreach ($entry in @(Read-WplJsonArray -Path $path)) {
        $id = [string]$entry.id
        $declared = [string]$entry.path
        if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($declared)) { continue }
        if ($entry.PSObject.Properties.Name -contains 'enabled' -and $entry.enabled -eq $false) { continue }
        $map[$id] = $declared
    }
    return $map
}

function Get-WplToolOverride {
    # Resolves one launcher override to a FileInfo, or $null when it is absent
    # or unusable. Only existing .exe files are accepted.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Root,[Parameter(Mandatory)][AllowEmptyString()][string]$LauncherId)
    if ([string]::IsNullOrWhiteSpace($LauncherId)) { return $null }
    $overrides = Read-WplToolOverrides -Root $Root
    if (-not $overrides.ContainsKey($LauncherId)) { return $null }
    $declared = [Environment]::ExpandEnvironmentVariables($overrides[$LauncherId])
    if (-not [IO.Path]::IsPathRooted($declared)) { $declared = Join-Path $Root $declared }
    if (-not (Test-Path -LiteralPath $declared -PathType Leaf)) { return $null }
    if ([IO.Path]::GetExtension($declared) -ine '.exe') { return $null }
    return Get-Item -LiteralPath $declared
}

Export-ModuleMember -Function Read-WplJson,Read-WplJsonArray,Get-WplRuntimePaths,Get-WplPackageDefinitions,Test-WplAdministrator,Initialize-WplRuntimeDirectory,Resolve-WplExecutable,Get-WplToolOverridePath,Read-WplToolOverrides,Get-WplToolOverride
