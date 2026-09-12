# 네이티브 메모리 정리

원팩에는 MemReduct가 제공하는 정리 영역 8개를 모두 같은 네이티브 API로 직접 호출하는 콘솔 기능이 있습니다. 별도 실행 파일을 번들하거나 내려받지 않으며, 메모리 상태를 읽고 사용자가 선택한 항목만 한 번 정리합니다.

## 무엇을 하는가

`WinPortableLab.Memory.psm1`은 `NtSetSystemInformation`의 `SystemMemoryListInformation`(클래스 80), `SystemFileCacheInformationEx`(클래스 81), `SystemCombinePhysicalMemoryInformation`(클래스 130), `SystemRegistryReconciliationInformation`(클래스 155)와 Windows의 `SetSystemFileCacheSize`, `EmptyWorkingSet`, `CreateFile`, `FlushFileBuffers`를 사용합니다. 실행 전후 스냅샷과 각 호출의 성공·실패·건너뜀 상태를 기록합니다. 작업은 현재 실행 동안만 적용되며 레지스트리 값이나 영구 설정을 바꾸지 않습니다.

실제 정리에는 관리자 권한과 토큰의 `SeProfileSingleProcessPrivilege`가 필요하며, 이 권한은 작업 집합·메모리 목록·물리 메모리 목록 병합에 함께 쓰입니다. 시스템 파일 캐시는 `SeIncreaseQuotaPrivilege`도 필요합니다. 일반 권한에서는 메모리 요약과 `-Report` 계획만 확인할 수 있습니다.

## 항목별 의미와 사용 시점

| 항목 | 동작 | 사용 시점 |
|---|---|---|
| `WorkingSet` | 프로세스 작업 집합을 비움 | 특정 앱을 다시 읽게 해도 되는 짧은 진단 전 |
| `SystemFileCache` | 파일 캐시를 flush하고 기존 최소·최대 한도와 플래그를 원복 | 캐시 영향까지 비교할 때. MemReduct 기본 마스크에 포함 |
| `ModifiedFileCache` | 탑재된 모든 볼륨의 쓰기 캐시를 flush | 파일 시스템 기록을 먼저 끝내야 할 때 |
| `ModifiedPageList` | 디스크 기록 대기 중인 수정 페이지를 flush | 선택형 freeze 영역. 쓰기 작업이 끝난 뒤에만 |
| `StandbyList` | 재사용 가능한 대기 캐시 페이지를 비움 | 선택형 freeze 영역. 즉시 가용 메모리 비교가 중요한 일회성 점검 |
| `LowPriorityStandbyList` | 낮은 우선순위 대기 페이지만 비움 | 전체 대기 목록을 건드리지 않고 좁게 비교할 때 |
| `RegistryCache` | 대기 중인 레지스트리 하이브를 디스크로 내림 (Windows 8.1 이상) | 레지스트리 사용이 많은 비교 전. 레지스트리 값은 바꾸지 않음 |
| `CombineMemoryLists` | 커널에 물리 메모리 목록 병합을 요청 (Windows 10 이상) | 물리 메모리 단편화를 줄일 때. MemReduct 기본 마스크에 포함 |

`Combined`의 기본 구성은 MemReduct의 기본 마스크와 같습니다. `WorkingSet`, `SystemFileCache`, `ModifiedFileCache`, `LowPriorityStandbyList`, `RegistryCache`, `CombineMemoryLists`이고, MemReduct가 freeze로 분류하는 `StandbyList`와 `ModifiedPageList`만 기본에서 빠집니다. 이 두 항목을 실제로 정리하려면 `-AcknowledgeRisk`가 필요합니다. `RegistryCache`와 `CombineMemoryLists`는 해당 클래스를 제공하지 않는 Windows 빌드에서 실행 대신 건너뜀으로 보고합니다. 특정 프로세스만 대상으로 하려면 `-ProcessId`를 추가하십시오. 보호된 프로세스의 핸들을 열 수 없으면 해당 프로세스만 건너뛰고 결과에 개수를 남깁니다.

실행할 때마다 `logs\memory-cleanup-stats.json`에 실행 횟수, 누적 확보량, 마지막 정리 시각이 누적됩니다. MemReduct가 설정 파일에 남기는 통계와 같은 항목입니다.

## 자동 정리와 상주 모니터링

자동 정리는 옵트인입니다. `config\settings.json`의 `memoryAutoCleanup` 항목이 기준 사용률, 최소 간격, 확인 주기와 대상 영역을 보관하며, 기본값은 MemReduct의 자동 축소와 같은 90%·30초·30초입니다. 기준을 넘고 최소 간격이 지나면 기본 묶음만 정리합니다. 대기 목록과 수정 페이지 목록은 자동 대상에서 제외되므로, 승인 없이 재사용 가능한 페이지를 버리는 일이 없습니다.

GUI의 `자동 정리 · 상주 모니터링` 영역에서 설정을 저장하거나, 같은 판정을 콘솔에서 한 번 실행할 수 있습니다.

```powershell
.\WinPortableLab.ps1 -Action memory-auto -Report -Json -Language ko
.\WinPortableLab.ps1 -Action memory-auto -Language ko
```

`-Report`는 판정 결과만 보여주고 실제 정리는 하지 않습니다. 상주 모니터링은 GUI 창이 열려 있는 동안 동작하며, 알림 영역 아이콘에서 창 열기·지금 정리·자동 정리 켜기/끄기·종료를 할 수 있습니다. `Windows 시작 시 상주 실행 등록`을 선택하면 로그온 때 트레이로 시작합니다. 등록은 `HKCU`의 `Run` 값 하나뿐이라 관리자 권한이 필요 없고 같은 화면에서 다시 해제할 수 있습니다. 원팩이 호스트에 남기는 영구 흔적은 이 값 하나이며, 해제하면 남는 것이 없습니다.

## 하지 않는 것

- `ClearPageFileAtShutdown`, `LargeSystemCache`, `DisablePagingExecutive` 같은 레지스트리 값이나 시스템 설정을 변경하지 않습니다. 레지스트리 캐시 정리는 값을 쓰지 않고 대기 중인 하이브를 디스크로 내리기만 합니다.
- 메모리 누수 진단 도구가 아닙니다. 누수 원인은 프로세스별 추적과 장시간 관찰로 확인해야 합니다.
- 안정성 테스트가 아닙니다. RAM 오버클럭·CPU·GPU 검증은 TestMem5, OCCT 등 별도 도구로 수행하십시오.
- 페이지 파일 크기, 프리페치, 서비스, 전원 계획을 변경하지 않습니다.

정리는 캐시를 버리는 일시적인 동작입니다. 다시 필요한 데이터는 Windows가 저장장치에서 읽어오므로, 정리 직후 첫 실행이 느려질 수 있습니다. 되돌릴 설정이 없으며 재부팅도 필요하지 않습니다.

## 명령행

권한 없이 계획만 확인합니다.

```powershell
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Report -Language ko
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Report -Json -Language ko
```

기본 묶음을 실제 실행하려면 관리자 PowerShell에서 위험을 확인합니다.

```powershell
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Area Combined -AcknowledgeRisk -Language ko
```

작업 집합만 선택하면 위험 확인 없이 실행할 수 있습니다.

```powershell
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Area WorkingSet -Language ko
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Area WorkingSet -ProcessId 1234,5678 -Language ko
```

`-Json`은 스냅샷, 전후 사용량, 변화량, 항목별 결과와 누적 통계를 JSON으로 출력합니다. 모든 실행 결과는 `logs\memory-cleanup-<timestamp>.json`에도 남습니다. 이 기능은 시스템을 영구 변경하지 않으므로 별도의 복원 명령은 필요하지 않습니다.

## MemReduct와의 비교

| 구분 | 이 기능 | MemReduct와의 관계 |
|---|---|---|
| 작업 집합 정리 | 지원 (`WorkingSet`) | MemReduct의 `REDUCT_WORKINGSET`과 같은 `MemoryEmptyWorkingSets` 명령 |
| 수정 페이지 목록 | 지원 (`ModifiedPageList`) | MemReduct의 `REDUCT_MODIFIEDLIST`과 같은 명령 상수 3 |
| 대기 목록 | 지원 (`StandbyList`, `LowPriorityStandbyList`) | MemReduct의 `REDUCT_STANDBYLIST`·`REDUCT_STANDBYPRIORITY0LIST`과 같은 명령 상수 4·5 |
| 시스템 파일 캐시 | 지원 (`SystemFileCache`) | MemReduct가 `SystemFileCacheInformationEx`로 요청하는 것과 같은 flush. 이 구현은 현재 한도를 먼저 읽어 원복 |
| 볼륨 쓰기 캐시 | 지원 (`ModifiedFileCache`) | `REDUCT_MODIFIEDFILECACHE`와 같은 볼륨 캐시 flush. 마운트 관리자 IOCTL 대신 문서화된 `CreateFile`/`FlushFileBuffers` 사용 |
| 레지스트리 캐시 | 지원 (`RegistryCache`) | `REDUCT_REGISTRYCACHE`와 같은 `SystemRegistryReconciliationInformation` 호출, 같은 Windows 8.1 게이트 |
| 물리 메모리 목록 병합 | 지원 (`CombineMemoryLists`) | `REDUCT_COMBINEMEMORYLISTS`와 같은 `SystemCombinePhysicalMemoryInformation` 호출, 같은 Windows 10 게이트 |
| 정리 통계 | 지원 (`logs\memory-cleanup-stats.json`) | MemReduct가 남기는 실행 횟수·누적 확보량·마지막 정리 시각과 같은 항목 |
| 개별 프로세스 | 지원 (`EmptyWorkingSet`, `-ProcessId`) | MemReduct의 전체 정리 보완용으로 제공 |
| 자동 정리 | 지원 (`memory-auto`, 기준 90%·최소 간격 30초) | MemReduct의 자동 축소와 같은 기본값. 대상은 기본 묶음으로 제한 |
| 상주 모니터링·트레이 아이콘 | 지원 (`-StartMinimized`, 알림 영역 메뉴) | MemReduct처럼 상주하며 창을 닫아도 감시가 유지됨 |
| Windows 시작 등록 | 지원 (`scripts\Set-WplStartup.ps1`, HKCU Run 1개) | 로그온 시 트레이로 시작. 관리자 권한 불필요, 같은 명령으로 완전 해제 |
| 전역 단축키 | 의도적으로 제외 | 트레이 메뉴로 같은 동작을 제공하고, 상주 프로세스에 키 후크를 두지 않음 |
| 레지스트리 값·시스템 설정 변경 | 범위 유지 | `ClearPageFileAtShutdown`·`LargeSystemCache`·`DisablePagingExecutive` 등은 쓰지 않음. 유일한 예외는 위 시작 등록 1개 |
| 기본 마스크 | `Combined`가 `REDUCT_MASK_DEFAULT`와 동일 | 기본 6개 영역이 그대로 실행되고 freeze 2개만 선택형으로 남음 |
| 제3자 실행 파일 | 의도적으로 제외 | MemReduct 실행 파일을 번들·다운로드하지 않고 Win32/NT API를 직접 호출 |
| 모달 확인 창 | 의도적으로 제외 | GUI 안의 인라인 위험 확인란과 결과 표시를 사용 |

`NtSetSystemInformation`은 Windows SDK에 정식으로 선언되지 않은 내부 API라 Windows 버전에 따라 동작이 달라질 수 있습니다. 따라서 호출별 NTSTATUS와 전후 스냅샷을 기록하고, 실패 시 일반적인 시스템 설정 변경으로 대체하지 않습니다. API 선언과 파일 캐시 flush 인자는 [Microsoft Learn의 NtSetSystemInformation](https://learn.microsoft.com/ko-kr/windows/win32/sysinfo/ntsetsysteminformation) 및 [SetSystemFileCacheSize](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-setsystemfilecachesize) 설명을 기준으로 했습니다.
