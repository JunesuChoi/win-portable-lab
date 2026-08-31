[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [switch]$SmokeReadOnlyGui,
    [int]$StartupSeconds=4,
    [ValidateSet('ko','en')][string]$Language='ko'
)

$ErrorActionPreference='Stop'
Import-Module (Join-Path $Root 'src\WinPortableLab.Core.psm1') -Force
Import-Module (Join-Path $Root 'src\WinPortableLab.Process.psm1') -Force
$launchers=@(Read-WplJsonArray -Path (Join-Path $Root 'config\tool-launchers.json'))
$cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
$cpuVendor=if($cpu.Manufacturer -match 'AMD'){'AMD'}elseif($cpu.Manufacturer -match 'Intel'){'Intel'}else{'Other'}
$reportRoot=Join-Path $Root ('reports\launcher-audit-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $reportRoot -Force | Out-Null
$rows=[Collections.Generic.List[object]]::new()

foreach($launcher in $launchers){
    $exe=Resolve-WplExecutable -Root $Root -Launcher $launcher
    $status='verified-path'
    $detail=''
    $hash=$null
    $signature=$null
    $smokeEligible=$launcher.launchMode -eq 'gui' -and [string]$launcher.risk -match '^read-only'
    if($launcher.launchMode -eq 'external-boot'){$status='external-boot-manual'}
    elseif(-not $exe){$status='missing-executable'}
    elseif($launcher.id -eq 'zentimings' -and $cpuVendor -ne 'AMD'){$status='skipped-incompatible-hardware';$detail='ZenTimings is AMD-only.'}
    else{
        $hash=(Get-FileHash -LiteralPath $exe.FullName -Algorithm SHA256).Hash
        $signature=[string](Get-AuthenticodeSignature -LiteralPath $exe.FullName).Status
        $installedManifest=Get-ChildItem -LiteralPath (Join-Path $Root 'tools') -Filter 'INSTALL-MANIFEST.json' -File -Recurse |
            ForEach-Object {try{Get-Content $_.FullName -Raw|ConvertFrom-Json}catch{}} |
            Where-Object id -eq $launcher.catalogId |
            Where-Object {@($_.executables.sha256) -contains $hash} |
            Select-Object -First 1
        if(-not $installedManifest){$status='manifest-hash-not-found'}
    }

    if($SmokeReadOnlyGui -and $smokeEligible -and $exe -and $status -eq 'verified-path'){
        $process=$null
        $beforeProcesses=@(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Select-Object ProcessId,CreationDate)
        $smokeStartedAt=Get-Date
        try{
            $arguments = @(ConvertTo-WplArgumentList -InputObject $launcher.arguments)
            $process=Start-WplProcess -FilePath $exe.FullName -ArgumentList $arguments -WorkingDirectory (Split-Path $exe.FullName)
            $stopwatch=[Diagnostics.Stopwatch]::StartNew()
            while(-not $process.HasExited -and $stopwatch.Elapsed.TotalSeconds -lt $StartupSeconds){Start-Sleep -Milliseconds 250;$process.Refresh()}
            $relatedIds=@(Get-WplRelatedProcessIds -RootProcessId $process.Id -ExecutablePath $exe.FullName -StartedAfter $smokeStartedAt -ExcludedProcesses $beforeProcesses)
            if($process.HasExited -and -not $relatedIds.Count){$status='exited-during-startup';$detail="ExitCode=$($process.ExitCode)"}
            else{$status='started-responsive';$detail="PID=$($process.Id); Related=$($relatedIds -join ','); Window=$($process.MainWindowTitle)"}
        }
        catch{$status='launch-error';$detail=$_.Exception.Message}
        finally{
            if($process -and -not $process.HasExited){
                [void]$process.CloseMainWindow()
                [void]$process.WaitForExit(1500)
            }
            if($process){
                $relatedIds=@(Get-WplRelatedProcessIds -RootProcessId $process.Id -ExecutablePath $exe.FullName -StartedAfter $smokeStartedAt -ExcludedProcesses $beforeProcesses)
                Stop-WplRelatedProcesses -ProcessIds $relatedIds
            }
        }
    }

    $rows.Add([pscustomobject]@{
        id=$launcher.id;catalogId=$launcher.catalogId;mode=$launcher.launchMode;risk=$launcher.risk
        executable=if($exe){$exe.FullName}else{$null};sha256=$hash;signature=$signature
        smokeEligible=$smokeEligible;status=$status;detail=$detail
    })
}

$jsonPath=Join-Path $reportRoot 'launcher-audit.json'
$csvPath=Join-Path $reportRoot 'launcher-audit.csv'
$rows | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding utf8
$rows | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding utf8
$rows | Format-Table id,mode,status,detail -AutoSize
Write-Host "Launcher audit: $reportRoot"
