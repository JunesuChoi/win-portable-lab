# Changelog

## Unreleased

- Request administrator privileges by default while preserving an explicit `-NoElevation` limited mode.
- Expand elevated inventory with storage topology and reliability, TPM, BitLocker status, Device Guard, signed drivers, hotfixes, page files and power-plan data.
- Split 27 package downloads into schema-backed per-package manifests.
- Added update reporting and redistribution-aware offline-pack generation.
- Added preview-first supervised launch sessions with cancellation, timeout, and low-memory stop conditions.
- Added GUI search, readiness/risk filters, latest-result access, and session-based launches.
- Profile buttons now reuse the current system snapshot; only the dedicated refresh control reruns inventory.
- Added detailed per-DIMM inventory and GUI memory summaries, plus AMD-only ZenTimings v1.39.
- Added TrafficMonitor Lite v1.86 for portable network/resource monitoring with redistribution blocked by policy.
- Fixed GUI launcher working directories and made CLI output visible and session-captured.
- Added structural/hash launcher auditing and safe read-only GUI smoke tests.
- Isolated each dashboard CIM query so one unavailable class no longer clears all system cards.
- Added persistent hardware/analysis failure logs with the original exception text.
- Tool launches now require a target-process confirmation signal before the GUI reports success.
- Fixed Windows PowerShell 5.1 launcher failures caused by literal path quotes, nested JSON arrays, and empty `ArgumentList` values.
- Standard-user dashboards elevate the launch supervisor so administrator-manifest tools no longer stall behind a hidden child process.
- Standardized non-ASCII PowerShell sources on UTF-8 with BOM for Windows PowerShell 5.1 and added mojibake validation.
- Rebuilt the dashboard as compact task, recommendation-list and selected-tool panes with independent scrolling.
- Added visible snapshot freshness, dark filter chips, automatic first selection, fixed safe launch, and consistent dark selected/disabled states.
- Consolidated full sensor monitoring on HWiNFO and removed Libre Hardware Monitor from the catalog, profiles, launcher and portable payload.
- Isolated failures during safe batch launch so one unavailable utility no longer terminates the WPF dashboard; batch results are logged per tool.
- Added a top-level WPF dispatcher recovery guard with localized status and a persistent unexpected-error log.
- Added bilingual product planning, a shared PowerShell 5.1/7 process layer, atomic launch records, and a cross-runtime regression runner.
- Added repository validation, Pester tests, release checksums, CycloneDX SBOM, and GitHub provenance attestation.
