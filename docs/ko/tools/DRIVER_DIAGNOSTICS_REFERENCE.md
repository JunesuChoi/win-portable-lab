# 드라이버·냉각·이벤트 진단 도구 상세 사용법

## Sysinternals Suite (sysinternals)

Autoruns는 서명된 Microsoft 항목을 숨긴 뒤 비-Microsoft 자동 시작만 검토합니다. Process Explorer는 트리·경로·서명 확인용이며 종료/삭제하지 않습니다. RAMMap, TCPView, Procmon은 관찰·증거 수집용으로만 씁니다.

## Driver Store Explorer (driverstoreexplorer)

Enumerate로 패키지·공급자·버전·사용 여부를 확인합니다. 새 드라이버와 복원 지점 없이는 삭제하지 않으며 Delete Driver(s), Force Deletion은 이 프로젝트에서 권장하지 않습니다. 저장장치·네트워크·디스플레이의 사용 중 드라이버는 지우지 않습니다.

## Fan Control (fancontrol)

처음에는 센서·팬 식별만 합니다. 팬 하나씩 짧게 낮춰 실제 연결을 확인하고 CPU/흡기/배기를 혼동하지 않습니다. BIOS 안전값보다 공격적인 곡선을 만들지 말고 Apply 후 유휴·게임·부하에서 팬 정지와 온도를 확인합니다.

## BlueScreenView / FullEventLogView (bluescreenview, fulleventlogview)

BlueScreenView의 Bug Check와 드라이버 이름은 후보일 뿐 WinDbg 전에는 원인 단정하지 않습니다. FullEventLogView로 Kernel-Power, WHEA, Disk, Display, 설치 이벤트를 시간순으로 내보내 상관관계를 봅니다.

## USBDeview (usbdeview)

VID/PID·마지막 연결·장치 이름 확인용입니다. Disable/Uninstall/Disconnect는 키보드·마우스·저장장치를 끊을 수 있으므로 일괄·자동 실행하지 않습니다.

복원 지점/교체 드라이버 없이 삭제하지 않으며 팬 제어 뒤 온도 상승이나 장치 반복 해제가 있으면 원래 상태로 복구합니다.
