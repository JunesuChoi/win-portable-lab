# RAM overclocking and stability guide

An XMP or EXPO profile is an overclock. The memory kit rating does not guarantee that every CPU memory controller, motherboard, BIOS, DIMM count and capacity combination will operate at that profile.

## Platform routing

| Platform | Profile type | Important domains |
| --- | --- | --- |
| Intel DDR4 | XMP 2.0 | DRAM, memory controller, Gear mode, command rate and DIMM topology |
| Intel DDR5 | XMP 3.0 | DRAM, controller mode, on-module power management, DIMM topology and training |
| AMD AM4 DDR4 | XMP interpreted as DOCP/A-XMP/board-specific naming | MCLK, UCLK, FCLK, timings and DIMM topology |
| AMD AM5 DDR5 | EXPO or board-supported XMP | MCLK, UCLK, FCLK, training, capacity and DIMM topology |
| OEM/notebook memory | Usually no supported profile control | Inspection and JEDEC stability only |

Intel describes XMP 2.0 as DDR4 and XMP 3.0 as DDR5. AMD EXPO is designed for DDR5 memory overclocking on socket AM5.

Sources:

- https://www.intel.com/content/www/us/en/gaming/extreme-memory-profile-xmp.html
- https://www.amd.com/en/products/processors/technologies/expo.html

## Record before tuning

- CPU, motherboard and BIOS/AGESA/microcode
- DIMM count, slot position, capacity, rank when available and part number
- JEDEC speed and active configured speed
- XMP/EXPO profile contents
- Primary timings and relevant controller/fabric ratios
- CPU tuning state
- Cold-boot behavior and previous memory errors

Do not compare two memory results unless these variables are preserved.

## Baseline procedure

1. Load CPU and memory defaults.
2. Install DIMMs in the motherboard-recommended slots.
3. Complete at least one cold boot at JEDEC defaults.
4. Run inventory and a short memory test.
5. Run a longer default-memory validation before diagnosing an overclock.
6. Save the stock report.

## Profile procedure

1. Enable only XMP, EXPO or the board's corresponding profile.
2. Do not simultaneously change CPU ratios, Curve Optimizer, cache, fabric or GPU settings.
3. Allow memory training to finish.
4. Confirm that the applied frequency, timings and voltage match the selected profile.
5. Run the quick ladder.
6. If it passes, run the standard ladder and cold-boot checks.

## Manual tuning procedure

1. Start from the last fully recorded passing profile.
2. Change one class of parameter at a time: frequency, controller/fabric ratio, primary timings, secondary timings, then tertiary timings.
3. Do not copy voltages from another CPU, board or DIMM kit.
4. Use only ranges exposed and documented for the exact platform. The toolkit does not provide universal voltage ceilings.
5. Save a new report for each change set.
6. Return to the last passing configuration after the first error; do not stack compensating changes without isolating the cause.

## DIMM topology rules

- Two DIMMs are generally easier on the memory controller than four.
- Higher total capacity and dual-rank loading can reduce achievable frequency.
- Mixed kits are not treated as one validated kit even when labels match.
- A kit's XMP/EXPO qualification is specific to the vendor test conditions, not every motherboard and CPU.
- On first boot, training time can be materially longer than a normal boot, especially on DDR5 platforms.

## Validation ladder

| Stage | Coverage | Stop condition |
| --- | --- | --- |
| POST/training | Firmware can train the selected configuration | Repeated training loop or failed POST |
| 5-10 minute smoke | Immediate data or cooling faults | Any memory/calculation error |
| 30-60 minute varied patterns | Multiple access patterns and controller load | Any error, WHEA or crash |
| Extended OS test | Heat and intermittent errors | Any non-zero error count |
| Bootable memory test | Memory outside the Windows allocation | Any reported error |
| Cold boot cycles | Retraining and marginal startup behavior | One failed or inconsistent cold boot |
| Daily workload | Real application behavior | Crash, corruption or unexplained mismatch |

No single tool proves absolute stability. Use more than one pattern family and retain exact versions and parameters.

## Recommended tool roles

- MemTest86+: bootable broad memory test
- y-cruncher: CPU, memory controller and RAM-sensitive verified calculations
- Prime95: CPU/cache/memory workload depending on FFT configuration
- OCCT Memory: convenient supervised memory workload when correctly licensed
- Windows event log: WHEA and unexpected shutdown correlation

## Failure routing

| Symptom | Likely first branch to test |
| --- | --- |
| No POST or training loop | Frequency, DIMM placement/count, controller load, BIOS training |
| Immediate memory error | DRAM profile, timings or gross controller instability |
| WHEA without memory-tool error | CPU core, memory controller or fabric/interconnect |
| Errors only after heating | DRAM/controller thermal margin or cooling airflow |
| Cold boot fails but warm reboot passes | Training and marginal startup settings |
| Application corruption with tests passing | Expand workloads and return to the last known stock baseline |

## Platform notes

### Intel 8th-11th Gen DDR4

Validate core/cache at stock before memory tuning. On platforms exposing Gear modes, record the selected mode because equal DRAM speed with a different controller ratio is not the same configuration.

### Intel 12th-14th Gen

Separate DDR4 and DDR5 boards. Preserve P-core/E-core and cache tuning state. For 13th/14th Gen desktop CPU instability diagnosis, use the current BIOS and Intel Default Settings before assigning errors to RAM.

### Intel Core Ultra desktop Series 2

Treat DDR5 controller/interface changes as a distinct experiment. Record DIMM type and loading; high advertised speeds commonly depend on a specific one-DIMM-per-channel configuration.

### AMD AM4

Record MCLK, UCLK and FCLK rather than only the advertised DDR4 rate. A memory test failure can originate from the fabric or controller even when the DIMMs are sound.

### AMD AM5

EXPO is a DDR5 overclock. Allow training to finish, validate at JEDEC first, and change PBO/Curve Optimizer separately. Preserve sleep/resume and cold-boot behavior in the report.

## Reporting language

Acceptable:

> DDR5-6000 EXPO configuration passed y-cruncher profile X for 60 minutes and MemTest86+ version Y for four passes with no reported errors under the recorded BIOS and temperature conditions.

Not acceptable:

> RAM is perfectly stable.

