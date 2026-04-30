#!/usr/bin/env nu
# SPDX-License-Identifier: BSD-2-Clause
# provider-adapters/oci.nu — Oracle Cloud Infrastructure adapter for lsd
#
# OCI Always Free: VM.Standard.A1.Flex (4 OCPU / 24 GB RAM)
# Strategy: BYOI (Bring Your Own Image) — no rescue-mode trampoline available
#
# cloud-init NOTE (docs-first):
#   OCI injects cloud-init via the NoCloud datasource. The NoCloud datasource
#   caches per-instance-id in /var/lib/cloud/instances/<instance-id>/.
#   Bumping instance-id does NOT always invalidate the cache if the seed device
#   (cdrom/virtfs) is still present with the old instance-id.
#   Reference: https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html
#   For BYOI FreeBSD images: cloud-init is NOT installed by default; OCI's
#   cloud-init integration is irrelevant for the BSD target. Documented here
#   because the rescue Linux (if used) may be cloud-init-managed.

export def "oci imds-shape" [] {
    {
        provider: "oci"
        imds_version: "v1"
        base_url: "http://169.254.169.254/opc/v1"
        endpoints: {
            instance:       "http://169.254.169.254/opc/v1/instance/"
            instance_id:    "http://169.254.169.254/opc/v1/instance/id"
            hostname:       "http://169.254.169.254/opc/v1/instance/hostname"
            region:         "http://169.254.169.254/opc/v1/instance/regionInfo/regionIdentifier"
            public_ip:      "http://169.254.169.254/opc/v1/vnics/"
            ssh_keys:       "http://169.254.169.254/opc/v1/instance/metadata/ssh_authorized_keys"
            user_data:      "http://169.254.169.254/opc/v1/instance/metadata/user_data"
        }
        auth_header: "Authorization: Bearer Oracle"
        notes: [
            "OCI IMDS requires 'Authorization: Bearer Oracle' header since 2023"
            "ssh_authorized_keys is a single string with newline-separated keys"
            "No rescue-mode boot available — BYOI is the only path for custom OS"
            "cloud-init on rescue Linux uses NoCloud datasource; instance-id cache caveat applies (see module header)"
        ]
    }
}

export def "oci quirks" [plan: string = "VM.Standard.A1.Flex"] {
    {
        provider: "oci"
        plan: $plan
        quirks: [
            {
                id: "oci-byoi-only"
                severity: "info"
                description: "OCI does not offer per-instance rescue boot; custom OS requires uploading a pre-built image"
                remediation: "Use lsd build to produce a raw/qcow2 image locally, then oci compute image import"
            }
            {
                id: "oci-imds-auth-header"
                severity: "warn"
                description: "OCI IMDS requires 'Authorization: Bearer Oracle' since early 2023; unauthenticated requests return 401"
                remediation: "bootstrap.sh and bsdinstall.script must include the auth header when querying IMDS"
            }
            {
                id: "oci-security-list-ssh"
                severity: "warn"
                description: "Default VCN Security List blocks inbound TCP/22; SSH will be unreachable until rule is added"
                remediation: "Add ingress rule 0.0.0.0/0 TCP 22 in OCI Console before deploying"
            }
            {
                id: "oci-boot-volume-virtio-blk"
                severity: "info"
                description: "Boot volume is paravirtualized virtio-blk; appears as /dev/vda inside Linux, vtbd0 inside FreeBSD"
                remediation: "bsdinstall.script targets vtbd0 automatically for OCI"
            }
            {
                id: "oci-cloud-init-nocloud-cache"
                severity: "warn"
                description: "If rescue Linux uses cloud-init NoCloud datasource, instance-id cache does NOT auto-invalidate on rebundle"
                remediation: "Run 'cloud-init clean' before imaging to avoid stale cache in the BYOI image; irrelevant for BSD target (no cloud-init)"
                reference: "https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html"
            }
            {
                id: "oci-image-format"
                severity: "info"
                description: "OCI custom images accept qcow2 or raw (imported via Object Storage). VMDK also accepted via Console."
                remediation: "Use qemu-img convert -f raw -O qcow2 to produce upload-ready image"
            }
            {
                id: "oci-always-free-region-lock"
                severity: "warn"
                description: "Always Free A1 capacity is region-specific and often exhausted; 'Out of capacity' errors are common"
                remediation: "Try multiple regions (us-ashburn-1, us-phoenix-1, eu-frankfurt-1) or retry at off-peak hours"
            }
        ]
    }
}

export def "oci qemu-params" [plan: string] {
    {
        arch: "aarch64"
        qemu_bin: "qemu-system-aarch64"
        qemu_machine: "virt"
        qemu_cpu: "max"
        # BYOI: QEMU runs locally to build the image, not in OCI rescue
        qemu_target_disk: "/dev/loop0"
        qemu_target_disk_in_bsd: "vtbd0"
        byoi_mode: true
        byoi_notes: [
            "Create a blank raw image: qemu-img create -f raw freebsd.raw 50G"
            "Attach as loop device: losetup /dev/loop0 freebsd.raw"
            "Run bootstrap.sh targeting /dev/loop0"
            "Convert for OCI: qemu-img convert -f raw -O qcow2 freebsd.raw freebsd.qcow2"
            "Upload: oci os object put --bucket-name images --file freebsd.qcow2"
            "Import: oci compute image import from-object-uri ..."
        ]
    }
}
