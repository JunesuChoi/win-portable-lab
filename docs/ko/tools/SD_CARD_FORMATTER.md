# SD Memory Card Formatter 상세 사용법

SD Association의 공식 SD/SDHC/SDXC 카드 포맷 도구입니다. 이 도구는 선택한 카드의 데이터를 삭제합니다. 진단 도구가 아니라 **복구·재초기화 작업**이므로, 문제를 먼저 읽기 전용 도구로 확인한 뒤에만 사용합니다.

실행 ID는 `sd-card-formatter`이며 위험도는 `formats-removable-media`입니다.

## 사용 전 확인

1. 카드 안의 필요한 데이터를 다른 저장장치에 복사합니다. 포맷 후 복구는 보장되지 않습니다.
2. 카드 리더기와 대상 SD 카드를 다시 확인합니다. 다른 이동식 디스크를 선택하지 마십시오.
3. CrystalDiskInfo·이벤트 로그로 PC 쪽 저장장치 오류와 카드 리더기 연결 문제를 먼저 확인합니다.
4. 쓰기 방지 탭이 있는 SD 카드는 잠금 해제 상태인지 확인합니다.

## 안전한 절차

1. 도구를 실행하고 설치 창에서 공식 EULA를 확인합니다.
2. `Select Card`에서 용량과 드라이브 문자를 대조해 대상만 선택합니다.
3. 일반적인 재사용은 Quick format을 사용합니다. 카드의 논리 오류를 다시 확인해야 할 때에만 Overwrite format을 검토합니다. Overwrite는 훨씬 오래 걸리고 전체 쓰기를 수행합니다.
4. 포맷을 시작하면 드라이브 문자와 용량을 한 번 더 확인합니다.
5. 완료 후 Windows에서 카드가 정상 마운트되는지 확인하고, 중요한 용도라면 H2testw 또는 ValiDrive로 별도 검증합니다.

## 주의

- 이 도구는 SD 카드용입니다. SSD·USB 메모리·시스템 드라이브를 포맷하는 용도로 쓰지 마십시오.
- 포맷은 카드의 물리 불량, 가짜 용량, 카드 리더기 문제를 고치지 않습니다.
- 프로그램 실행 자체는 설치형입니다. 포맷 실행은 이 프로젝트에서 자동화하지 않습니다.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id sd-card-formatter -AcknowledgeRisk -Language ko
```
