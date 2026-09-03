# CPU, memory calculation, and tuning detailed guide

Capture HWiNFO, retain a known-good BIOS profile, and ensure recovery before starting.

## y-cruncher (y-cruncher)

Run the default Stress Tester preset for ten minutes first. VST/FFT exercise CPU and memory controller together. Any error, calculation mismatch, WHEA, or temperature excursion fails; grow a passing run to 30 minutes then one to two hours.

## Intel XTU (intel-xtu)

Confirm supported generation and BIOS lock state. Record current Basic Tuning values and a benchmark, then change one voltage, power-limit, or multiplier setting by one step only. Apply, reboot, and run a short stability test. Avoid auto tuning and unknown profiles.

## AMD Ryzen Master (ryzen-master)

Confirm CPU, chipset, and BIOS support. Record PPT/TDC/EDC, temperature, and clock. Manage PBO/Curve Optimizer in either BIOS or Ryzen Master, not both. Change per-core values in small steps and validate boot, idle, and load.

Restore the last stable setting on errors, freezes/reboots, temperature near the vendor limit, or storage errors.
