# 10-Partition-Management

파티션 생성·삭제·포맷·리사이즈와 MBR/GPT 복구, 배드섹터 정밀 검사를 담당합니다. 이 분류의 도구는 디스크 구조를 직접 바꾸므로 위험 등급이 최상위이며, GUI를 사용자가 직접 조작하는 방식으로만 지원합니다. 스크립트가 파티션 쓰기를 자동 수행하지 않습니다.

This folder covers partition create/delete/format/resize plus MBR/GPT repair and bad-sector scans. Tools here modify disk structure, so they carry the top risk tier and are supported only as operator-driven GUI sessions; this project never scripts partition writes.

| Tool | 용도 / Purpose |
|---|---|
| `macrorit-partition-expert` | 일상 파티션 작업 / everyday partition operations |
| `diskgenius` | MBR/GPT 복구, 배드섹터 검사, 클론 / repair, bad-sector scan, cloning |
