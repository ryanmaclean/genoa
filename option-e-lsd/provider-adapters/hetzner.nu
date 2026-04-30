#!/usr/bin/env nu
# SPDX-License-Identifier: BSD-2-Clause
# provider-adapters/hetzner.nu — Hetzner Cloud + Robot adapter for lsd
#
# Exports:
#   hetzner imds-shape  — returns the IMDS JSON shape for this provider
#   hetzner quirks      — returns known quirks list
#   hetzner rescue-info — returns rescue image info

# IMDS shape for Hetzner Cloud (cloud-init compatible)
# Docs: https://docs.hetzner.cloud/#server-metadata
export def "hetzner imds-shape" [] {
    {
        provider: "hetzner-cloud"
        imds_version: "v1"
        base_url: "http://169.254.169.254/hetzner/v1/metadata"
        endpoints: {
            hostname:     "http://169.254.169.254/hetzner/v1/metadata/hostname"
            instance_id:  "http://169.254.169.254/hetzner/v1/metadata/instance-id"
            public_ipv4:  "http://169.254.169.254/hetzner/v1/metadata/public-ipv4"
            public_ipv6:  "http://169.254.169.254/hetzner/v1/metadata/public-ipv6"
            region:       "http://169.254.169.254/hetzner/v1/metadata/region"
            ssh_keys:     "http://169.254.169.254/hetzner/v1/metadata/public-keys"
            user_data:    "http://169.254.169.254/hetzner/v1/metadata/user-data"
        }
        notes: [
            "Cloud metadata is cloud-init compatible (v1 schema)"
            "Hetzner Robot (dedicated) uses a different rescue system — SSH into rescue, no IMDS"
        ]
    }
}

# Quirks relevant to mfsBSD trampoline on Hetzner
export def "hetzner quirks" [plan: string = "cax11"] {
    let base_quirks = [
        {
            id: "hetzner-virtio-mmio-arm64"
            severity: "warn"
            applies_to: ["cax11", "cax21", "cax31", "cax41"]
            description: "ARM64 CAX instances use virtio-mmio bus not virtio-pci; loader.conf needs virtio_mmio_load=YES"
            remediation: "bsdinstall.script sets virtio_mmio_load in /boot/loader.conf automatically"
        }
        {
            id: "hetzner-rescue-is-real-kvm"
            severity: "info"
            applies_to: ["cax11", "cax21", "cax31", "cax41", "cx22", "cx32", "cx42"]
            description: "Hetzner rescue boots real KVM — hardware acceleration is available, QEMU -enable-kvm is safe"
            remediation: "No action needed; bootstrap.sh auto-detects /dev/kvm"
        }
        {
            id: "hetzner-rescue-disk-device"
            severity: "info"
            applies_to: ["*"]
            description: "Primary disk is typically /dev/sda in rescue; verify with lsblk before running"
            remediation: "bootstrap.sh validates block device existence before proceeding"
        }
        {
            id: "hetzner-rescue-debian12"
            severity: "info"
            applies_to: ["*"]
            description: "Default rescue is Debian 12; apt-get is available for QEMU install"
            remediation: "bootstrap.sh handles Debian automatically"
        }
        {
            id: "hetzner-cax-uefi-firmware"
            severity: "warn"
            applies_to: ["cax11", "cax21", "cax31", "cax41"]
            description: "ARM64 QEMU needs AAVMF/OVMF UEFI firmware; package is ovmf on Debian"
            remediation: "bootstrap.sh installs ovmf via apt and locates firmware automatically"
        }
    ]

    let plan_quirks = if ($plan | str starts-with "cax") {
        $base_quirks | where {|q| ("*" in $q.applies_to) or ($plan in $q.applies_to)}
    } else {
        $base_quirks | where {|q| ("*" in $q.applies_to) or ($plan in $q.applies_to)}
    }

    {
        provider: "hetzner-cloud"
        plan: $plan
        quirks: $plan_quirks
    }
}

# Rescue image information for a given plan
export def "hetzner rescue-info" [plan: string = "cax11"] {
    let arch = if ($plan | str starts-with "cax") { "aarch64" } else { "x86_64" }
    {
        provider: "hetzner-cloud"
        plan: $plan
        arch: $arch
        default_rescue_distro: "debian-12"
        rescue_method: "hetzner-api-or-console"
        rescue_notes: [
            "Activate rescue via Hetzner Cloud API: POST /v1/servers/{id}/actions/enable_rescue"
            "Then hard-reboot the server to boot into rescue"
            "Rescue persists for one boot only — after QEMU exits the server boots from disk"
        ]
        qemu_machine: (if $arch == "aarch64" { "virt,accel=kvm" } else { "pc,accel=kvm" })
        qemu_cpu: "host"
        qemu_target_disk_in_bsd: (if $arch == "aarch64" { "vtbd0" } else { "vtbd0" })
    }
}

# Derive QEMU parameters for a given manifest target
export def "hetzner qemu-params" [plan: string] {
    let arch = if ($plan | str starts-with "cax") { "aarch64" } else { "amd64" }
    {
        arch: $arch
        qemu_bin: (if $arch == "aarch64" { "qemu-system-aarch64" } else { "qemu-system-x86_64" })
        qemu_machine: (if $arch == "aarch64" { "virt,accel=kvm" } else { "pc,accel=kvm" })
        qemu_cpu: "host"
        qemu_target_disk: "/dev/sda"
        qemu_target_disk_in_bsd: "vtbd0"
        firmware_package: (if $arch == "aarch64" { "ovmf" } else { "ovmf" })
    }
}
