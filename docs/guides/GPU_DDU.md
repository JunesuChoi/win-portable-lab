# GPU inspection, driver cleanup and DDU guide

DDU is a repair tool, not a routine prerequisite for every driver update. Start with the vendor installer's normal or clean-install path. Use DDU when changing vendors, resolving a failed installation, removing persistent leftovers, or following a vendor troubleshooting procedure.

## GPU routing

| Vendor and family | Examples | Driver route | Test emphasis |
| --- | --- | --- | --- |
| NVIDIA legacy | Kepler/Maxwell-era products | Verify current vendor support before changing the driver | Driver availability, VRAM errors, fan and thermal behavior |
| NVIDIA Pascal/Turing | GTX 10, GTX 16, RTX 20 | NVIDIA driver package; DDU only when justified | Core/VRAM separation, hotspot where available, clock stability |
| NVIDIA Ampere/Ada/Blackwell | RTX 30/40/50 families | Current supported NVIDIA package | Power connector/state, VRAM, hotspot, transient and sustained load |
| AMD GCN/Polaris/Vega | RX 400/500, Vega and related products | Confirm supported or legacy AMD branch | Driver timeout, VRAM and thermal/fan behavior |
| AMD RDNA 1/2/3/4 | RX 5000/6000/7000/9000 families | Current AMD Software branch for the exact product | Junction temperature, VRAM, power limit and driver reset |
| Intel integrated | HD/UHD/Iris/Xe | Prefer the OEM driver on notebooks and customized systems | Shared memory, media engine and sleep/resume |
| Intel Arc A/B | Alchemist/Battlemage | Intel Arc driver or OEM package as applicable | ReBAR state, VRAM, idle power, media and game workloads |
| Hybrid notebook | Intel/AMD iGPU plus discrete GPU | OEM package priority; preserve switching components | Sleep/resume, display routing and per-GPU load |

Do not classify a GPU solely by the marketing name reported by one API. Preserve PNP ID, subsystem/OEM identity, driver version and physical topology where available.

## Pre-test inspection

- Capture GPU model, PNP ID, VBIOS where available, driver version/date and display topology.
- Record idle core, memory, hotspot, fan, power and clock sensors where exposed.
- Check recent `Display`, WHEA, Kernel-PnP and unexpected-power events.
- Confirm the monitor is connected to the intended GPU.
- For Arc systems, record Resizable BAR state when an approved API is available.
- For notebooks, identify the OEM graphics package before installing a generic driver.

## DDU decision

Use DDU only when at least one condition applies:

- Switching between NVIDIA, AMD and Intel discrete graphics
- Standard uninstall or clean installation failed
- Driver package repeatedly fails or the device remains on a broken driver
- Leftovers are implicated by reproducible evidence
- The GPU vendor's troubleshooting guidance recommends it

Do not use DDU merely because a benchmark score is lower than expected.

## DDU preparation

1. Save all work and back up important data.
2. Confirm the BitLocker recovery key is available.
3. Download the correct replacement driver before cleanup.
4. Download the current DDU release from Wagnardsoft, not a mirror.
5. Extract DDU to a local disk. Do not run it from a network path.
6. Record the current GPU and driver inventory.
7. Disconnect the network or otherwise prevent Windows Update from inserting a driver during the cleanup window.
8. Know how to enter and exit Safe Mode before changing boot state.

Official DDU guide: https://www.wagnardsoft.com/content/How-use-Display-Driver-Uninstaller-DDU-Guide-Tutorial

## DDU execution

1. Enter Windows Safe Mode using the normal Windows recovery flow.
2. Start DDU from the local extracted directory.
3. Select `GPU` and the exact vendor to remove.
4. Choose `Clean and restart` when retaining the GPU.
5. Choose `Clean and shutdown` when physically replacing the GPU.
6. After returning to normal Windows, install the prepared driver while still offline.
7. Reboot when required.
8. Reconnect the network only after the intended driver is installed.

Avoid forcing DDU's Safe Mode option before proving the PC can enter Safe Mode normally. PIN-only sign-in and BitLocker state can make recovery more difficult.

## Vendor-specific alternatives

### AMD

AMD Cleanup Utility is the first-party alternative for removing AMD graphics and audio software. AMD recommends Safe Mode for best results, creates a restore point, and requires a reboot. It does not remove AMD chipset drivers.

Source: https://www.amd.com/en/resources/support-articles/faqs/GPU-601.html

### Intel

The Intel graphics installer offers a clean-install option. Intel also documents DDU as a fallback and warns that generic drivers can replace OEM customizations.

Sources:

- https://www.intel.com/content/www/us/en/support/articles/000057389/graphics.html
- https://www.intel.com/content/www/us/en/support/articles/000091878/graphics.html

### NVIDIA

Use the NVIDIA installer's custom/clean-install path before escalating to DDU unless changing vendors or troubleshooting persistent corruption. Preserve notebook OEM requirements and the exact driver branch needed by the GPU.

## Post-clean verification

- Device Manager shows the intended GPU with no problem code.
- The installed driver version matches the prepared package.
- No unexpected second vendor package was reinserted by Windows Update.
- Display layout, refresh rate, HDR and audio endpoints are restored.
- Idle sensors are plausible.
- A short 3D test completes without artifact, driver reset or WHEA.
- The report contains before/after driver inventory and the cleanup method used.

## GPU stability sequence

1. Stock driver and stock GPU settings
2. Short render smoke test
3. VRAM-focused test
4. Sustained core load
5. Mixed gaming-like workload
6. Idle and display sleep/resume
7. Combined CPU/GPU power test only when cooling and PSU evidence justify it

Stop on artifacts, calculation/VRAM errors, display-driver reset, WHEA, unexpected reboot, fan failure or the configured thermal limit.

