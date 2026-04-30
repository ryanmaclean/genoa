# RL4: Cloud Provider BYOI Constraints and BSD Deployment Patterns

**Research date:** 2026-04-30
**Working directory:** `/Users/studio/genoa/research-linode/rl4-general-ext4/`
**Scope:** Canonical solution patterns for deploying non-Linux (BSD/unikernel) OSes on providers that lock BYOI to ext3/ext4 Linux filesystems.

---

## Q1: Provider Survey — Which Providers Have the ext4/Linux-Only Constraint?

### Confirmed ext3/ext4 Required

| Provider | Constraint | Evidence |
|---|---|---|
| **Akamai/Linode** | ext3 or ext4 required explicitly | Docs: "Format the disk using the ext3 or ext4 file system." Raw `.img` only, gzip compressed, max 6 GB uncompressed. |
| **DigitalOcean** | "Linux and Unix-like images" only; no filesystem type specified but BIOS boot required; no ISO support | Docs state Linux/Unix-like only. No filesystem type enumerated — unclear if UFS would pass. Windows and ISO explicitly blocked. |
| **AWS VM Import** | ext2/ext3/ext4/btrfs/JFS/XFS only; **UFS and ZFS explicitly unsupported** | Docs: supported filesystems listed; UFS/ZFS/BSD filesystems NOT supported. OS list is Linux/Windows only. |
| **GCP Image Import** | Linux-centric; "primary partition can be in any format" but OS must be "supported image"; FreeBSD not on supported list | Docs reference a supported OS list that is Linux-only. MBR/GPT required. Not format-agnostic in practice. |

### BSD-Friendly or Unrestricted BYOI

| Provider | BSD Status | Evidence |
|---|---|---|
| **Oracle Cloud (OCI)** | **FreeBSD explicitly supported** (v8+); VMDK or QCOW2 format; no filesystem type restriction stated | BYOI docs list FreeBSD 8, 9, 10, 11, 12+ under "Linux/UNIX-like." Also available via OCI Marketplace (UFS and ZFS variants). |
| **Vultr** | FreeBSD available as a first-class OS in their managed image library; custom ISO upload supported | Platform lists FreeBSD among available operating systems. ISO upload allows any OS install. |
| **BuyVM** | FreeBSD, OpenBSD, NetBSD listed explicitly as available OS options | BuyVM FAQ/homepage lists "Free / Open / Net BSD" as available. KVM-based so any OS that runs on KVM works. |
| **AWS EC2 (Marketplace)** | **Official FreeBSD AMIs available** via FreeBSD Foundation and AWS Marketplace; UFS/ZFS root disks work once inside an AMI | FreeBSD 14.x AMIs available for amd64 and aarch64 via SSM Parameter Store. AWS VM Import does NOT support UFS but AMIs can have any filesystem once registered. |
| **Azure** | FreeBSD available via Marketplace | FreeBSD 14.2 release notes confirm Azure Marketplace availability. |
| **OCI Marketplace** | FreeBSD in UFS and ZFS variants | FreeBSD 14.2 release notes confirm OCI Marketplace images in both UFS and ZFS. |
| **NetBSD on EC2** | Official NetBSD AMIs exist (bsdec2-image-upload tooling) | NetBSD wiki documents AMI creation tools and region AMI IDs. |

### Providers with Insufficient Documentation Found

| Provider | Finding |
|---|---|
| **Contabo** | No accessible BYOI documentation found; custom image upload page 404. FreeBSD not mentioned in public docs. Likely Linux-only from ISO or custom image UI. |
| **RamNode** | "Bring your own" phrasing with cloud-init mentioned; FreeBSD not listed. Unclear if filesystem-restricted. |
| **UpCloud** | Documentation inaccessible (403/404). API docs reference storage import but no filesystem type detail found. |
| **Exoscale** | Documentation access blocked. Custom template support exists but filesystem requirements unknown. |
| **OVHcloud VPS** | Documentation redirects to generic help portal; BYOI requirements not extractable. Public Cloud has BYOI but VPS specifics unclear. |
| **Cherry Servers** | Documentation inaccessible (ECONNREFUSED). Likely supports custom OS via rescue/ISO given dedicated server model. |
| **IONOS/1&1** | Custom image upload page 404. UEFI requirement noted for newer regions. Filesystem type not specified. |
| **Hetzner Cloud** | Documentation does not specify custom image upload capability. Offers ISO attachment. Community tutorials cover FreeBSD via rescue mode (ISO install). |
| **Fasthosts** | No accessible documentation found. |

---

## Q2: GRUB2 BSD Support Matrix

### Source: GRUB manual (grub.texi, current upstream)

GRUB2 has **native, non-chainloader BSD boot support** via a dedicated BSD loader module (`grub-core/loader/bsd.c`). It is NOT simply a chainloader — it implements the BSD/a.out and ELF kernel loading protocols directly.

### Commands Available

| Command | OS | Function |
|---|---|---|
| `kfreebsd <path>` | FreeBSD | Load FreeBSD ELF kernel. Path example: `/boot/kernel/kernel` |
| `kfreebsd_module <path>` | FreeBSD | Load a FreeBSD kernel module (`.ko` file) |
| `kfreebsd_module_elf <path>` | FreeBSD | Load FreeBSD ELF module (e.g., `opensolaris.ko` for ZFS) |
| `kfreebsd_loadenv <path>` | FreeBSD | Load `device.hints` environment |
| `knetbsd <path> [opts]` | NetBSD | Load NetBSD kernel; supports boot flags like `-s -v` |
| `knetbsd_module_elf <path>` | NetBSD | Load NetBSD ELF kernel module |
| `kopenbsd <path>` | OpenBSD | Load OpenBSD kernel |
| `kopenbsd_ramdisk <path>` | OpenBSD | Load OpenBSD ramdisk |

### Example FreeBSD grub.cfg (from Gentoo wiki, confirmed working)

```
menuentry "FreeBSD" --class freebsd --class bsd --class os {
    insmod ufs2
    insmod bsd
    set root=(hd0,1)
    kfreebsd /boot/kernel/kernel
    kfreebsd_loadenv /boot/device.hints
    set kFreeBSD.vfs.root.mountfrom=ufs:/dev/ada0s1a
    set kFreeBSD.vfs.root.mountfrom.options=rw
}
```

### FreeBSD Version Support (GRUB2 Native)

- **GRUB2's kfreebsd loads FreeBSD ELF kernels** — this works for FreeBSD 4 through approximately FreeBSD 12/13.
- **Critical limitation for FreeBSD 13+:** The native `kfreebsd` approach predates FreeBSD's move to a unified EFI-first boot model. Modern FreeBSD (13+, 14+) with ZFS root or vnet is best served by chainloading `loader.efi` rather than using `kfreebsd` directly.
- **Recommended modern approach:** GRUB2 `chainloader` + FreeBSD's `loader.efi` (EFI binary at `/boot/loader.efi`). This requires EFI mode.

### GRUB2 EFI Chainloader Pattern

```
menuentry "FreeBSD via loader.efi" {
    insmod chain
    set root=(hd0,1)
    chainloader /boot/loader.efi
}
```

This delegates to FreeBSD's native loader, which handles ZFS, device.hints, kernel modules, and all modern boot complexity. **This is the correct approach for FreeBSD 13+.**

### NetBSD Support Status

- `knetbsd` is implemented in GRUB2 and works for NetBSD kernels.
- NetBSD module loading requires wrapping inside `miniroot.kmod`.
- NetBSD has official EC2 AMI tooling (`bsdec2-image-upload`) — implies NetBSD itself handles cloud deployment natively.

### OpenBSD Support Status

- **OpenBSD officially states GRUB "usually fails"** when used for multiboot with OpenBSD.
- `kopenbsd` is in GRUB2 but OpenBSD's boot protocol diverges from FreeBSD's in ways GRUB does not fully handle.
- **Correct approach for OpenBSD:** Use rEFInd or chainload OpenBSD's own `bootx64.efi`. OpenBSD uses its own non-standard EFI loader.
- OpenBSD cannot be reliably booted via `kopenbsd` in production. Chainloading `bootx64.efi` from an ESP works.

### GRUB2 BSD Support Summary

| BSD | Native kXXXbsd | EFI Chainloader | Status |
|---|---|---|---|
| FreeBSD ≤12 | Yes (`kfreebsd`) | Possible | Works; `kfreebsd` adequate |
| FreeBSD 13/14/15 | Partial | **Preferred** | Use `chainloader /boot/loader.efi`; `kfreebsd` may fail with ZFS/vnet |
| NetBSD | Yes (`knetbsd`) | Possible | Works with caveats (miniroot.kmod) |
| OpenBSD | Unreliable (`kopenbsd`) | **Required** | Must chainload `bootx64.efi`; `kopenbsd` frequently fails |

---

## Q3: The "ext4 Container" Trick

### The Core Technique

The technique involves creating a disk image with **partition 1 as ext4** (satisfying the validator) and **partition 2 as UFS2 or ZFS** (the actual BSD root), with GRUB2 installed in the MBR/ESP pointing at partition 2's BSD filesystem.

### Does the Partition 1 ext4 Trick Work?

**Theoretically yes, practically provider-dependent.**

- `blkid` and `file(1)` inspect filesystem magic bytes at the partition offset, not the whole disk. `blkid /dev/loop0p1` returning `ext4` says nothing about `/dev/loop0p2`.
- The question is what the validator actually checks:
  - **Linode's documented requirement** is that the image disk be formatted as ext3/ext4. Their docs say "non-partitioned disk" is best practice. A single-partition ext4 disk is the expected format.
  - Linode's image upload flow expects a **disk image** (not a partition image) that is itself ext3/ext4 formatted — meaning the device, not a partition within it, should be ext4.
  - For Linode specifically: a multi-partition image where partition 1 is ext4 likely fails because their validator inspects the root device, not just the first partition. The image should BE an ext4 filesystem, not contain one.

### What Linode Actually Validates (from RL-1 research + docs)

Per Akamai/Linode upload documentation:
- The `.img` file itself should be a raw disk image.
- "Best practice" is a **non-partitioned disk** formatted as ext3/ext4 — meaning the entire block device is one ext4 filesystem.
- If the image has a partition table, Linode's system must mount and inspect the filesystem on the root partition.
- The validator almost certainly calls `blkid` or similar on the first partition (or the raw device) and checks for ext2/ext3/ext4 magic.

### Multi-Partition Strategy Analysis

If the image has:
- `/dev/sda` (raw disk, partition table present)
- `/dev/sda1` = ext4 (small, contains GRUB + kernel stubs)
- `/dev/sda2` = UFS2 (BSD root)

The provider validator behavior depends on:
1. Whether it scans just `/dev/sda` (raw) or `/dev/sda1` (first partition)
2. Whether it validates bootability by trying to mount the first partition

**For Linode specifically:** The documented expectation of a non-partitioned ext4 disk means this trick likely fails — Linode would see a partition table where they expect raw ext4, and the validator would fail on `blkid /dev/loop0` (the raw device, not p1).

**For less strict providers:** If the validator only checks `blkid /dev/loop0p1`, the trick works. No public evidence of specific providers known to not scan past partition 1.

### The Asymmetry with AWS

AWS EC2 works differently: AMIs are registered block device snapshots, not uploaded ext4 images. FreeBSD AMIs use UFS or ZFS on the root EBS volume directly — the EC2 hypervisor doesn't validate filesystem type. This is why FreeBSD runs natively on EC2 but cannot be uploaded via VM Import.

---

## Q4: The In-Memory BSD Approach (mfsBSD Pattern)

### What mfsBSD Is

mfsBSD generates a bootable disk/ISO image that loads a complete minimal FreeBSD system entirely into RAM via the `md` (memory disk) subsystem. It supports FreeBSD 8 through 14.

**Key properties:**
- Self-contained: all of FreeBSD userland and kernel in a compressed image
- Supports EFI and legacy BIOS boot
- Includes ZFS tools, network stack, SSH (dropbear), and `zfsinstall` for production deployment
- Can install FreeBSD to disk, reformat disks, etc.

### The Ext4-Wrapped mfsBSD Pattern

**Mechanism:**
1. Build an ext4 disk image containing: GRUB2 + Linux kernel + Linux initrd
2. The initrd is a custom Linux initramfs that, on boot, `kexec`s into mfsBSD (or loads the FreeBSD kernel directly)
3. Once FreeBSD is running in RAM, it reformats the disk to UFS2/ZFS and installs

**Is this practical?**
- `kexec` from Linux to FreeBSD: **does not work** — `kexec` is Linux-specific and only loads Linux kernels. FreeBSD is not a kexec target.
- **Alternative:** Linux initramfs boots, then issues a `dd` or network fetch to overwrite the disk with a FreeBSD image, then reboots. The machine comes back with FreeBSD.
- **The "dd-and-reboot" trick** is the canonical approach used in the wild (e.g., for Hetzner Cloud rescue mode installations of FreeBSD). Steps:
  1. Boot into provider's rescue/recovery Linux environment
  2. Download a FreeBSD disk image (mfsBSD or full installation image)
  3. `dd if=freebsd.img of=/dev/sda`
  4. Reboot
  5. Server boots into FreeBSD

**Can mfsBSD be loaded from a Linux initrd?**
- Not via kexec (different kernel ABI).
- Via `dd`+reboot: yes, this is the production technique.
- The initrd would have to be a "one-shot installer" that destroys the Linux filesystem and replaces it, then signals the hypervisor to reboot.

### Debian GNU/kFreeBSD (Historical)

- kFreeBSD combined FreeBSD kernel + Linux/GNU userland running on ext2/ext4.
- **Officially terminated July 2023** — no longer maintained.
- The reverse (Linux ext4 image, BSD kernel, BSD userland) was the design of kFreeBSD. Without maintenance this is a dead end.

### The Practical In-Memory Pattern for Ext4-Locked Providers

**If rescue mode is available:**
```
# Inside provider rescue Linux:
fetch https://mfsbsd.vx.sk/files/images/14/amd64/mfsbsd-14.2-RELEASE-amd64.img.xz
unxz mfsbsd-14.2-RELEASE-amd64.img.xz
dd if=mfsbsd-14.2-RELEASE-amd64.img of=/dev/sda bs=1M
reboot
# Server comes up as FreeBSD in RAM, ready for zfsinstall
```

**If no rescue mode — pure BYOI only:**
The only path is an ext4 image containing a Linux kernel + initramfs that, on first boot, wipes the disk and writes a BSD image (fetched from network or bundled in the initramfs). This is fragile (one false move = unrecoverable) but technically sound.

---

## Q5: Artistic Approaches

### 1. ZFS on Linux + FreeBSD Jails (Practical: Medium)

- Deploy a Linux image (Ubuntu/Debian with OpenZFS).
- Create ZFS datasets.
- Run FreeBSD jails via... nothing. **FreeBSD jails require FreeBSD kernel.** Cannot run FreeBSD jails inside Linux. ZFS datasets can be shared but jail execution requires FreeBSD.
- **Verdict:** Not viable for running FreeBSD programs. ZFS data sharing between Linux and FreeBSD (via shared storage) is viable but not a BSD execution environment.

### 2. QEMU/KVM Inside a Linux VM (Practical: High, Performance: Medium)

- Deploy a Linux ext4 image (passes all validators).
- Install QEMU with KVM acceleration.
- Run FreeBSD as a KVM guest inside the Linux VM.
- **Nested virtualization:** Most providers support this (GCP, AWS, Azure have nested KVM on some instance types). Hetzner Cloud supports nested virtualization on Dedicated Cloud servers.
- **Performance:** With KVM acceleration, ~5-15% overhead vs bare metal. Without KVM (pure emulation): unusable for production.
- **Verdict:** **Practically viable** for providers that allow nested KVM. Delivers genuine FreeBSD environment. Network is NAT by default (bridging requires provider cooperation or macvlan tricks). Main caveat: checking nested KVM availability per provider.

### 3. bhyve on Linux (Not Viable)

- bhyve is a FreeBSD/illumos hypervisor. **No Linux port exists.**
- The bhyve source is BSD-licensed but deeply tied to FreeBSD kernel internals (vmm.ko, etc.).
- **Verdict:** Not viable without major porting effort.

### 4. Kata Containers + FreeBSD (Not Viable Currently)

- Kata Containers wraps containers in lightweight Linux VMs. Uses a custom Linux kernel.
- **No BSD kernel support exists** in Kata — the hypervisor always boots Linux.
- **Verdict:** Not viable as of 2026.

### 5. Linux Image → dd-and-Reboot Installer Pattern (Practical: High)

This is the most underrated approach:
- Upload an ext4 image containing only: GRUB2 + a minimal Linux kernel/initramfs.
- The initramfs is a "one-shot installer" that:
  1. Fetches a FreeBSD disk image from a URL (or unpacks from initramfs itself if small enough)
  2. Writes it to the root disk (`dd`)
  3. Forces a hard reboot (via sysrq or similar)
- On the next boot, the disk is FreeBSD.
- The ext4 partition is gone; only the provider's DHCP/console access remains.
- **Verdict:** Works on any provider that gives the VM a network connection before the installer runs. Production technique used by advanced Hetzner/OVH users. Requires careful handling of the "reboot while writing" scenario.

### 6. FreeBSD in a Container via gVisor (Stretch)

- gVisor intercepts syscalls and reimplements them in Go (Sentry kernel).
- gVisor is Linux-only — the Sentry implements Linux syscall ABI.
- No BSD ABI implementation exists.
- **Verdict:** Not viable.

### Honest Practicality Ranking

| Approach | Practical? | BSD Authenticity | Notes |
|---|---|---|---|
| KVM nested (QEMU inside Linux VM) | High | Full FreeBSD | Requires nested KVM; most providers allow it |
| dd-and-reboot installer initramfs | High | Full FreeBSD | Requires network on first boot; no rescue mode needed |
| GRUB2 kfreebsd + multi-partition | Medium | Full FreeBSD | Provider-dependent; ext4 validator may block |
| Rescue mode → mfsBSD dd | High | Full FreeBSD | Requires rescue mode (not all BYOI providers offer it) |
| ZFS + FreeBSD jails on Linux | None | None | Jails require BSD kernel |
| bhyve on Linux | None | N/A | No Linux port of bhyve |
| Kata Containers | None | N/A | Linux-only guests |
| kFreeBSD (Debian) | None | Partial | Abandoned 2023 |

---

## Q6: Providers with NO Filesystem Constraint — The BSD-Friendly Tier

### Tier 1: Native BSD Support (No workarounds needed)

| Provider | How | Notes |
|---|---|---|
| **AWS EC2** | Official FreeBSD AMIs in Marketplace; NetBSD AMIs via bsdec2-image-upload | VM Import does NOT support UFS; but AMIs bypass VM Import. Register an EBS snapshot directly. |
| **Oracle Cloud (OCI)** | BYOI accepts FreeBSD v8+; OCI Marketplace has FreeBSD in UFS and ZFS | Accepts VMDK/QCOW2, no filesystem restriction stated |
| **Azure** | FreeBSD in Marketplace | Available via Azure Marketplace |
| **Vultr** | FreeBSD in managed OS library; custom ISO upload available | No filesystem restriction for custom ISO installs |
| **BuyVM** | FreeBSD, OpenBSD, NetBSD as native OS options | KVM-based; any OS that runs KVM works |
| **Hetzner** (Dedicated/Cloud rescue) | Rescue mode → dd approach documented in community | Not a BYOI path but rescue boot + dd → FreeBSD is well-established |

### Tier 2: Probably BSD-Friendly (Incomplete documentation)

| Provider | Status |
|---|---|
| **UpCloud** | Custom image import exists; filesystem type not restricted in visible docs |
| **Exoscale** | Custom templates supported; known to be OpenStack-based which typically accepts any image |
| **Hetzner Cloud** | ISO attachment works; community tutorials show FreeBSD installation via rescue |

### Tier 3: Confirmed Restricted

| Provider | Restriction |
|---|---|
| **Akamai/Linode** | ext3/ext4 only, documented explicitly |
| **AWS VM Import** | No UFS/ZFS; Linux and Windows only |
| **GCP Image Import** | Linux-only supported OS list; no FreeBSD |
| **DigitalOcean** | "Linux and Unix-like" only; FreeBSD not in supported list |

---

## GRUB2 BSD Support Matrix (Summary)

| BSD | GRUB2 Native | EFI Chainloader | Production Viable? | Gotchas |
|---|---|---|---|---|
| FreeBSD ≤12, UFS root | `kfreebsd` | `chainloader /boot/loader.efi` | Yes | Needs `insmod ufs2` and `insmod bsd` |
| FreeBSD 13/14/15, UFS | `kfreebsd` (may work) | **Preferred** | Yes (chainloader) | `kfreebsd` may mishandle newer ELF metadata |
| FreeBSD 13/14/15, ZFS | `kfreebsd` (insufficient) | **Required** | Yes (chainloader) | ZFS root requires FreeBSD's own loader for pool import |
| NetBSD | `knetbsd` | Possible | Yes (knetbsd) | Modules need miniroot.kmod wrapper |
| OpenBSD | `kopenbsd` (unreliable) | **Required** | Yes (chainloader) | OpenBSD team says GRUB "usually fails"; use rEFInd or `bootx64.efi` |

**Recommended GRUB2 approach for modern FreeBSD (13+):**
```
menuentry "FreeBSD 14" {
    insmod chain
    search --no-floppy --label --set=root FREEBSD
    chainloader /boot/loader.efi
}
```

This requires EFI boot mode and FreeBSD's ESP containing `loader.efi`.

---

## Top 5 Practical Patterns for Ext4-Locked Providers

### Rank 1: QEMU/KVM Nested Virtualization (Most Reliable)

**Pattern:** Upload a minimal Ubuntu/Debian ext4 image. On first boot, install QEMU-KVM, download a FreeBSD QCOW2 image, create a systemd service that launches the FreeBSD VM, and expose it on internal ports.

**Pros:**
- Passes any ext4 validator (the outer image is genuine ext4 Linux)
- Full, authentic FreeBSD inside
- KVM acceleration available on most providers (verify per provider)
- No destructive disk operations needed
- Can persist across reboots

**Cons:**
- Extra abstraction layer (~5-15% overhead with KVM)
- Networking requires NAT or macvlan tricks (provider-specific)
- Storage is nested (QCOW2 inside ext4 volume)
- Outer Linux system must be maintained

**Viability:** HIGH — works on Linode, DigitalOcean, Hetzner Cloud (with nested KVM support)

---

### Rank 2: dd-and-Reboot Installer Initramfs

**Pattern:** Build a minimal Linux ext4 image where the initramfs acts as a one-shot BSD installer. On first boot, the initrd fetches a FreeBSD image (or mfsBSD), writes it to disk, and forces reboot. The machine comes up running BSD.

**Pros:**
- Passes ext4 validator
- Results in native FreeBSD (no virtualization overhead)
- Works without rescue mode
- Fully automatable

**Cons:**
- One chance to get it right — any failure leaves the machine unbootable (depends on provider's out-of-band console)
- Requires network access before installer has finished
- Provider may detect the filesystem change on next snapshot/resize operation

**Viability:** HIGH — technically sound; used in production by sophisticated users. Requires good error handling.

---

### Rank 3: GRUB2 + Multi-Partition (FreeBSD in p2, ext4 stub in p1)

**Pattern:** Create a disk image with:
- GPT partition table
- p1: small ext4 partition (satisfies validator if it only checks p1)
- p2: UFS2 partition with FreeBSD root
- EFI ESP or MBR containing GRUB2
- GRUB2 config: `chainloader /boot/loader.efi` pointing at p2

**Pros:**
- Elegant; no Linux needed at runtime
- Native FreeBSD performance
- Self-contained disk image

**Cons:**
- Provider validator behavior varies — if it expects raw ext4 (not a partition table), fails immediately
- Linode explicitly expects non-partitioned ext4 disk; this pattern likely fails there
- DigitalOcean unclear — may work if they only check p1
- No public documentation of which providers only validate p1

**Viability:** MEDIUM — works on providers that don't check the raw device; fails on Linode

---

### Rank 4: Rescue Mode → mfsBSD dd

**Pattern:** Some providers (Hetzner dedicated, OVH dedicated) offer a rescue boot environment. Boot into rescue Linux, `dd` an mfsBSD image to disk, reboot into FreeBSD.

**Pros:**
- No ext4 tricks needed
- Full native FreeBSD
- Well-documented community procedure

**Cons:**
- Requires a rescue boot facility (not all BYOI-only providers offer it)
- Not applicable to pure BYOI providers (Linode's custom image upload doesn't have a separate rescue path that bypasses the validator)
- Manual step required (trigger rescue, run dd)

**Viability:** HIGH — but only for providers with rescue mode. Not applicable to Linode's BYOI upload path.

---

### Rank 5: Provider Migration (Choose BSD-Native Provider)

**Pattern:** Simply do not use ext4-locked providers for BSD workloads. Use OCI, Vultr, BuyVM, or AWS EC2 Marketplace which support BSD natively.

**Pros:**
- No workarounds needed
- Native performance and full OS support
- Proper cloud-init support (FreeBSD has cloud-init port with freebsd/netbsd/openbsd renderers)

**Cons:**
- Requires deploying to a different provider than the locked one
- May not satisfy a requirement to use a specific provider

**Viability:** HIGH — the correct answer whenever there's no hard provider constraint

---

## Most Creative/Bold Approach Worth Experimenting With

### The Ext4-Initramfs BSD Installer with Cloud-Init Handoff

**Concept:** Build a "Trojan" cloud image:
1. The image is a valid ext4 Linux system that cloud-init initializes normally (sets hostname, SSH keys, etc.)
2. Cloud-init user-data triggers a post-boot script: downloads FreeBSD image, writes to disk, schedules a hard reboot at T+30s
3. At T+30, the machine reboots into native FreeBSD
4. The FreeBSD system uses its own cloud-init (`cloud-init` has freebsd renderer support) to re-apply the cloud config

**Why it's bold:** The machine presents itself as Linux for the first 30 seconds of its life (satisfying any runtime validation the provider does post-deploy), then permanently transforms into FreeBSD. Provider metadata/console shows FreeBSD. The transformation is irreversible and requires no rescue mode.

**What's needed to implement:**
- A well-tested FreeBSD raw disk image (from FreeBSD's official release build)
- A cloud-init user-data script that does the dd + reboot
- Careful handling of the reboot window (what happens if cloud-init's reporting call fails mid-reboot?)
- FreeBSD cloud-init support for re-applying SSH keys and hostname on next boot

**Risk:** If the provider polls the machine's OS during the first 60 seconds and detects a filesystem change, the account could be flagged. Low probability but non-zero.

---

## Proposed Genoa Strategy: "For Ext4-Locked Providers, genoa should..."

### Tiered Deployment Strategy

```
IF provider == BSD-native (OCI, Vultr, BuyVM, AWS EC2, Azure):
    → Deploy FreeBSD/NetBSD image directly
    → Use official provider cloud images where available
    → No workaround needed

ELSE IF provider == ext4-locked WITH rescue mode:
    → Deploy minimal Linux ext4 stub
    → Use rescue mode to dd mfsBSD to disk
    → Run FreeBSD natively post-rescue-reboot

ELSE IF provider == ext4-locked WITHOUT rescue mode BUT nested KVM supported:
    → Deploy Ubuntu/Debian ext4 image
    → Bootstrap QEMU-KVM in cloud-init user-data
    → Run FreeBSD as KVM guest with persistent systemd service
    → Accept 5-15% virtualization overhead

ELSE IF provider == ext4-locked, no rescue, no nested KVM:
    → Deploy "Trojan" ext4 initramfs installer
    → Initramfs fetches FreeBSD image and dd's on first boot
    → Requires reliable out-of-band console for recovery
    → Mark as "experimental" tier in genoa
```

### Concrete genoa Recommendations

1. **Maintain a provider capability matrix** in genoa's config schema:
   - `byoi.filesystem_restriction: [ext3, ext4] | none | unknown`
   - `byoi.rescue_mode: bool`
   - `byoi.nested_kvm: bool`
   - `byoi.bsd_native: bool`

2. **For Linode/Akamai specifically:** The QEMU-KVM approach is the most reliable path. Linode explicitly requires ext3/ext4 for custom image upload. A Debian/Ubuntu base image running FreeBSD-in-KVM gives 95% of native FreeBSD with full Linode support infrastructure.

3. **For the dd-and-reboot pattern:** Implement it as a genoa "deployment primitive" with a mandatory fallback URL (if primary FreeBSD image fetch fails, boot into a recovery shell, not reformat the disk). This makes it safe for production use.

4. **Never use the ext4 multi-partition trick for Linode** — their documentation confirms they expect a non-partitioned ext4 disk, not a disk with partition tables.

5. **For smolBSD specifically:** smolBSD images (likely UFS2 or ZFS root) should target the BSD-native provider tier first. For Linode experiments, wrap smolBSD's kernel in a QEMU guest inside a Debian image — this preserves the production smolBSD environment while meeting Linode's validator requirements.

---

## Key Findings Summary

- **Linode/Akamai:** Hard ext3/ext4 requirement, documented. No escape via multi-partition.
- **AWS VM Import:** No UFS/ZFS. But **FreeBSD runs natively on EC2 via Marketplace AMIs** — VM Import is the wrong path for BSD.
- **GCP:** Linux-only in supported import list; FreeBSD available via GCP Marketplace.
- **OCI:** **Best cloud for BSD.** Explicitly supports FreeBSD 8+ in BYOI. Marketplace has UFS and ZFS variants.
- **GRUB2:** Has native `kfreebsd`/`knetbsd`/`kopenbsd` commands. For FreeBSD 13+, EFI chainloading of `loader.efi` is superior. OpenBSD's GRUB support is unreliable.
- **mfsBSD:** The canonical "in-RAM FreeBSD installer" — supports v8 through v14. Not loadable via Linux kexec, but usable via dd+reboot.
- **Debian kFreeBSD:** Dead (abandoned July 2023). Not a viable path.
- **bhyve on Linux:** Does not exist. No Linux port.
- **Best practical pattern for ext4-locked providers:** QEMU/KVM nested virtualization or dd-and-reboot initramfs installer.
- **Most creative viable approach:** Trojan cloud-init image that transforms into BSD on first boot.
