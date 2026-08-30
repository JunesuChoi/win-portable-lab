# Safety policy

## Risk levels

| Level | Examples | Default behavior |
| --- | --- | --- |
| Read-only | Inventory, SMART read, event logs | May run without confirmation |
| Temporary writes | File-based storage benchmark | Show path, free space and estimated writes |
| High load | CPU, RAM, GPU stress | Require confirmation and sensor availability |
| State changing | DDU, driver cleanup, tuning utility | Guided manual operation only |
| Destructive | Raw disk write, secure erase, firmware flash | Not supported by profiles |

## Required gates

- Identify desktop versus notebook and confirm AC power for notebooks.
- Save work before any stress, cleanup or reboot operation.
- Capture BIOS, driver and tuning state before testing.
- Keep the replacement graphics driver available before DDU or cleanup.
- Confirm the BitLocker recovery key is available before Safe Mode or boot changes.
- Do not start a high-load test when required sensors are missing.
- Stop on calculation error, memory error, WHEA error, display-driver reset, unexpected reboot, or an applicable user-defined thermal limit.
- Never infer a physical connector from a Windows logical PnP port number.
- Return CPU, GPU and RAM to defaults when isolating the source of instability.

## Temperature policy

There is no universal safe temperature limit across all CPU and GPU generations. The eventual supervisor must identify the part, obtain a supported limit from vendor data when available, and otherwise require the operator to choose a conservative stop threshold. Missing or implausible telemetry is a test-blocking condition, not permission to continue.

## Stability language

Reports may state that a system passed a named workload for a recorded duration. They must not claim absolute stability. A pass is bounded by the exact firmware, settings, tool version, workload, ambient conditions and duration recorded in the report.

