[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [ValidateSet('status','register','unregister')][string]$Action = 'status',
    [ValidateSet('ko','en','auto')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Root = (Resolve-Path -LiteralPath $Root).Path
$Language = Resolve-WplLanguage -Root $Root -Requested $Language

# This script is the only place in the project that writes a registry value. The
# write is confined to one value under HKCU, so it needs no administrator rights
# and changes nothing machine-wide. Unregister removes it again, which is why the
# portable pack can still promise that nothing permanent is left on the host.
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$valueName = 'WinPortableLabOnePack'
$launcher = Join-Path $Root 'WinPortableLab.ps1'

function Get-WplStartupCommand {
    # Resident mode starts without a UAC prompt so a logon stays quiet. An
    # unelevated resident window reports only; an elevated instance acts.
    return ('powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Action gui -StartMinimized -NoElevation -Language auto' -f $launcher)
}

function Get-WplStartupEntry {
    if (-not (Test-Path -LiteralPath $runKey -PathType Container)) { return $null }
    $entry = Get-ItemProperty -LiteralPath $runKey -Name $valueName -ErrorAction SilentlyContinue
    if (-not $entry) { return $null }
    return [string]$entry.$valueName
}

$current = Get-WplStartupEntry
switch ($Action) {
    'register' {
        if (-not (Test-Path -LiteralPath $launcher -PathType Leaf)) { throw (Get-WplText -Key StartupLauncherMissing -Language $Language -ArgumentList @($launcher)) }
        if (-not (Test-Path -LiteralPath $runKey -PathType Container)) { New-Item -Path $runKey -Force | Out-Null }
        Set-ItemProperty -LiteralPath $runKey -Name $valueName -Value (Get-WplStartupCommand) -Type String
        $current = Get-WplStartupEntry
        Write-Host (Get-WplText -Key StartupRegistered -Language $Language -ArgumentList @($current)) -ForegroundColor Green
    }
    'unregister' {
        if ($current) { Remove-ItemProperty -LiteralPath $runKey -Name $valueName -ErrorAction SilentlyContinue }
        $current = Get-WplStartupEntry
        Write-Host (Get-WplText -Key StartupUnregistered -Language $Language) -ForegroundColor Green
    }
    default {
        Write-Host ($(if ($current) { Get-WplText -Key StartupStatusRegistered -Language $Language -ArgumentList @($current) } else { Get-WplText -Key StartupStatusMissing -Language $Language })) -ForegroundColor Cyan
    }
}

[pscustomobject][ordered]@{
    Action = $Action
    ValueName = $valueName
    Key = $runKey
    Registered = [bool]$current
    Command = $current
    Launcher = $launcher
}
exit 0
