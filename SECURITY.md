# Security policy

## Supported channel

Only the latest tagged source release is supported. Third-party diagnostic binaries are not part of the core release.

## Reporting

Report suspected command injection, unsafe download definitions, hash bypasses, privilege-boundary issues, or accidental collection of sensitive system data through GitHub private vulnerability reporting. Do not include unredacted system reports, serial numbers, user names, or private paths in a public issue.

Detailed elevated reports contain device instance identifiers, driver inventory, volume layout and security-state summaries. Treat report folders as private diagnostic data. The collector does not request or serialize BitLocker recovery passwords, TPM owner secrets, network addresses or account credentials.

## Package trust

Every downloadable package definition must pin SHA-256. HTTP is rejected except for an explicitly documented, signed, hash-pinned legacy source. Update candidates require review before their hash or version is changed. The offline-pack builder excludes redistribution-restricted archives.

Authenticode signing is recorded but not required. Several long-standing diagnostic utilities ship unsigned, including Prime95, y-cruncher, H2testw, smartctl, TrafficMonitor, TestMem5, HCI MemTest, Ventoy and some NirSoft tools. For those the pinned archive SHA-256 is the integrity control, and `scripts/Test-ToolLaunchers.ps1` records the observed signature state for every resolved executable so a change is visible. TestMem5 in particular is frequently flagged by antivirus heuristics because of its low-level memory access.

The installer refuses any package definition whose `sha256` is absent or not 64 hex characters, and deletes a rejected archive rather than leaving unverified bytes in `downloads/`. An unpinned definition fails the download instead of skipping verification.

## Trust boundary of the medium

This console runs elevated from removable media, so the write permissions on that medium are part of its security model. Anyone who can write to the project directory can edit `config/*.json` and the scripts themselves, and nothing here verifies first-party file integrity. Treat write access to the medium as equivalent to the administrator authority the console acquires when the operator approves elevation.

`config/user-tool-paths.json` is the one supported way to point a launcher at a binary outside the bundled tree. It is per-machine, untracked and unsigned, so it is treated as untrusted input at launch time rather than only when it is written. A launcher backed by a user-declared path requires an explicit acknowledgement before it starts, even when its catalog risk tier is read-only: `-AcknowledgeRisk` on the command line, or a confirmation dialog in the console. The prompt states the resolved path, whether it sits inside the tools tree, and its Authenticode status. A path inside the tools tree with a valid signature is accepted without the extra prompt. This does not make an untrusted binary safe; it removes the silent case where a repointed read-only tool would launch with no prompt at all.

Known residual risks, stated rather than fixed: `7z.exe`, `curl.exe` and `pnputil.exe` are resolved through `PATH` rather than absolute paths, so they assume `PATH` is not writable by an unprivileged user; the `7z-sfx` extraction branch delegates traversal handling to `7z.exe`; and `restore` in `scripts/Set-WplNetworkDriver.ps1` installs every INF under the selected folder without comparing it against the backup manifest, relying on Windows driver signature enforcement.
