# Architecture

## Execution model

WinPortableLab separates read-only inspection from state-changing operations.

1. The launcher resolves the portable root, requests UAC elevation by default and starts without installing the application.
2. The inventory layer records the host state using built-in Windows APIs; `-NoElevation` produces an explicitly limited report.
3. The catalog decides whether a tool may be bundled, downloaded, supplied by the user, or only launched when already installed.
4. A profile selects test adapters and required safety gates.
5. The supervisor records launch/session state, timeout, cancellation and free-memory stops. HWiNFO is the single operator-visible sensor baseline; temperature is not currently an automatic stop input, so high-load sessions require a separate manual-monitoring acknowledgement.
6. The reporter writes a self-contained evidence bundle to the portable drive.

## Planned components

| Component | Responsibility |
| --- | --- |
| Launcher | Portable root resolution, privilege detection and mode selection |
| Inventory | CPU, GPU, board, BIOS, RAM, storage, drivers, PnP and OS state |
| Catalog | Distribution, license, risk, detection and automation metadata |
| Downloader | Official source resolution, hash/signature validation and cache management |
| Adapter | One wrapper per external tool; no generic arbitrary command execution |
| Process layer | PowerShell 5.1/7 argument normalization, quoted process starts, startup observation and atomic JSON records |
| Supervisor | Duration, cancellation, free-memory policy, startup/nonzero-exit detection and session evidence |
| Reboot journal | Safe Mode, boot-memory-test and reboot continuation state |
| Reporter | JSON source data, CSV series and HTML summary |
| GUI | Profile selection, plan preview, progress, warnings and report review |

Process start is not equivalent to diagnostic success. `started`, `completed`, `failed`, and future operator-verified test outcomes remain separate states. The field workflow and delivery priorities are defined in the bilingual product plan.

## Trust boundaries

- Repository-owned scripts and application code
- Downloaded third-party binaries
- Host firmware and Windows APIs
- User-supplied tools and profiles
- High-privilege helper process

Downloaded binaries must be stored outside Git, traced to the official source, and verified against an available vendor hash or Authenticode signature. A successful download is not treated as a successful installation or test.
