# AMD CPU 세대별 세팅과 검증

## 공통 시작값

- CPU: AMD Default/Auto
- PBO: Auto
- Curve Optimizer: 0
- 수동 고정 전압과 고정 배수: 설정하지 않음
- RAM: JEDEC/Auto

| 플랫폼 | 세팅 경로 | 검증 중점 |
| --- | --- | --- |
| Ryzen 2000 이전·초기 AM4 | 지원되는 레거시 Ryzen Master 또는 BIOS | CPU와 메모리/패브릭 분리, 콜드 부팅 |
| Ryzen 3000/4000 | 일치하는 Ryzen Master 계열 | CCD, FCLK/UCLK/MCLK, 부스트 전환 |
| Ryzen 5000 | 지원 CPU의 PBO/CO | 코어별 CO 오류와 가벼운 부하 |
| Ryzen 7000/8000 AM5 | Ryzen Master 3.x, 지원 시 PBO/CO | JEDEC 기준선 후 EXPO, DDR5 훈련 |
| Ryzen 9000 | 지원 시 Curve Shaper | 코어별 CO, 온도·주파수 구간, DDR5 |
| X3D | CPU가 노출하는 기능만 사용 | 고정 전압 금지, 게임형 순간 부하와 유휴 전환 |
| 노트북/OEM | 검사 전용 | 공유 전력·온도와 제조사 펌웨어 |

CPU 기본값과 JEDEC에서 먼저 통과한 뒤 PBO/CO와 EXPO를 서로 다른 단계로 검증합니다. 오류가 나오면 마지막 변경만 되돌립니다. 허용 오류와 새 WHEA는 0개입니다.

영어 상세판: [CPU_AMD.md](../guides/CPU_AMD.md)
