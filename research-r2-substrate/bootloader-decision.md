# genoa Bootloader Decision

## License Constraints (genoa policy)

Allowed: MIT, BSD-2-Clause, BSD-3-Clause, Apache-2.0
Disqualified for vendoring: GPL-2, GPL-3, LGPL, AGPL, CDDL

| Bootloader | License | Vendorable? | Strategy |
|---|---|---|---|
| GRUB2 | GPL-3 | NO — must not vendor | OK to invoke if provider pre-installs; do not ship in genoa image |
| U-Boot | GPL-2 | NO — must not vendor | OK to invoke as firmware (external); do not ship in genoa image |
| syslinux/ISOLINUX | GPL-2 | NO | Do not use |
| systemd-boot | LGPL-2.1+ | NO — LGPL disqualified | Do not use |
| FreeBSD loader.efi | BSD-2-Clause | YES | Primary choice for FreeBSD images |
| NetBSD bootaa64.efi / bootx64.efi | BSD-2-Clause | YES | Primary choice for NetBSD images |
| OpenBSD BOOTX64.EFI | ISC | YES | Primary choice for OpenBSD images |
| Limine | BSD-2-Clause | YES | Alternative for multi-OS images or Linux-only fallback |
| edk2/OVMF (firmware) | BSD-2-Clause | YES (firmware, not image) | Host-side UEFI firmware for bhyve/QEMU |
| OpenSBI (RISC-V M-mode) | BSD-2-Clause | YES | Required on RISC-V as M-mode firmware |

---

## Per-OS Bootloader Decision

### FreeBSD 15

**Loader**: `loader.efi` (BSD-2-Clause)

**Source**: `stand/efi/loader/` in FreeBSD src tree  
**Binary location in image**: `/boot/loader.efi` on the root UFS  
**ESP placement**: Copy to `EFI/BOOT/BOOTX64.EFI` (amd64) or `EFI/BOOT/BOOTAA64.EFI` (arm64)

**Boot chain**:
1. UEFI firmware reads ESP (FAT32)
2. UEFI loads `EFI/BOOT/BOOTX64.EFI` = `loader.efi`
3. `loader.efi` reads `/boot/loader.conf` from the freebsd-ufs or freebsd-zfs partition
4. `loader.efi` loads `/boot/kernel/kernel` + modules
5. Kernel takes over

**efibootmgr registration** (optional, for non-fallback path):
```sh
efibootmgr -c -l 'EFI\FreeBSD\loader.efi' -L "FreeBSD 15"
```

**Hyper-V (Azure) note**: Hyper-V Gen2 VMs are UEFI-only. `loader.efi` works
correctly. Azure requires the image to have `BOOTX64.EFI` in the fallback path
`EFI/BOOT/BOOTX64.EFI` — not just a registered boot entry.

**PVH boot (Xen) note**: For Xen PVH, `loader.efi` is NOT used. Xen loads the
kernel directly from the ELF image with Xen ELF notes embedded. The `XENHVM +
xenpci` options in the kernel handle the PVH entry point. No loader.efi in the
Xen PVH boot path.

**Firecracker note**: Firecracker loads `vmlinux` directly (Linux ELF binary)
without any firmware or bootloader. FreeBSD is NOT a supported Firecracker guest;
`loader.efi` is irrelevant here.

**BIOS legacy fallback** (if required):
- `pmbr` → `gptboot` → UFS → `loader` (ASCII loader, not EFI)
- Files: `/boot/pmbr`, `/boot/gptboot`, `/boot/loader`
- License: BSD-2-Clause (all FreeBSD components)
- Command: `gpart bootcode -b /boot/pmbr -p /boot/gptboot -i 1 ada0`

---

### NetBSD 11

**Loader**: `bootx64.efi` / `bootaa64.efi` (BSD-2-Clause)

**Source**: `sys/arch/amd64/stand/efiboot/` (amd64) and equivalent for arm64  
**Binary installed at**: `/usr/mdec/bootx64.efi` after `make install`

**ESP placement**:
```
EFI/BOOT/BOOTX64.EFI    (amd64 fallback path)
EFI/BOOT/BOOTAA64.EFI   (arm64 fallback path)
EFI/NetBSD/boot.cfg     (NetBSD boot configuration)
```

**boot.cfg** (placed in ESP at `EFI/NetBSD/boot.cfg`):
```
# NetBSD genoa cloud boot configuration
consdev com0
stty com0 115200
menu=Boot NetBSD:boot netbsd
menu=Boot single user:boot netbsd -s
timeout=5
default=1
```

**NetBSD 10.0 EFI improvements** (from release notes, relevant to 11):
- Boot from raid(4) volumes
- ISO9660 support
- boot.cfg support
- `gop` command for video mode selection
- Loading kernel modules from the bootloader

**RISC-V (riscv64)**: NetBSD riscv64 uses OpenSBI as M-mode firmware (GPL-2 for
OpenSBI itself, but it runs as separate firmware, not vendored in the OS image).
The S-mode loader is NetBSD's own boot code (BSD-licensed). OpenSBI is analogous
to firmware/BIOS — it is external to the OS image.

**Note on OpenSBI licensing**: OpenSBI is **BSD-2-Clause** (not GPL). Confirmed:
the OpenSBI project at https://github.com/riscv-software-src/opensbi is BSD-2-Clause.
This is safe to vendor if needed.

---

### OpenBSD 7.6

**Loader**: `BOOTX64.EFI` / `BOOTAA64.EFI` (ISC license)

**Source**: `sys/arch/amd64/stand/efiboot/` in OpenBSD src  
**Binary installed at**: `/usr/mdec/BOOTX64.EFI`

**ESP placement**:
```
EFI/BOOT/BOOTX64.EFI    (amd64)
EFI/BOOT/BOOTAA64.EFI   (arm64)
```

**boot.conf** (lives on FFS root, NOT in ESP — unique to OpenBSD):
```
# /etc/boot.conf (on root FFS partition)
set tty com0
stty com0 115200
boot
```

**OpenBSD boot process notes**:
- The EFI loader reads `/etc/boot.conf` from the FFS root partition
- No `boot.cfg` in the ESP (unlike NetBSD)
- `set tty com0` must appear before `boot` in boot.conf
- OpenBSD 7.7+ aarch64: new bootloader options available

**Cloud image note**: OpenBSD's official installer does not support unattended
cloud provisioning natively. The Exoscale openbsd-cloud-init (MIT license) or
a custom firstboot script handles cloud init (see cloud-init-strategy.md).

---

### Linux (control reference)

genoa is primarily BSD-focused; Linux is the control. For Linux images
produced by genoa tooling:

**Option A: Embedded bzImage** — For Firecracker / Cloud Hypervisor / direct
kernel boot. No bootloader in the image at all. The hypervisor loads the kernel.

**Option B: Provider-installed GRUB2** — For AWS/GCP/Azure Linux AMIs where the
provider's infrastructure has GRUB. genoa installs the kernel + initrd;
GRUB is the provider's responsibility. genoa does NOT vendor GRUB2 (GPL-3).

**Option C: Limine** (BSD-2-Clause) — For Linux images where genoa must ship
its own bootloader. Limine is a modern UEFI bootloader under BSD-2-Clause.
It supports Linux (bzImage), multiboot2, and chainloading. Viable alternative
to GRUB2 without the GPL contamination.

Limine source: https://github.com/limine-bootloader/limine  
License: BSD-2-Clause (confirmed)  
Supports: x86_64, aarch64 (in development as of 2025)

---

## U-Boot Strategy (ARM/RISC-V)

U-Boot (GPL-2) is often the only available bootloader for embedded ARM and
RISC-V platforms (Pi 4, Pi 5, StarFive boards). It is NOT vendored in genoa
images, but it is the FIRMWARE that genoa images boot FROM on these platforms.

**Strategy**: U-Boot is pre-installed on the board's SPI flash or SD boot
partition by the board manufacturer or platform configuration scripts. genoa's
image installs only the OS-native EFI loader into the ESP; U-Boot's UEFI
implementation loads `EFI/BOOT/BOOTAA64.EFI` from the ESP.

For Raspberry Pi:
- Pi 4/5 with UEFI firmware (Pete Batard's rpi-uefi): loads `BOOTAA64.EFI` from
  the FAT32 boot partition. genoa's `BOOTAA64.EFI` (FreeBSD/NetBSD/OpenBSD EFI
  loader) is placed there. U-Boot not directly involved.
- Pi 4/5 with raw U-Boot: U-Boot's `bootefi` command or distro boot script loads
  `BOOTAA64.EFI`. Same outcome.
- License of Pete Batard's rpi-uefi: BSD-licensed (uses edk2/Tianocore which is
  BSD-2-Clause). Safe to reference but genoa does not ship this firmware.

---

## Multi-OS / Dual-Boot in Same Image

genoa produces single-OS images. A "multi-OS" genoa image is out of scope.
However, for an image that supports multiple kernel configurations (e.g.,
cloud vs bare-metal kernel), the ESP can hold multiple EFI binaries:

```
EFI/BOOT/BOOTX64.EFI       (default boot, cloud-optimized kernel)
EFI/FreeBSD/loader-cloud.efi
EFI/FreeBSD/loader-baremetal.efi
```

Selection is done via `efibootmgr` boot entries or via loader.conf menu.

---

## Summary Table

| OS | Architecture | Primary Loader | License | In Image? | Notes |
|---|---|---|---|---|---|
| FreeBSD 15 | amd64 | loader.efi | BSD-2 | YES | ESP: BOOTX64.EFI |
| FreeBSD 15 | aarch64 | loader.efi | BSD-2 | YES | ESP: BOOTAA64.EFI |
| FreeBSD 15 | riscv64 | loader.efi + OpenSBI fw | BSD-2 + BSD-2 | YES (loader) | OpenSBI is platform firmware |
| NetBSD 11 | amd64 | bootx64.efi | BSD-2 | YES | ESP: BOOTX64.EFI |
| NetBSD 11 | aarch64 | bootaa64.efi | BSD-2 | YES | ESP: BOOTAA64.EFI |
| OpenBSD 7.6 | amd64 | BOOTX64.EFI | ISC | YES | ESP: BOOTX64.EFI |
| OpenBSD 7.6 | aarch64 | BOOTAA64.EFI | ISC | YES | ESP: BOOTAA64.EFI |
| Linux 6.x | amd64 | Limine (if needed) | BSD-2 | YES | Or direct kernel boot |
| Linux 6.x | aarch64 | Limine or direct | BSD-2 | YES | |
