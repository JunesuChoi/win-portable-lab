# 시스템 맞춤 권장 설정 파일

```powershell
.\Start.cmd -Mode recommend -Language ko
```

생성되는 값은 보수적인 시작점입니다. 안정성을 보증하지 않으며 BIOS에 불러오는 실행형 프로필도 아닙니다.

최근 7일의 WHEA 또는 Kernel-Power 41이 발견되면 `recommendationMode`가 `diagnostic-baseline-only`로 바뀝니다. 이 상태에서는 오버클럭 권장으로 해석하지 말고 기본값 진단부터 진행합니다. 모든 정보 처리는 로컬에서 끝나며 업로드하지 않습니다.

## 공통 시작값

| 영역 | 권장 초기값 |
| --- | --- |
| CPU 프로필 | Auto/Default. 감지된 Intel 13·14세대 데스크톱은 Intel Default Settings |
| CPU 수동 전압 | 설정하지 않음 / Auto |
| CPU 고정 배수 | 설정하지 않음 / Auto |
| AMD PBO | Auto |
| AMD Curve Optimizer | 0 |
| 메모리 | 먼저 JEDEC/Auto. 기본 검증 후에만 XMP/EXPO Profile 1 검토 |
| 센서 기록 간격 | 1초 |
| 유휴 기준선 | 10분 |
| CPU 스모크/혼합/확장 | 10분 / 30분 / 60분 |
| RAM 스모크/다중 패턴 | 10분 / 60분 |
| 부팅형 RAM 검사 | 4패스 |
| 콜드 부팅 검사 | 3회 |
| 저장장치 벤치 | 1GiB 제한 테스트 파일, 3회. 물리 디스크 직접 쓰기 금지 |
| 허용 계산 오류·RAM 오류·새 WHEA | 0개 |

온도 상한은 CPU/GPU 모델마다 달라 자동 생성하지 않습니다. 감지된 모델의 공식 한계값을 사용하고 스로틀링, 센서 이상, 계산 오류, WHEA, 멈춤, 재부팅, BSOD, 데이터 손상이 하나라도 있으면 중단합니다.

JSON에는 `applyAllowed: false`가 들어갑니다. 앞으로 별도 적용기가 만들어져도 이 파일을 자동 튜닝 프로필로 받아들이면 안 됩니다.
