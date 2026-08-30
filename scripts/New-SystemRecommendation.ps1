[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [string]$OutputRoot = (Join-Path $Root 'recommendations'),
    [ValidateSet('ko','en','auto')][string]$Language = 'auto'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WinPortableLab.Localization.ps1')
$Language = Resolve-WplLanguage -Root $Root -Requested $Language

function Read-CimSafe([string]$ClassName) {
    try { return @(Get-CimInstance -ClassName $ClassName -ErrorAction Stop) }
    catch { return @() }
}

$cpu = @(Read-CimSafe 'Win32_Processor') | Select-Object -First 1
$system = @(Read-CimSafe 'Win32_ComputerSystem') | Select-Object -First 1
$os = @(Read-CimSafe 'Win32_OperatingSystem') | Select-Object -First 1
$board = @(Read-CimSafe 'Win32_BaseBoard') | Select-Object -First 1
$bios = @(Read-CimSafe 'Win32_BIOS') | Select-Object -First 1
$memory = @(Read-CimSafe 'Win32_PhysicalMemory')
$gpus = @(Read-CimSafe 'Win32_VideoController')
$disks = @(Read-CimSafe 'Win32_DiskDrive')
# Desktops report no battery, which is how the battery tool stays hidden there.
$batteries = @(Read-CimSafe 'Win32_Battery')
$recentSystemEvents = try { @(Get-WinEvent -LogName System -MaxEvents 3000 -ErrorAction Stop | Where-Object { $_.TimeCreated -ge [datetime]::Now.AddDays(-7) }) } catch { @() }
$wheaCount = @($recentSystemEvents | Where-Object ProviderName -eq 'Microsoft-Windows-WHEA-Logger').Count
$unexpectedPowerCount = @($recentSystemEvents | Where-Object { $_.ProviderName -eq 'Microsoft-Windows-Kernel-Power' -and $_.Id -eq 41 }).Count
$recommendationMode = if ($wheaCount -gt 0 -or $unexpectedPowerCount -gt 0) { 'diagnostic-baseline-only' } else { 'conservative-baseline' }

$cpuName = [string]$cpu.Name
$vendor = if ($cpuName -match '(?i)Intel') { 'Intel' } elseif ($cpuName -match '(?i)AMD|Ryzen') { 'AMD' } else { 'Unknown' }
$generation = $null
$route = 'unknown-stock-only'
$unlocked = $false
$x3d = $cpuName -match '(?i)X3D'

if ($vendor -eq 'Intel') {
    if ($cpuName -match '(?i)Core\s+Ultra\s+\d+\s+(2\d{2})') { $generation=[int]$Matches[1]; $route='intel-core-ultra-series-2-plus' }
    elseif ($cpuName -match '(?i)i[3579]-?(\d{4,5})') {
        $model=$Matches[1]
        $generation = if ($model.Length -ge 5) { [int]$model.Substring(0,2) } else { [int]$model.Substring(0,1) }
        $route = "intel-core-gen-$generation"
    }
    $unlocked = $cpuName -match '(?i)\d+(?:KS|KF|HK|HX|XE|K|X)\b'
}
elseif ($vendor -eq 'AMD') {
    if ($cpuName -match '(?i)(?:Ryzen|Threadripper).*?([1-9]\d{3})') {
        $modelNumber=[int]$Matches[1]
        $generation=[int]([math]::Floor($modelNumber / 1000) * 1000)
        $route = if($cpuName -match '(?i)Threadripper'){"amd-threadripper-$generation"}else{"amd-ryzen-$generation"}
    }
}

$memoryGB = [math]::Round((($memory | Measure-Object Capacity -Sum).Sum / 1GB), 1)
$configuredSpeeds = @($memory | ForEach-Object {[int]$_.ConfiguredClockSpeed} | Where-Object {$_ -gt 0} | Sort-Object -Unique)
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$computerName = if ($env:COMPUTERNAME) { $env:COMPUTERNAME } else { 'UNKNOWN-PC' }
$safeName = ($computerName -replace '[^A-Za-z0-9._-]', '_')
$output = Join-Path $OutputRoot "$safeName-$timestamp"
New-Item -ItemType Directory -Path $output -Force | Out-Null

$cpuInitial = [ordered]@{ profile='Auto/Default'; manualVoltage=$null; fixedRatio=$null; pbo=$null; curveOptimizer=$null }
$firmwareNoteKo = 'BIOS 기본값에서 기준선을 먼저 측정하십시오.'
$firmwareNoteEn = 'Measure the baseline at BIOS defaults first.'
if ($vendor -eq 'Intel' -and $generation -in @(13,14)) {
    $cpuInitial.profile='Intel Default Settings'
    $firmwareNoteKo='최신 보드 BIOS와 Intel Default Settings를 사용하고, CPU 진단 중에는 XMP를 끄십시오.'
    $firmwareNoteEn='Use the current board BIOS and Intel Default Settings, with XMP disabled during CPU diagnosis.'
}
elseif ($vendor -eq 'AMD') {
    $cpuInitial.profile='AMD Default/Auto'
    $cpuInitial.pbo='Auto'
    $cpuInitial.curveOptimizer=0
    if ($x3d) { $firmwareNoteKo='X3D 전용 경로입니다. 수동 고정 전압을 사용하지 말고 CPU가 노출한 PBO/CO만 검토하십시오.'; $firmwareNoteEn='X3D route: avoid fixed manual voltage and review only PBO/CO controls exposed for this CPU.' }
}

$recommendation = [ordered]@{
    schemaVersion='1.0.0'
    kind='WinPortableLab-recommendation-only'
    applyAllowed=$false
    generatedAt=(Get-Date).ToString('o')
    processing='local-only-no-upload'
    languageFiles=@('ko','en')
    detected=[ordered]@{
        operatingSystem=[ordered]@{caption=$os.Caption;version=$os.Version;build=$os.BuildNumber;architecture=$os.OSArchitecture}
        computer=[ordered]@{manufacturer=$system.Manufacturer;model=$system.Model}
        cpu=[ordered]@{name=$cpuName;vendor=$vendor;generation=$generation;route=$route;unlockedSuffixDetected=$unlocked;x3d=$x3d;cores=$cpu.NumberOfCores;threads=$cpu.NumberOfLogicalProcessors}
        motherboard=[ordered]@{manufacturer=$board.Manufacturer;product=$board.Product;version=$board.Version}
        bios=[ordered]@{version=$bios.SMBIOSBIOSVersion;releaseDate=$bios.ReleaseDate}
        memory=[ordered]@{moduleCount=$memory.Count;totalGB=$memoryGB;reportedMTs=@($memory.Speed | Sort-Object -Unique);configuredMTs=$configuredSpeeds;partNumbers=@($memory.PartNumber | ForEach-Object {$_.Trim()} | Where-Object {$_})}
        graphics=@($gpus | ForEach-Object {[ordered]@{name=$_.Name;driverVersion=$_.DriverVersion;driverDate=$_.DriverDate}})
        storage=@($disks | ForEach-Object {[ordered]@{model=$_.Model;interface=$_.InterfaceType;sizeGB=[math]::Round($_.Size/1GB,1);firmware=$_.FirmwareRevision}})
        battery=@($batteries | ForEach-Object {[ordered]@{name=$_.Name;deviceId=$_.DeviceID;designVoltage=$_.DesignVoltage;chemistry=$_.Chemistry;estimatedChargeRemaining=$_.EstimatedChargeRemaining}})
        healthSignals=[ordered]@{windowDays=7;wheaEvents=$wheaCount;unexpectedKernelPower41=$unexpectedPowerCount;recommendationMode=$recommendationMode}
    }
    recommendedSettings=[ordered]@{
        firmware=[ordered]@{cpuProfile=$cpuInitial.profile;memoryProfileInitial='JEDEC/Auto';biosVersionDetected=$bios.SMBIOSBIOSVersion;note=[ordered]@{ko=$firmwareNoteKo;en=$firmwareNoteEn}}
        cpu=[ordered]@{manualVoltage=$cpuInitial.manualVoltage;fixedRatio=$cpuInitial.fixedRatio;pbo=$cpuInitial.pbo;curveOptimizer=$cpuInitial.curveOptimizer;smokeMinutes=10;mixedMinutes=30;extendedMinutes=60;allowedCalculationErrors=0;allowedNewWheaEvents=0}
        memory=[ordered]@{initialProfile='JEDEC/Auto';xmpExpoAfterBaseline='Profile 1 only when supported';smokeMinutes=10;variedPatternMinutes=60;bootablePasses=4;coldBootCycles=3;allowedErrors=0}
        monitoring=[ordered]@{sampleIntervalSeconds=1;idleBaselineMinutes=10;logTemperatures=$true;logClocks=$true;logThrottling=$true;temperatureLimitC=$null;temperatureRule='Use the exact CPU/GPU vendor limit reported for the detected model'}
        storage=[ordered]@{healthReadOnly=$true;benchmarkTarget='bounded test file only';testFileGiB=1;runs=3;rawDiskWrites=$false;smartSelfTest='disabled by default'}
        graphics=[ordered]@{driverCleanup='only for failed uninstall/install or GPU vendor change';dduSafeModePreferred=$true;networkDisconnectedDuringCleanup=$true;replacementDriverPrepared=$true}
    }
    stopConditions=@(
        [ordered]@{id='calculation-error';threshold=0;ko='계산 또는 워커 오류가 하나라도 발생';en='Any calculation or worker error'},
        [ordered]@{id='memory-error';threshold=0;ko='메모리 오류가 하나라도 발생';en='Any memory error'},
        [ordered]@{id='whea';threshold=0;ko='새 WHEA 이벤트가 하나라도 발생';en='Any new WHEA event'},
        [ordered]@{id='crash';threshold=0;ko='멈춤, 재부팅, BSOD 또는 데이터 손상';en='Freeze, reboot, BSOD, or data corruption'}
    )
    limitations=@(
        [ordered]@{ko='CIM 정보만으로 XMP/EXPO 프로필 내용, DIMM 랭크, AGESA/마이크로코드 또는 냉각 성능을 확정할 수 없습니다.';en='CIM alone cannot confirm XMP/EXPO contents, DIMM ranks, AGESA/microcode, or cooling capability.'},
        [ordered]@{ko='그래서 보편 전압 상한이나 모델별 오버클럭 수치를 생성하지 않습니다.';en='Therefore no universal voltage ceiling or model-specific overclock value is generated.'}
    )
}

$jsonPath = Join-Path $output 'recommended-settings.json'
$recommendation | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding utf8

function Write-Guide([string]$Code) {
    $ko = $Code -eq 'ko'
    $title = if($ko){'시스템 맞춤 권장 설정'}else{'System-specific recommended settings'}
    $warning = Get-WplText -Key RecommendationOnly -Language $Code
    $detectedTitle=if($ko){'감지된 시스템'}else{'Detected system'}
    $settingsTitle=if($ko){'권장 시작값'}else{'Recommended starting values'}
    $stopTitle=if($ko){'즉시 중단 조건'}else{'Immediate stop conditions'}
    $unknown=if($ko){'확인되지 않음'}else{'Not detected'}
    $settingLines = if($ko){@(
        "- BIOS CPU 프로필: $($cpuInitial.profile)",'- CPU 수동 전압: Auto / 설정하지 않음','- CPU 고정 배수: Auto / 설정하지 않음',"- PBO: $(if($null -eq $cpuInitial.pbo){'해당 없음'}else{$cpuInitial.pbo})","- Curve Optimizer: $(if($null -eq $cpuInitial.curveOptimizer){'해당 없음'}else{$cpuInitial.curveOptimizer})",'- 초기 메모리 프로필: JEDEC/Auto','- 센서 기록 간격: 1초','- CPU 스모크 / 혼합 / 확장: 10 / 30 / 60분','- 메모리 스모크 / 다중 패턴: 10 / 60분','- 부팅형 메모리 검사: 4패스','- 콜드 부팅 확인: 3회','- 허용 계산·메모리·WHEA 오류: 0개','- 저장장치 벤치: 1GiB 제한 테스트 파일, 3회'
    )}else{@(
        "- BIOS CPU profile: $($cpuInitial.profile)",'- CPU manual voltage: Auto / unset','- CPU fixed ratio: Auto / unset',"- PBO: $(if($null -eq $cpuInitial.pbo){'Not applicable'}else{$cpuInitial.pbo})","- Curve Optimizer: $(if($null -eq $cpuInitial.curveOptimizer){'Not applicable'}else{$cpuInitial.curveOptimizer})",'- Initial memory profile: JEDEC/Auto','- Sensor interval: 1 second','- CPU smoke / mixed / extended: 10 / 30 / 60 minutes','- Memory smoke / varied: 10 / 60 minutes','- Bootable memory test: 4 passes','- Cold boot checks: 3 cycles','- Allowed calculation, memory, WHEA errors: 0','- Storage benchmark: 1 GiB bounded test file, 3 runs'
    )}
    $systemLines = if($ko){@(
        "- CPU: $(if($cpuName){$cpuName}else{$unknown})","- 분류 경로: $route","- 메인보드: $($board.Manufacturer) $($board.Product)","- BIOS: $($bios.SMBIOSBIOSVersion)","- 메모리: $memoryGB GB / $($memory.Count)개 모듈 / $($configuredSpeeds -join ', ') MT/s","- GPU: $(@($gpus.Name) -join '; ')","- 최근 7일 WHEA / Kernel-Power 41: $wheaCount / $unexpectedPowerCount","- 권장 모드: $recommendationMode"
    )}else{@(
        "- CPU: $(if($cpuName){$cpuName}else{$unknown})","- Route: $route","- Mainboard: $($board.Manufacturer) $($board.Product)","- BIOS: $($bios.SMBIOSBIOSVersion)","- Memory: $memoryGB GB / $($memory.Count) modules / $($configuredSpeeds -join ', ') MT/s","- GPU: $(@($gpus.Name) -join '; ')","- Recent 7-day WHEA / Kernel-Power 41: $wheaCount / $unexpectedPowerCount","- Recommendation mode: $recommendationMode"
    )}
    $lines=@(
        "# $title",'',"> $warning",'',"## $detectedTitle",'',
        $systemLines,'',
        "## $settingsTitle",'',
        $settingLines,'',
        "## $stopTitle",'',
        ($recommendation.stopConditions | ForEach-Object { '- ' + $_.$Code }),'',
        "## $(if($ko){'플랫폼 메모'}else{'Platform note'})",'',"- $(if($ko){$firmwareNoteKo}else{$firmwareNoteEn})",'',
        $(if($ko){'전체 기계 판독값: recommended-settings.json'}else{'Full machine-readable values: recommended-settings.json'})
    )
    $lines | Set-Content -LiteralPath (Join-Path $output "recommended-settings.$Code.md") -Encoding utf8
}

Write-Guide 'ko'
Write-Guide 'en'
Write-Output $output
