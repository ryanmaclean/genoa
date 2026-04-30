#!/usr/bin/env nu
# SPDX-License-Identifier: BSD-2-Clause
# provider-adapters/digitalocean.nu — DigitalOcean adapter for lsd
#
# Strategy: QEMU trampoline from a standard DO Droplet, export raw disk,
#           upload as DO custom image, then deploy a new Droplet from it.
#
# HARD LIMIT — IPv6 on custom-image Droplets:
#   DigitalOcean does NOT automatically configure IPv6 on Droplets created
#   from custom images. The DO networking agent (do-agent) that handles IPv6
#   config is not present in custom/BYOI images. Even if IPv6 is enabled at
#   Droplet creation time, the interface will not receive an address unless
#   the BSD install manually configures it from IMDS.
#   This is a structural provider limit, not a config problem. lsd describe
#   ALWAYS emits the digitalocean-custom-images-no-ipv6 warning for DO.
#   Reference: https://docs.digitalocean.com/products/custom-images/
#
# cloud-init NOTE (docs-first):
#   DO standard Droplets use cloud-init with the ConfigDrive datasource (not NoCloud).
#   However, if a rescue or builder Droplet was previously cloud-init initialized,
#   the NoCloud datasource cache at /var/lib/cloud/instances/<instance-id>/ can
#   persist across snapshots. Bumping instance-id does NOT always invalidate this
#   cache — run 'cloud-init clean --logs' before snapshotting a builder Droplet
#   to avoid stale cloud-init state in the resulting custom image.
#   Reference: https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html

# Structural IPv6 warning — always emitted for DO targets
export const DO_IPV6_WARNING = {
    id: "digitalocean-custom-images-no-ipv6"
    severity: "error"
    description: "DigitalOcean custom-image Droplets do not receive automatic IPv6 configuration. The DO networking agent is absent from BYOI images. IPv6 must be manually configured from IMDS if required, and is unreliable in this path."
    reference: "https://docs.digitalocean.com/products/custom-images/"
    remediation: "Set ipv6=false in manifest [network]. If IPv6 is required, consider Hetzner Cloud (better custom-image networking support)."
}

export def "digitalocean imds-shape" [] {
    {
        provider: "digitalocean"
        imds_version: "v1"
        base_url: "http://169.254.169.254/metadata/v1"
        endpoints: {
            hostname:    "http://169.254.169.254/metadata/v1/hostname"
            instance_id: "http://169.254.169.254/metadata/v1/id"
            region:      "http://169.254.169.254/metadata/v1/region"
            public_ipv4: "http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address"
            public_ipv6: "http://169.254.169.254/metadata/v1/interfaces/public/0/ipv6/address"
            ssh_keys:    "http://169.254.169.254/metadata/v1/public-keys"
            user_data:   "http://169.254.169.254/metadata/v1/user-data"
            dns:         "http://169.254.169.254/metadata/v1/dns/nameservers"
        }
        auth_header: null
        notes: [
            "DO IMDS does not require auth headers (unlike OCI)"
            "public-keys returns newline-separated SSH public keys"
            "IPv6 endpoint will return empty/error on custom-image Droplets (structural limit)"
        ]
    }
}

export def "digitalocean quirks" [plan: string = "s-1vcpu-2gb"] {
    {
        provider: "digitalocean"
        plan: $plan
        # IPv6 warning is ALWAYS present for DO — not conditional on manifest ipv6 flag
        warnings: [$DO_IPV6_WARNING]
        quirks: [
            {
                id: "digitalocean-no-rescue-custom-image"
                severity: "info"
                description: "DO does not provide per-Droplet rescue boot for custom images. Recovery ISO via console is limited."
                remediation: "Build the FreeBSD image externally (QEMU trampoline on a temp Droplet), then upload as custom image."
            }
            {
                id: "digitalocean-custom-image-size-limit"
                severity: "warn"
                description: "Custom images must be < 100 GB compressed. Raw images are compressed before upload."
                remediation: "Keep filesystem use below ~60 GB to stay safely under compressed limit."
            }
            {
                id: "digitalocean-no-freebsd-agent"
                severity: "warn"
                description: "DO monitoring agent (do-agent) is Linux-only. FreeBSD Droplets will show as offline in DO console metrics."
                remediation: "Use external monitoring (Datadog, etc). This is expected and non-fatal."
            }
            {
                id: "digitalocean-cloud-init-cache-on-builder"
                severity: "warn"
                description: "If snapshotting a builder Droplet, cloud-init NoCloud cache may persist. Instance-id bump does NOT always invalidate it."
                remediation: "Run 'cloud-init clean --logs' on the builder before snapshotting. Reference: https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html"
            }
            {
                id: "digitalocean-virtio-disk"
                severity: "info"
                description: "Droplet disk is virtio-blk; appears as /dev/vda in Linux, vtbd0 in FreeBSD."
                remediation: "bsdinstall.script targets vtbd0 for DO manifests."
            }
            {
                id: "digitalocean-custom-image-upload-format"
                severity: "info"
                description: "DO accepts raw, qcow2, or ISO for custom image upload (via URL or direct upload)."
                remediation: "Use raw format from QEMU output for widest compatibility."
            }
        ]
    }
}

export def "digitalocean qemu-params" [plan: string] {
    {
        arch: "amd64"
        qemu_bin: "qemu-system-x86_64"
        qemu_machine: "pc,accel=kvm"
        qemu_cpu: "host"
        qemu_target_disk: "/dev/sda"
        qemu_target_disk_in_bsd: "vtbd0"
        byoi_mode: false
        trampoline_notes: [
            "Spin up a standard Debian/Ubuntu Droplet as the build host"
            "Bootstrap.sh runs on that Droplet targeting /dev/sda"
            "After QEMU exits, power off the Droplet"
            "Take a Droplet snapshot in DO console — this becomes your custom image"
            "Deploy new Droplets from that snapshot"
            "Alternative: export disk image and upload via DO API /v2/images endpoint"
        ]
    }
}

# Returns warnings that must always be surfaced for DO targets
# Called by lsd describe to ensure IPv6 warning is never suppressed
export def "digitalocean mandatory-warnings" [] {
    [$DO_IPV6_WARNING]
}
