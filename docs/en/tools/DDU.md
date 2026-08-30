# DDU (Display Driver Uninstaller) detailed usage

Removes a graphics driver completely, including registry entries and leftover files. Use it only for problems that a normal uninstall cannot fix. It is not a preventive maintenance tool for a healthy system.

Launch id is `ddu`, risk is system changing with a reboot.

## When to use it

| Situation | DDU needed |
|---|---|
| Switching NVIDIA to AMD or the reverse | Yes |
| Driver installation fails repeatedly | Yes |
| Corruption or black screen that reinstalling does not fix | Yes |
| Only moving to a newer driver version | No. A normal install is enough |
| Routine cleanup with no symptom | No |

## Prepare before running

1. Download the replacement driver first. After DDU runs, the display falls back to a default resolution and network drivers are sometimes affected.
2. Record the current driver version in case a rollback becomes necessary.
3. On a notebook, check whether the driver is vendor-specific. Replacing it with a generic driver can break brightness control or external outputs.
4. Safe mode is recommended; DDU can arrange the safe-mode reboot.

## Key options

| Option | Meaning | Recommendation |
|---|---|---|
| Device type | GPU, audio, network | GPU only for a graphics problem |
| Vendor selection | NVIDIA, AMD, Intel | Whatever is installed now |
| Clean and restart | Remove then reboot automatically | The default recommendation |
| Clean and shutdown | Remove then power off | When physically swapping the card |
| Clean, no restart | Remove only | Only when further work must follow |
| Prevent Windows Update drivers | Temporarily block automatic installation | Enable when installing a specific version |
| Delete C:\AMD and C:\NVIDIA folders | Remove installer leftovers | Enable |

Use `Clean and shutdown` when actually replacing the card: the driver is removed, the machine powers off, and the new card can be installed before the fresh driver.

## Procedure

1. Download the new driver in advance.
2. Run DDU and select the device type and vendor.
3. Enable prevention of automatic Windows Update drivers.
4. Press `Clean and restart`.
5. The system starts at a low resolution after reboot. That is expected.
6. Install the driver downloaded earlier.
7. Confirm the driver version and detection with GPU-Z.
8. Restore the Windows Update setting to its original state.

If no display appears at step 5, try the motherboard's integrated output.

## Cautions

- Do not leave the Windows Update block enabled; it stops other driver updates too.
- Removing network drivers as well cuts internet access, leaving no way to fetch drivers. For a graphics problem, select GPU only.
- Replacing a notebook vendor driver with a generic one can reduce functionality.

## Relationship to other tools

DriverStore Explorer handles duplicate packages accumulated in the driver store. While still deciding whether a driver is responsible, gather evidence first with LatencyMon and FullEventLogView. DDU is the last step once the cause is narrowed to the driver.

```powershell
.\scripts\Open-PortableTool.ps1 -Root . -Id ddu -AcknowledgeRisk -Language en
```

