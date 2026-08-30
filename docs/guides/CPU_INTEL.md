# Intel CPU inspection and stability guide

This guide routes the operator by platform rather than pretending that one voltage or frequency recommendation applies to every processor and motherboard.

## Identification

Record these values before changing or testing anything:

- Full CPU model and suffix
- Desktop, notebook or OEM system
- Motherboard model and chipset
- BIOS version and date
- Microcode reported by the available inventory tool
- Current power limits, CPU ratios, memory profile and cooling state
- Idle sensor baseline and relevant WHEA events

Intel XTU tuning support is generally limited to supported unlocked suffixes such as K, KF, HK, X and XE. Desktop CPU overclocking also requires a supporting board, normally a Z-series chipset. Do not infer support from the CPU generation alone.

Official support check: https://www.intel.com/content/www/us/en/support/articles/000057552/processors/intel-core-processors.html

## Platform routing

| Platform group | Detection notes | Tool route | Validation emphasis |
| --- | --- | --- | --- |
| 8th-11th Gen Core desktop | Conventional core layout; DDR4 era | XTU 7.x only when the exact unlocked CPU and chipset are supported | Core/cache load, AVX heat, memory controller and cold boot |
| 12th Gen Core | First mainstream P-core/E-core hybrid generation on applicable SKUs | XTU 7.x for supported unlocked parts | P-core, E-core and combined workloads; scheduler and Windows build |
| 13th/14th Gen Core desktop | Hybrid desktop family with an Intel-published Vmin Shift issue affecting some parts | Update BIOS and restore Intel Default Settings before any OC diagnosis; supported parts use XTU 7.x | Light-load/idle as well as sustained load; WHEA and application crashes |
| Core Ultra desktop Series 2 and newer | New XTU branch and DDR5-only desktop platform | XTU 10.x for supported unlocked parts | Compute/SoC domains, P/E behavior, DDR5 and idle-to-boost transitions |
| Locked, mobile and OEM systems | Tuning controls may be absent or restricted | Inspection and stability testing only | OEM power/thermal behavior; do not force desktop profiles |

Intel states that XTU 7.14 supports eligible 14th Gen and older unlocked processors, while XTU 10.0 supports eligible Core Ultra Series 2 and newer processors. Installing the wrong branch can fail.

Source: https://www.intel.com/content/www/us/en/download/17881/intel-extreme-tuning-utility-intel-xtu.html

## 8th-11th Gen procedure

1. Load BIOS defaults and disable any existing CPU and memory overclock.
2. Record a short idle and stock-load baseline.
3. Validate CPU core/cache stability with memory at JEDEC defaults.
4. Validate memory separately.
5. If tuning manually, change only one domain between reports.
6. Re-run light, mixed and sustained workloads; a heavy all-core pass does not cover idle or boost transitions.

## 12th Gen procedure

12th Gen introduced performance hybrid architecture on applicable processors. A useful report must preserve P-core and E-core counts and not treat the CPU as a homogeneous set of cores.

1. Confirm a supported Windows 11 build and current BIOS.
2. Test stock settings with memory at defaults.
3. Run a P-core-sensitive calculation workload.
4. Run an all-thread mixed workload to include E-cores.
5. Run a memory-controller workload.
6. Inspect WHEA, application errors and clock throttling after each phase.

Intel hybrid architecture reference: https://www.intel.com/content/www/us/en/products/docs/processors/core/12th-gen-vpro-desktop-processors-brief.html

## 13th/14th Gen desktop procedure

Do not begin by increasing voltage or overriding motherboard limits. Intel currently recommends the relevant Intel Default Settings and a BIOS containing microcode `0x12F` or later for the published Vmin Shift instability issue.

1. Record the existing BIOS and microcode.
2. Update through the motherboard or system manufacturer when appropriate.
3. Apply Intel Default Settings.
4. Keep memory at JEDEC defaults for the first CPU-only diagnosis.
5. Test idle/light boost transitions, mixed load and sustained load.
6. If crashes or freezes persist at Intel defaults, retain the evidence and follow Intel/OEM support rather than masking the symptom with more voltage.

Current Intel notice: https://www.intel.com/content/www/us/en/support/articles/000102331/processors.html

## Core Ultra desktop Series 2 procedure

1. Use the XTU 10.x branch only when the exact processor is supported.
2. Record CPU, board, BIOS and DDR5 configuration before opening tuning controls.
3. Establish a default baseline across P-core, E-core, memory and idle-to-boost transitions.
4. Treat compute, SoC and memory tuning as separate experiments.
5. Re-run memory validation after any change affecting the memory controller or fabric/interface clocks.

## Test ladder

| Stage | Purpose | Pass language |
| --- | --- | --- |
| Inventory | Verify routing and detect unsupported tuning | Identification completed |
| 5-10 minute smoke | Catch immediate errors and cooling faults | Passed named smoke workload |
| 30-60 minute mixed | Observe sustained clocks, temperatures and WHEA | Passed mixed workload for recorded duration |
| Extended calculation | Detect intermittent core/cache calculation errors | Passed exact tool/version/configuration |
| Idle and transition | Catch instability missed by all-core load | No relevant error during recorded transition window |

## Stop and reset conditions

- Any calculation mismatch or worker error
- New WHEA event
- Unexpected reboot, freeze or BSOD
- Thermal limit or persistent throttling outside the expected platform behavior
- Sensor data becomes unavailable or implausible
- A result differs drastically after a BIOS change without a recorded configuration change

Reset CPU and RAM to defaults before assigning the fault to either domain.

