# WinPortableLab 한국어 안내

## 주요 명령

```powershell
.\Start.cmd -Mode inventory -Language ko
.\Start.cmd -Mode recommend -Language ko
.\Start.cmd -Mode validate -Language ko
.\Start.cmd -Mode launch -Language ko
.\Start.cmd -Mode smart -Language ko
.\WinPortableLab.ps1 -Action check -Profile quick -Language ko
.\WinPortableLab.ps1 -Action menu -Profile all -Language ko
```

통합 `WinPortableLab.ps1`은 시스템 정보와 최근 오류 신호를 확인하고, 권장 설정과 실제 실행 파일 경로가 들어 있는 `recommended-programs.json`을 생성합니다.

인자 없이 `WinPortableLab.ps1`을 실행하면 **원팩 포터블 코리아** WPF 대시보드가 열립니다. 창은 시스템 분석 후에도 종료되지 않으며 프로필별 분석, 권장 도구 선택 실행, 안전 도구 일괄 실행, 보고서와 GitHub 프로젝트 열기를 버튼으로 제공합니다.

빠른 점검·전체·저장장치·메모리·GPU 버튼은 이미 수집한 시스템 스냅샷을 재사용하고 권장 프로그램 목록만 바꿉니다. 하드웨어나 드라이버가 바뀐 뒤에만 **시스템 정보 새로고침**을 누르십시오. 메모리 카드에는 용량·DDR 세대·DIMM 수·동작 속도·모듈별 용량이 표시되고, 마우스를 올리면 슬롯·제조사·부품번호·전압·일련번호를 확인할 수 있습니다.

기본 실행은 Windows UAC 관리자 권한을 요청합니다. 승인하면 저장장치 신뢰성, 볼륨·파티션, TPM, BitLocker 보호 상태, Device Guard, 서명 드라이버, 장치 문제, 최근 업데이트, 페이지 파일과 전원 계획까지 상세 수집합니다. BitLocker 복구 키는 수집하지 않습니다. 의도적으로 제한된 일반 권한 보고서가 필요할 때만 `-NoElevation`을 사용하십시오.

```powershell
# 저장장치 전용 권장 프로그램과 실행 경로 생성
.\WinPortableLab.ps1 -Action list -Profile storage -Language ko

# 하나의 프로그램 실행
.\WinPortableLab.ps1 -Action launch -ToolId hwinfo -Language ko

# 읽기 전용 recommended-now GUI만 일괄 실행
.\WinPortableLab.ps1 -Action launch-recommended -Profile quick -Language ko

# 위험 도구는 안내서 확인 후 명시 승인 필요
.\WinPortableLab.ps1 -Action launch -ToolId prime95 -AcknowledgeRisk -Language ko
```

`launch-recommended`는 읽기 전용 GUI만 엽니다. Prime95, OCCT, 저장장치 쓰기, DDU, XTU/Ryzen Master 설치 프로그램은 자동 실행 대상에서 제외됩니다.

`recommend`는 Windows CIM으로 현재 CPU, 메인보드, BIOS, RAM, GPU, 저장장치를 읽고 다음 파일만 생성합니다.

- `recommended-settings.json`: 기계가 읽을 수 있는 권장값
- `recommended-settings.ko.md`: 한국어 설명
- `recommended-settings.en.md`: 영어 설명

BIOS, 전압, 배수, XMP/EXPO, PBO/CO, 팬 곡선이나 드라이버는 자동 적용하지 않습니다.

## 업데이트·오프라인 팩·감독 실행

~~~powershell
.\scripts\Test-ToolUpdates.ps1 -Root .
.\scripts\Test-ToolUpdates.ps1 -Root . -Online
.\scripts\New-OfflinePack.ps1 -Root . -IncludeRedistributableArchives
.\scripts\Start-WplToolSession.ps1 -Root . -LauncherId occt
.\scripts\Start-WplToolSession.ps1 -Root . -LauncherId occt -Start -AcceptRisk
.\scripts\Test-ToolLaunchers.ps1 -Root . -SmokeReadOnlyGui -Language ko
~~~

감독 실행은 sessions에 기록되며 기본 30분 제한, 여유 메모리 하한, 취소 요청을 적용합니다. GUI 도구는 DLL·설정 파일을 정상적으로 찾도록 실행 파일 폴더를 작업 경로로 사용합니다. CLI 도구는 보이는 콘솔에서 실행되고 `console-output.txt`에 내용을 남긴 뒤 사용자가 확인할 때까지 닫히지 않습니다. 센서 기준선과 부하 온도는 HWiNFO 하나로 감시합니다. HWiNFO 공유 메모리 연동은 라이선스와 실행 시간 제약이 있어 자동 중단 조건에 포함하지 않습니다.

TrafficMonitor Lite는 네트워크 속도와 CPU·RAM·GPU·디스크 사용률을 작업 표시줄에서 관찰합니다. ZenTimings는 AMD Ryzen에서만 권장되며 적용 타이밍을 확인하는 관리자 권한 도구입니다. Intel 시스템에서는 CPU-Z·HWiNFO와 상세 DIMM 보고서를 사용하십시오.

상단 하드웨어 카드는 OS·CPU·메인보드·BIOS·GPU·RAM·디스크를 독립적으로 조회합니다. 특정 클래스만 실패하면 나머지 카드는 계속 표시되고 `logs/gui-hardware-latest.log`에 실패 항목이 기록됩니다. 전체 권장 분석 실패 원인은 `logs/gui-analysis-latest.log`에 남습니다. 프로그램 실행은 실제 대상 PID가 시작됐다는 확인 신호를 받은 후에만 성공으로 표시하며, 현재 대시보드가 일반 권한이면 실행 감독기가 UAC를 요청합니다.

소스 인코딩은 Windows PowerShell 5.1과 PowerShell 7에서 동일하게 보이도록 UTF-8 BOM으로 통일했습니다. 검증 스크립트는 잘못된 UTF-8, 대체 문자, 대표적인 깨진 문자열과 BOM 없는 비ASCII PowerShell 파일을 차단합니다. GUI는 왼쪽 작업 선택, 중앙 권장 목록, 오른쪽 선택 도구 상세의 3단 구조입니다. 마지막 점검 시각과 프로필을 항상 표시하고 검색·상태 필터, 자동 첫 항목 선택, 고정 실행 버튼을 제공합니다.

## 안내서

- [시스템 맞춤 권장값](SETTING_GUIDE.md)
- [Intel CPU](CPU_INTEL.md)
- [AMD CPU](CPU_AMD.md)
- [GPU와 DDU](GPU_DDU.md)
- [RAM 오버클럭](RAM_OVERCLOCK.md)
- [SSD 더티·지속 쓰기·무결성 테스트](SSD_DIRTY_TEST.md)
- [안전 원칙](SAFETY.md)
