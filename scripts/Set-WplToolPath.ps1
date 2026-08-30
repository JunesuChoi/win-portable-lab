[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [ValidateSet('list','set','remove','verify')][string]$Action = 'list',
    [string]$Id,
    [string]$Path,
    [ValidateSet('ko','en','auto')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Language = Resolve-WplLanguage -Root $Root -Requested $Language
Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force
Import-Module (Join-Path $Root 'src\WinPortableLab.Process.psm1') -Force

$overridePath = Get-WplToolOverridePath -Root $Root
$launchers = @(Read-WplJsonArray -Path (Join-Path $Root 'config\tool-launchers.json'))

function Read-Entries {
    # Callers always wrap the result in @(), which keeps a one-element result
    # usable. Returning ,$entries would instead nest the array inside itself.
    if (-not (Test-Path -LiteralPath $overridePath -PathType Leaf)) { return @() }
    try { return @(Read-WplJsonArray -Path $overridePath) } catch { return @() }
}

function Write-Entries([object[]]$Entries) {
    # ConvertTo-Json flattens a one-element array into a bare object, which the
    # readers then cannot enumerate. Write the JSON array shape explicitly.
    $items = @($Entries)
    $body = if ($items.Count -eq 0) { '[]' }
        elseif ($items.Count -eq 1) { '[' + ($items[0] | ConvertTo-Json -Depth 8) + ']' }
        else { $items | ConvertTo-Json -Depth 8 }
    $directory = Split-Path -Parent $overridePath
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    $temporary = "$overridePath.$([guid]::NewGuid().ToString('N')).tmp"
    Set-Content -LiteralPath $temporary -Value $body -Encoding utf8
    Move-Item -LiteralPath $temporary -Destination $overridePath -Force
}

function Resolve-DeclaredPath([string]$Declared) {
    $expanded = [Environment]::ExpandEnvironmentVariables($Declared)
    if (-not [IO.Path]::IsPathRooted($expanded)) { $expanded = Join-Path $Root $expanded }
    return $expanded
}

function Get-EntryState([object]$Entry) {
    $resolved = Resolve-DeclaredPath ([string]$Entry.path)
    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { return 'missing-file' }
    if ([IO.Path]::GetExtension($resolved) -ine '.exe') { return 'not-an-executable' }
    if ($Entry.PSObject.Properties.Name -contains 'enabled' -and $Entry.enabled -eq $false) { return 'disabled' }
    return 'active'
}

switch ($Action) {
    'list' {
        $entries = @(Read-Entries)
        if (-not $entries.Count) {
            Write-Host (Get-WplText -Key UserPathNone -Language $Language -ArgumentList @($overridePath)) -ForegroundColor Yellow
            return
        }
        $entries | ForEach-Object {
            [pscustomobject]@{
                Id = [string]$_.id
                State = Get-EntryState $_
                Path = Resolve-DeclaredPath ([string]$_.path)
                Note = [string]$_.note
            }
        } | Format-Table -AutoSize
        return
    }
    'set' {
        if ([string]::IsNullOrWhiteSpace($Id)) { throw (Get-WplText -Key UserPathIdRequired -Language $Language) }
        if ([string]::IsNullOrWhiteSpace($Path)) { throw (Get-WplText -Key UserPathPathRequired -Language $Language) }
        $launcher = @($launchers | Where-Object { [string]$_.id -eq $Id.Trim() }) | Select-Object -First 1
        if (-not $launcher) { throw (Get-WplText -Key UserPathUnknownId -Language $Language -ArgumentList @($Id,(@($launchers.id) -join ', '))) }
        $resolved = Resolve-DeclaredPath $Path
        if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw (Get-WplText -Key UserPathNotFound -Language $Language -ArgumentList @($resolved)) }
        if ([IO.Path]::GetExtension($resolved) -ine '.exe') { throw (Get-WplText -Key UserPathNotExe -Language $Language -ArgumentList @($resolved)) }
        $signature = [string](Get-AuthenticodeSignature -LiteralPath $resolved).Status
        $entries = @(@(Read-Entries) | Where-Object { [string]$_.id -ne $Id.Trim() })
        $entries += [ordered]@{
            id = $Id.Trim()
            path = $Path
            enabled = $true
            recordedAt = (Get-Date).ToString('o')
            observedSignature = $signature
            note = 'user-declared path; overrides the bundled tools tree'
        }
        Write-Entries $entries
        Write-Host (Get-WplText -Key UserPathSaved -Language $Language -ArgumentList @($Id.Trim(),$resolved,$signature)) -ForegroundColor Green
        return
    }
    'remove' {
        if ([string]::IsNullOrWhiteSpace($Id)) { throw (Get-WplText -Key UserPathIdRequired -Language $Language) }
        $entries = @(Read-Entries)
        $remaining = @($entries | Where-Object { [string]$_.id -ne $Id.Trim() })
        if ($remaining.Count -eq $entries.Count) { throw (Get-WplText -Key UserPathNoEntry -Language $Language -ArgumentList @($Id)) }
        Write-Entries $remaining
        Write-Host (Get-WplText -Key UserPathRemoved -Language $Language -ArgumentList @($Id.Trim())) -ForegroundColor Green
        return
    }
    'verify' {
        $entries = @(Read-Entries)
        $bad = @()
        foreach ($entry in $entries) {
            $id = [string]$entry.id
            $state = Get-EntryState $entry
            if (-not (@($launchers.id) -contains $id)) { $bad += "$id : unknown launcher id"; continue }
            if ($state -eq 'missing-file') { $bad += "$id : file not found" }
            elseif ($state -eq 'not-an-executable') { $bad += "$id : not an .exe" }
        }
        if ($bad.Count) {
            $bad | ForEach-Object { Write-Error $_ -ErrorAction Continue }
            exit 1
        }
        Write-Host (Get-WplText -Key UserPathVerified -Language $Language -ArgumentList @($entries.Count)) -ForegroundColor Green
        exit 0
    }
}
