#!/usr/bin/env nu
# profiles/kboot.nu — kboot image profile for genoa
# Purpose: Build FreeBSD images for ext4-only cloud providers (Linode, AWS, GCP)
# Approach: GRUB2 + Linux mini-kernel + loader.kboot initrd + UFS2 FreeBSD root
#
# kboot (FreeBSD's kexec bootloader) runs as Linux PID 1 inside an initrd.
# It uses Linux host syscalls to read filesystems, then kexec()s into FreeBSD.
# This solves the "ext4 root required" problem: the image is ext4 (boot partition),
# but FreeBSD runs on UFS2/ZFS (data partition).
#
# Reference: https://cgit.freebsd.org/src/tree/stand/kboot
# Production use: GCE ARM64 FreeBSD images
#
# License: BSD-2-Clause
# SPDX-License-Identifier: BSD-2-Clause

export def kboot_build [manifest: record, dry_run: bool = false] {
    # Build a comprehensive JSON plan for kboot image generation
    # Returns JSON with steps in execution order. When dry_run=true,
    # all destructive steps have action="would-run" and no side effects.

    let hostname = $manifest.hostname? | default "freebsd-kboot"
    let image_size_gb = $manifest.image_size_gb? | default 8
    let image_path = $manifest.image_path? | default "/tmp/genoa-kboot.raw"
    let task_endpoint = $manifest.task_endpoint? | default "https://api.example.com"

    let plan = {
        profile: "kboot"
        version: "1.0.0"
        hostname: $hostname
        image_path: $image_path
        image_size_gb: $image_size_gb
        arch: "amd64"
        bootloader: "GRUB2"
        kernel_provider: "Linux mini-kernel"
        init_provider: "loader.kboot (FreeBSD)"

        description: "GRUB2 + Linux + loader.kboot + FreeBSD UFS2 root. ext4 boot partition satisfies provider requirements. FreeBSD runs on UFS2 partition 2."

        partition_layout: {
            p1: {
                size: "512M"
                type: "ef00"
                purpose: "EFI System Partition (ESP)"
                filesystem: "FAT32"
                label: "ESP"
            }
            p2: {
                size: "512M"
                type: "8300"
                purpose: "ext4 boot (GRUB, kernel, kboot initrd)"
                filesystem: "ext4"
                label: "KBOOT"
            }
            p3: {
                size: "remaining"
                type: "a502"
                purpose: "FreeBSD UFS2 root (real FreeBSD root filesystem)"
                filesystem: "UFS2"
                label: "FREEBSD_ROOT"
            }
        }

        steps: [
            {
                step: 1
                label: "create_disk"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: $"truncate -s ($image_size_gb)G ($image_path)"
                description: $"Create ($image_size_gb)G raw disk image"
            }
            {
                step: 2
                label: "partition"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "sgdisk -n1:0:+512M -t1:ef00 -n2:0:+512M -t2:8300 -n3:0:0 -t3:a502 /dev/loop0"
                description: "Partition disk: p1=ESP(FAT32) p2=ext4(kboot) p3=UFS2(FreeBSD root)"
                details: "Uses GPT and modern partition type GUIDs for clarity"
            }
            {
                step: 3
                label: "format_esp"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "mkfs.fat -F32 -n ESP /dev/loop0p1"
                description: "Format p1 as FAT32 for EFI System Partition"
            }
            {
                step: 4
                label: "format_p2_ext4"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "mkfs.ext4 -L KBOOT -O ^metadata_csum,^64bit,^inline_data /dev/loop0p2"
                description: "Format p2 as ext4 without modern features that FreeBSD ext2fs cannot handle"
                notes: [
                    "^metadata_csum: FreeBSD ext2fs does not support metadata checksums"
                    "^64bit: Disable 64-bit feature for broader compatibility"
                    "^inline_data: Disable inline data support (unsupported in FreeBSD)"
                    "This creates an ext3-like ext4 image that FreeBSD will accept read-write"
                ]
            }
            {
                step: 5
                label: "mount_boot_partition"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "mount /dev/loop0p2 /mnt/kboot"
                description: "Mount p2 to /mnt/kboot for file staging"
            }
            {
                step: 6
                label: "install_grub2"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "grub-install --target=x86_64-efi --boot-directory=/mnt/kboot/boot --efi-directory=/mnt/kboot/boot/efi"
                description: "Install GRUB2 (EFI) to p1/p2 boot partition"
                notes: [
                    "GRUB2 is GPL-2 licensed — invoked as external tool, never vendored"
                    "Requires grub2-efi-modules and efi-grub2 packages on builder"
                ]
            }
            {
                step: 7
                label: "render_grub_cfg"
                action: "render"
                template: "templates/kboot/grub.cfg.tera"
                output: "/mnt/kboot/boot/grub/grub.cfg"
                context: {
                    hostname: $hostname
                    task_endpoint: $task_endpoint
                }
                description: "Render GRUB2 config with Linux kernel + kboot initrd boot entry"
            }
            {
                step: 8
                label: "fetch_linux_kernel"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "curl -L https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.tar.xz | tar -xz --strip-components=1 -C /tmp/linux-build"
                description: "Download minimal Linux kernel source"
                notes: [
                    "Minimal build: only virtio, kexec, ext4 drivers — kernel should be <50 MB"
                    "Alternative: use provider's rescue kernel if small enough"
                ]
            }
            {
                step: 9
                label: "build_linux_kernel"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "cd /tmp/linux-build && make -j$(nproc) x86_64_defconfig && make menuconfig && make -j$(nproc) bzImage"
                description: "Build minimal Linux kernel (virtio + kexec + ext4)"
                notes: [
                    "Kernel image (bzImage) will be placed at /tmp/linux-build/arch/x86_64/boot/bzImage"
                    "Should be <10 MB uncompressed"
                ]
            }
            {
                step: 10
                label: "install_linux_kernel_to_boot"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "cp /tmp/linux-build/arch/x86_64/boot/bzImage /mnt/kboot/boot/vmlinuz-kboot"
                description: "Copy Linux kernel to boot partition as vmlinuz-kboot"
            }
            {
                step: 11
                label: "build_kboot_initrd"
                action: "render"
                template: "templates/kboot/initrd-build.sh.tera"
                output: "/tmp/build-kboot-initrd.sh"
                context: {
                    hostname: $hostname
                    task_endpoint: $task_endpoint
                }
                description: "Render shell script that builds kboot.cpio.gz initrd"
                notes: [
                    "Script will be executed to generate /tmp/kboot.cpio.gz"
                    "Initrd contains: loader.kboot binary as /init, loader.kboot.conf, FreeBSD kernel"
                ]
            }
            {
                step: 12
                label: "execute_kboot_initrd_build"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "bash /tmp/build-kboot-initrd.sh"
                description: "Execute kboot initrd build script — produces kboot.cpio.gz"
            }
            {
                step: 13
                label: "install_kboot_initrd_to_boot"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "cp /tmp/kboot.cpio.gz /mnt/kboot/boot/kboot.cpio.gz"
                description: "Install kboot initrd to boot partition"
            }
            {
                step: 14
                label: "format_p3_ufs2"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "newfs -U /dev/loop0p3"
                description: "Format p3 as UFS2 with soft updates — FreeBSD root"
                notes: [
                    "UFS2 is FreeBSD's native filesystem with full feature support"
                    "-U flag enables soft updates for journaling-like consistency"
                ]
            }
            {
                step: 15
                label: "mount_freebsd_root"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "mount /dev/loop0p3 /mnt/freebsd"
                description: "Mount UFS2 root partition"
            }
            {
                step: 16
                label: "extract_freebsd_base"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "tar -xf /path/to/FreeBSD-13.2-RELEASE-amd64-base.txz -C /mnt/freebsd"
                description: "Extract FreeBSD base system to UFS2 root"
                notes: [
                    "Must source FreeBSD release media (base.txz, kernel.txz)"
                    "Configure boot hint in /mnt/freebsd/boot/loader.conf"
                ]
            }
            {
                step: 17
                label: "render_loader_conf"
                action: "render"
                template: "templates/kboot/loader-kboot.conf.tera"
                output: "/mnt/freebsd/boot/loader.kboot.conf"
                context: {
                    hostname: $hostname
                    task_endpoint: $task_endpoint
                }
                description: "Render loader.kboot config (kernel boot parameters)"
            }
            {
                step: 18
                label: "configure_fstab"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "cat > /mnt/freebsd/etc/fstab <<'EOF'\n/dev/vtbd0p3  /  ufs  rw  1  1\nEOF"
                description: "Create /etc/fstab pointing to UFS2 root on /dev/vtbd0p3"
                notes: [
                    "Assumes cloud provider uses virtio block device (vtbd0)"
                    "Partition 3 is the UFS2 root configured above"
                ]
            }
            {
                step: 19
                label: "umount_all"
                action: (if $dry_run { "would-run" } else { "stub" })
                cmd: "umount /mnt/freebsd /mnt/kboot"
                description: "Unmount all partitions after configuration"
            }
            {
                step: 20
                label: "emit_receipt"
                action: "real"
                description: "Compute sha256 of output image and emit receipt.json"
                implementation: "This step actually runs: computes sha256 of the image, verifies partitions exist, outputs receipt"
            }
        ]

        ext4_compliance: "Partition p2 is ext4 (without modern features). Satisfies ext4-only provider requirements."
        freebsd_root_real: "Partition p3 is UFS2 with real FreeBSD root. No modifications to ext4 partition by FreeBSD kernel."
        freebsd_native_boot: "FreeBSD kernel boots via kexec, runs normally. No FreeBSD bootloader modifications needed."

        kboot_source: "https://cgit.freebsd.org/src/tree/stand/kboot"
        kboot_build_cmd: "cd /usr/src/stand/kboot && make MK_LOADER_KBOOT=yes MACHINE_CPUARCH=amd64"
        kboot_production_use: "GCE ARM64 (Google Cloud Engine) uses kboot for FreeBSD ARM64 images"

        licensing: {
            genoa_profile: "BSD-2-Clause"
            grub2: "GPL-2.0 (invoked as external tool, never vendored)"
            loader_kboot: "BSD-2-Clause (FreeBSD in-tree)"
            linux_kernel: "GPL-2.0 (used as boot trampoline, minimal)"
        }
    }

    $plan | to json
}
