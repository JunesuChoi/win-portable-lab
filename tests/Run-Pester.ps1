[CmdletBinding()]
param([string]$Path = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
$available = Get-Module -ListAvailable Pester | Sort-Object Version -Descending | Select-Object -First 1
if (-not $available) {
    Write-Warning 'Pester is not installed for this PowerShell host; no network installation was attempted.'
    exit 2
}

Import-Module $available.Path -Force
$major = (Get-Module Pester).Version.Major
if ($major -ge 5) {
    $result = Invoke-Pester -Path $Path -PassThru
}
else {
    $result = Invoke-Pester -Script $Path -PassThru
}

if ([int]$result.FailedCount -gt 0) { exit 1 }
Write-Host ("Pester {0}: {1} tests passed." -f (Get-Module Pester).Version,$result.PassedCount) -ForegroundColor Green
exit 0
