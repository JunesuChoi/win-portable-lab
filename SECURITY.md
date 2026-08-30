# Security policy

## Supported channel

Only the latest tagged source release is supported. Third-party diagnostic binaries are not part of the core release.

## Reporting

Report suspected command injection, unsafe download definitions, hash bypasses, privilege-boundary issues, or accidental collection of sensitive system data through GitHub private vulnerability reporting. Do not include unredacted system reports, serial numbers, user names, or private paths in a public issue.

Detailed elevated reports contain device instance identifiers, driver inventory, volume layout and security-state summaries. Treat report folders as private diagnostic data. The collector does not request or serialize BitLocker recovery passwords, TPM owner secrets, network addresses or account credentials.

## Package trust

Every downloadable package definition must pin SHA-256. HTTP is rejected except for an explicitly documented, signed, hash-pinned legacy source. Update candidates require review before their hash or version is changed. The offline-pack builder excludes redistribution-restricted archives.

Authenticode signing is recorded but not required. Several long-standing diagnostic utilities ship unsigned, including Prime95, y-cruncher, H2testw, smartctl, TrafficMonitor, TestMem5, HCI MemTest, Ventoy and some NirSoft tools. For those the pinned archive SHA-256 is the integrity control, and `scripts/Test-ToolLaunchers.ps1` records the observed signature state for every resolved executable so a change is visible. TestMem5 in particular is frequently flagged by antivirus heuristics because of its low-level memory access.
