# CPU·메모리 계산 및 튜닝 도구 상세 사용법

HWiNFO 기록, 안정 BIOS 프로필, 복구 가능한 부팅 상태를 먼저 확보합니다.

## y-cruncher (y-cruncher)

Stress Tester 기본 프리셋을 10분부터 실행합니다. VST/FFT는 CPU와 메모리 컨트롤러를 함께 자극합니다. 오류·계산 불일치·WHEA·온도 급등 하나라도 실패이며, 통과하면 30분 후 1~2시간으로 늘립니다.

## Intel XTU (intel-xtu)

지원 세대와 BIOS 잠금 상태를 확인합니다. Basic Tuning의 현재값·벤치마크를 먼저 기록하고, 전압·전력 제한·배수는 한 번에 한 항목만 1단계 바꿉니다. 적용→재부팅→짧은 안정성 검사를 지키며 자동 튜닝·불명확한 프로필은 사용하지 않습니다.

## AMD Ryzen Master (ryzen-master)

지원 CPU·칩셋·BIOS를 확인합니다. PPT/TDC/EDC·온도·클록을 기록하고, PBO/Curve Optimizer는 BIOS 또는 Ryzen Master 한 곳에서만 관리합니다. 코어별 값은 작은 단계로 바꾼 뒤 부팅·유휴·부하를 모두 검증합니다.

오류, 멈춤/재부팅, 제조사 한계 근접 온도, 저장장치 오류가 생기면 즉시 마지막 안정값으로 되돌립니다.
