# Third-party software

## Licence scope

The MIT licence in [LICENSE](LICENSE) covers this project's own scripts, configuration and documentation only. It does not cover the third-party diagnostic programs the project downloads on demand. Each of those remains under its own vendor terms, and several are free for personal use only. Third-party binaries are never committed to this repository and are not included in core release archives.

WinPortableLab core releases do not contain third-party diagnostic binaries. Package definitions record the upstream source, pinned SHA-256, trust class, risk metadata, and whether redistribution is permitted.

The offline-pack builder includes an archive only when its package manifest explicitly allows redistribution and the cached file matches the pinned hash. Vendor-restricted packages remain download definitions and are not copied into distributable packs.

Each upstream program remains subject to its own license and terms. Review the current vendor terms before redistributing any archive.
