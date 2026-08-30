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
        GuiDetailTitleOs=@{ko='운영체제 상세 정보';en='Operating system detail'}
        GuiDetailTitleCpu=@{ko='CPU · 메인보드 상세 정보';en='CPU and mainboard detail'}
        GuiDetailTitleGpu=@{ko='그래픽 상세 정보';en='Graphics detail'}
        GuiDetailTitleMemory=@{ko='메모리 · 저장장치 상세 정보';en='Memory and storage detail'}
        GuiDetailClose=@{ko='닫기';en='Close'}
        GuiDetailUnavailable=@{ko='아직 수집된 상세 정보가 없습니다. 시스템 정보 새로고침을 먼저 실행하세요.';en='No detail has been collected yet. Run the system information refresh first.'}
        GuiOpenVendorPage=@{ko='제조사 지원 페이지 열기';en='Open vendor support page'}
        AdviceBiosHeading=@{ko='BIOS 업데이트 확인 권장';en='Check for a BIOS update'}
        AdviceGpuHeading=@{ko='그래픽 드라이버 업데이트 확인 권장';en='Check for a graphics driver update'}
        AdviceBiosCheckHeading=@{ko='BIOS 버전 확인';en='BIOS version'}
        AdviceGpuCheckHeading=@{ko='그래픽 드라이버 버전 확인';en='Graphics driver version'}
        AdviceBiosRecent=@{ko='설치된 BIOS {0} (출시 {1})은 약 {2}개월 전 버전입니다. 비교적 최근이지만 더 새 버전이 나왔을 수 있으니 필요하면 제조사 페이지에서 확인하세요.';en='The installed BIOS {0} (released {1}) is about {2} months old. That is fairly recent, but a newer release may exist; check the vendor page if needed.'}
        AdviceGpuDriverRecent=@{ko='드라이버 {0} (출시 {1})은 약 {2}개월 전 버전입니다. 비교적 최근이지만 더 새 버전이 나왔을 수 있으니 아래에서 확인할 수 있습니다.';en='Driver {0} (released {1}) is about {2} months old. That is fairly recent, but a newer release may exist; you can check below.'}
        AdviceGpuDriverUnknownDate=@{ko='드라이버 {0}의 출시 날짜를 확인할 수 없습니다. 최신 버전은 아래에서 확인하세요.';en='The release date for driver {0} could not be read. Check the latest version below.'}
        AdviceBiosAge=@{ko='설치된 BIOS {0} (출시 {1})은 약 {2}개월 전 버전입니다. 제조사 페이지에서 더 새 버전이 있는지 확인하세요. 이 도구는 최신 버전 목록을 조회하지 않습니다.';en='The installed BIOS {0} (released {1}) is about {2} months old. Check the vendor page for a newer release. This tool does not query vendor catalogues.'}
        AdviceGpuDriverAge=@{ko='드라이버 {0} (출시 {1})은 약 {2}개월 전 버전입니다. 제조사 페이지에서 더 새 버전이 있는지 확인하세요. 이 도구는 최신 버전 목록을 조회하지 않습니다.';en='Driver {0} (released {1}) is about {2} months old. Check the vendor page for a newer release. This tool does not query vendor catalogues.'}
        GuiCheckLatestDriver=@{ko='최신 버전 온라인 확인';en='Check latest version online'}
        GuiSearchBios=@{ko='내 모델 BIOS 검색 열기';en='Search BIOS for this model'}
        GuiBiosManualSteps=@{ko='확인 순서: 검색 결과에서 {0} 제품 페이지를 열고 BIOS 또는 지원 탭으로 이동한 뒤, 최신 버전 번호를 현재 설치본 {1}과 비교하세요. 같으면 최신입니다.';en='How to check: open the {0} product page from the search results, go to its BIOS or support tab, then compare the newest version number with the installed {1}. If they match, it is current.'}
        GuiCheckingLatest=@{ko='제조사 서버에서 최신 버전을 확인하는 중입니다...';en='Checking the vendor server for the latest version...'}
        GuiCheckLatestFailed=@{ko='온라인 확인 실패({0}). 네트워크가 없거나 제조사 응답이 바뀌었을 수 있습니다. 제조사 페이지에서 직접 확인하세요.';en='Online check failed ({0}). There may be no network, or the vendor response changed. Confirm on the vendor page instead.'}
        GuiLatestAvailable=@{ko='최신 버전 {0} (출시 {1})이 있습니다. 설치본보다 새 버전입니다.';en='Version {0} (released {1}) is available and is newer than what is installed.'}
        GuiLatestCurrent=@{ko='설치된 드라이버가 최신입니다 ({0}).';en='The installed driver is current ({0}).'}
        GuiLatestAhead=@{ko='설치된 드라이버가 공개된 최신본 {0}보다 새 버전입니다. 베타나 OEM 빌드일 수 있습니다.';en='The installed driver is newer than the published release {0}. It may be a beta or OEM build.'}
        GuiLatestUnknown=@{ko='제조사 최신본은 {0} (출시 {1})입니다. 설치본과 자동 비교하지 못했으니 직접 확인하세요.';en='The vendor lists {0} (released {1}). Automatic comparison was not possible, so verify manually.'}
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
        NetDriverAdapters=@{ko='물리 네트워크 어댑터 {0}개를 확인했습니다.';en='Detected {0} physical network adapter(s).'}
        NetDriverSdioState=@{ko='SDIO 상태: 설치={0}, 인덱스 {1}개, 드라이버 팩 {2}개';en='SDIO state: installed={0}, indexes={1}, driver packs={2}'}
        NetDriverPacksMissing=@{ko='SDIO 인덱스만 있고 실제 드라이버 팩이 없습니다. 오프라인 설치를 하려면 인터넷이 되는 PC에서 SDIO를 실행해 네트워크 팩을 받은 뒤 {0} 폴더를 그대로 복사하십시오.';en='SDIO has indexes but no driver archives. For an offline install, run SDIO on a PC that still has internet, download the network packs, then copy the {0} folder as-is.'}
        NetDriverBackupCount=@{ko='보관된 드라이버 백업 {0}개. 위치: {1}';en='{0} driver backup(s) stored in {1}.'}
        NetDriverOfflineReady=@{ko='오프라인 네트워크 드라이버 복구 자료가 준비되어 있습니다.';en='Offline network driver recovery material is available.'}
        NetDriverOfflineNotReady=@{ko='오프라인 복구 자료가 없습니다. 네트워크가 살아 있는 동안 backup 동작을 먼저 실행하거나 SDIO 팩을 준비하십시오.';en='No offline recovery material yet. Run the backup action while the network still works, or prepare SDIO packs.'}
        NetDriverNoAdapters=@{ko='물리 네트워크 어댑터를 찾지 못했습니다. 백업할 대상이 없습니다.';en='No physical network adapter was found, so there is nothing to back up.'}
        NetDriverBackupDone=@{ko='네트워크 드라이버 {0}/{1}개를 내보냈습니다. 위치: {2}';en='Exported {0} of {1} network drivers to {2}.'}
        NetDriverNoBackups=@{ko='{0}에 저장된 드라이버 백업이 없습니다.';en='No driver backup is stored in {0}.'}
        NetDriverRestoreNeedsRisk=@{ko='드라이버 복원은 시스템을 변경합니다. 안내서를 읽은 뒤 -AcknowledgeRisk와 함께 다시 실행하십시오.';en='Restoring a driver changes the system. Re-run with -AcknowledgeRisk after reading the guide.'}
        NetDriverRestoreNeedsPath=@{ko='복원할 백업 폴더 경로가 필요합니다. -BackupPath 값을 지정하십시오.';en='The backup folder to restore is required. Provide -BackupPath.'}
        NetDriverRestoreBadPath=@{ko='백업 폴더를 찾을 수 없습니다: {0}';en='Backup folder not found: {0}'}
        NetDriverRestoreNoInf=@{ko='{0}에서 설치할 INF 파일을 찾지 못했습니다.';en='No INF file to install was found in {0}.'}
        NetDriverRestoreDone=@{ko='INF {0}/{1}개를 드라이버 저장소에 추가했습니다. 안내가 나오면 재부팅하십시오.';en='Added {0} of {1} INF packages to the driver store. Reboot if Windows asks for it.'}
        NetDriverNeedsAdmin=@{ko='드라이버 내보내기와 설치에는 관리자 권한이 필요합니다. 관리자 권한으로 다시 실행하십시오.';en='Exporting and installing drivers requires administrator rights. Re-run elevated.'}
        NetDriverPauseHint=@{ko='창을 닫으려면 Enter 키를 누르십시오.';en='Press Enter to close this window.'}
        GuiNetworkDriver=@{ko='네트워크 드라이버';en='Network drivers'}
        GuiNetDriverTitle=@{ko='네트워크 드라이버 백업과 오프라인 설치';en='Network driver backup and offline install'}
        GuiNetDriverIntro=@{ko='랜과 무선 드라이버가 없으면 인터넷 자체가 안 되므로 다른 드라이버보다 먼저 확보해야 합니다. 네트워크가 살아 있는 지금 백업해 두면, 재설치한 PC에서 이 USB만으로 랜을 살릴 수 있습니다.';en='Without a LAN or Wi-Fi driver there is no internet at all, so it must be secured before every other driver. Back it up while the network still works and this USB alone can restore connectivity on a freshly installed PC.'}
        GuiNetDriverStatusAction=@{ko='상태 확인';en='Check status'}
        GuiNetDriverBackupAction=@{ko='지금 백업';en='Back up now'}
        GuiNetDriverListAction=@{ko='백업 목록';en='List backups'}
        GuiNetDriverRestoreAction=@{ko='선택 백업 설치';en='Install selected backup'}
        GuiNetDriverSdioAction=@{ko='SDIO 오프라인 설치';en='SDIO offline install'}
        GuiNetDriverGuideAction=@{ko='안내서 열기';en='Open guide'}
        GuiNetDriverBackupLabel=@{ko='설치에 사용할 백업';en='Backup to install'}
        GuiNetDriverRunning=@{ko='{0} 작업을 실행하고 있습니다...';en='Running the {0} action...'}
        GuiNetDriverNoBackupSelected=@{ko='설치할 백업을 먼저 선택하십시오. 목록이 비어 있으면 이 PC나 같은 모델 PC에서 백업을 먼저 만드십시오.';en='Select a backup to install first. If the list is empty, create a backup on this PC or on the same model first.'}
        GuiNetDriverRestoreConfirm=@{ko="'{0}' 백업의 네트워크 드라이버를 이 PC에 설치합니다. 드라이버 저장소가 변경되고 재부팅이 필요할 수 있습니다. 계속하시겠습니까?";en="This installs the network drivers from '{0}' on this PC. The driver store changes and a reboot may be required. Continue?"}
        GuiNetDriverActionFailed=@{ko='네트워크 드라이버 작업 실패: {0}';en='Network driver action failed: {0}'}
        GuiNetDriverBackupConfirm=@{ko='현재 PC의 네트워크 드라이버를 USB로 내보냅니다. 시스템 설정은 바꾸지 않습니다. 계속하시겠습니까?';en='This exports the current network drivers to the USB. No system setting is changed. Continue?'}
       GuiNetDriverSdioMissing=@{ko='SDIO 실행 파일을 찾지 못했습니다. 도구 목록에서 SDIO 준비 상태를 확인하십시오.';en='The SDIO executable was not found. Check the SDIO readiness in the tool list.'}
        GuiNetDriverOnePackAction=@{ko='원팩 받기 경로';en='Get a network one-pack'}
        GuiNetDriverOnePackTitle=@{ko='네트워크 드라이버 원팩 받는 경로';en='Where to get a network driver one-pack'}
        GuiNetDriverOnePackIntro=@{ko='랜이 죽은 PC를 살리려면 랜 드라이버가 미리 담긴 통합팩이 필요합니다. 아래는 실제로 널리 쓰이는 세 갈래입니다. 이 프로젝트는 용량과 배포 조건 때문에 팩 자체를 포함하지 않고, 인터넷이 되는 지금 직접 받아 USB에 두도록 경로만 안내합니다.';en='Reviving a PC with no LAN needs a pack that already contains the network driver. These are the three routes people actually use. This project does not bundle the packs themselves because of their size and distribution terms; it points you at the source so you can fetch one now, while you still have internet, and keep it on the USB.'}
        GuiNetDriverOnePackOpen=@{ko='다운로드 페이지 열기';en='Open download page'}
        GuiNetDriverOnePackCopy=@{ko='주소 복사';en='Copy address'}
        GuiNetDriverOnePackCopied=@{ko='주소를 클립보드에 복사했습니다: {0}';en='Address copied to the clipboard: {0}'}
       GuiNetPackBundled=@{ko='이 USB에 본체 포함됨';en='Program bundled on this USB'}
        GuiNetPackReputation=@{ko='커뮤니티 평판';en='Community reputation'}
        GuiNetPackOfficialOnly=@{ko='공식 배포처에서만 받으십시오. 이 도구들은 서드파티 PE 이미지와 파일공유 게시판에 널리 재배포되며, 비공식 사본에는 광고 설치기나 채굴기가 심긴 변조본이 확인된 사례가 있습니다.';en='Download from the official source only. These tools are widely re-hosted in third-party PE images and file-sharing boards, and tampered copies carrying adware installers or coin miners have been observed in unofficial mirrors.'}
        GuiNetPackUserResponsibility=@{ko='사용 여부와 결과에 대한 판단과 책임은 사용자에게 있습니다. 이 프로젝트는 경로와 알려진 평판만 제공하며 서드파티 배포물을 보증하지 않습니다.';en='The decision to use these tools, and the outcome, rest with the operator. This project provides the source and the known reputation only; it does not vouch for third-party distributions.'}
        GuiNetPack3dpReputation=@{ko='국내 커뮤니티에서 오래 쓰인 도구로, 랜 복구 용도로는 평가가 안정적입니다. 검색으로 나오는 재배포본에 광고 설치기가 끼워진 사례가 보고되므로 공식 페이지만 사용하십시오.';en='Long-established in Korean communities and consistently well regarded for LAN recovery specifically. Mirrors found through search have been reported to bundle adware installers, so use the official page only.'}
        GuiNetPackSdioReputation=@{ko='영어권 커뮤니티가 오프라인 드라이버 팩 대안으로 가장 자주 지목하는 도구입니다. 오픈소스이고 광고를 끼우지 않아 셋 중 평판이 가장 깨끗합니다.';en='The tool English-speaking communities most often point to as the offline driver pack option. It is open source and bundles no adware, giving it the cleanest reputation of the three.'}
        GuiNetPackDrvceoReputation=@{ko='평이 갈립니다. 중국 수리·시스템 배포 기술자 사이에서는 정상 유틸리티로 통하고 구세대 드라이버 도구보다 낫다는 평가를 받습니다. 반면 레딧과 보안 커뮤니티는 이런 자동 드라이버 설치기 전반을 권하지 않고 PUP(잠재적 원치 않는 프로그램) 위험으로 분류합니다. 설치 뒤에는 브라우저 홈페이지와 확장, 새로 설치된 앱을 반드시 점검하십시오.';en='Opinion is split. Chinese repair and system-deployment technicians treat it as a legitimate utility and rate it above the older generation of driver tools. Reddit and security communities, by contrast, advise against automatic driver installers as a class and file it under PUP (potentially unwanted program) risk. After installing, check your browser home page, extensions, and newly installed apps.'}
        GuiNetPack3dpNote=@{ko='용량 약 100MB · 한국어 공식 배포 · 자동 압축 해제형';en='About 100 MB, official Korean distribution, self-extracting'}
        GuiNetPack3dpDesc=@{ko='랜카드 모델을 자동으로 감지해 오프라인에서 유선·무선 드라이버를 설치합니다. 셋 중 가장 가볍고 한국어 안내가 있어, 랜만 살리는 목적이면 첫 선택으로 적당합니다. 랜이 붙은 뒤 나머지 드라이버는 3DP Chip이나 SDIO로 이어서 처리하십시오. 변조본을 피하려면 공식 페이지에서만 받으십시오.';en='Detects the network card model and installs the wired or wireless driver offline. It is the lightest of the three and ships Korean guidance, which makes it a sensible first choice when the only goal is getting LAN back. Once the link is up, continue with 3DP Chip or SDIO for the remaining drivers. Download only from the official page to avoid repackaged builds.'}
        UntrustedOverrideBlocked=@{ko="'{0}'은(는) 사용자 지정 경로로 연결되어 있습니다: {1} (도구 폴더 내부: {2}, 서명: {3}). 이 경로는 관리자 권한으로 실행됩니다. 확인했다면 -AcknowledgeRisk와 함께 다시 실행하십시오.";en="'{0}' resolves through a user-declared path: {1} (inside tools root: {2}, signature: {3}). It would run with administrator rights. Re-run with -AcknowledgeRisk once you have verified it."}
        GuiOverrideConfirm=@{ko="'{0}'은(는) 번들 도구가 아니라 사용자 지정 경로로 실행됩니다.`n`n경로: {1}`n도구 폴더 내부: {2}`n서명 상태: {3}`n`n이 파일은 관리자 권한으로 실행됩니다. 신뢰할 수 있는 파일인지 확인했습니까?";en="'{0}' will start from a user-declared path rather than the bundled tool.`n`nPath: {1}`nInside tools root: {2}`nSignature: {3}`n`nThis file runs with administrator rights. Have you verified that you trust it?"}
        GuiOverrideBadge=@{ko='사용자 지정 경로';en='User-declared path'}
        GuiNetPackSdioNote=@{ko='네트워크 팩만 고르면 수 GB · 본체는 이미 이 USB에 있음';en='A few GB if you select only the network packs; the program already ships on this USB'}
        GuiNetPackSdioDesc=@{ko='이 프로젝트에 포함된 SDIO 본체에 팩만 추가로 받는 방식입니다. 첫 실행 안내에서 네트워크 드라이버만 받기를 고르거나, 상단 업데이트 목록에서 _LAN_ 과 _WLAN-WiFi_ 항목만 체크하십시오. 전체 팩은 60GB를 넘지만 네트워크 계열만 고르면 수 GB로 끝납니다. 받은 팩은 drivers 폴더에 그대로 두십시오.';en='Add just the packs to the SDIO program this project already bundles. Pick the network-drivers-only option on the first-run prompt, or tick only the _LAN_ and _WLAN-WiFi_ entries in the update list. The full collection exceeds 60 GB, but the network families alone finish in a few GB. Leave the downloaded packs in the drivers folder.'}
        GuiNetPackDrvceoNote=@{ko='랜카드 버전 수백 MB · 중국어 화면 · 백신 오탐 사례 있음';en='Network-card edition is a few hundred MB, Chinese interface, antivirus false positives reported'}
        GuiNetPackDrvceoDesc=@{ko='중국 SysCeo가 배포하는 통합 드라이버 도구로, 만능 랜카드 버전과 무설치 판을 따로 제공합니다. 랜카드 외에 USB와 저장장치 컨트롤러까지 담아, 랜 자체가 잡히지 않는 까다로운 기종에서 마지막 수단으로 쓸 만합니다. 다만 화면이 중국어이고 드라이버 주입 방식 때문에 백신이 악성으로 오탐하는 사례가 보고됩니다. 셋 중 가장 신중하게 판단할 항목입니다.';en="SysCeo's all-in-one driver tool, distributed as a universal network-card edition plus a separate no-install build. It also carries USB and storage controller drivers, which makes it a reasonable last resort on awkward machines where the NIC is not detected at all. The interface is Chinese, and its driver-injection approach is reported to trigger antivirus false positives, so treat it as the entry needing the most judgement."}
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
