# Driver, cooling, and event diagnostics detailed guide

## Sysinternals Suite (sysinternals)

Hide signed Microsoft entries in Autoruns and review non-Microsoft startup items only. Use Process Explorer for tree, path, and signature inspection; do not terminate or delete. Treat RAMMap, TCPView, and Procmon as observation/evidence tools.

## Driver Store Explorer (driverstoreexplorer)

Use Enumerate to inspect package, provider, version, and in-use state. Do not delete without a replacement driver and restore point. This project does not recommend Delete Driver(s) or Force Deletion, especially for active storage, network, and display drivers.

## Fan Control (fancontrol)

Identify sensors and fans first. Briefly lower one fan at a time to verify its physical connection and do not confuse CPU, intake, and exhaust. Keep curves no more aggressive than safe BIOS defaults and validate temperature/fan movement at idle, game, and load.

## BlueScreenView / FullEventLogView (bluescreenview, fulleventlogview)

Bug Check and driver names in BlueScreenView are candidates, not root cause before WinDbg confirmation. Export Kernel-Power, WHEA, Disk, Display, and install events chronologically with FullEventLogView.

## USBDeview (usbdeview)

Use it for VID/PID, last-connected time, and device names. Disable/Uninstall/Disconnect can remove keyboard, mouse, or storage devices, so never bulk or automate those actions.

Do not delete drivers without recovery. Restore the previous state on abnormal fan heat or repeated device disconnects.
