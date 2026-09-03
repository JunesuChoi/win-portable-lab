# 저장장치 점검 도구 상세 사용법

쓰기 검사 전에는 디스크 번호·드라이브 문자·백업 여부를 다시 확인합니다. 원본 데이터가 있는 볼륨에는 쓰기 검사를 하지 않습니다.

## AS SSD Benchmark · ATTO Disk Benchmark · HD Tune Pro

세 도구 모두 공식 사본의 실행 파일을 **도구 경로 추가/편집**으로 등록해서 사용합니다. 자동 다운로드하지 않습니다. AS SSD와 ATTO는 테스트 파일 I/O를 만들므로 회복 대상, 증거 보존 디스크, 여유 공간이 거의 없는 드라이브에는 실행하지 마십시오. HD Tune Pro는 먼저 **Info, Health, Error Scan(읽기)**만 사용합니다. Write Benchmark, Erase, Extra Tests는 대상 디스크와 백업을 다시 확인한 뒤 별도 승인으로만 진행합니다.

## smartmontools (smartmontools)

smartctl 전체 SMART/NVMe 로그에서 Reallocated, Pending, Media and Data Integrity Errors, Critical Warning을 봅니다. 값이 0이 아니거나 증가하면 벤치마크 대신 백업과 제조사 진단을 먼저 합니다.

## CrystalDiskInfo (crystaldiskinfo)

모델, 펌웨어, 온도, 건강 상태를 기록합니다. 주의/나쁨, 비정상 고온, 급격한 NAND 쓰기량 증가는 제조사 도구로 재확인합니다. AAM/APM·펌웨어 명령은 지원 범위 밖입니다.

## DiskSpd (diskspd)

파일 대상만 사용합니다. 예: diskspd.exe -c4G -d60 -r -w30 -t2 -o4 -b1M test.dat. c는 파일 크기, d는 시간, r은 랜덤, w는 쓰기 비율, t/o는 스레드·큐 깊이, b는 블록 크기입니다. 물리 디스크·파티션 raw write는 금지합니다.

## CrystalDiskMark (crystaldiskmark)

드라이브 문자·크기·반복 횟수를 확인합니다. 기본은 1 GiB·3회, 캐시/지속 쓰기 확인은 16~32 GiB·3회부터 시작합니다. SEQ1M은 순차, RND4K Q1T1은 체감 반응성 참고값입니다.

## ValiDrive (validrive)

USB/SD 신고 용량의 빠른 표본 검사입니다. 통과는 전체 용량 인증이 아니며, 의심 장치는 빈 상태에서 H2testw 전체 쓰기·검증으로 확정합니다.

SMART 경고, I/O 오류, WHEA, 연결 해제가 생기면 즉시 중단하고 모델·펌웨어·온도·연결 방식을 결과와 함께 기록합니다.
