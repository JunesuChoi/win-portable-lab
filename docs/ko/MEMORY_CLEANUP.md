# 네이티브 메모리 정리

원팩에는 MemReduct가 제공하는 핵심적인 Windows 메모리 목록 정리 기능을 네이티브 API로 직접 호출하는 콘솔 기능이 있습니다. 별도 실행 파일을 번들하거나 내려받지 않으며, 메모리 상태를 읽고 사용자가 선택한 항목만 한 번 정리합니다.

## 무엇을 하는가

`WinPortableLab.Memory.psm1`은 `NtSetSystemInformation`의 `SystemMemoryListInformation`(정보 클래스 80)과 Windows의 `EmptyWorkingSet`, `SetSystemFileCacheSize`를 사용합니다. 실행 전후 스냅샷과 각 호출의 성공·실패·건너뜀 상태를 기록합니다. 작업은 현재 실행 동안만 적용되며 레지스트리나 영구 설정을 바꾸지 않습니다.

실제 정리에는 관리자 권한과 토큰의 `SeProfileSingleProcessPrivilege`가 필요합니다. 시스템 파일 캐시는 `SeIncreaseQuotaPrivilege`도 필요합니다. 일반 권한에서는 메모리 요약과 `-Report` 계획만 확인할 수 있습니다.

## 항목별 의미와 사용 시점

| 항목 | 동작 | 사용 시점 |
|---|---|---|
| `WorkingSet` | 프로세스 작업 집합을 비움 | 특정 앱을 다시 읽게 해도 되는 짧은 진단 전 |
| `SystemWorkingSet` | Windows 시스템 작업 집합을 비움 | 시스템 캐시가 비정상적으로 커졌는지 비교할 때 |
| `ModifiedPageList` | 디스크 기록 대기 중인 수정 페이지를 flush | 쓰기 작업이 끝난 뒤에만, 원인 비교가 필요할 때 |
| `StandbyList` | 재사용 가능한 대기 캐시 페이지를 비움 | 캐시 재사용보다 즉시 가용 메모리 비교가 중요한 일회성 점검 |
| `LowPriorityStandbyList` | 낮은 우선순위 대기 페이지만 비움 | 전체 대기 목록을 건드리지 않고 좁게 비교할 때 |
| `SystemFileCache` | 파일 캐시를 flush하고 기존 최소·최대 한도와 플래그를 원복 | 기본 선택에는 포함되지 않으며, 캐시 영향까지 확인할 때만 명시적으로 선택 |

`Combined`의 기본 구성은 `WorkingSet`, `SystemWorkingSet`, `ModifiedPageList`, `StandbyList`, `LowPriorityStandbyList`입니다. 파일 캐시는 기본에서 제외됩니다. 대기 목록·수정 목록·파일 캐시를 실제로 정리하려면 `-AcknowledgeRisk`가 필요합니다. 특정 프로세스만 대상으로 하려면 `-ProcessId`를 추가하십시오. 보호된 프로세스의 핸들을 열 수 없으면 해당 프로세스만 건너뛰고 결과에 개수를 남깁니다.

## 하지 않는 것

- `ClearPageFileAtShutdown`, `LargeSystemCache`, `DisablePagingExecutive` 같은 레지스트리나 시스템 설정을 변경하지 않습니다.
- 자동 실행, 부팅 시 실행, 임계값 기반 실행, 예약 작업을 만들지 않습니다.
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
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Area WorkingSet,SystemWorkingSet -Language ko
.\scripts\Clear-WplSystemMemory.ps1 -Root . -Area WorkingSet -ProcessId 1234,5678 -Language ko
```

`-Json`은 스냅샷, 전후 사용량, 변화량, 항목별 결과를 JSON으로 출력합니다. 모든 실행 결과는 `logs\memory-cleanup-<timestamp>.json`에도 남습니다. 이 기능은 시스템을 영구 변경하지 않으므로 별도의 복원 명령은 필요하지 않습니다.

## MemReduct와의 비교

| 구분 | 이 기능 | MemReduct와의 관계 |
|---|---|---|
| 작업 집합 정리 | 지원 (`WorkingSet`, `SystemWorkingSet`) | MemReduct의 핵심 작업 집합 정리와 같은 Windows 메모리 목록 명령을 사용 |
| 수정 페이지 목록 | 지원 (`ModifiedPageList`) | MemReduct의 수정 목록 flush와 같은 명령 상수 3 |
| 대기 목록 | 지원 (`StandbyList`, `LowPriorityStandbyList`) | MemReduct의 대기·낮은 우선순위 대기 목록과 같은 명령 상수 4·5 |
| 시스템 파일 캐시 | 명시 선택 시 지원, 기본 제외 | `SetSystemFileCacheSize(-1,-1,0)`로 flush한 뒤 읽어 둔 한도와 플래그를 원복 |
| 개별 프로세스 | 지원 (`EmptyWorkingSet`, `-ProcessId`) | MemReduct의 전체 정리 보완용으로 제공 |
| 자동·예약 정리 | 의도적으로 제외 | 프로젝트 원칙상 자동 실행과 예약 작업을 만들지 않음 |
| 레지스트리 캐시·레지스트리 설정 | 의도적으로 제외 | 설정 변경 없음 원칙과 범위를 지키며 레지스트리에 쓰지 않음 |
| 제3자 실행 파일 | 의도적으로 제외 | MemReduct 실행 파일을 번들·다운로드하지 않고 Win32/NT API를 직접 호출 |
| 모달 확인 창 | 의도적으로 제외 | GUI 안의 인라인 위험 확인란과 결과 표시를 사용 |

`NtSetSystemInformation`은 Windows SDK에 정식으로 선언되지 않은 내부 API라 Windows 버전에 따라 동작이 달라질 수 있습니다. 따라서 호출별 NTSTATUS와 전후 스냅샷을 기록하고, 실패 시 일반적인 시스템 설정 변경으로 대체하지 않습니다. API 선언과 파일 캐시 flush 인자는 [Microsoft Learn의 NtSetSystemInformation](https://learn.microsoft.com/ko-kr/windows/win32/sysinfo/ntsetsysteminformation) 및 [SetSystemFileCacheSize](https://learn.microsoft.com/en-us/windows/win32/api/memoryapi/nf-memoryapi-setsystemfilecachesize) 설명을 기준으로 했습니다.
