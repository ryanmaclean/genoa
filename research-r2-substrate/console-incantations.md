# Console Incantations for genoa Universal Image

## Overview

Nearly every cloud provider exposes a serial console for out-of-band access. The
guest must direct kernel output to the serial port AND the framebuffer so that
both the provider's "System Log" / "Serial Console" feature and any graphical
console work. The canonical approach is dual-console: serial first, framebuffer
second (or vice versa depending on OS).

---

## FreeBSD

### Files involved

- `/boot/boot.config` — flags passed to boot0/boot1 before loader starts
- `/boot/loader.conf` — loader(8) configuration: console selection, baud rate,
  kernel tuning
- `/etc/ttys` — controls which tty devices get a `getty` (login prompt)

### Universal cloud configuration (amd64 and aarch64)

**/boot/loader.conf** (minimum viable cloud config):

```
# Dual console: serial first, framebuffer second
# Serial wins for early boot messages; EFI framebuffer provides graphical output
boot_multicons="YES"
boot_serial="YES"
comconsole_speed="115200"
console="comconsole,vidconsole"

# Reduce hz to lower CPU steal under hypervisors
# (comment out for latency-sensitive workloads)
kern.hz=100

# Cloud: skip 5-second boot menu delay
autoboot_delay="3"
```

**/boot/boot.config** (for BIOS/MBR path only — UEFI ignores this):

```
-Dh
```

The `-h` flag redirects output to the serial port from the very first
stage. `-D` enables dual-console. Only relevant if the image uses a
legacy BIOS boot path (Hetzner Robot, old OCI bare metal).

**/etc/ttys** — enable login on serial:

```
# Change: ttyu0 (com0) from "off" to "on"
ttyu0  "/usr/libexec/getty 3wire.115200"  vt100  on  secure
```

### Provider-specific notes

| Provider / Hypervisor | Serial Device | Baud Rate | Special |
|---|---|---|---|
| AWS EC2 (Nitro + pre-Nitro) | COM1 / ttyu0 | 115200 | System Log = COM1 output |
| GCP | COM1 / ttyu0 | 115200 | GCP historically used 38400 on very old instances; modern is 115200 |
| Azure / Hyper-V | COM1 / ttyu0 | 115200 | Azure Serial Console uses COM1; COM2 used for SAC (not relevant for FreeBSD) |
| Hetzner Cloud | COM1 / ttyu0 | 115200 | Standard |
| Hetzner Robot (bare metal) | COM1 / ttyu0 | 115200 | May need BIOS serial redirect |
| OCI (Oracle Cloud) | COM1 / ttyu0 | 115200 | Xen-based legacy tiers: same |
| bhyve (FreeBSD host) | `com0` mapped to pts | 115200 | bhyve `-c stdio` or `-l com1,stdio` |
| OpenBSD vmm/vmd | COM1 / ttyu0 | 115200 | vmd exposes serial as COM1 |
| Linode/Akamai | COM1 / ttyu0 | 115200 | Uses "Lish" serial console |
| QEMU TCG | COM1 / ttyS0 equivalent | 115200 | `-serial stdio` or `-serial mon:stdio` |
| Firecracker | COM1 | 115200 | FreeBSD not supported; documented for Linux |
| Apple HVF (UTM/Lima) | pl011 or 16550 | 115200 | Architecture-specific |

### GCP historical note

Very early GCP instances used 38400 baud for the serial console. GCP's
documentation and modern instances (2020+) use 115200. Set 115200 in genoa
images; the baud mismatch on old instances is acceptable since those tiers
are being retired.

### aarch64 serial (pl011 vs ns16550)

On ARM64, the serial port may be a pl011 (ARM PrimeCell UART) rather than
an NS16550-compatible UART. FreeBSD's `uart(4)` driver handles both.
The console device name is still `ttyu0`. No additional kernel option is
needed beyond `device uart`.

For QEMU SBSA/virt machine type:

```
# QEMU invocation showing serial:
qemu-system-aarch64 -machine virt -cpu cortex-a57 \
  -serial mon:stdio -display none ...
```

---

## NetBSD

### Console selection mechanism

NetBSD uses the boot loader's `consdev` command and MD boot configuration.
The specific mechanism varies by architecture.

**x86 (amd64/i386) — boot.cfg in ESP at /EFI/NetBSD/boot.cfg**:

```
# /EFI/NetBSD/boot.cfg
menu=Boot normally:boot
menu=Boot single user:boot -s
menu=Boot with serial console:consdev com0;boot
default=0
timeout=5

# For always-serial (cloud default):
consdev com0
```

The `consdev com0` command routes console to the first serial port (COM1)
before the kernel is loaded.

**Kernel command-line for direct QEMU invocation (NetBSD 11 PVH/MICROVM)**:

```
# NetBSD 11 PVH boot via pv(4) pseudo-bus; kernel command line:
console=com0
```

**MD_BOOTCFG mechanism (for platforms using FDT/chosen node)**:

On aarch64, NetBSD reads `stdout-path` from the FDT `/chosen` node.
Set in the DTB or QEMU machine definition:

```
# QEMU aarch64 with NetBSD - serial via FDT chosen node
qemu-system-aarch64 -append "console=com0 root=ld0a" ...
```

### /etc/ttys for serial login (NetBSD)

```
# Enable getty on com0 (COM1)
com0  "/usr/libexec/getty 115200"  vt100  on  secure
```

### Baud rates

Same as FreeBSD: 115200 universally. NetBSD's `getty` specification
uses the numeric baud directly or a gettytab entry.

---

## OpenBSD

### Boot loader serial console

OpenBSD uses `boot(8)` with `set tty com0` before booting the kernel.

**/etc/boot.conf** (placed in root of FFS partition, NOT the ESP):

```
# Always use serial console at 115200
set tty com0
stty com0 115200
boot
```

If this file is absent or inaccessible before the boot loader runs,
add to the UEFI loader prompt interactively:

```
boot> set tty com0
boot> stty com0 115200
boot> boot
```

For unattended cloud images, `/etc/boot.conf` is the authoritative method.

### Kernel console (OpenBSD)

OpenBSD's kernel reads the console from the boot loader's `set tty`
command. No kernel command line manipulation is needed — the loader
communicates the console choice to the kernel via its protocol.

### /etc/ttys for serial login (OpenBSD)

```
# Enable cua00 (COM1) in /etc/ttys
cua00  "/usr/libexec/getty std.115200"  vt220  on  secure
```

### Cloud provider compatibility

OpenBSD has official cloud images for AWS (pre-Nitro Xen) and some
providers. The serial console settings above work universally.

---

## Linux (reference control)

### Kernel command line

```
# Universal cloud kernel command line
console=ttyS0,115200n8 console=tty0

# AWS Nitro / GCP / Hetzner / OCI: 115200 is standard
# The second 'console=tty0' keeps framebuffer working

# For aarch64 (pl011 UART):
console=ttyAMA0,115200 console=tty0

# For Hyper-V (COM1 is the same ttyS0 on amd64):
console=ttyS0,115200n8 console=tty0
# Azure also exposes: earlycon=uart,io,0x3f8,115200n8
```

### GRUB2 (not vendored — system-provided only)

```
# /etc/default/grub
GRUB_CMDLINE_LINUX="console=ttyS0,115200n8 console=tty0"
GRUB_TERMINAL="serial console"
GRUB_SERIAL_COMMAND="serial --unit=0 --speed=115200 --word=8 --parity=no --stop=1"
```

**License note**: GRUB2 is GPL-3. genoa must NOT vendor GRUB2 in its image
build toolchain or distribute it as a component. Where GRUB2 is present,
it is the provider's installed loader (e.g., AWS marketplace Linux AMIs).
genoa's own images use OS-native loaders (see bootloader-decision.md).

### systemd-boot (not vendored)

systemd-boot is LGPL-2.1+. Not vendorable under genoa's license policy.
If the provider environment already has systemd-boot, genoa images can
coexist, but genoa must not ship systemd-boot itself.

---

## Hyper-V Serial Console Notes

Hyper-V exposes COM1 to the guest. The Special Administration Console (SAC)
is a Windows-side management channel on COM2 and is irrelevant for BSD/Linux
guests.

For FreeBSD on Hyper-V (Azure):

```
# /boot/loader.conf
console="comconsole,vidconsole"
comconsole_speed="115200"
boot_multicons="YES"
boot_serial="YES"
```

Azure Serial Console in the portal connects to COM1 (ttyu0 / ttyS0).
No special baud rate — 115200 standard.

---

## GCP Serial Console Notes

Historical GCP serial baud: Some documentation from 2017-2019 references 38400.
As of 2023+, GCP uses 115200. The `gcloud compute connect-to-serial-port`
command connects to the console at whatever baud the guest uses. Set 115200
in genoa images. If 38400 is needed for a legacy instance, it can be overridden
in `/boot/loader.conf` for FreeBSD.

---

## AWS Nitro Serial Console Notes

AWS Nitro instances expose COM1 at 115200. The EC2 "System Log" in the AWS
console captures output written to COM1 from early boot. The FreeBSD
`console="comconsole,vidconsole"` + 115200 setting provides full coverage.

Colin Percival (original FreeBSD EC2 maintainer) notes that the EC2 serial
console can be "laggy" — output may not appear for several minutes after boot.
This is normal; wait before assuming the console is broken.

---

## bhyve Serial Console Notes

bhyve exposes serial via `-l com1,stdio` (redirected to host stdio) or
`-l com1,/dev/nmdmXA` (null modem device for separate terminal). For genoa's
use case (FreeBSD physical fleet hosts running bhyve), the standard serial
configuration works. The guest sees COM1 as ttyu0.
