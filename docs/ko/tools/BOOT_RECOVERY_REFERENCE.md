# 부팅 메모리·AMD 드라이버 복구 상세 사용법

## MemTest86+ (memtest86plus)

Ventoy USB에 ISO를 넣고 UEFI 부팅 메뉴에서 USB를 선택합니다. Secure Boot 호환을 먼저 확인합니다. 전체 RAM을 기본으로 최소 4회 패스·오류 0을 기준으로 합니다. 오류가 하나라도 나오면 오버클럭을 해제하고 DIMM 한 개씩·슬롯 교차 검사부터 합니다. 검사 중 강제 종료하지 않습니다.

## AMD Cleanup Utility (amd-cleanup-utility)

AMD 그래픽 드라이버 문제에만 씁니다. 새 AMD 드라이버와 BitLocker 복구 키를 미리 준비하고 복원 지점 생성 가능 여부를 확인합니다. Safe Mode 권고를 따르고 제거 후 재부팅합니다. NVIDIA/Intel을 함께 정리하는 도구도, 정상 시스템의 정기 유지보수 도구도 아닙니다.

## 복구 순서

증상·이벤트 로그 기록 → 교체 드라이버 확보 → 제거/부팅 검사 한 번 → 재부팅 → 장치 관리자와 짧은 3D 부하 확인 순서입니다.
