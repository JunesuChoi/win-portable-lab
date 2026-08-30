# 내 프로그램 경로 등록 / 사용자 정의 도구 경로

이미 보유한 프로그램이 있다면 다시 받지 않고 그 경로를 등록해 쓸 수 있습니다. 등록한 경로는 번들 `tools/` 폴더 검색보다 **우선 적용**됩니다.

설정은 `config/user-tool-paths.json`에 저장되며, 이 파일은 기기마다 다르므로 저장소에 커밋되지 않습니다.

## 등록

```powershell
.\scripts\Set-WplToolPath.ps1 -Root . -Action set -Id hwinfo -Path "D:\Portable\HWiNFO64.exe"
```

`-Id`는 도구의 실행 ID입니다. 목록은 아래 명령으로 확인합니다.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -List
```

## 확인

```powershell
.\scripts\Set-WplToolPath.ps1 -Root . -Action list
```

| 상태 | 의미 |
|---|---|
| `active` | 정상 적용 중 |
| `missing-file` | 파일이 그 위치에 없습니다. 번들 검색으로 되돌아갑니다 |
| `not-an-executable` | `.exe`가 아닙니다 |
| `disabled` | `enabled: false`로 잠시 끈 상태 |

## 제거

```powershell
.\scripts\Set-WplToolPath.ps1 -Root . -Action remove -Id hwinfo
```

제거하면 번들 `tools/` 폴더 검색으로 되돌아갑니다.

## 일괄 검증

```powershell
.\scripts\Set-WplToolPath.ps1 -Root . -Action verify
```

등록된 모든 항목의 실행 ID와 파일 존재를 확인합니다. 문제가 있으면 0이 아닌 코드로 종료하므로 점검 스크립트에 넣을 수 있습니다.

## 경로 표기

- 절대 경로를 권장합니다.
- 상대 경로는 프로젝트 폴더 기준으로 해석됩니다.
- 환경 변수를 쓸 수 있습니다. 예: `%ProgramFiles%\CPUID\CPU-Z\cpuz.exe`

## 안전 규칙

등록 시 다음을 검사하고, 하나라도 어긋나면 저장하지 않습니다.

1. 실행 ID가 카탈로그에 있는지
2. 파일이 실제로 존재하는지
3. 확장자가 `.exe`인지

Authenticode 서명 상태도 함께 기록합니다. 서명이 없어도 등록은 되지만, 어떤 상태였는지 파일에 남습니다.

등록한 경로가 나중에 사라지면 해당 도구는 자동으로 번들 검색으로 되돌아갑니다. 진단 도중에 오류로 중단되지 않습니다.

## 주의

위험 등급은 카탈로그가 정합니다. 경로만 바꿔도 그 도구의 위험 등급과 확인 절차는 그대로 유지됩니다. 예를 들어 DDU 경로를 바꿔도 여전히 시스템 변경 도구로 취급되어 확인을 요구합니다.

GUI에서 경로를 바꾼 뒤에는 `시스템 정보 새로고침`을 눌러야 반영됩니다.

