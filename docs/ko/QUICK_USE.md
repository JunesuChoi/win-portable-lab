# 도구 빠른 사용 안내

각 도구가 무엇을 보는 것인지, 언제 쓰는지, 무엇을 확인하면 정상인지만 짧게 정리했습니다. 옵션별 상세 설명은 `docs/ko/tools/` 폴더의 도구별 문서를 참고합니다.

모든 도구는 GUI에서 목록을 선택해 실행하거나 아래 명령으로 열 수 있습니다. 명령은 프로그램 창만 열고 검사를 자동으로 시작하지 않습니다.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id <도구ID> -Language ko
```

## 시스템 정보와 모니터링

| 도구 | 무엇을 보는가 | 언제 쓰는가 | 정상 판단 |
|---|---|---|---|
| CPU-Z (`cpuz`) | CPU, 메인보드, 메모리 구성 | 점검 시작 시 구성 확인 | 모델과 메모리 클럭이 예상과 일치 |
| GPU-Z (`gpuz`) | GPU 모델, 드라이버, 센서 | 그래픽 문제 확인 시작 | 드라이버 버전과 PCIe 링크 폭이 정상 |
| HWiNFO (`hwinfo`) | 온도, 클럭, 전압, 스로틀링 | 모든 부하 검사 중 상시 감시 | 부하 중 온도 한계 미달, 스로틀링 없음 |
| BatteryInfoView (`batteryinfoview`) | 배터리 설계 용량 대비 마모율, 사이클 | 노트북 현장 점검 | 마모율이 사용 기간에 비해 과도하지 않음 |
| FanControl (`fancontrol`) | 팬 곡선 설정 | 소음·냉각 조정이 필요할 때 | 부하 중 온도가 안정 구간 유지 |

## 저장장치 상태와 테스트

| 도구 | 무엇을 보는가 | 언제 쓰는가 | 정상 판단 |
|---|---|---|---|
| CrystalDiskInfo (`crystaldiskinfo`) | SMART 상태, 온도, 수명 | 모든 쓰기 테스트 전후 | 상태 `좋음`, 재할당 섹터 증가 없음 |
| smartctl (`smartctl-scan`) | SMART 원시값과 자기진단 로그 | 상세 수치가 필요할 때 | 미디어 오류와 오류 로그 항목이 0 |
| WizTree (`wiztree`) | 디스크 공간 사용 분포 | 쓰기 테스트 전 빈 공간 확보 판단 | 테스트에 필요한 여유 공간 확인 |
| CrystalDiskMark (`crystaldiskmark`) | 순차·무작위 성능 기준선 | 성능 저하 의심 시 | 모델 사양 대비 편차가 작음 |
| DiskSpd (`diskspd-help`) | 제한된 반복 I/O 부하 | 재현 가능한 측정이 필요할 때 | 지연 시간 급증 없음 |
| 나래온 더티 테스트 (`naraeon-dirty-test`) | SLC 캐시 소진 후 지속 쓰기 | 대용량 복사 중 속도 급락 확인 | 캐시 이후 속도가 급격히 무너지지 않음 |
| H2testw (`h2testw`) | 빈 공간 전체 쓰기·읽기 무결성 | 용량 허위 표기, 데이터 손상 의심 | 오류 0바이트 |
| ValiDrive (`validrive`) | USB 표시 용량 스폿체크 | USB 진위 빠른 확인 | 전 구간 정상 응답 |

## CPU와 메모리 안정성

| 도구 | 무엇을 보는가 | 언제 쓰는가 | 정상 판단 |
|---|---|---|---|
| Prime95 (`prime95`) | CPU 계산 안정성 | 오버클럭 후 CPU 검증 | 워커 오류 0, 하드웨어 오류 0 |
| y-cruncher (`y-cruncher`) | 메모리 컨트롤러 경로 계산 오류 | CPU와 RAM 복합 검증 | 계산 결과 검증 통과 |
| TestMem5 (`testmem5`) | RAM 오버클럭 서브타이밍 오류 | 메모리 오버클럭 검증 | 사이클 완료까지 오류 0 |
| HCI MemTest (`hci-memtest`) | RAM 커버리지 기반 오류 | TM5 통과 후 추가 확인 | 오류 0, 커버리지 누적 |
| OCCT (`occt`) | 복합 부하와 오류 검출 | 전원·발열 종합 확인 | 오류 0, 전압 강하 없음 |
| MemTest86+ (`memtest86plus`) | Windows 밖에서 RAM 검사 | OS 환경 영향을 배제할 때 | 전 패스 오류 0 |
| Ventoy (`ventoy`) | 부팅 USB 제작 | MemTest86+ 매체 준비 | USB로 부팅 성공 |

## 드라이버와 시스템 진단

| 도구 | 무엇을 보는가 | 언제 쓰는가 | 정상 판단 |
|---|---|---|---|
| FullEventLogView (`fulleventlogview`) | WHEA, 디스크, 전원 이벤트 | 원인 불명 오류 추적 | 관련 오류 이벤트 없음 |
| BlueScreenView (`bluescreenview`) | 미니덤프 요약 | 블루스크린 발생 후 | 최근 덤프 없음 |
| LatencyMon (`latencymon`) | DPC·ISR 지연 | 소리 끊김, 미세 멈춤 | 최대 DPC 지연이 낮게 유지 |
| TCPView (`sysinternals-tcpview`) | 프로세스별 네트워크 연결 | 의심스러운 통신 확인 | 알 수 없는 원격 연결 없음 |
| Process Explorer (`sysinternals-process-explorer`) | 프로세스 상세와 핸들 | 자원 점유 원인 추적 | 비정상 점유 프로세스 없음 |
| Process Monitor (`sysinternals-process-monitor`) | 파일·레지스트리 접근 추적 | 접근 실패 원인 추적 | 반복 실패 항목 없음 |
| DriverStore Explorer (`driverstoreexplorer`) | 드라이버 저장소 정리 | 드라이버 잔여물 정리 | 중복 패키지 정리됨 |
| USBDeview (`usbdeview`) | USB 장치 이력 | USB 인식 문제 | 대상 장치 정상 등록 |
| DDU (`ddu`) | 그래픽 드라이버 완전 제거 | 업체 변경, 제거 실패 시에만 | 재부팅 후 클린 설치 성공 |
| SDIO (`sdio`) | 누락·구형 드라이버 검사 | 재설치 후 미확인 장치 | 장치 관리자에 문제 표시 없음 |
| SD Memory Card Formatter (`sd-card-formatter`) | SD/SDHC/SDXC 카드 공식 포맷 | 카드 파일시스템 오류·호환성 문제 | 필요한 데이터 백업 후 새 파일시스템 생성 |
| Glary Utilities (`glary-utilities`) | 시작 항목·디스크·시스템 개요 | 부팅 지연 원인 초기 파악 | 불필요한 시작 항목 없음 |

## 위험도 표기

- 읽기 전용: 시스템을 바꾸지 않습니다. 바로 실행해도 됩니다.
- 고부하: 발열과 전력 소모가 큽니다. 온도 감시와 중단 조건이 필요합니다.
- 쓰기: 저장장치 수명을 소모합니다. 백업 후 실행합니다.
- 시스템 변경: 드라이버나 장치 구성을 바꿉니다. 복구 계획이 필요합니다.

위험 도구는 GUI에서 확인 창을 거치며, 명령줄에서는 `-AcknowledgeRisk`가 필요합니다.

이미 보유한 프로그램이 있으면 [내 프로그램 경로 등록](USER_TOOL_PATHS.md)으로 그 경로를 쓸 수 있습니다.

랜이 죽은 PC를 다루려면 [네트워크 드라이버 백업과 원팩 경로](NETWORK_DRIVERS.md)를 먼저 읽으십시오. 네트워크가 살아 있는 동안 준비해야 하는 유일한 항목입니다.

## 하드웨어 카드 상세 보기

상단의 OS, CPU, GPU, RAM/DISK 카드를 클릭하면 상세 정보 창이 열립니다. 요약에 담기지 않은 항목까지 확인할 수 있습니다.

| 카드 | 상세 항목 |
|---|---|
| OS | 에디션, 버전, 빌드, 아키텍처, 설치일, 마지막 부팅, 제조사, 모델, 하이퍼바이저 상태 |
| CPU | 프로세서, 코어·스레드, 기본 클럭, 소켓, 가상화 펌웨어, 메인보드 제조사·모델·리비전, BIOS 버전·출시일 |
| GPU | 어댑터별 제조사, 드라이버 버전·날짜, 비디오 모드, 보고된 VRAM |
| RAM / DISK | 슬롯별 용량·제조사·파트번호·설정 클럭·정격 클럭·전압, 디스크별 인터페이스·용량·펌웨어·상태 |

상세 정보는 시스템 정보 수집 시 한 번만 모아두므로, 카드를 여러 번 열어도 다시 조회하지 않습니다.

## BIOS · 그래픽 드라이버 업데이트 안내

수집한 날짜를 기준으로 오래된 항목이 있으면 상세 창에 안내가 함께 표시됩니다.

| 대상 | 안내 기준 | 표시 위치 |
|---|---|---|
| BIOS | 출시 후 18개월 경과 (36개월 이상은 주의 등급) | CPU 카드 상세 |
| 그래픽 드라이버 | 출시 후 12개월 경과 (24개월 이상은 주의 등급) | GPU 카드 상세 |

안내에는 제조사 지원 페이지를 여는 버튼이 함께 나옵니다. MSI, ASUS, GIGABYTE, ASRock, BIOSTAR, Dell, HP, Lenovo, Acer, Samsung, Intel 메인보드와 NVIDIA, AMD, Intel 그래픽을 인식합니다.

**중요한 한계입니다.** 이 도구는 제조사의 최신 버전 목록을 조회하지 않습니다. 따라서 안내는 "더 새 버전이 있다"는 뜻이 아니라 "확인해볼 시점이다"라는 뜻입니다. 실제로 최신인지는 제조사 페이지에서 직접 확인해야 합니다.

다운로드나 설치는 자동으로 하지 않습니다. 링크 버튼을 눌렀을 때만 기본 브라우저로 해당 페이지를 엽니다.

BIOS 업데이트는 실패 시 메인보드가 부팅되지 않을 수 있습니다. 제조사 안내를 그대로 따르고, 정전 위험이 있는 환경에서는 진행하지 않습니다. 그래픽 드라이버 교체가 반복 실패하면 [DDU 안내서](tools/DDU.md)를 참고합니다.

### 최신 버전 온라인 확인

NVIDIA 그래픽은 상세 창에서 **실제 최신 버전을 조회**할 수 있습니다. `최신 버전 온라인 확인` 버튼을 누르면 제조사 서버에 질의해 설치본과 비교합니다.

| 결과 | 의미 |
|---|---|
| 최신 버전 N이 있습니다 | 설치본보다 새 버전 확인됨 |
| 설치된 드라이버가 최신입니다 | 공개된 최신본과 동일 |
| 공개된 최신본보다 새 버전입니다 | 베타나 OEM 빌드일 수 있음 |
| 온라인 확인 실패 | 네트워크 없음 또는 제조사 응답 변경. 수동 확인 필요 |

조회는 버튼을 눌렀을 때만 실행됩니다. 시스템 분석 중에는 네트워크를 쓰지 않으므로 인터넷이 없는 현장에서도 나머지 기능은 그대로 동작합니다.

AMD·Intel 그래픽과 메인보드 BIOS는 공개 조회 경로가 없어 날짜 기반 안내와 제조사 페이지 링크만 제공합니다. 없는 근거로 최신 여부를 단정하지 않기 위한 선택입니다.

## 도구별 사용법 문서

옵션별 상세 설명과 판정 기준은 아래 문서에 있습니다. GUI에서 도구를 선택하고 `선택 도구 사용법` 버튼을 눌러도 열립니다.

| 도구 | 문서 |
|---|---|
| Prime95 | [PRIME95.md](tools/PRIME95.md) |
| OCCT | [OCCT.md](tools/OCCT.md) |
| TestMem5 | [TESTMEM5.md](tools/TESTMEM5.md) |
| HCI MemTest | [HCI_MEMTEST.md](tools/HCI_MEMTEST.md) |
| 나래온 더티 테스트 | [NARAEON_DIRTY_TEST.md](tools/NARAEON_DIRTY_TEST.md) |
| H2testw | [H2TESTW.md](tools/H2TESTW.md) |
| WizTree | [WIZTREE.md](tools/WIZTREE.md) |
| DDU | [DDU.md](tools/DDU.md) |
| LatencyMon | [LATENCYMON.md](tools/LATENCYMON.md) |
| BatteryInfoView | [BATTERYINFOVIEW.md](tools/BATTERYINFOVIEW.md) |
| Ventoy | [VENTOY.md](tools/VENTOY.md) |
| SDIO | [SDIO.md](tools/SDIO.md) |
| Glary Utilities | [GLARY_UTILITIES.md](tools/GLARY_UTILITIES.md) |
