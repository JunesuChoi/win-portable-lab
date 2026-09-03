# System identification and monitoring detailed guide

Keep CPU, board, BIOS, memory, and GPU-driver versions with every baseline screenshot or report.

## HWiNFO (hwinfo)

Start Sensors-only and record CPU Package/CCD, GPU Hot Spot, VRM, SSD, power, and clocks. Separate values after three idle minutes from load values. Do not run it beside motherboard monitoring software when it warns of EC contention.

## CPU-Z (cpuz)

Capture CPU model/core/multiplier, board/BIOS, channel/DRAM Frequency, and each DIMM XMP/EXPO. DDR rate is double DRAM Frequency: 1800 MHz is DDR4-3600.

## GPU-Z (gpuz)

Compare GPU/VRAM/bus, temperature/hot spot/power, and PerfCap Reason before and under load. Do not use BIOS save/flash.

## TrafficMonitor Lite (trafficmonitor)

Show only CPU, RAM, network, GPU, and disk fields required. Move or hide the overlay when it obscures a benchmark. It identifies unusual activity during long runs; it does not validate sensor accuracy.

## ZenTimings (zentimings)

AMD only. Capture FCLK/UCLK/MCLK, timings, and DIMM voltages, then compare them with values actually applied in BIOS. A readout is not a voltage-change recommendation.
