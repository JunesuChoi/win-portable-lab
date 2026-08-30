# Glary Utilities Portable 상세 사용법

시작 프로그램, 디스크 사용량, 시스템 정보를 한 화면에서 확인할 수 있는 종합 유지관리 도구입니다. 이 프로젝트에서는 **읽기 전용 점검 용도로만** 사용합니다. 정리·삭제 기능은 진단 결과를 훼손할 수 있어 범위 밖입니다.

실행 ID는 `glary-utilities`이고 위험도는 시스템 변경입니다.

## 이 프로젝트에서 쓰는 기능

| 기능 | 용도 | 성격 |
|---|---|---|
| Startup Manager | 부팅 시 자동 실행 항목 확인 | 읽기 확인 후 선택적 비활성화 |
| Disk Analysis | 디스크 사용량 분포 | 읽기 전용 |
| System Information | 하드웨어·OS 요약 | 읽기 전용 |
| Process Manager | 실행 중 프로세스 확인 | 읽기 전용 |

부팅이 느린 원인을 찾을 때 Startup Manager가 유용합니다. Autoruns보다 항목이 적게 표시되지만 그만큼 읽기 쉽습니다. 정밀한 추적이 필요하면 Autoruns를 씁니다.

## 쓰지 않는 기능

패키지에는 아래 기능도 들어 있지만 이 프로젝트의 원칙과 충돌합니다.

| 기능 | 왜 쓰지 않는가 |
|---|---|
| Registry Cleaner | 레지스트리 정리는 이득이 불확실하고 되돌리기 어렵습니다 |
| 1-Click Maintenance | 여러 변경을 한 번에 적용해 무엇이 바뀌었는지 추적 불가 |
| Disk Cleaner | 진단 근거가 되는 로그와 덤프를 지울 수 있습니다 |
| Tracks Eraser | 이벤트 기록 삭제. 원인 추적을 방해합니다 |
| File Shredder | 복구 불가 삭제 |
| Boot Defrag | 커널 드라이버(`BootDefragDriver.sys`)를 적재합니다 |
| Uninstaller | 프로그램 제거는 점검 범위를 넘습니다 |
| Registry Defrag | 재부팅 중 레지스트리를 재작성합니다 |

특히 Disk Cleaner와 Tracks Eraser는 주의가 필요합니다. 이 프로젝트는 이벤트 로그와 미니덤프를 진단 근거로 쓰는데, 이 기능들이 그 근거를 지울 수 있습니다. **점검 전에 정리 도구를 돌리면 원인을 찾을 수 없게 됩니다.**

## 실행 시 주의

1. 첫 화면의 1-Click Maintenance 버튼을 누르지 않습니다. 여러 정리 작업이 한꺼번에 실행됩니다.
2. Advanced Tools 탭에서 필요한 개별 기능만 엽니다.
3. 무료판은 실행 시 유료판 안내가 표시됩니다. 기능 제한이 있을 수 있습니다.
4. 포터블판이지만 일부 기능은 서비스나 드라이버를 적재합니다. 완전한 무흔적 실행이 보장되지 않습니다.

## 라이선스

개인 사용은 무료입니다. 업무용은 라이선스가 필요합니다. 이 프로젝트는 오프라인 팩에 포함하지 않습니다.

## 다른 도구와의 관계

시작 항목 정밀 분석은 Sysinternals Autoruns가, 프로세스 상세는 Process Explorer가, 디스크 공간 분석은 WizTree가 더 정확하고 빠릅니다. 글래리는 여러 기능을 한 화면에서 훑을 때의 편의성이 장점이므로, 초기 개요 파악용으로 쓰고 정밀 분석은 전용 도구로 넘기는 편이 좋습니다.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id glary-utilities -AcknowledgeRisk -Language ko
```

