# SSD 더티·지속 쓰기·무결성 테스트

SSD 테스트는 목적별로 도구가 다릅니다. 테스트 전 중요 데이터를 백업하고 대상 드라이브 문자, 남은 공간, SMART 상태와 온도를 다시 확인합니다. 아래 쓰기 테스트는 SSD 수명(TBW)을 소비하므로 자동 실행하지 않습니다.

| 목적 | 도구 | 권장 사용 |
|---|---|---|
| 상태·수명·온도 확인 | CrystalDiskInfo, smartmontools | 모든 쓰기 테스트 전후 |
| 짧은 성능 기준선 | CrystalDiskMark | 작은 테스트 크기부터 시작 |
| 제한된 반복 부하 | Microsoft DiskSpd | 일반 파일만 대상으로 크기·시간 제한 |
| SLC 캐시 이후 지속 쓰기와 더티 상태 | 나래온 더티 테스트 | 백업된 테스트 볼륨에서 그래프가 충분한 사용률 범위를 덮도록 실행 |
| 빈 공간 전체 쓰기·읽기 무결성 | H2testw | 비어 있거나 새로 포맷한 테스트 볼륨 권장 |
| USB 저장장치 허위 용량 빠른 확인 | GRC ValiDrive | USB 대용량 저장장치 스폿체크; 전체 검증은 H2testw로 확인 |

## 안전 순서

1. 모델·펌웨어·연결 방식과 드라이브 문자를 기록합니다.
2. CrystalDiskInfo 또는 `smartctl`로 경고, 온도와 미디어 오류를 확인합니다.
3. 중요한 데이터가 없는지 확인하고 예상 쓰기량을 기록합니다.
4. 짧은 기준선부터 시작한 뒤 필요한 경우에만 나래온/H2testw를 실행합니다.
5. 테스트 중 온도 상승, I/O 오류, 장치 재연결, 이벤트 로그의 디스크·컨트롤러 오류가 발생하면 즉시 중단합니다.
6. 종료 후 SMART와 Windows 시스템 이벤트를 다시 수집합니다.

나래온 더티 테스트 결과는 최고 속도만 보지 말고 SLC 캐시 소진 이후 속도, 그래프의 변동 폭과 낮은 속도 구간을 함께 봅니다. 운영체제 드라이브나 데이터가 있는 드라이브에 무작정 전체 채움 테스트를 실행하지 않습니다.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id naraeon-dirty-test -AcknowledgeRisk -Language ko
.\scripts\Open-PortableTool.ps1 -Root . -Id h2testw -AcknowledgeRisk -Language ko
.\scripts\Open-PortableTool.ps1 -Root . -Id validrive -AcknowledgeRisk -Language ko
```

명령은 프로그램 UI만 열며 테스트를 자동 시작하지 않습니다.
