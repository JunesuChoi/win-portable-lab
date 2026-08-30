# Driver detection and system maintenance / 드라이버 감지와 시스템 유지관리

Snappy Driver Installer Origin detects missing or outdated drivers and can work offline once driver packs have been fetched. Scanning is read-only; installing replaces drivers, so create a restore point first. The bundled `SDIO_auto.bat` performs unattended installation and is never used by this project.

Snappy Driver Installer Origin은 누락되거나 오래된 드라이버를 찾아냅니다. 드라이버팩을 미리 받아두면 오프라인에서도 동작합니다. 검사는 읽기 전용이지만 설치는 드라이버를 교체하므로 복원 지점을 먼저 만듭니다. 패키지에 포함된 `SDIO_auto.bat`은 확인 없이 일괄 설치하므로 이 프로젝트에서는 사용하지 않습니다.

Glary Utilities Portable is used only for read-only inspection: startup entries, disk analysis, system information and running processes. Its registry cleaning, disk cleanup, tracks erasing, shredding and boot-defragment features are out of scope. Disk Cleaner and Tracks Eraser in particular can delete the event logs and minidumps this project relies on as diagnostic evidence.

Glary Utilities Portable은 시작 항목, 디스크 사용량, 시스템 정보, 실행 중 프로세스 확인 용도로만 사용합니다. 레지스트리 정리, 디스크 정리, 사용 기록 삭제, 완전 삭제, 부트 조각모음 기능은 범위 밖입니다. 특히 Disk Cleaner와 Tracks Eraser는 이 프로젝트가 진단 근거로 쓰는 이벤트 로그와 미니덤프를 지울 수 있습니다.

Driver packs are not bundled here. They are very large and change often, so fetch them from inside the tool when needed.

드라이버팩은 포함하지 않습니다. 용량이 매우 크고 갱신이 잦아 필요할 때 도구 안에서 직접 받습니다.

