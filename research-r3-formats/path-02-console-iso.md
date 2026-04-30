# Path 2: Console ISO Mount

**Priority: 5 (low) — manual only, no automation path**

## STATUS: INTERACTIVE ONLY — NOT FOR AUTOMATION

This path is documented for completeness and for operators who need a fallback
when no API exists. It cannot be automated by genoa-deploy without screen-scraping
or browser automation (which we will not implement).

## Summary

The operator boots a stock provider VPS, accesses the provider's web console,
and mounts a bootable ISO image via the console's virtual media / KVM-over-IP
feature. The ISO contains a minimal installer that writes the genoa image to
disk, then the ISO is unmounted and the server reboots.

This is the "lowest common denominator" for providers with no image import API
and no rescue system.

## Works for

| Provider | Console type | Notes |
|----------|-------------|-------|
| Hetzner Cloud | VNC console in Hetzner Cloud web UI | "Mount ISO" option available |
| IONOS (1&1) | KVM console in IONOS web UI | VNC-based |
| OVHcloud | IPMI / IDRAC / iLO (bare metal) | For dedicated servers only |
| Contabo | VNC console in Contabo web UI | |
| Generic colo / bare metal | IPMI, iLO, iDRAC, Redfish | Full remote console |
| Raspberry Pi 4/5 (USB-OTG) | USB gadget mode as virtual CD | Niche, hardware-specific |

## Does NOT work for

- Providers with no console access (managed container / FaaS platforms)
- Providers where the console only shows serial output (no virtual media)
- Any automated CI/CD pipeline

## Required artifacts

A bootable ISO that:
1. Contains the genoa raw image (or fetches it from URL at boot)
2. Has a minimal init that writes the image to /dev/vda (or /dev/sda)
3. Handles UEFI boot (ISO 9660 with El Torito + EFI boot catalog)

Building this ISO is a separate concern from genoa-deploy's core path. The ISO
itself can be a tiny FreeBSD/NetBSD/mfsBSD image with a `genoa-install` script.

## Procedure (operator)

1. Upload genoa-install.iso to the provider's ISO library (or use a URL)
2. In the provider console: Servers > select server > ISO > Mount ISO
3. Reboot into ISO
4. ISO init script runs: `curl URL | dd of=/dev/vda bs=4M status=progress`
5. Unmount ISO in console
6. Reboot server

## Implementation effort

**Low for genoa-deploy** (no code needed in the deploy tool), but **high for
operators** (manual steps, console UI varies by provider).

Genoa should document this as a "manual fallback" with a guide, not implement
it as an automated path.

## License traps

- No CLI tools from genoa-deploy are involved in this path
- The ISO builder would use: `mkisofs` (GPL-2) / `xorriso` (GPL-3) — use as
  external subprocess only, never vendor. Alternatively `hdiutil` on macOS (free).
- **No iPXE** — if the ISO netboots internally, use `syslinux/isolinux`
  (GPL-2, exec-only) or the OS-native EFI loader

## References

- Hetzner Cloud ISO mount: https://docs.hetzner.com/cloud/servers/iso-support/
- mfsBSD (minimal FreeBSD ISO builder): https://mfsbsd.vx.sk/ (BSD-2-Clause)
