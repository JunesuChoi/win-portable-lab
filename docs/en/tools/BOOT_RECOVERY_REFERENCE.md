# Boot memory and AMD driver recovery detailed guide

## MemTest86+ (memtest86plus)

Put the ISO on a Ventoy USB and select it from the UEFI boot menu. Check Secure Boot compatibility. Use at least four passes with zero errors. One error is enough to remove overclocking and test DIMMs individually across slots. Never force power off during a run.

## AMD Cleanup Utility (amd-cleanup-utility)

Use only for AMD graphics-driver problems. Obtain the replacement AMD driver and BitLocker recovery key first, and confirm a restore point can be created. Follow the Safe Mode recommendation and reboot after removal. It is neither a multi-vendor cleaner nor routine maintenance for a working system.

## Recovery order

Record symptoms/events, obtain the replacement driver, perform one removal or boot test, reboot, then verify Device Manager and a brief 3D load.
