# Path 5: kexec Linux→OS-kernel

**Priority: 6 (lowest) — RESEARCH ONLY, NOT FOR v1**

## STATUS: RESEARCH ONLY — DO NOT IMPLEMENT IN v1

This path is documented so the team understands why it was evaluated and
rejected for v1. Revisit only if no other path exists for a specific target.

## What it would do

`kexec` allows a running Linux kernel to chainload another kernel without
going through firmware/bootloader. The idea: boot provider's rescue Linux,
then `kexec` directly into the BSD kernel, bypassing the need to write an image
to disk.

## Why it does not work reliably for BSDs

### 1. BSD multiboot / load-format incompatibility

Linux's `kexec-tools` understands:
- Linux bzImage/zImage
- Linux `kexec --load` with initrd
- ELF kernels (limited)
- Multiboot 1 (limited, via `--type=multiboot`)

FreeBSD and NetBSD kernels use:
- Multiboot 2 (FreeBSD 12+) — Linux kexec has **incomplete** Multiboot 2 support
- Their own ELF loader format with FreeBSD-specific header fields
- Module loading conventions that differ from Linux initrd

### 2. depenguinator-3 (Allan Jude) — tried, stalled

Allan Jude's `depenguinator` project attempted kexec Linux→FreeBSD:
- depenguinator-3: https://github.com/allanjude/depenguinator
- Status: unmaintained as of ~2021. Last commit attempts Multiboot 2 path.
- Works only on specific kernel versions and hardware configurations.
- Not production-grade. Not suitable for a fleet deployment tool.

### 3. Architecture gaps

- **aarch64**: Linux `kexec` on ARM64 is even less mature than x86_64 for
  non-Linux targets. FreeBSD's ARM64 kernel uses a different ELF entry
  convention. No working path demonstrated.

- **x86_64**: Partial success reported by depenguinator users in 2019-2020.
  Breaks on modern kernels (Linux 5.x+) due to changed boot protocol.

### 4. Memory map and ACPI handoff

kexec hands the new kernel a Linux-style memory map (E820 on x86). BSD kernels
expect firmware-provided ACPI/EFI memory map. The mismatch causes random
panics during BSD boot — the BSD kernel may overwrite memory it thinks is free
but Linux's kexec has reserved.

### 5. No rescue mode needed → no benefit

The only advantage of kexec would be: skip the dd step, boot BSD directly.
But Path 3 (rescue+dd) already avoids QEMU and completes in ~5-10 minutes.
The marginal benefit of kexec does not justify the implementation risk.

## Verdict

Do not implement in v1. Path 3 (rescue+dd) covers the same provider set with
far greater reliability. Revisit kexec only if:
- A provider offers no rescue disk access AND no image import API
- AND the community has produced a working kexec→FreeBSD path for that kernel version

## References

- depenguinator-3: https://github.com/allanjude/depenguinator (BSD-2-Clause license, but unmaintained)
- Linux kexec documentation: https://www.kernel.org/doc/html/latest/admin-guide/kdump/kdump.html
- FreeBSD Multiboot 2 support: https://wiki.freebsd.org/Multiboot
- kexec-tools: GPL-2.0 — even if it worked, invoke as subprocess only
