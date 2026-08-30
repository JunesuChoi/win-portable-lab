# Tools by purpose / 용도별 도구

실행 파일은 이름이 아니라 점검 목적에 따라 분류합니다. `SOURCE.json`은 출처와 위험도를, 각 버전의 `INSTALL-MANIFEST.json`은 다운로드 URL과 SHA-256을 기록합니다.

Tools are grouped by diagnostic purpose. `SOURCE.json` records provenance and risk; each version's `INSTALL-MANIFEST.json` records its resolved download and SHA-256 values.

| Folder | 용도 / Purpose |
|---|---|
| `01-System-Info-Monitoring` | 시스템 식별, 센서, 냉각 모니터링 / identification, sensors, cooling |
| `02-Storage-Health-SMART` | SSD/HDD/NVMe 상태와 SMART / storage health and SMART |
| `03-Storage-Benchmark-Dirty-Integrity` | 성능, 지속 쓰기, 더티 상태, 용량·무결성 / benchmark, sustained write, dirty state, capacity and integrity |
| `04-CPU-Memory-Stability` | CPU·RAM 부하 및 안정성 / CPU and memory stability |
| `05-GPU-Driver-Cleanup` | GPU 드라이버 제거·정리 / GPU driver cleanup |
| `06-CPU-Tuning-Installers` | CPU 튜닝용 설치 프로그램, 포터블 아님 / CPU tuning installers, not portable |
| `07-System-Driver-Diagnostics` | Windows, 충돌, 이벤트, USB 진단 / Windows, crash, event and USB diagnostics |
| `08-Network-Traffic-Monitoring` | 네트워크 속도와 작업 표시줄 자원 모니터링 / network throughput and taskbar resource monitoring |
| `09-Driver-Detection-Maintenance` | 드라이버 자동 감지와 시스템 유지관리 / driver detection and system maintenance |
