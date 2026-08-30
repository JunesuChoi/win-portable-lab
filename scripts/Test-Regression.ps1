[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [ValidateSet('ko','en')][string]$Language = 'en'
)

$ErrorActionPreference = 'Stop'
$resolvedRoot = [IO.Path]::GetFullPath($Root)
$repositoryTest = Join-Path $resolvedRoot 'scripts\Test-Repository.ps1'
$pesterRunner = Join-Path $resolvedRoot 'tests\Run-Pester.ps1'
$hosts = [Collections.Generic.List[object]]::new()

$windowsPowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (Test-Path -LiteralPath $windowsPowerShell -PathType Leaf) {
    $hosts.Add([pscustomobject]@{Name='Windows PowerShell 5.1';Path=$windowsPowerShell})
}
$pwsh = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($pwsh -and @($hosts.Path) -notcontains $pwsh.Source) {
    $hosts.Add([pscustomobject]@{Name='PowerShell 7';Path=$pwsh.Source})
}
if ($hosts.Count -eq 0) { throw 'No supported PowerShell host was found.' }

$failures = [Collections.Generic.List[string]]::new()
$pesterRuns = 0
foreach ($runtime in $hosts) {
    Write-Host ("== {0}: repository validation ==" -f $runtime.Name) -ForegroundColor Cyan
    & $runtime.Path -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $repositoryTest -Root $resolvedRoot -Language $Language
    if ($LASTEXITCODE -ne 0) { $failures.Add("$($runtime.Name) repository validation exited with code $LASTEXITCODE.") }

    Write-Host ("== {0}: Pester ==" -f $runtime.Name) -ForegroundColor Cyan
    & $runtime.Path -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $pesterRunner -Path (Join-Path $resolvedRoot 'tests')
    if ($LASTEXITCODE -eq 2) {
        Write-Warning "$($runtime.Name) has no local Pester module. Skipped without installing from the network."
    }
    elseif ($LASTEXITCODE -ne 0) {
        $failures.Add("$($runtime.Name) Pester run exited with code $LASTEXITCODE.")
    }
    else { $pesterRuns++ }
}

if ($pesterRuns -eq 0) { $failures.Add('Pester was unavailable in every PowerShell host.') }
if ($failures.Count -gt 0) {
    $failures | ForEach-Object { Write-Error $_ -ErrorAction Continue }
    exit 1
}
Write-Host ("Cross-runtime regression passed. Hosts: {0}; Pester runs: {1}." -f $hosts.Count,$pesterRuns) -ForegroundColor Green
exit 0
