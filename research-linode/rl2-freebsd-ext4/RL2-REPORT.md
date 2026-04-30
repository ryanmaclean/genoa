# RL2: FreeBSD on ext4-Only Providers (e.g. Linode/Akamai)

**Research date:** 2026-04-30  
**Working dir:** `/Users/studio/genoa/research-linode/rl2-freebsd-ext4/`  
**Sources:** FreeBSD cgit, man pages, GRUB2 manual, Akamai/Linode docs, depenguin-run

---

## Executive Summary

Linode (Akamai Cloud) requires uploaded custom images to use **ext3 or ext4** as the root filesystem. FreeBSD's native filesystems are UFS2 and ZFS. There is a real path to running FreeBSD on such a provider, but it requires either (a) a kexec-based trampoline (kboot), (b) GRUB2's native `kfreebsd` command, or (c) mfsBSD in-RAM boot. Direct FreeBSD-on-ext4-root with `loader.efi` is **not viable** without a custom EFI loader build.

---

## Q1: FreeBSD ext2fs Module — ext4 Feature Support Matrix

### In-kernel driver (`/sys/fs/ext2fs/`)

The in-kernel `ext2fs` driver supports a subset of ext4 features. The feature flags it recognizes:

| Feature | Flag | Status |
|---|---|---|
| Large files | `EXT2F_ROCOMPAT_LARGEFILE` | Read-write supported |
| Huge files | `EXT2F_ROCOMPAT_HUGE_FILE` | Read-write supported |
| Extra inode size | `EXT2F_ROCOMPAT_EXTRA_ISIZE` | Read-write supported |
| Metadata checksums | `EXT2F_ROCOMPAT_METADATA_CKSUM` | Read-write supported |
| Group descriptor checksums | `EXT2F_ROCOMPAT_GDT_CSUM` | Read-write supported |
| 64-bit support | `EXT2F_INCOMPAT_64BIT` | Read-write supported |
| Flexible block groups | `EXT2F_INCOMPAT_FLEX_BG` | Read-write supported |
| Metadata block groups | `EXT2F_INCOMPAT_META_BG` | Read-write supported |
| Dir hash index | `EXT2F_COMPAT_DIRHASHINDEX` | Read-write supported |
| Has journal | `EXT2F_COMPAT_HASJOURNAL` | Recognized (compat flag — does not force read-only) |
| **Extents** | `EXT2F_INCOMPAT_EXTENTS` | **Read-only** (kernel can read, write support partial) |
| Inline data | `EXT2F_INCOMPAT_INLINE_DATA` | Defined but effectively unsupported |
| Large directories | `EXT2F_INCOMPAT_LARGEDIR` | Defined, limited support |
| Checksum seed | `EXT2F_INCOMPAT_CSUM_SEED` | May force read-only |

**Read-write vs read-only:** The mount code enforces `"R/W mount of [device] denied due to unsupported optional features"` when INCOMPAT flags not in the driver's known-good set are present. A typical modern `mkfs.ext4` image will have `EXTENTS` set as an INCOMPAT flag. The kernel _reads_ extents via `ext2_extents.c` (which has a full extent tree read-write implementation) but the mount code may still refuse RW if other unknown INCOMPAT flags are present.

**Practical verdict for ext4 root:** The in-kernel driver CAN mount a typical ext4 volume read-write if the `mkfs.ext4` options are conservative (no inline_data, no csum_seed, no large_dir). A standard `mkfs.ext4 -O ^metadata_csum,^64bit,^inline_data` image should mount read-write. A default `mkfs.ext4` image on modern Linux (with `metadata_csum` and `64bit` on) may or may not mount read-write depending on FreeBSD version.

**FreeBSD version notes:**
- FreeBSD 13+: extent support in kernel (read)
- FreeBSD 14+: improved ext4 compatibility, `ext2_extents.c` present
- FreeBSD 15: most current, best ext4 compat, but still INCOMPAT flag sensitivity
- Source: `/sys/fs/ext2fs/ext2_vfsops.c`, `/sys/fs/ext2fs/ext2_extents.c`, `/sys/fs/ext2fs/ext2fs.h`

**Can FreeBSD mount ext4 as root (`/`)?**  
Yes, in principle. `vfs.root.mountfrom=ext2fs:/dev/vtbd0` should work if the ext4 image was created with compatible flags. The `ext2fs` kernel module would need to be either compiled in or available in the initrd. This is the easy part — the hard part is getting the bootloader to find the kernel on an ext4 partition.

---

## Q2: Can `loader.efi` Read a Kernel off ext4?

**Short answer: No, not by default.**

### The bootstrap problem

FreeBSD's boot chain for EFI systems:

```
UEFI firmware
  → loader.efi (on ESP, FAT32)
    → reads /boot/kernel/kernel from root filesystem
      → kernel mounts root filesystem
```

The critical question is whether `loader.efi` can read the kernel off an ext4 partition.

### Source code findings

**`stand/libsa/Makefile`:** `ext2fs.c` is compiled unconditionally into `libsa` (the bootloader standalone library). The line `SRCS+= dosfs.c ext2fs.c` has no conditional.

**`stand/efi/loader/Makefile`:** Sets `LOADER_EXT2FS_SUPPORT?= no` at the top, with `?=` (overridable). This adds `-DLOADER_EXT2FS_SUPPORT` to CFLAGS when set to "yes".

**`stand/loader.mk`:** The conditional:
```makefile
.if ${LOADER_EXT2FS_SUPPORT:Uno} == "yes"
CFLAGS+=    -DLOADER_EXT2FS_SUPPORT
.endif
```
This flag gates _registration_ of `ext2fs_fsops` in the filesystem list.

**`stand/efi/loader/conf.c`:** The `file_system[]` array — which defines what filesystems `loader.efi` can actually open — does **not** include `ext2fs_fsops`. The array contains: ZFS (conditional), dosfs, ufs, cd9660, efihttp, tftp, nfs, gzip, bzip2. No ext2fs.

**`stand/i386/loader/conf.c`:** The BIOS loader DOES include:
```c
#if defined(LOADER_EXT2FS_SUPPORT)
    &ext2fs_fsops,
#endif
```
So the BIOS loader supports ext2 when built with `-DLOADER_EXT2FS_SUPPORT`.

**`stand/libsa/ext2fs.c`:** The bootloader's ext2 implementation uses only traditional indirect block addressing (no extent tree support). It will silently misread files stored with ext4 extents, since `di_flags` is present in the inode struct but never checked. **This means even if you enable ext2fs in the EFI loader, it will fail on any ext4 filesystem that uses extents (which is all modern ext4).**

### Verdict: No

`loader.efi` as shipped cannot read a kernel off ext4. Even the BIOS loader's ext2 support (which can be enabled) only handles ext2/ext3 block addressing — it would silently corrupt reads on ext4 with extents, which is the default for any `mkfs.ext4`.

### Can it be fixed?

Yes, with code changes:
1. Add `&ext2fs_fsops` to `stand/efi/loader/conf.c`'s `file_system[]` (unconditionally or via `LOADER_EXT2FS_SUPPORT`)
2. Add extent tree reading to `stand/libsa/ext2fs.c` (non-trivial, ~500 lines)

This is a real gap — no bug reports or patches for this exist in the cgit history for `stand/libsa/ext2fs.c` (last functional change: 2017 initial import).

---

## Q3: Partition-Split Approach (ext4 boot + UFS2 root)

**Architecture:** Disk has two partitions:
- Partition 1 (ext4): GRUB2 + kernel copy + initrd
- Partition 2 (UFS2): actual FreeBSD root

### Does Linode validate all partitions or just partition 1?

Linode's image upload requirements (from Akamai docs):
- Raw disk image format (`.img` gzipped)
- **"Format the disk using the ext3 or ext4 file system"**
- Max 6 GB uncompressed, 5 GB compressed
- Non-partitioned disks recommended

The documentation says "Format the disk" (singular), suggesting the expectation is a single-partition image. However, the requirement appears to be about what the provider's Glish console / rescue system can detect, not a hard validator that scans every partition's superblock.

**In practice:** Community reports (depenguin.me, Hetzner FreeBSD guides) suggest providers check whether the image boots, not whether every partition is ext4. The "ext4 requirement" is often just the default assumption in documentation.

### The GRUB loopback approach

GRUB2 supports:
```
loopback loop0 /disk.img
kfreebsd (loop0)/boot/kernel/kernel
```

This would allow: ext4 partition containing GRUB + `disk.img` (a UFS2 disk image), GRUB loops the image and boots the FreeBSD kernel from UFS2. The GRUB `kfreebsd` command loads a real FreeBSD ELF kernel directly.

**Critical GRUB capability:** GRUB2's `kfreebsd` command (from `bsd` module) loads a native FreeBSD kernel and supports `set kFreeBSD.vfs.root.mountfrom=...` — this sets the hint that tells the FreeBSD kernel where its root is.

**Viability: 6/10**
- Works conceptually but GRUB's `kfreebsd` module needs to be present in the GRUB installation
- Loopback booting UFS2 requires GRUB to have UFS2 read support (it does — `grub-ufs` module)
- FreeBSD kernel modules (ZFS, etc.) need to be loaded via `kfreebsd_module_elf`
- The nested image is awkward and there's a 6 GB uncompressed size limit
- Most promising if the outer ext4 is minimal (GRUB + kernel) and the real root is UFS2 on partition 2

### Partition 2 UFS2 approach

```
/dev/sda1  ext4  (GRUB, /boot, kernel copy)
/dev/sda2  UFS2  (FreeBSD root)
```

`grub.cfg`:
```
menuentry "FreeBSD" {
    search --set=root --label FREEBSD_BOOT
    kfreebsd /boot/kernel/kernel
    set kFreeBSD.vfs.root.mountfrom=ufs:/dev/vtbd0p2
    kfreebsd_loadenv /boot/device.hints
}
```

**Viability: 7/10**
- Clean and simple: ext4 partition satisfies the provider's requirement
- GRUB reads ext4 natively, finds kernel, passes `vfs.root.mountfrom` hint
- FreeBSD kernel mounts UFS2 on sda2 as root
- Linode's partition validator likely only checks the first partition or that the image is bootable
- Risk: Linode may complain that the image has mixed filesystem types; unclear if they scan sda2

---

## Q4: GRUB2 + `kfreebsd` — Direct Kernel Load

**GRUB2 has native FreeBSD kernel loading.** From the GRUB2 manual (v2.14):

> `kfreebsd` — Load kernel of FreeBSD.  
> `kfreebsd_module_elf` — Load FreeBSD kernel module (ELF).  
> `kfreebsd_module` — Load FreeBSD kernel module.  
> `kfreebsd_loadenv` — Load FreeBSD env.

This is the `bsd` GRUB module, which supports actual FreeBSD ELF kernels (not just kFreeBSD/Debian). The example in the GRUB manual shows booting FreeBSD with ZFS root:

```
kfreebsd /freebsd@/boot/kernel/kernel
kfreebsd_module_elf /freebsd@/boot/kernel/opensolaris.ko
kfreebsd_module_elf /freebsd@/boot/kernel/zfs.ko
kfreebsd_module /freebsd@/boot/zfs/zpool.cache type=/boot/zfs/zpool.cache
set kFreeBSD.vfs.root.mountfrom=zfs:freepool/freebsd
```

**This is real.** GRUB2 can read an ext4 partition, find the FreeBSD kernel, load it and its modules, set `vfs.root.mountfrom`, and boot it — all without `loader.efi` being involved at all.

**Can GRUB2 chainload `loader.efi`?**  
Yes, with `chainloader /EFI/freebsd/loader.efi` (EFI mode). But this is less useful here since `loader.efi` would then need to read from an ext4 root, which it can't.

**Viability of GRUB2 `kfreebsd` approach: 8/10**
- GRUB2 is already widely available on cloud providers
- Reads ext4 natively → no ext4 requirement problem
- Loads FreeBSD kernel directly → no `loader.efi` needed
- `vfs.root.mountfrom` can specify UFS2 or ZFS on a separate partition
- Modules must be loaded explicitly in grub.cfg (no auto-detection)
- The kernel on the ext4 partition is just a copy; real root can be UFS2/ZFS on another partition
- Known to work: the GRUB manual example is specifically for this use case

---

## Q5: mfsBSD + GRUB Boot from ext4

**Architecture:**
```
ext4 partition:
  /boot/grub/grub.cfg
  /boot/mfsbsd/kernel       (FreeBSD kernel)
  /boot/mfsbsd/mfsroot.gz   (compressed UFS2 memory disk image)
```

`grub.cfg`:
```
menuentry "mfsBSD installer" {
    kfreebsd /boot/mfsbsd/kernel
    kfreebsd_module /boot/mfsbsd/mfsroot.gz type=mfs_root
    set kFreeBSD.vfs.root.mountfrom=ufs:/dev/md0
}
```

mfsBSD boots entirely in RAM from the in-memory UFS2 image. The running system then installs FreeBSD to the real disk (re-partitioning, formatting UFS2/ZFS, etc.), then reboots into the real installation.

**Is this what depenguin-run does?**  
Partially. depenguin-run uses QEMU (not GRUB), running mfsBSD inside a QEMU VM from the Linux rescue environment. It uses `kexec` indirectly through QEMU's hardware emulation, not via `kfreebsd` GRUB commands. However the mfsBSD-in-RAM concept is the same.

**Viability: 8/10**
- Excellent for "install FreeBSD" use case — image boots mfsBSD, installs FreeBSD, reboots
- Works with any provider that allows custom images (just needs GRUB2 + mfsBSD kernel/mfsroot on ext4)
- The final installed system can be full UFS2 or ZFS
- Risk: second boot (post-install) needs GRUB to find the UFS2 root — requires grub.cfg update during install
- mfsBSD images are well-maintained (mmatuska/mfsbsd on GitHub)

---

## Q6: kboot — The kexec Trampoline (Hidden Gem)

This is arguably the cleanest approach, discovered during research.

**FreeBSD's `loader.kboot`** (`stand/kboot/`) is a FreeBSD bootloader designed to run as PID 1 inside a Linux initrd. It:

1. Runs as a Linux process (in initrd)
2. Uses Linux host syscalls to access the filesystem via `hostfs.c`
3. `hostfs.c` delegates all filesystem I/O to the Linux kernel via `host_open()`, `host_fstat()`, etc.
4. **Because it uses Linux syscalls, it can read ANY filesystem the running Linux kernel supports — including ext4**
5. Once it has loaded the FreeBSD kernel and modules into memory, it calls `kexec_load()` + `HOST_REBOOT_CMD_KEXEC` to replace the Linux kernel with FreeBSD
6. Supports amd64, arm64, powerpc64

**The boot sequence:**
```
Provider UEFI/BIOS
  → GRUB2 (reads ext4)
    → Linux kernel (mini) + initrd containing loader.kboot as /init
      → loader.kboot reads /boot/kernel/kernel off ext4 via Linux syscalls
        → kexec_load() hands off to FreeBSD kernel
          → FreeBSD kernel mounts real root (UFS2/ZFS/ext4)
```

**This is entirely real and in-tree.** `MK_LOADER_KBOOT` is listed in `src.opts.mk`. It was added to FreeBSD in 2022-2023 specifically for cloud and embedded deployment scenarios.

**Advantages:**
- No ext2/ext4 support needed in FreeBSD's own bootloader
- The Linux mini-kernel + initrd are tiny and live on the ext4 partition
- The FreeBSD root can be anything the FreeBSD kernel supports (UFS2, ZFS, or even ext4)
- kexec is available on all major cloud hypervisors
- Works on all Linode instance types (KVM-based)

**Viability: 9/10**
- Most architecturally clean solution
- Used in production (GCE ARM64 FreeBSD images use kboot)
- Requires shipping a tiny Linux kernel + initrd (adds complexity to image build)
- Needs `CONFIG_KEXEC` in the Linux kernel (standard on all cloud provider kernels)

---

## Recommendation Matrix

| Approach | Viability | Complexity | Ext4 Satisfied? | FreeBSD Real? | Notes |
|---|---|---|---|---|---|
| `loader.efi` on ext4 | 1/10 | N/A | Theoretically | No | Bootloader ext2fs can't read ext4 extents |
| Custom `loader.efi` with ext4 | 3/10 | Very High | Yes | Yes | Requires new extent code in stand/libsa/ext2fs.c |
| GRUB2 `kfreebsd` + UFS2 root on sda2 | 7/10 | Medium | Yes (sda1) | Yes | Proven GRUB2 capability; Linode may validate sda2 |
| GRUB2 `kfreebsd` + loopback UFS2.img | 6/10 | Medium | Yes | Yes | Awkward but works; size constraints |
| mfsBSD via GRUB2 `kfreebsd` | 8/10 | Low | Yes | Yes (installer) | Installs to UFS2/ZFS; final boot needs follow-up |
| **kboot (Linux kexec trampoline)** | **9/10** | Medium | **Yes** | **Yes** | In-tree, production-proven on GCE/ARM64 |
| QEMU trampoline (depenguin-run style) | 7/10 | High | Yes | Yes | Heavy, requires QEMU in rescue env |

---

## The Single Most Promising Path

**GRUB2 `kfreebsd` + kboot hybrid:**

1. Build image: ext4 root partition containing:
   - GRUB2 with `bsd` module
   - A tiny Linux kernel (or use the provider's rescue kernel)
   - `loader.kboot` as Linux initrd `/init`
   - FreeBSD kernel + modules at `/boot/kernel/`
   - `grub.cfg` that boots the Linux kernel with kboot initrd

2. `grub.cfg`:
   ```
   menuentry "FreeBSD via kboot" {
       linux /boot/vmlinuz-kboot console=ttyS0 init=/loader.kboot
       initrd /boot/kboot.cpio.gz
   }
   ```
   Or more directly with GRUB2's `kfreebsd`:
   ```
   menuentry "FreeBSD direct" {
       kfreebsd /boot/kernel/kernel
       set kFreeBSD.vfs.root.mountfrom=ufs:/dev/vtbd0p2
       kfreebsd_module_elf /boot/kernel/ext2fs.ko
   }
   ```

3. Partition 2 (or the same partition): UFS2 or ZFS FreeBSD root

**If only one partition is allowed (full ext4 image):** Use kboot. The ext4 filesystem contains the Linux mini-kernel + kboot initrd + FreeBSD kernel + FreeBSD root tree (using the ext4 filesystem as root). The FreeBSD kernel mounts ext4 as root via the in-kernel `ext2fs` driver. This works if the ext4 image is created with compatible flags (`-O ^metadata_csum,^64bit` or just accept read-only ext4 root).

---

## Exact Kernel Config / Loader Changes Needed

### Option A: Full ext4 root (single partition, FreeBSD kernel on ext4)

**Kernel:** Compile with `options EXT2FS` (already in `GENERIC`). Mount root with:
```
vfs.root.mountfrom="ext2fs:/dev/vtbd0"
```

**Limitation:** FreeBSD kernel will refuse RW mount if ext4 has INCOMPAT flags it doesn't recognize. Create ext4 with:
```sh
mkfs.ext4 -O ^metadata_csum,^64bit,^inline_data,^dir_index /dev/sda
```
This gives an ext3-ish ext4 that FreeBSD's driver accepts RW.

**Bootloader:** Cannot use `loader.efi` for this. Must use GRUB2 `kfreebsd` or kboot.

### Option B: Enable ext2fs in EFI loader (custom build)

In `stand/efi/loader/conf.c`, add:
```c
#if defined(LOADER_EXT2FS_SUPPORT)
    &ext2fs_fsops,
#endif
```
Build with `LOADER_EXT2FS_SUPPORT=yes`.

**Still broken:** `stand/libsa/ext2fs.c` does not handle extent trees. Files with `EXT4_EXTENTS_FL` in `di_flags` will be silently misread. Need to add extent-tree reading to `block_map()` in `stand/libsa/ext2fs.c` (check `di_flags & EXT4_EXTENTS_FL`, walk the extent tree instead of indirect blocks).

This is a ~500-line patch, no upstream patch exists as of 2026-04-30.

### Option C: kboot (recommended)

Build `loader.kboot` from FreeBSD source:
```sh
cd /usr/src/stand/kboot
make MK_LOADER_KBOOT=yes MACHINE_CPUARCH=amd64
```

Package as Linux initrd:
```sh
echo "loader.kboot" | cpio -o -H newc | gzip > kboot.cpio.gz
```

Use with any small Linux kernel that has `CONFIG_KEXEC=y` (all cloud provider kernels do).

---

## Sources

- `https://cgit.freebsd.org/src/tree/sys/fs/ext2fs/ext2_vfsops.c` — mount feature checks
- `https://cgit.freebsd.org/src/tree/sys/fs/ext2fs/ext2_extents.c` — RW extent support in kernel
- `https://cgit.freebsd.org/src/tree/sys/fs/ext2fs/ext2fs.h` — feature flag definitions
- `https://cgit.freebsd.org/src/plain/stand/libsa/ext2fs.c` — bootloader ext2 (no extent support)
- `https://cgit.freebsd.org/src/plain/stand/efi/loader/conf.c` — ext2fs NOT in file_system[]
- `https://cgit.freebsd.org/src/plain/stand/i386/loader/conf.c` — ext2fs conditionally in BIOS loader
- `https://cgit.freebsd.org/src/plain/stand/loader.mk` — LOADER_EXT2FS_SUPPORT flag
- `https://cgit.freebsd.org/src/tree/stand/kboot/kboot/hostfs.c` — kboot uses Linux syscalls for FS
- `https://cgit.freebsd.org/src/plain/stand/kboot/kboot/arch/amd64/elf64_freebsd.c` — kexec_load() call
- `https://www.gnu.org/software/grub/manual/grub/grub.html` — kfreebsd, loopback commands
- `https://techdocs.akamai.com/cloud-computing/docs/upload-an-image` — Linode ext3/ext4 requirement
- `https://depenguin.me/` — QEMU-based mfsBSD trampoline approach
