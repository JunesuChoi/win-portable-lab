[CmdletBinding()]
param(
    [ValidateSet('inventory', 'validate', 'tools', 'install', 'launch', 'recommend', 'smart')]
    [string]$Mode = 'smart',
    [ValidateSet('ko','en','auto')]
    [string]$Language = 'auto',
    [switch]$NoElevation
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Language = Resolve-WplLanguage -Root $root -Requested $Language

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdministrator = ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $NoElevation -and -not $isAdministrator) {
    $hostExecutable = (Get-Process -Id $PID).Path
    $arguments = '-NoLogo -NoProfile -ExecutionPolicy Bypass -File "{0}" -Mode {1} -Language {2}' -f $PSCommandPath,$Mode,$Language
    Write-Host (Get-WplText -Key ElevationRequest -Language $Language) -ForegroundColor Cyan
    try {
        # Smart mode opens the WPF console. Do not leave this non-elevated
        # bootstrap console waiting behind it for the rest of the session.
        if ($Mode -eq 'smart') {
            Start-Process -FilePath $hostExecutable -ArgumentList $arguments -Verb RunAs
            exit 0
        }
        $elevated = Start-Process -FilePath $hostExecutable -ArgumentList $arguments -Verb RunAs -Wait -PassThru
        exit $elevated.ExitCode
    }
    catch {
        Write-Error (Get-WplText -Key ElevationCancelled -Language $Language)
        exit 1223
    }
}

Write-Host (Get-WplText -Key AppTitle -Language $Language) -ForegroundColor Cyan
Write-Host "$(Get-WplText -Key Root -Language $Language): $root"

switch ($Mode) {
    'validate' {
        & (Join-Path $PSScriptRoot 'Test-Repository.ps1') -Root $root -Language $Language
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        & (Join-Path $PSScriptRoot 'Test-InstalledTools.ps1') -Root $root -Language $Language
        exit $LASTEXITCODE
    }
    'inventory' {
        $report = & (Join-Path $PSScriptRoot 'Invoke-Inventory.ps1') -OutputRoot (Join-Path $root 'reports') -Language $Language
        Write-Host (Get-WplText -Key ReportCreated -Language $Language -ArgumentList @($report)) -ForegroundColor Green
    }
    'tools' {
        & (Join-Path $PSScriptRoot 'Setup-Tools.ps1') -Root $root -Language $Language
    }
    'install' {
        & (Join-Path $PSScriptRoot 'Install-PortableTools.ps1') -Root $root -IncludeHighLoad -Language $Language
    }
    'launch' {
        & (Join-Path $PSScriptRoot 'Open-PortableTool.ps1') -Root $root -List -Language $Language
    }
    'recommend' {
        $recommendation = & (Join-Path $PSScriptRoot 'New-SystemRecommendation.ps1') -Root $root -Language $Language
        Write-Host (Get-WplText -Key RecommendationCreated -Language $Language -ArgumentList @($recommendation)) -ForegroundColor Green
    }
    'smart' {
        & (Join-Path $root 'WinPortableLab.ps1') -Action gui -Profile quick -Language $Language -NoElevation:$NoElevation
    }
}
