function Resolve-WplLanguage {
    param([string]$Root, [string]$Requested = 'auto')
    if ($Requested -in @('ko', 'en')) { return $Requested }
    $settingsPath = Join-Path $Root 'config\settings.json'
    if (Test-Path -LiteralPath $settingsPath) {
        try {
            $configured = (Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json).language
            if ($configured -in @('ko', 'en')) { return [string]$configured }
        } catch { }
    }
    if ([Globalization.CultureInfo]::CurrentUICulture.Name -match '^ko') { return 'ko' }
    return 'en'
}

function Get-WplText {
    param([Parameter(Mandatory)][string]$Key, [Parameter(Mandatory)][string]$Language, [object[]]$ArgumentList)
    $messages = @{
        AppTitle=@{ko='WinPortableLab 포터블 진단 도구';en='WinPortableLab portable diagnostics'}
        ElevationRequest=@{ko='정밀 시스템 점검을 위해 관리자 권한을 요청합니다...';en='Requesting administrator privileges for detailed system diagnostics...'}
        ElevationCancelled=@{ko='관리자 권한 요청이 취소되었습니다. 일반 권한으로 실행하려면 -NoElevation을 명시하십시오.';en='Administrator elevation was cancelled. Specify -NoElevation to run with standard privileges.'}
        Root=@{ko='루트';en='Root'}
        ReportCreated=@{ko='보고서 생성 완료: {0}';en='Report created: {0}'}
        RecommendationCreated=@{ko='권장 설정 파일 생성 완료: {0}';en='Recommendation files created: {0}'}
        Downloading=@{ko='{0} {1} 다운로드 중...';en='Downloading {0} {1}...'}
        DownloadFailed=@{ko='다운로드 실패: {0}';en='Download failed: {0}'}
        UnknownDownloadId=@{ko='알 수 없는 다운로드 도구 ID: {0}';en='Unknown downloadable tool id: {0}'}
        HashMismatch=@{ko='{0} SHA-256 불일치: {1}';en='SHA256 mismatch for {0}: {1}'}
        ExtractFailed=@{ko='7-Zip 압축 해제 실패: {0}';en='7-Zip extraction failed: {0}'}
        DownloadSafe=@{ko='다운로드와 검사만 완료했습니다. 벤치마크나 스트레스 부하는 시작하지 않았습니다.';en='Downloaded and inspected only. No benchmark or stress workload was started.'}
        UnknownLaunchId=@{ko='알 수 없는 실행 도구 ID: {0}';en='Unknown launchable tool id: {0}'}
        NotInstalled=@{ko='도구가 설치되지 않았습니다: {0}';en='Tool is not installed: {0}'}
        RiskBlocked=@{ko="'{0}'의 위험 등급은 '{1}'입니다. 관련 안내서를 읽은 뒤 -AcknowledgeRisk로 다시 실행하십시오.";en="'{0}' has risk '{1}'. Re-run with -AcknowledgeRisk after reading the applicable guide."}
        Started=@{ko='{0} 실행: {1}';en='Started {0} from {1}'}
        ExternalBootOnly=@{ko="'{0}'은 부팅형 도구입니다. 실행 파일 대신 안내서에 따라 USB 부팅 미디어를 준비하십시오.";en="'{0}' is a bootable tool. Prepare USB boot media using the guide instead of launching an executable."}
        UnknownToolId=@{ko='알 수 없는 도구 ID: {0}';en='Unknown tool id: {0}'}
        NoBinaryDownloaded=@{ko='이 준비 단계에서는 외부 바이너리를 다운로드하지 않았습니다.';en='No third-party binaries were downloaded automatically.'}
        SetupHint=@{ko='docs\ko\README.md를 확인하거나 승인된 포터블 파일을 준비된 디렉터리에 배치하십시오.';en='Use docs\en\README.md and place approved portable files in each prepared directory.'}
        InstalledValidationPassed=@{ko='설치 도구 검증 통과. 패키지: {0}';en='Installed tool validation passed. Packages: {0}'}
        RepositoryValidationPassed=@{ko='저장소 검증 통과. 도구: {0}';en='Repository validation passed. Tools: {0}'}
        RecommendationOnly=@{ko='이 파일은 권장 정보 전용이며 설정을 자동 적용하지 않습니다.';en='This file is recommendation-only and does not apply settings automatically.'}
        RecommendationValidationPassed=@{ko='권장 설정 안전 검증 통과: {0}';en='Recommendation safety validation passed: {0}'}
        IntegratedCheckStart=@{ko='시스템 정보와 권장 프로그램을 확인합니다...';en='Checking system information and recommended programs...'}
        ProgramPlanCreated=@{ko='권장 프로그램 연결 파일 생성 완료: {0}';en='Recommended program connection file created: {0}'}
        ProgramName=@{ko='도구명';en='Tool name'}
        ProgramId=@{ko='프로그램 ID';en='Program ID'}
        RecommendationState=@{ko='권장 상태';en='Recommendation state'}
        ReadyState=@{ko='준비 상태';en='Ready state'}
        Installed=@{ko='확보됨';en='Installed'}
        Launchable=@{ko='실행 가능';en='Launchable'}
        Risk=@{ko='위험도';en='Risk'}
        LaunchMode=@{ko='실행 모드';en='Launch mode'}
        Reason=@{ko='권장 이유';en='Reason'}
        RecommendedPrograms=@{ko='시스템 맞춤 권장 프로그램';en='System-specific recommended programs'}
        DetectedSummary=@{ko='감지 요약';en='Detected summary'}
        ProgramConnections=@{ko='프로그램 연결';en='Program connections'}
        MenuPrompt=@{ko='1=목록, 2=안전 권장 프로그램 실행, 3=ID로 실행, 4=보고서 열기, 5=권장 안내서 열기, 0=종료';en='1=list, 2=launch safe recommendations, 3=launch by id, 4=open report, 5=open recommendation guide, 0=exit'}
        EnterToolId=@{ko='실행할 프로그램 ID를 입력하십시오';en='Enter the program ID to launch'}
        NoSafeLaunch=@{ko='자동으로 열 수 있는 읽기 전용 권장 프로그램이 없습니다.';en='No read-only recommended GUI program is available to launch.'}
        MissingPrograms=@{ko='확보되지 않은 권장 프로그램: {0}';en='Missing recommended programs: {0}'}
        ProgramPlanValidationPassed=@{ko='권장 프로그램 연결 검증 통과. 항목: {0}';en='Recommended program connection validation passed. Items: {0}'}
        RecIdentity=@{ko='CPU, 메인보드와 메모리 구성을 읽기 전용으로 확인합니다.';en='Read-only identification of CPU, mainboard and memory configuration.'}
        RecSensors=@{ko='온도, 클럭과 스로틀링 기준선을 확인합니다.';en='Checks temperature, clock and throttling baselines.'}
        RecStorageHealth=@{ko='쓰기 테스트 전에 SSD/HDD/NVMe 상태와 SMART를 확인합니다.';en='Checks SSD/HDD/NVMe health and SMART before write testing.'}
        RecGpuIdentity=@{ko='GPU 모델, 드라이버와 센서 정보를 확인합니다.';en='Checks GPU model, driver and sensor information.'}
        RecEvents=@{ko='WHEA, 디스크, 드라이버와 전원 이벤트를 확인합니다.';en='Reviews WHEA, disk, driver and power events.'}
        RecTrafficMonitor=@{ko='작업 표시줄에서 네트워크 속도와 CPU·RAM·GPU·디스크 사용률을 지속 확인합니다.';en='Continuously shows network throughput and CPU, RAM, GPU and disk use in the taskbar.'}
        RecTcpView=@{ko='프로세스별 네트워크 연결과 원격 주소를 읽기 전용으로 확인합니다.';en='Lists per-process network connections and remote endpoints read-only.'}
        RecTestMem5=@{ko='메모리 오버클럭 서브타이밍 오류를 짧은 시간에 검출합니다.';en='Detects memory overclock sub-timing errors quickly.'}
        RecHciMemtest=@{ko='커버리지를 누적해 메모리 오류를 오래 검증합니다. 무료판은 인스턴스를 수동으로 나눠 실행합니다.';en='Validates memory over long runs by accumulating coverage. The free edition needs manually split instances.'}
        RecLatencyMon=@{ko='DPC·ISR 지연을 측정해 소리 끊김과 미세 멈춤의 드라이버 원인을 찾습니다.';en='Measures DPC and ISR latency to find the driver behind audio dropouts and micro stutter.'}
        RecBatteryInfo=@{ko='배터리 설계 용량 대비 마모율과 충전 사이클을 확인합니다.';en='Reports battery wear against designed capacity and the charge cycle count.'}
        RecWizTree=@{ko='쓰기 테스트 전에 디스크 여유 공간과 대용량 항목을 빠르게 확인합니다.';en='Quickly reviews free space and large items before a write test.'}
        RecVentoy=@{ko='MemTest86+ 부팅 USB를 준비합니다. 대상 USB를 초기화하므로 확인이 필요합니다.';en='Prepares MemTest86+ boot media. It erases the target USB, so confirmation is required.'}
        RecSdio=@{ko='누락되거나 오래된 드라이버를 오프라인에서 검사합니다. 검사는 읽기 전용이며 설치는 복원 지점 후에만 진행합니다.';en='Scans offline for missing or outdated drivers. Scanning is read-only; install only after a restore point.'}
        RecGlary=@{ko='시작 항목, 디스크 사용량, 시스템 정보를 한 화면에서 확인합니다. 정리 기능은 진단 근거를 지울 수 있어 사용하지 않습니다.';en='Reviews startup entries, disk usage and system information in one place. Its cleanup features can erase diagnostic evidence and are not used.'}
        RecProcessMonitor=@{ko='파일과 레지스트리 접근을 추적합니다. 필요할 때만 짧게 기록하세요.';en='Traces file and registry access. Capture only briefly when needed.'}
        RecMemoryTimings=@{ko='AMD 시스템의 실제 메모리 타이밍, MCLK·UCLK·FCLK, 전압과 지원되는 DIMM SPD 정보를 읽습니다.';en='Reads applied AMD memory timings, MCLK, UCLK, FCLK, voltages and supported DIMM SPD data.'}
        RecCpuStress=@{ko='CPU 계산 안정성을 단계적으로 검사하는 고부하 도구입니다.';en='High-load tool for staged CPU calculation stability testing.'}
        RecMemoryStress=@{ko='메모리 컨트롤러와 RAM 경로의 계산 오류를 검사합니다.';en='Checks calculation errors across the memory controller and RAM path.'}
        RecStorageBaseline=@{ko='제한된 테스트 파일로 저장장치 성능 기준선을 측정합니다.';en='Measures a storage baseline with a bounded test file.'}
        RecDiskSpd=@{ko='DiskSpd 명령과 옵션을 연결합니다. 부하는 자동 시작하지 않습니다.';en='Connects DiskSpd commands and options without starting a workload.'}
        RecOcct=@{ko='복합 부하와 오류 검출용이며 센서 감시와 중단 조건이 필요합니다.';en='Combined-load error detection requiring sensor monitoring and stop conditions.'}
        RecBootMemory=@{ko='Windows 밖에서 RAM을 검사하는 USB 부팅형 도구입니다.';en='Bootable USB tool for testing RAM outside Windows.'}
        RecDirty=@{ko='SLC 캐시 소진 이후 SSD 지속 쓰기와 더티 상태를 확인합니다.';en='Measures SSD sustained write and dirty-state behavior after SLC cache.'}
        RecIntegrity=@{ko='선택한 빈 공간 전체에 파일을 쓰고 읽어 용량과 무결성을 확인합니다.';en='Writes and reads selected free space to verify capacity and integrity.'}
        RecUsbCapacity=@{ko='USB 대용량 저장장치의 표시 용량을 빠르게 스폿체크합니다.';en='Quickly spot-checks declared capacity of USB mass storage.'}
        RecDdu=@{ko='GPU 업체 변경이나 정상 제거 실패 때만 사용하는 조건부 드라이버 정리 도구입니다.';en='Conditional driver cleanup for GPU vendor changes or failed normal uninstall.'}
        RecAmdCleanup=@{ko='AMD 그래픽 드라이버 정상 제거 실패 때만 사용하는 조건부 도구입니다.';en='Conditional tool for failed normal removal of AMD graphics drivers.'}
        RecIntelXtu=@{ko='지원되는 언락 Intel CPU의 설치형 튜닝 도구이며 기준선 안정화 후에만 검토합니다.';en='Installed tuning utility for supported unlocked Intel CPUs; review only after a stable baseline.'}
        RecRyzenMaster=@{ko='지원되는 AMD Ryzen CPU의 설치형 튜닝 도구이며 기준선 안정화 후에만 검토합니다.';en='Installed tuning utility for supported AMD Ryzen CPUs; review only after a stable baseline.'}
        RecCrash=@{ko='미니덤프가 있을 때 빠르게 확인하고 디버거로 최종 검증합니다.';en='Quickly triages minidumps before debugger confirmation.'}
        GuiBrand=@{ko='원팩 포터블 코리아';en='ONEPACK PORTABLE KOREA'}
        GuiDescription=@{ko='Windows 11 현장 진단, 시스템 정보, SSD 더티 테스트, CPU·GPU·RAM 안정성 도구를 하나의 휴대용 GitHub 프로젝트로 관리합니다.';en='A portable GitHub project for Windows 11 field diagnostics, system inventory, SSD dirty tests, and CPU, GPU and RAM stability tools.'}
        GuiBadge=@{ko='PORTABLE DIAGNOSTIC CONSOLE';en='PORTABLE DIAGNOSTIC CONSOLE'}
        GuiSystem=@{ko='현재 시스템';en='CURRENT SYSTEM'}
        GuiRecordsSection=@{ko='기록';en='HISTORY'}
        GuiManageSection=@{ko='관리';en='MANAGE'}
        GuiMore=@{ko='더보기';en='More'}
        GuiSnapshotAt=@{ko='마지막 점검 {0} · {1} 프로필';en='Last scan {0} · {1} profile'}
        GuiSnapshotPending=@{ko='시스템 스냅샷 준비 중';en='Preparing system snapshot'}
        GuiProfileQuick=@{ko='빠른 점검';en='Quick'}
        GuiProfileStorage=@{ko='저장장치';en='Storage'}
        GuiProfileMemory=@{ko='CPU·RAM';en='CPU and RAM'}
        GuiProfileGpu=@{ko='GPU';en='GPU'}
        GuiProfileAll=@{ko='전체';en='All'}
        GuiProfileStandard=@{ko='표준';en='Standard'}
        GuiRecommended=@{ko='시스템 맞춤 권장 프로그램';en='SYSTEM-SPECIFIC RECOMMENDATIONS'}
        GuiQuick=@{ko='빠른 시스템 점검';en='Quick system check'}
        GuiAll=@{ko='전체 권장 분석';en='Full recommendation scan'}
        GuiStorage=@{ko='SSD · 저장장치';en='SSD and storage'}
        GuiMemory=@{ko='CPU · RAM 안정성';en='CPU and RAM stability'}
        GuiGpu=@{ko='GPU · DDU';en='GPU and DDU'}
        GuiRefreshSystem=@{ko='시스템 정보 새로고침';en='Refresh system information'}
        GuiReusingSnapshot=@{ko='기존 시스템 스냅샷으로 권장 목록을 전환합니다...';en='Switching recommendations using the existing system snapshot...'}
        GuiSafeLaunch=@{ko='안전 권장 도구 실행';en='Launch safe recommendations'}
        GuiSafeLaunchConfirm=@{ko="읽기 전용 권장 도구 {0}개를 실행합니다:`n`n{1}`n`n계속하시겠습니까?";en="Launch {0} read-only recommended tools?`n`n{1}`n`nContinue?"}
        GuiSafeLaunchRunning=@{ko='읽기 전용 권장 도구 {0}개를 순서대로 실행하고 있습니다...';en='Launching {0} read-only recommendations in sequence...'}
        GuiSafeLaunchCompleted=@{ko='읽기 전용 권장 도구 {0}개를 실행했습니다.';en='Launched {0} read-only recommendations.'}
        GuiSafeLaunchPartial=@{ko='권장 도구 {0}개 실행, {1}개 실패 — GUI는 계속 실행됩니다.';en='Launched {0} recommendations; {1} failed. The dashboard remains open.'}
        GuiReports=@{ko='보고서 폴더';en='Reports folder'}
        GuiLatestResult=@{ko='최근 결과 보기';en='Open latest result'}
        GuiNoResults=@{ko='아직 생성된 점검 결과가 없습니다.';en='No diagnostic results have been created yet.'}
        GuiSearchHint=@{ko='프로그램 이름 또는 ID 검색';en='Search by program name or ID'}
        GuiSearchPlaceholder=@{ko='프로그램 이름 또는 ID를 검색하세요';en='Search program name or ID'}
        GuiFilterAll=@{ko='전체 상태';en='All states'}
        GuiFilterReady=@{ko='실행 준비됨';en='Ready to launch'}
        GuiFilterMissing=@{ko='확보 필요';en='Missing'}
        GuiFilterRisk=@{ko='주의 필요';en='Risk requires review'}
        GuiGithub=@{ko='GitHub 프로젝트';en='GitHub project'}
        GuiValidate=@{ko='도구 무결성 검증';en='Validate tool integrity'}
        GuiLaunchSelected=@{ko='선택 프로그램 실행';en='Launch selected tool'}
        GuiOpenGuide=@{ko='권장 안내서 열기';en='Open recommendation guide'}
        GuiOpenToolGuide=@{ko='선택 도구 사용법';en='Selected tool guide'}
        UserPathNone=@{ko='등록된 사용자 경로가 없습니다. 파일 위치: {0}';en='No user-declared paths are registered. File location: {0}'}
        UserPathIdRequired=@{ko='도구 실행 ID가 필요합니다. -Id 값을 지정하세요.';en='A launcher id is required. Provide -Id.'}
        UserPathPathRequired=@{ko='실행 파일 경로가 필요합니다. -Path 값을 지정하세요.';en='An executable path is required. Provide -Path.'}
        UserPathUnknownId=@{ko='알 수 없는 실행 ID: {0}. 사용 가능한 ID: {1}';en='Unknown launcher id: {0}. Available ids: {1}'}
        UserPathNotFound=@{ko='파일을 찾을 수 없습니다: {0}';en='File not found: {0}'}
        UserPathNotExe=@{ko='실행 파일(.exe)이 아닙니다: {0}';en='Not an executable (.exe): {0}'}
        UserPathSaved=@{ko='{0} 경로를 저장했습니다: {1} (서명 상태: {2})';en='Saved the path for {0}: {1} (signature: {2})'}
        UserPathNoEntry=@{ko='{0}에 등록된 사용자 경로가 없습니다.';en='No user-declared path is registered for {0}.'}
        UserPathRemoved=@{ko='{0} 사용자 경로를 제거했습니다. 번들 도구 검색으로 되돌아갑니다.';en='Removed the user-declared path for {0}. Falling back to the bundled tools tree.'}
        UserPathVerified=@{ko='사용자 경로 검증 통과. 항목: {0}';en='User-declared path validation passed. Entries: {0}'}
        GuiNoToolGuide=@{ko='{0}의 상세 사용법 문서가 아직 없습니다. 빠른 사용 안내를 엽니다.';en='No detailed guide exists for {0} yet. Opening the quick reference instead.'}
        GuiLaunching=@{ko='{0} 실행을 준비하고 있습니다...';en='Preparing to launch {0}...'}
        GuiLaunchPreview=@{ko='실행 전 미리보기';en='Launch preview'}
        GuiLaunchSessionPolicy=@{ko='실행 기록을 남깁니다. 고부하·쓰기·설정 변경 도구에는 시간 및 여유 메모리 중단 조건을 적용합니다. 온도는 HWiNFO에서 직접 감시하십시오. 계속하시겠습니까?';en='The launch is recorded. High-load, write, and system-changing tools receive timeout and free-memory stop conditions. Monitor temperatures directly in HWiNFO. Continue?'}
        GuiLaunchStarted=@{ko='{0} 프로그램을 실행했습니다.';en='Launched {0}.'}
        GuiLaunchFailed=@{ko='프로그램 실행 실패: {0}';en='Program launch failed: {0}'}
        GuiUnexpectedError=@{ko='예상하지 못한 작업 오류가 발생했습니다. GUI는 유지됩니다: {0}';en='An unexpected action error occurred. The dashboard remains open: {0}'}
        GuiLanguage=@{ko='EN';en='KO'}
        GuiReady=@{ko='대시보드 준비 완료';en='Dashboard ready'}
        GuiChecking=@{ko='{0} 프로필로 시스템을 분석하고 있습니다...';en='Analyzing the system with the {0} profile...'}
        GuiJobBusy=@{ko='이미 시스템 분석이 진행 중입니다.';en='A system analysis is already running.'}
        GuiSelectTool=@{ko='먼저 권장 프로그램 표에서 항목을 선택하십시오.';en='Select an item from the recommendation table first.'}
        GuiNotLaunchable=@{ko='이 항목은 Windows에서 직접 실행할 수 없습니다. 부팅형 도구 안내서를 확인하십시오.';en='This item cannot be launched directly in Windows. See the bootable-tool guide.'}
        GuiRiskConfirm=@{ko="위험 등급: {0}`n`n이 프로그램은 시스템 설정 변경, 고부하 또는 저장장치 쓰기를 수행할 수 있습니다. 관련 안내서를 확인했고 실행하시겠습니까?";en="Risk: {0}`n`nThis program may change system settings, create high load, or write to storage. Have you read the applicable guide and want to launch it?"}
        GuiNoPlan=@{ko='권장 프로그램 분석이 아직 완료되지 않았습니다.';en='The recommended program analysis has not completed yet.'}
        GuiValidationStarted=@{ko='별도 콘솔에서 무결성 검증을 시작했습니다.';en='Integrity validation started in a separate console.'}
        GuiGithubMissing=@{ko='GitHub 원격 저장소가 아직 연결되지 않아 로컬 README를 엽니다.';en='No GitHub remote is configured yet; opening the local README.'}
        GuiSelectedReason=@{ko='선택 도구';en='SELECTED TOOL'}
        GuiNoToolSelected=@{ko='도구를 선택하세요';en='Select a tool'}
        GuiAnalysisRunning=@{ko='분석 진행 중';en='Analysis running'}
        GuiAnalysisIdle=@{ko='분석 대기 중';en='Analysis idle'}
        GuiAnalysisButtonsDisabled=@{ko='분석 중에는 재실행 버튼이 비활성화됩니다.';en='Rerun buttons are disabled while analysis is running.'}
        GuiCheckPartial=@{ko='분석 완료 · 일부 항목은 아직 준비되지 않았습니다 ({0}/{1} 준비됨)';en='Analysis complete - some items are not ready yet ({0}/{1} ready)'}
        GuiCheckComplete=@{ko='분석 완료 · {0}개 권장 프로그램이 연결되었습니다';en='Analysis complete - {0} recommended programs connected'}
        GuiCheckFailed=@{ko='시스템 분석 실패: {0}';en='System analysis failed: {0}'}
        GuiCheckFailedNoDetail=@{ko='원인 정보가 없습니다. 로그 확인: {0}';en='No failure detail was reported. See log: {0}'}
        GuiProgressInventory=@{ko='1/3 시스템 정보 수집';en='1/3 collecting system inventory'}
        GuiProgressRecommendation=@{ko='2/3 권장 프로그램 분석';en='2/3 building recommendation plan'}
        GuiProgressConnection=@{ko='3/3 실행 연결 확인';en='3/3 verifying executable links'}
        GuiProgressReady=@{ko='분석 준비 완료';en='Analysis ready'}
        GuiProgressFailed=@{ko='분석 실패';en='Analysis failed'}
        GuiAdminStatus=@{ko='권한';en='Privilege'}
        GuiAdminElevated=@{ko='관리자';en='Administrator'}
        GuiAdminStandard=@{ko='일반 사용자';en='Standard user'}
        GuiAdminLimited=@{ko='일부 저장장치 정보 제한 가능';en='Some storage details may be limited'}
        GuiProgramName=@{ko='프로그램';en='Program'}
        GuiStorageDevices=@{ko='저장장치 {0}개';en='{0} storage devices'}
        GuiDetailName=@{ko='도구명';en='Tool name'}
        GuiDetailId=@{ko='실행 ID';en='Execution ID'}
        GuiDetailState=@{ko='권장 상태';en='Recommendation state'}
        GuiDetailRisk=@{ko='위험도';en='Risk'}
        GuiDetailMode=@{ko='실행 모드';en='Launch mode'}
        GuiDetailReady=@{ko='준비 상태';en='Ready state'}
        GuiDetailPath=@{ko='경로';en='Path'}
        GuiDetailAction=@{ko='실행 버튼은 현재 항목의 실제 실행 파일을 엽니다. 읽기 전용이 아닌 항목은 기존 확인 게이트를 유지합니다.';en='The launch button opens the exact executable for the selected row. Non-read-only items still keep the existing confirmation gate.'}
        GuiBootMediaGuide=@{ko='USB 부팅 안내서';en='Boot media guide'}
        ProgramReady=@{ko='준비됨';en='Ready'}
        ProgramMissing=@{ko='없음';en='Missing'}
        ProgramUnavailable=@{ko='실행 불가';en='Unavailable'}
        ProgramProfileGated=@{ko='확보됨 · 프로필 전환 필요';en='Acquired, switch profile'}
        ProgramBootReady=@{ko='부팅형 준비됨';en='Boot media ready'}
        StateRecommendedNow=@{ko='지금 권장';en='Recommended now'}
        StateGuidedTest=@{ko='가이드 테스트';en='Guided test'}
        StateConditionalHighWrite=@{ko='조건부 · 고위험 쓰기';en='Conditional · high-write'}
        StateConditionalUsbOnly=@{ko='조건부 · USB 전용';en='Conditional · USB-only'}
        StateConditionalDriverRecovery=@{ko='조건부 · 드라이버 복구';en='Conditional · driver recovery'}
        StateConditionalIfDumpExists=@{ko='조건부 · 덤프 있을 때';en='Conditional · if dump exists'}
        StateConditionalBootMedia=@{ko='조건부 · 부팅 매체 준비';en='Conditional · boot media prep'}
        StateDeferredBaseline=@{ko='보류 · 기준선 안정 후';en='Deferred · after baseline'}
        StateExternalBoot=@{ko='외부 부팅 검사';en='External boot test'}
        StateAvailableInProfile=@{ko='GPU·DDU 버튼에서 사용';en='Use via the GPU/DDU button'}
        StateUnknown=@{ko='상태 미상';en='Unknown state'}
        RiskReadOnly=@{ko='읽기 전용';en='Read-only'}
        RiskReadOnlyAdmin=@{ko='읽기 전용 · 관리자';en='Read-only · administrator'}
        RiskReadOnlyDefault=@{ko='읽기 전용';en='Read-only'}
        RiskReadOnlyHelp=@{ko='읽기 전용 도움말';en='Read-only help'}
        RiskWritesTestFile=@{ko='시험 파일 쓰기';en='Writes test file'}
        RiskHighLoad=@{ko='고부하';en='High load'}
        RiskVeryHighLoad=@{ko='초고부하';en='Very high load'}
        RiskSystemChanging=@{ko='시스템 변경';en='System changing'}
        RiskSystemChangingOptional=@{ko='선택적 시스템 변경';en='Optional system change'}
        RiskSystemChangingReboot=@{ko='시스템 변경 · 재부팅';en='System changing · reboot'}
        RiskInstallerChangesCpuSettings=@{ko='설치형 · CPU 설정 변경';en='Installer · changes CPU settings'}
        RiskInstallerChangesCpuMemorySettings=@{ko='설치형 · CPU/RAM 설정 변경';en='Installer · changes CPU/RAM settings'}
        RiskRebootExternalBoot=@{ko='재부팅 필요 · 외부 부팅';en='Requires reboot · external boot'}
        RiskChangesCoolingSettings=@{ko='냉각 설정 변경';en='Changes cooling settings'}
        RiskFillsFreeSpaceHighWrite=@{ko='고용량 쓰기';en='High write'}
        RiskWritesSpotChecksUsb=@{ko='USB 스폿체크 쓰기';en='USB spot-check write'}
        RiskMixedManual=@{ko='수동 혼합';en='Mixed manual'}
        RiskUnknown=@{ko='위험도 미상';en='Unknown risk'}
        LaunchModeGui=@{ko='GUI 실행';en='GUI'}
        LaunchModeInstaller=@{ko='설치형';en='Installer'}
        LaunchModeCli=@{ko='명령행';en='CLI'}
        LaunchModeCliHelp=@{ko='도움말 전용';en='Help only'}
        LaunchModeExternalBoot=@{ko='외부 부팅';en='External boot'}
        }
    $entry = $messages[$Key]
    if (-not $entry) { return $Key }
    $value = [string]$entry[$Language]
    if ($null -ne $ArgumentList -and $ArgumentList.Count -gt 0) { return $value -f $ArgumentList }
    return $value
}
