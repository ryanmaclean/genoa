# genoa Universal Image: Partition Layout

## Recommended Layout: GPT + UEFI

### Why GPT over MBR

- UEFI requires GPT for standard boot. All modern hypervisors (KVM/QEMU with OVMF,
  bhyve, Hyper-V Gen2, ESXi, Cloud Hypervisor, AWS Nitro) default to UEFI.
- GPT supports disks > 2TB; MBR does not.
- GPT partition labels/UUIDs provide stable device naming across Xen block device
  renaming (xvda vs nvme0n1 problem — labels survive device name changes).
- MBR ("BIOS boot") is only needed for: legacy Hetzner Robot bare metal with
  BIOS-only firmware, very old OCI bare-metal tiers, some OpenStack deployments
  on antique hosts. These are diminishing and can be addressed with a separate MBR
  compatibility partition (see below).

---

## Standard GPT Layout (FreeBSD Primary Image)

```
Disk: /dev/vtblk0 (or /dev/nvme0ns1, /dev/ada0, etc.)
Total: 20 GB minimum recommended for base cloud image

Partition  Type               Size    Label           Purpose
---------  -----------------  ------  --------------  ----------------------------------------
p1         EFI System (ESP)   512 MB  ESP             FAT32; holds loader.efi + EFI/BOOT/
p2         freebsd-ufs        16 GB   rootfs          UFS2 + Soft Updates; root filesystem
p3         freebsd-swap       2 GB    swap0           Swap (omit for stateless agent images)
```

### GPT Type GUIDs

| Partition | GUID |
|---|---|
| EFI System Partition | C12A7328-F81F-11D2-BA4B-00A0C93EC93B |
| FreeBSD UFS | 516E7CB6-6ECF-11D6-8FF8-00022D09712B |
| FreeBSD ZFS | 516E7CBA-6ECF-11D6-8FF8-00022D09712B |
| FreeBSD swap | 516E7CB5-6ECF-11D6-8FF8-00022D09712B |
| Linux filesystem | 0FC63DAF-8483-4772-8E79-3D69D8477DE4 |
| NetBSD FFS | 49F48D5A-B10E-11DC-B99B-0019D1879648 |

### ESP Contents (FreeBSD image)

```
/EFI/
  BOOT/
    BOOTX64.EFI      (copy of /boot/loader.efi, renamed; UEFI fallback path)
    BOOTAA64.EFI     (arm64 equivalent)
  FreeBSD/
    loader.efi       (canonical path; registered via efibootmgr)
```

FreeBSD's `loader.efi` is the Stage 3 bootloader. It reads `/boot/loader.conf`
from the freebsd-ufs or freebsd-zfs partition, then loads the kernel.

`loader.efi` location in FreeBSD source: `stand/efi/loader/` — **BSD-2-Clause license**.
It is fully vendorable.

### ESP Contents (NetBSD image)

```
/EFI/
  BOOT/
    BOOTX64.EFI      (copy of /usr/mdec/bootx64.efi)
    BOOTAA64.EFI     (arm64: /usr/mdec/bootaa64.efi)
  NetBSD/
    boot.cfg         (NetBSD boot configuration; consdev, menu entries)
```

NetBSD EFI bootloader source: `sys/arch/*/stand/bootXX/` — **BSD-2-Clause / BSD-3-Clause**.
Fully vendorable.

NetBSD's `/EFI/NetBSD/boot.cfg` is read from the ESP (FAT32), not from the root
filesystem. This is distinct from FreeBSD's `loader.conf` which lives on UFS.

### ESP Contents (OpenBSD image)

OpenBSD uses its own EFI bootloader `BOOTX64.EFI` (from `sys/arch/amd64/stand/efiboot/`).
License: **ISC** (OpenBSD standard). Fully vendorable.

```
/EFI/
  BOOT/
    BOOTX64.EFI      (OpenBSD EFI boot loader)
    BOOTAA64.EFI     (arm64)
```

OpenBSD's `/etc/boot.conf` lives on the FFS root partition, not the ESP.

---

## ZFS Variant (FreeBSD)

```
Partition  Type               Size    Label     Purpose
---------  -----------------  ------  --------  ----------------------------------------
p1         EFI System (ESP)   512 MB  ESP       FAT32; loader.efi
p2         freebsd-zfs        16 GB   zroot     ZFS pool (single-disk vdev for cloud image)
           (no swap — use zfs zvol or none)
```

ZFS notes:
- `loader.efi` supports ZFS boot natively; prefers ZFS over UFS if both present
- ZFS pool should be named `zroot` (FreeBSD convention) for loader auto-discovery
- Disable ZFS dedup in cloud images (write amplification, no benefit for uniform reads)
- Enable `compression=lz4` on datasets
- For genoa, UFS is recommended as the default: simpler, faster single-disk image
  creation, no pool-import needed at boot

---

## MBR / BIOS Legacy Fallback

Required for: Hetzner Robot (some bare-metal products), very old OCI shapes,
some OpenStack deployments on hardware without UEFI.

```
Partition  Type       Size    Purpose
---------  ---------  ------  ----------------------------------------
p1         freebsd-boot  512KB  BIOS boot partition (holds boot2)
p2         EFI System  512 MB  ESP (FAT32, populated even in MBR mode for hybrid)
p3         freebsd-ufs  16 GB  Root filesystem
p4         freebsd-swap  2 GB  Swap
```

**Hybrid GPT+MBR**: gdisk/gpart can create a protective MBR with a real MBR
partition table in addition to GPT. This allows BIOS firmware to boot from
the MBR path while UEFI firmware uses the GPT path. Use `gpart bootcode -b
/boot/pmbr -p /boot/gptboot -i 1` on FreeBSD.

**Recommendation for genoa**: Default to pure GPT+UEFI. Create a separate
"legacy-bios" image variant for Hetzner Robot / OpenStack-legacy environments.
Do not use hybrid MBR by default — it adds complexity and some UEFI firmware
is confused by hybrid layouts.

---

## Partition Labeling Strategy

GPT partition labels provide stable device naming across hypervisors.
Xen block devices rename on migration (xvda → xvdb); NVMe vs virtio-blk
devices have different names. Labels survive this.

```
# FreeBSD gpart labeling:
gpart add -t efi -s 512M -l esp ada0
gpart add -t freebsd-ufs -s 16G -l rootfs ada0
gpart add -t freebsd-swap -s 2G -l swap0 ada0

# Reference by label in fstab:
/dev/gpt/rootfs  /       ufs  rw,noatime  1 1
/dev/gpt/swap0   none    swap sw          0 0
```

Colin Percival's EC2 porting advice: use GPT labels or UFS labels
(`tunefs -L rootfs /dev/ada0p2`) so the root device is always findable
regardless of whether it appears as xvda, nvme0n1, or vtblk0.

---

## Provider-Specific Disk Size Guidance

| Provider | Minimum Boot Volume | Recommended Image Size |
|---|---|---|
| AWS EC2 | 8 GB (gp3 EBS) | 20 GB |
| GCP Compute | 10 GB (pd-standard) | 20 GB |
| Azure | 30 GB minimum OS disk | 30 GB |
| Hetzner Cloud | 20 GB | 20 GB |
| OCI | 47 GB (minimum shape) | 50 GB |
| bhyve (local) | As needed | 10 GB+ |
| Firecracker | As needed | < 1 GB (minimal rootfs) |

---

## Swap Recommendation for Cloud Images

- **Agent/ephemeral images**: No swap partition. Use a RAM-backed tmpfs or
  swap file created on first boot if needed. Reduces image size and avoids
  zeroing a swap partition on every write.
- **General-purpose cloud VMs**: 1–2 GB swap as p3. Helps with OOM situations.
- **Never**: Fixed swap partition in Firecracker / container-style environments
  where the image is read-only and rootfs is overlayfs.

---

## NetBSD Partition Layout

NetBSD uses its own FFSv2 (Fast File System version 2) as the native filesystem.

```
Partition  Type               Size    Purpose
---------  -----------------  ------  ----------------------------------------
p1         EFI System (ESP)   512 MB  FAT32; bootaa64.efi / bootx64.efi + boot.cfg
p2         NetBSD FFS2        16 GB   Root filesystem (FFSv2)
p3         NetBSD swap        2 GB    Swap
```

NetBSD disklabel lives inside the GPT partition (NetBSD tradition). The
`/EFI/NetBSD/boot.cfg` file in the ESP controls boot; `consdev com0` for
serial console.

---

## OpenBSD Partition Layout

OpenBSD uses its own disklabel within a GPT partition.

```
GPT:
  p1: EFI System Partition (512 MB, FAT32)
  p2: OpenBSD data (rest of disk) — contains OpenBSD disklabel

OpenBSD disklabel (inside p2):
  a: / (FFS2, 16 GB)
  b: swap (2 GB)
```

OpenBSD's installer creates this layout by default. The EFI bootloader
(`BOOTX64.EFI`) is placed in the ESP by the installer.

---

## Providers Still Requiring MBR (2026 Assessment)

| Provider | MBR Required? | Notes |
|---|---|---|
| AWS EC2 | NO | UEFI available on Nitro; PVH on Xen pre-Nitro (no MBR) |
| GCP | NO | UEFI only on modern shapes |
| Azure | NO | UEFI required for Gen2 VMs (recommended) |
| Hetzner Cloud | NO | UEFI supported |
| Hetzner Robot | SOMETIMES | Depends on server model; some have BIOS only |
| OCI | NO | UEFI supported |
| OpenStack | SOMETIMES | Depends on host config; config-drive may need special handling |
| bhyve | NO | UEFI with OVMF |
| vmm/vmd | NO | OpenBSD boots directly; UEFI path supported |
| Vultr | NO | UEFI supported |
| DigitalOcean | NO | UEFI on newer droplets |
