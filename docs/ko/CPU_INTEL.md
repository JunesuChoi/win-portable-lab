# Intel CPU 세대별 세팅과 검증

## 공통 원칙

CPU 전체 모델명, 메인보드·칩셋, BIOS 버전과 날짜, 현재 메모리 프로필, 냉각 상태를 먼저 기록합니다. CPU와 RAM 오버클럭을 동시에 바꾸지 않습니다.

| 플랫폼 | 시작 설정 | 도구 경로 | 확인 항목 |
| --- | --- | --- | --- |
| 8~11세대 데스크톱 | CPU Auto, RAM JEDEC | 지원되는 K/KF/X 계열만 XTU 7.x 검토 | 코어·캐시, AVX 열, 콜드 부팅 |
| 12세대 | CPU Auto, RAM JEDEC | 지원되는 언락 CPU만 XTU 7.x | P코어·E코어·혼합 부하 |
| 13·14세대 데스크톱 | 최신 BIOS, Intel Default Settings, XMP 끔 | 지원 CPU만 XTU 7.x | 유휴/가벼운 부스트, 혼합·지속 부하, WHEA |
| Core Ultra 데스크톱 Series 2+ | CPU/메모리 Auto | 지원 CPU만 XTU 10.x | P/E코어, SoC, DDR5, 유휴 전환 |
| 잠금·노트북·OEM | 제조사 기본값 | 검사 전용 | OEM 전력·온도 동작 |

## 권장 검사값

- 유휴 센서 기준선: 10분
- 계산 스모크: 10분
- 혼합 부하: 30분
- 확장 계산 검사: 60분 이상
- 허용 계산 오류와 새 WHEA: 0개

13·14세대에서 기본값으로도 오류가 계속되면 전압을 더해 숨기지 말고 BIOS·마이크로코드·오류 자료를 보존해 제조사 지원 경로로 진행합니다.

영어 상세판: [CPU_INTEL.md](../guides/CPU_INTEL.md)
