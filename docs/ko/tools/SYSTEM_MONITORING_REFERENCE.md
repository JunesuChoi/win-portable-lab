# 시스템 식별·모니터링 도구 상세 사용법

튜닝 전 CPU·보드·BIOS·메모리·GPU 드라이버 버전을 스크린샷 또는 보고서에 남깁니다.

## HWiNFO (hwinfo)

Sensors-only로 시작해 CPU Package/CCD, GPU Hot Spot, VRM, SSD, 전력, 클록의 최소·최대값을 기록합니다. 유휴 3분 후 값과 부하 값을 구분합니다. EC 충돌 경고가 있으면 보드 유틸리티와 동시에 실행하지 않습니다.

## CPU-Z (cpuz)

CPU 모델·코어·배수, 메인보드·BIOS, 채널·DRAM Frequency, DIMM별 XMP/EXPO를 캡처합니다. DDR은 DRAM Frequency의 두 배이므로 1800 MHz는 DDR4-3600입니다.

## GPU-Z (gpuz)

GPU·VRAM·버스, 온도·Hot Spot·전력·PerfCap Reason을 부하 전후 비교합니다. BIOS 저장/플래시는 사용하지 않습니다.

## TrafficMonitor Lite (trafficmonitor)

CPU, RAM, 업/다운로드, GPU, 디스크 항목만 표시합니다. 게임·벤치마크를 가리면 위치를 바꾸거나 끕니다. 장시간 부하의 이상 점유율 확인용이지 센서 정확도 검증용은 아닙니다.

## ZenTimings (zentimings)

AMD 전용입니다. FCLK/UCLK/MCLK, 1·2차 타이밍, DIMM 전압을 캡처하고 BIOS 실제 적용값과 대조합니다. 읽은 값만으로 전압 변경을 권장하지 않습니다.
