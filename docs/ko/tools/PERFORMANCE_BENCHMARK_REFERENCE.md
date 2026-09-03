# 성능 벤치마크 빠른 안내

이 항목들은 안정성 판정기가 아닙니다. 기준선 성능을 같은 버전·전원 계획·실내 온도에서 비교하는 도구입니다. 실행 전 HWiNFO 센서를 열고 오류, 멈춤, WHEA, 과도한 온도가 하나라도 보이면 즉시 중단합니다.

## AIDA64 Extreme

공식 portable trial 또는 라이선스 사본의 `aida64.exe`를 사용자 경로로 등록합니다. Cache & Memory Benchmark의 Read/Write/Copy/Latency를 기록하되, 한 번의 수치로 메모리 오버클럭 안정성을 결론내리지 않습니다. 안정성은 TM5, HCI MemTest, y-cruncher로 별도 확인합니다.

## Cinebench 2024

공식 Maxon 사본의 `Cinebench.exe`를 등록합니다. CPU Multi Core를 먼저 한 번 실행하고 GPU 시험은 드라이버·온도 기준선 확인 뒤에 합니다. 2024 점수는 R23과 직접 비교하지 않습니다.

## 3DMark

공식 Steam, Epic 또는 라이선스 standalone 설치만 사용합니다. `3DMark.exe` 경로를 등록하고 시스템에 맞는 기본 시험을 선택합니다. Storage Benchmark는 일반 GPU 비교와 분리합니다. 프레임 이상, 드라이버 재시작, WHEA가 보이면 결과를 저장하고 즉시 중단합니다.

## Blender Benchmark

공식 Open Data Benchmark Client의 `benchmark-launcher.exe`를 등록합니다. 온라인 제출은 선택 사항입니다. CPU/GPU 렌더링은 장시간 최대 부하이므로 노트북 배터리 모드와 열이 갇힌 환경에서는 피합니다.

## 사용자 경로 등록

GUI의 **도구 경로 추가/편집**에서 실행 파일 하나를 고릅니다. 이 프로젝트는 상용·스토어 도구를 자동 다운로드하거나 번들하지 않습니다. 등록 파일은 관리자 권한으로 실행될 수 있으므로 공식 출처와 서명을 직접 확인해야 합니다.
