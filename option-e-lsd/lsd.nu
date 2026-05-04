#!/usr/bin/env nu
# SPDX-License-Identifier: BSD-2-Clause
#
# lsd.nu — Linux→BSD Stomper Deploy CLI
# Option E in the genoa bake-off
#
# Emits a Linux→QEMU→mfsBSD trampoline installer for cloud providers
# that only support Linux base images (Hetzner Cloud CAX, OCI Always Free,
# DigitalOcean custom images, etc).
#
# AX-first: every subcommand emits structured JSON.
# Schema versioned at schema/manifest.v1.json and schema/receipt.v1.json
#
# Usage:
#   nu lsd.nu catalog
#   nu lsd.nu schema
#   nu lsd.nu describe <manifest.toml>
#   nu lsd.nu build <manifest.toml> --out <dir>
#   nu lsd.nu verify <manifest.toml> <receipt.json>

const LSD_VERSION = "0.1.0"
const SCHEMA_VERSION = "1.0.0"

# Catalog of supported (provider, base, arch) tuples
# AX-first: machine-readable, schema-versioned
const CATALOG = {
    schema_version: "1.0.0"
    generated_at: "2026-04-30T00:00:00Z"
    tool: "lsd"
    tool_version: "0.1.0"
    providers: [
        {
            id: "hetzner-cloud"
            display_name: "Hetzner Cloud"
            rescue_method: "api-rescue-boot"
            trampoline_strategy: "rescue-qemu-passthrough"
            imds_base: "http://169.254.169.254/hetzner/v1/metadata"
            supported_bases: [
                {
                    os: "freebsd"
                    version: "15.0-RELEASE"
                    arch: "aarch64"
                    plans: ["cax11", "cax21", "cax31", "cax41"]
                    filesystem: ["zfs", "ufs"]
                    status: "spec"
                    mfsbsd_url: "https://mfsbsd.vx.sk/files/iso/15/aarch64/mfsbsd-se-15.0-RELEASE-arm64-aarch64.iso"
                    notes: ["virtio-mmio bus on ARM64; UEFI required; KVM available in rescue"]
                }
                {
                    os: "freebsd"
                    version: "15.0-RELEASE"
                    arch: "amd64"
                    plans: ["cx22", "cx32", "cx42", "cx52"]
                    filesystem: ["zfs", "ufs"]
                    status: "spec"
                    mfsbsd_url: "https://mfsbsd.vx.sk/files/iso/15/amd64/mfsbsd-se-15.0-RELEASE-amd64.iso"
                    notes: ["x86_64; virtio-pci; KVM available in rescue"]
                }
            ]
        }
        {
            id: "hetzner-robot"
            display_name: "Hetzner Robot (Dedicated)"
            rescue_method: "robot-rescue-ssh"
            trampoline_strategy: "rescue-qemu-passthrough"
            imds_base: null
            supported_bases: [
                {
                    os: "freebsd"
                    version: "15.0-RELEASE"
                    arch: "amd64"
                    plans: ["ax41", "ax51", "ax61", "ax101", "ax161"]
                    filesystem: ["zfs", "ufs"]
                    status: "spec"
                    mfsbsd_url: "https://mfsbsd.vx.sk/files/iso/15/amd64/mfsbsd-se-15.0-RELEASE-amd64.iso"
                    notes: ["No IMDS; keys available via Robot API; pattern from depenguin-run"]
                }
            ]
        }
        {
            id: "oci"
            display_name: "Oracle Cloud Infrastructure (Always Free)"
            rescue_method: "byoi-upload"
            trampoline_strategy: "local-qemu-byoi"
            imds_base: "http://169.254.169.254/opc/v1"
            supported_bases: [
                {
                    os: "freebsd"
                    version: "15.0-RELEASE"
                    arch: "aarch64"
                    plans: ["VM.Standard.A1.Flex"]
                    filesystem: ["zfs", "ufs"]
                    status: "spec"
                    mfsbsd_url: "https://mfsbsd.vx.sk/files/iso/15/aarch64/mfsbsd-se-15.0-RELEASE-arm64-aarch64.iso"
                    notes: ["BYOI path; OCI IMDS needs 'Authorization: Bearer Oracle' header; Always Free capacity varies by region"]
                }
            ]
        }
        {
            id: "digitalocean"
            display_name: "DigitalOcean"
            rescue_method: "builder-droplet-snapshot"
            trampoline_strategy: "rescue-qemu-passthrough"
            imds_base: "http://169.254.169.254/metadata/v1"
            supported_bases: [
                {
                    os: "freebsd"
                    version: "15.0-RELEASE"
                    arch: "amd64"
                    plans: ["s-1vcpu-1gb", "s-1vcpu-2gb", "s-2vcpu-2gb", "s-2vcpu-4gb"]
                    filesystem: ["ufs", "zfs"]
                    status: "spec"
                    mfsbsd_url: "https://mfsbsd.vx.sk/files/iso/15/amd64/mfsbsd-se-15.0-RELEASE-amd64.iso"
                    notes: ["HARD LIMIT: no auto IPv6 on custom-image Droplets; no DO agent in BSD"]
                    mandatory_warnings: ["digitalocean-custom-images-no-ipv6"]
                }
            ]
        }
    ]
}

# Emit the full catalog as JSON
def "main catalog" [] {
    $CATALOG | to json
}

# Emit the JSON Schema for lsd.toml manifests
def "main schema" [] {
    let schema_path = ([$env.FILE_PWD, "schema", "manifest.v1.json"] | path join)
    if ($schema_path | path exists) {
        open --raw $schema_path | from json | to json
    } else {
        # Inline fallback if running from a different cwd
        {
            "$schema": "https://json-schema.org/draft/2020-12/schema"
            "$id": "https://github.com/ryanmaclean/genoa/option-e-lsd/schema/manifest.v1.json"
            title: "LSD Manifest"
            version: "1.0.0"
            note: "Full schema at schema/manifest.v1.json"
            required: ["lsd_schema_version", "target", "base", "network", "trust"]
            properties: {
                lsd_schema_version: { type: "string" }
                target: { type: "object", required: ["provider", "plan", "region"] }
                base: { type: "object", required: ["os", "version", "arch", "filesystem"] }
                network: { type: "object", required: ["ssh_keys", "hostname"] }
                trust: { type: "object", required: ["mfs_image_sha256"] }
            }
        } | to json
    }
}

# Validate a manifest against the catalog and schema rules
# Returns {valid: bool, errors: [...], warnings: [...]}
def validate_manifest [manifest: record] {
    mut errors = []
    mut warnings = []

    # Schema version check
    if not ("lsd_schema_version" in $manifest) {
        $errors = ($errors | append "missing required field: lsd_schema_version")
    } else if not ($manifest.lsd_schema_version =~ '^1\.\d+\.\d+$') {
        $errors = ($errors | append $"lsd_schema_version must match ^1\\.\\d+\\.\\d+$ got: ($manifest.lsd_schema_version)")
    }

    # Target validation
    let valid_providers = ["hetzner-cloud", "hetzner-robot", "oci", "digitalocean"]
    if not ($manifest.target.provider in $valid_providers) {
        $errors = ($errors | append $"target.provider '($manifest.target.provider)' not in catalog: ($valid_providers | str join ', ')")
    }

    # Base OS validation
    let valid_os = ["freebsd", "netbsd"]
    if not ($manifest.base.os in $valid_os) {
        $errors = ($errors | append $"base.os '($manifest.base.os)' must be one of: ($valid_os | str join ', ')")
    }

    let valid_arch = ["amd64", "aarch64"]
    if not ($manifest.base.arch in $valid_arch) {
        $errors = ($errors | append $"base.arch '($manifest.base.arch)' must be one of: ($valid_arch | str join ', ')")
    }

    let valid_fs = ["zfs", "ufs"]
    if not ($manifest.base.filesystem in $valid_fs) {
        $errors = ($errors | append $"base.filesystem '($manifest.base.filesystem)' must be one of: ($valid_fs | str join ', ')")
    }

    # base.mode validation
    let mode = if ("mode" in $manifest.base) { $manifest.base.mode } else { "mfsbsd" }
    let valid_modes = ["mfsbsd", "custom_image"]
    if not ($mode in $valid_modes) {
        $errors = ($errors | append $"base.mode '($mode)' must be one of: ($valid_modes | str join ', ')")
    }
    if $mode == "custom_image" {
        if not ("custom_image_url" in $manifest.base) or ($manifest.base.custom_image_url | str length) == 0 {
            $errors = ($errors | append "base.custom_image_url is required and must be non-empty when base.mode=custom_image")
        }
        if not ("custom_image_sha256" in $manifest.base) {
            $errors = ($errors | append "base.custom_image_sha256 is required when base.mode=custom_image")
        } else if not ($manifest.base.custom_image_sha256 =~ '^[0-9a-f]{64}$') {
            $errors = ($errors | append $"base.custom_image_sha256 must be exactly 64 hex chars, got: '($manifest.base.custom_image_sha256)'")
        }
    }

    # SHA256 format check
    if not ($manifest.trust.mfs_image_sha256 =~ '^[0-9a-f]{64}$') {
        $errors = ($errors | append $"trust.mfs_image_sha256 must be 64 hex chars, got: '($manifest.trust.mfs_image_sha256)'")
    }

    # Placeholder sha256 warning
    if $manifest.trust.mfs_image_sha256 == "0000000000000000000000000000000000000000000000000000000000000000" {
        $warnings = ($warnings | append "trust.mfs_image_sha256 is a placeholder (all zeros) — replace with real digest before production use")
    }

    # SSH keys check
    if ($manifest.network.ssh_keys | length) == 0 {
        $errors = ($errors | append "network.ssh_keys must contain at least one key")
    }

    # Hostname format
    if not ($manifest.network.hostname =~ '^[a-z0-9][a-z0-9\-]{0,61}[a-z0-9]?$') {
        $errors = ($errors | append $"network.hostname '($manifest.network.hostname)' is not a valid RFC-1123 hostname")
    }

    # Provider-arch compatibility
    if $manifest.target.provider == "oci" and $manifest.base.arch != "aarch64" {
        $errors = ($errors | append "oci Always Free only supports aarch64 (VM.Standard.A1.Flex)")
    }
    if $manifest.target.provider == "digitalocean" and $manifest.base.arch != "amd64" {
        $warnings = ($warnings | append "digitalocean custom images are primarily tested on amd64; aarch64 support is limited")
    }

    # DigitalOcean mandatory IPv6 warning — structural provider limit
    if $manifest.target.provider == "digitalocean" {
        $warnings = ($warnings | append "digitalocean-custom-images-no-ipv6: DigitalOcean custom-image Droplets do not receive automatic IPv6 configuration. The DO networking agent is absent from BYOI images. Set ipv6=false in [network]. Reference: https://docs.digitalocean.com/products/custom-images/")
    }

    # IPv6 conflict for DO
    if $manifest.target.provider == "digitalocean" and ("ipv6" in $manifest.network) and $manifest.network.ipv6 == true {
        $errors = ($errors | append "network.ipv6=true is incompatible with digitalocean provider (structural limit: no auto-IPv6 on custom images)")
    }

    {valid: (($errors | length) == 0), errors: $errors, warnings: $warnings}
}

# Look up provider entry from catalog
def lookup_provider [provider_id: string] {
    $CATALOG.providers | where {|p| $p.id == $provider_id} | first
}

# Look up the mfsBSD URL for a given provider/os/arch combo from catalog
def lookup_mfsbsd_url [provider_id: string, os: string, arch: string] {
    let provider = lookup_provider $provider_id
    let matches = $provider.supported_bases | where {|b| $b.os == $os and $b.arch == $arch}
    if ($matches | length) == 0 {
        null
    } else {
        ($matches | first).mfsbsd_url
    }
}

# Derive QEMU parameters from manifest
def derive_qemu_params [manifest: record] {
    let provider = $manifest.target.provider
    let arch = $manifest.base.arch

    let qemu_bin = if $arch == "aarch64" { "qemu-system-aarch64" } else { "qemu-system-x86_64" }
    let qemu_machine = if $arch == "aarch64" { "virt,accel=kvm" } else { "pc,accel=kvm" }
    let qemu_cpu = "host"
    let qemu_target_disk_in_linux = if $provider == "oci" { "/dev/loop0" } else { "/dev/sda" }
    let qemu_target_disk_in_bsd = "vtbd0"

    {
        qemu_bin: $qemu_bin
        qemu_machine: $qemu_machine
        qemu_cpu: $qemu_cpu
        qemu_target_disk: $qemu_target_disk_in_linux
        qemu_target_disk_in_bsd: $qemu_target_disk_in_bsd
        firmware_required: ($arch == "aarch64")
        firmware_package: (if $arch == "aarch64" { "ovmf" } else { null })
    }
}

# Render bootstrap.sh for custom_image mode (dd raw image path)
# Uses str replace substitution to avoid Nushell $"..." subexpression conflicts
def render_bootstrap_custom_image [manifest: record, qemu: record] {
    let image_url     = $manifest.base.custom_image_url
    let image_sha256  = $manifest.base.custom_image_sha256
    let target_disk   = $qemu.qemu_target_disk
    let hostname      = $manifest.network.hostname
    let callback_url  = if ("callback_url" in $manifest.trust) { $manifest.trust.callback_url } else { "" }
    let imds_endpoint = get_imds_endpoint $manifest.target.provider
    let built_at      = (date now | format date "%Y-%m-%dT%H:%M:%SZ")

    # Raw bash template — no Nushell interpolation inside, only {{ token }} markers
    let tmpl = '#!/usr/bin/env bash
# SPDX-License-Identifier: BSD-2-Clause
# lsd-generated bootstrap.sh -- custom_image mode
# Built at: {{ built_at }}
# Manifest: lsd.toml
# Mode: custom_image -- dd raw image, no QEMU, no bsdinstall
set -euo pipefail

CUSTOM_IMAGE_MODE=1
IMAGE_URL="{{ image_url }}"
IMAGE_SHA256="{{ image_sha256 }}"
TARGET_DISK="{{ target_disk }}"
BSD_HOSTNAME="{{ hostname }}"
IMDS_ENDPOINT="{{ imds_endpoint }}"
CALLBACK_URL="{{ callback_url }}"

log() { echo "[lsd] $*"; }
die() { echo "[lsd] FATAL: $*" >&2; exit 1; }

fetch_and_verify_image() {
    log "Fetching image from: $IMAGE_URL"
    if [[ "$IMAGE_URL" == file://* ]]; then
        local local_path="${IMAGE_URL#file://}"
        [[ -f "$local_path" ]] || die "local image not found: $local_path"
        log "Copying local image: $local_path -> /tmp/genoa.img"
        cp "$local_path" /tmp/genoa.img
    else
        curl -fSL -o /tmp/genoa.img "$IMAGE_URL" || die "curl failed for: $IMAGE_URL"
    fi
    log "Verifying sha256 of /tmp/genoa.img"
    if command -v sha256sum >/dev/null 2>&1; then
        echo "$IMAGE_SHA256  /tmp/genoa.img" | sha256sum -c - || die "sha256 mismatch for genoa.img"
    elif command -v sha256 >/dev/null 2>&1; then
        local actual
        actual=$(sha256 -q /tmp/genoa.img)
        [[ "$actual" == "$IMAGE_SHA256" ]] || die "sha256 mismatch: expected $IMAGE_SHA256 got $actual"
    else
        die "no sha256sum or sha256 found -- cannot verify image integrity"
    fi
    log "Image verified OK"
}

write_image_to_disk() {
    log "Writing /tmp/genoa.img -> $TARGET_DISK via dd bs=8M conv=fdatasync"
    dd if=/tmp/genoa.img of="$TARGET_DISK" bs=8M conv=fdatasync status=progress || die "dd failed writing to $TARGET_DISK"
    sync
    log "Image written and synced to disk"
}

run_callback() {
    if [[ -n "$CALLBACK_URL" ]]; then
        log "POSTing completion callback to $CALLBACK_URL"
        curl -fsSL -X POST -H "Content-Type: application/json" \
            -d "{\"status\":\"complete\",\"mode\":\"custom_image\",\"host\":\"$BSD_HOSTNAME\"}" \
            "$CALLBACK_URL" || log "WARNING: callback POST failed, non-fatal"
    fi
}

main() {
    log "lsd custom_image bootstrap starting"
    log "Target disk : $TARGET_DISK"
    log "Image URL   : $IMAGE_URL"
    log "SHA-256     : $IMAGE_SHA256"

    fetch_and_verify_image
    write_image_to_disk
    run_callback

    log "Done. Rebooting into installed BSD image..."
    sync
    reboot
}

main "$@"
'

    $tmpl
    | str replace --all "{{ built_at }}"      $built_at
    | str replace --all "{{ image_url }}"     $image_url
    | str replace --all "{{ image_sha256 }}"  $image_sha256
    | str replace --all "{{ target_disk }}"   $target_disk
    | str replace --all "{{ hostname }}"      $hostname
    | str replace --all "{{ imds_endpoint }}" $imds_endpoint
    | str replace --all "{{ callback_url }}"  $callback_url
}

# Render the bootstrap.sh from the template
def render_bootstrap [manifest: record, qemu: record] {
    let mode = if ("mode" in $manifest.base) { $manifest.base.mode } else { "mfsbsd" }

    if $mode == "custom_image" {
        return (render_bootstrap_custom_image $manifest $qemu)
    }

    let template_path = ([$env.FILE_PWD, "templates", "bootstrap.sh.tera"] | path join)
    let template = if ($template_path | path exists) {
        open --raw $template_path
    } else {
        "# ERROR: template not found at templates/bootstrap.sh.tera"
    }

    let mfsbsd_url = if ("mfsbsd_url" in $manifest.base) {
        $manifest.base.mfsbsd_url
    } else {
        lookup_mfsbsd_url $manifest.target.provider $manifest.base.os $manifest.base.arch
    }

    let callback_url = if ("callback_url" in $manifest.trust) { $manifest.trust.callback_url } else { "" }
    let ssh_keys = $manifest.network.ssh_keys | str join "\n"
    let ipv6 = if ("ipv6" in $manifest.network) { $manifest.network.ipv6 } else { false }

    # Tera-style substitution — simple string replace for v0.1
    # A real implementation would use the tera crate or equivalent
    $template
    | str replace --all "{{ mfsbsd_url }}" ($mfsbsd_url | default "https://mfsbsd.vx.sk/files/iso/15/amd64/mfsbsd-se-15.0-RELEASE-amd64.iso")
    | str replace --all "{{ mfsbsd_sha256 }}" $manifest.trust.mfs_image_sha256
    | str replace --all "{{ target_disk }}" $qemu.qemu_target_disk
    | str replace --all "{{ bsd_hostname }}" $manifest.network.hostname
    | str replace --all "{{ ssh_authorized_keys }}" $ssh_keys
    | str replace --all "{{ arch }}" $manifest.base.arch
    | str replace --all "{{ callback_url }}" $callback_url
    | str replace --all "{{ qemu_machine }}" $qemu.qemu_machine
    | str replace --all "{{ qemu_cpu }}" $qemu.qemu_cpu
    | str replace --all "{{ imds_endpoint }}" (get_imds_endpoint $manifest.target.provider)
    | str replace --all "{{ manifest_path }}" "lsd.toml"
    | str replace --all "{{ built_at }}" (date now | format date "%Y-%m-%dT%H:%M:%SZ")
}

# Render the bsdinstall script from the template
def render_bsdinstall [manifest: record, qemu: record] {
    let mode = if ("mode" in $manifest.base) { $manifest.base.mode } else { "mfsbsd" }
    if $mode == "custom_image" {
        return ""
    }

    let template_path = ([$env.FILE_PWD, "templates", "bsdinstall.script.tera"] | path join)
    let template = if ($template_path | path exists) {
        open --raw $template_path
    } else {
        "# ERROR: template not found at templates/bsdinstall.script.tera"
    }

    let ssh_keys = $manifest.network.ssh_keys | str join "\n"
    let ipv6 = if ("ipv6" in $manifest.network) { ($manifest.network.ipv6 | into string) } else { "false" }
    let fs = $manifest.base.filesystem

    $template
    | str replace --all "{{ qemu_target_disk }}" $qemu.qemu_target_disk_in_bsd
    | str replace --all "{{ bsd_hostname }}" $manifest.network.hostname
    | str replace --all "{{ ssh_authorized_keys }}" $ssh_keys
    | str replace --all "{{ arch }}" $manifest.base.arch
    | str replace --all "{{ bsd_arch }}" (if $manifest.base.arch == "aarch64" { "arm64/aarch64" } else { "amd64/amd64" })
    | str replace --all "{{ bsd_version }}" $manifest.base.version
    | str replace --all "{{ filesystem }}" $fs
    | str replace --all "{{ ipv6 }}" $ipv6
    | str replace --all "{% if filesystem == \"zfs\" %}" (if $fs == "zfs" { "" } else { "# [zfs block - skipped]" })
    | str replace --all "{% else %}" (if $fs == "zfs" { "# [ufs block - skipped]" } else { "" })
    | str replace --all "{% endif %}" ""
    | str replace --all "{% if arch == \"aarch64\" %}" (if $manifest.base.arch == "aarch64" { "" } else { "# [aarch64 block - skipped]" })
    | str replace --all "{% if ipv6 %}" (if $ipv6 == "true" { "" } else { "# [ipv6 block - skipped]" })
}

# Get IMDS endpoint for a provider
def get_imds_endpoint [provider: string] {
    match $provider {
        "hetzner-cloud" => "http://169.254.169.254/hetzner/v1/metadata"
        "hetzner-robot" => "none"
        "oci"           => "http://169.254.169.254/opc/v1"
        "digitalocean"  => "http://169.254.169.254/metadata/v1"
        _               => "unknown"
    }
}

# Describe a manifest: structured plan with provider info, URLs, warnings
def "main describe" [manifest_path: string] {
    if not ($manifest_path | path exists) {
        {error: $"manifest not found: ($manifest_path)"} | to json
        return
    }

    let manifest = open $manifest_path
    let validation = validate_manifest $manifest
    let qemu = derive_qemu_params $manifest

    let mode = if ("mode" in $manifest.base) { $manifest.base.mode } else { "mfsbsd" }

    let mfsbsd_url = if ("mfsbsd_url" in $manifest.base) {
        $manifest.base.mfsbsd_url
    } else {
        lookup_mfsbsd_url $manifest.target.provider $manifest.base.os $manifest.base.arch
    }

    let provider_info = lookup_provider $manifest.target.provider
    let imds_endpoint = get_imds_endpoint $manifest.target.provider

    # Build installer block — differs by mode
    let installer = if $mode == "custom_image" {
        {
            install_method: "dd-raw-image"
            mfsbsd_url: null
            mfsbsd_sha256_expected: null
            sha256_is_placeholder: false
            provenance_url: (if ("provenance_url" in $manifest.trust) { $manifest.trust.provenance_url } else { null })
        }
    } else {
        {
            install_method: "bsdinstall"
            mfsbsd_url: ($mfsbsd_url | default "not found in catalog")
            mfsbsd_sha256_expected: $manifest.trust.mfs_image_sha256
            sha256_is_placeholder: ($manifest.trust.mfs_image_sha256 == "0000000000000000000000000000000000000000000000000000000000000000")
            provenance_url: (if ("provenance_url" in $manifest.trust) { $manifest.trust.provenance_url } else { null })
        }
    }

    # custom_image section — only present when mode=custom_image
    let custom_image_section = if $mode == "custom_image" {
        let raw_sha = if ("custom_image_sha256" in $manifest.base) { $manifest.base.custom_image_sha256 } else { "" }
        let sha_display = if ($raw_sha | str length) >= 16 { $"($raw_sha | str substring 0..16)..." } else { $raw_sha }
        let img_url = if ("custom_image_url" in $manifest.base) { $manifest.base.custom_image_url } else { "" }
        {
            mode: "custom_image"
            image_url: $img_url
            image_sha256: $sha_display
            install_method: "dd-raw-image"
        }
    } else {
        null
    }

    # next_steps differ by mode
    let next_steps = if $validation.valid {
        if $mode == "custom_image" {
            [
                $"1. Activate rescue boot for '($manifest.target.plan)' in ($manifest.target.provider) console/API"
                "2. SSH into rescue environment"
                $"3. Run: lsd build ($manifest_path) --out ./out && scp out/bootstrap.sh rescue-host:/tmp/"
                "4. On the rescue host: bash /tmp/bootstrap.sh"
                "5. bootstrap.sh fetches the raw image, dd-writes it to disk, then reboots"
                "6. Server will boot directly into the installed BSD image (no QEMU, no bsdinstall)"
            ]
        } else {
            [
                $"1. Activate rescue boot for '($manifest.target.plan)' in ($manifest.target.provider) console/API"
                "2. SSH into rescue environment"
                $"3. Run: curl -fsSL <bootstrap-url> | bash  -- alt: lsd build ($manifest_path) --out ./out, scp out/bootstrap.sh rescue-host:/tmp/"
                "4. Wait for QEMU to complete BSD install (~15-45 min depending on ISO download speed)"
                "5. Hard-reboot the server — it will boot into FreeBSD"
            ]
        }
    } else {
        ["Fix validation errors before building"]
    }

    # Build the describe output
    mut out = {
        schema_version: $SCHEMA_VERSION
        tool: "lsd"
        tool_version: $LSD_VERSION
        manifest: $manifest_path
        valid: $validation.valid
        errors: $validation.errors
        warnings: $validation.warnings
        plan: {
            provider: $manifest.target.provider
            provider_display: $provider_info.display_name
            plan: $manifest.target.plan
            region: $manifest.target.region
            rescue_method: $provider_info.rescue_method
            trampoline_strategy: $provider_info.trampoline_strategy
            base_os: $manifest.base.os
            base_version: $manifest.base.version
            arch: $manifest.base.arch
            filesystem: $manifest.base.filesystem
            hostname: $manifest.network.hostname
            ipv6: (if ("ipv6" in $manifest.network) { $manifest.network.ipv6 } else { false })
            mode: $mode
        }
        installer: $installer
        qemu: $qemu
        imds: {
            endpoint: $imds_endpoint
            provider_notes: (do {
                let base_matches = ($provider_info.supported_bases
                    | where {|b| $b.os == $manifest.base.os and $b.arch == $manifest.base.arch})
                if ($base_matches | length) == 0 { [] } else { ($base_matches | first).notes }
            })
        }
        next_steps: $next_steps
    }

    if $custom_image_section != null {
        $out = ($out | insert custom_image $custom_image_section)
    }

    $out | to json
}

# Build: render bootstrap.sh and bsdinstall.script, write receipt
def "main build" [
    manifest_path: string
    --out: string = "./lsd-out"
] {
    if not ($manifest_path | path exists) {
        {error: $"manifest not found: ($manifest_path)", success: false} | to json
        return
    }

    let manifest = open $manifest_path
    let validation = validate_manifest $manifest

    if not $validation.valid {
        {
            success: false
            error: "manifest validation failed"
            errors: $validation.errors
            warnings: $validation.warnings
        } | to json
        return
    }

    # Create output directory
    mkdir $out

    let qemu = derive_qemu_params $manifest
    let built_at = (date now | format date "%Y-%m-%dT%H:%M:%SZ")

    # Render bootstrap.sh
    let bootstrap_content = render_bootstrap $manifest $qemu
    let bootstrap_path = ([$out, "bootstrap.sh"] | path join)
    $bootstrap_content | save --force $bootstrap_path

    # Render bsdinstall.script
    let bsdinstall_content = render_bsdinstall $manifest $qemu
    let bsdinstall_path = ([$out, "bsdinstall.script"] | path join)
    $bsdinstall_content | save --force $bsdinstall_path

    # Copy manifest
    let manifest_copy_path = ([$out, "manifest.toml"] | path join)
    open --raw $manifest_path | save --force $manifest_copy_path

    # Compute hashes
    let bootstrap_sha256 = (open --raw $bootstrap_path | hash sha256)
    let bsdinstall_sha256 = (open --raw $bsdinstall_path | hash sha256)
    let manifest_sha256 = (open --raw $manifest_path | hash sha256)
    let manifest_copy_sha256 = (open --raw $manifest_copy_path | hash sha256)

    let bootstrap_size = ($bootstrap_path | path exists | if $in { ls $bootstrap_path | first | get size } else { 0 })
    let bsdinstall_size = ($bsdinstall_path | path exists | if $in { ls $bsdinstall_path | first | get size } else { 0 })

    # Build receipt
    let receipt = {
        schema_version: $SCHEMA_VERSION
        built_at: $built_at
        manifest_sha256: $manifest_sha256
        artifacts: [
            {
                name: "bootstrap.sh"
                sha256: $bootstrap_sha256
                size_bytes: ($bootstrap_size | into int)
                role: "bootstrap-script"
            }
            {
                name: "bsdinstall.script"
                sha256: $bsdinstall_sha256
                size_bytes: ($bsdinstall_size | into int)
                role: "bsdinstall-script"
            }
            {
                name: "manifest.toml"
                sha256: $manifest_copy_sha256
                size_bytes: (open --raw $manifest_copy_path | str length)
                role: "manifest-copy"
            }
        ]
        tool: {
            name: "lsd"
            version: $LSD_VERSION
            commit: "unknown"
        }
        signing: {
            method: "none"
        }
        trust_level: "unsigned"
        warnings: $validation.warnings
    }

    let receipt_path = ([$out, "lsd-receipt.json"] | path join)
    $receipt | to json | save --force $receipt_path

    {
        success: true
        out_dir: $out
        artifacts: {
            bootstrap_sh: $bootstrap_path
            bsdinstall_script: $bsdinstall_path
            manifest_copy: $manifest_copy_path
            receipt: $receipt_path
        }
        receipt: $receipt
        warnings: $validation.warnings
    } | to json
}

# Verify: recompute artifact hashes and compare to receipt
def "main verify" [
    manifest_path: string
    receipt_path: string
] {
    if not ($manifest_path | path exists) {
        {verified: false, error: $"manifest not found: ($manifest_path)"} | to json
        return
    }
    if not ($receipt_path | path exists) {
        {verified: false, error: $"receipt not found: ($receipt_path)"} | to json
        return
    }

    let receipt = open $receipt_path
    let manifest_sha256_actual = (open --raw $manifest_path | hash sha256)
    let out_dir = ($receipt_path | path dirname)

    mut mismatches = []
    mut checks = []

    # Verify manifest hash
    if $manifest_sha256_actual == $receipt.manifest_sha256 {
        $checks = ($checks | append {file: $manifest_path, status: "ok", sha256: $manifest_sha256_actual})
    } else {
        $mismatches = ($mismatches | append {
            file: $manifest_path
            expected: $receipt.manifest_sha256
            actual: $manifest_sha256_actual
        })
        $checks = ($checks | append {file: $manifest_path, status: "MISMATCH", expected: $receipt.manifest_sha256, actual: $manifest_sha256_actual})
    }

    # Verify each artifact in receipt
    for artifact in $receipt.artifacts {
        let artifact_path = ([$out_dir, $artifact.name] | path join)
        if not ($artifact_path | path exists) {
            $mismatches = ($mismatches | append {file: $artifact_path, expected: $artifact.sha256, actual: "FILE_MISSING"})
            $checks = ($checks | append {file: $artifact_path, status: "MISSING"})
        } else {
            let actual_sha256 = (open --raw $artifact_path | hash sha256)
            if $actual_sha256 == $artifact.sha256 {
                $checks = ($checks | append {file: $artifact_path, status: "ok", sha256: $actual_sha256})
            } else {
                $mismatches = ($mismatches | append {
                    file: $artifact_path
                    expected: $artifact.sha256
                    actual: $actual_sha256
                })
                $checks = ($checks | append {file: $artifact_path, status: "MISMATCH", expected: $artifact.sha256, actual: $actual_sha256})
            }
        }
    }

    {
        verified: (($mismatches | length) == 0)
        schema_version: $SCHEMA_VERSION
        receipt_built_at: $receipt.built_at
        trust_level: $receipt.trust_level
        checks: $checks
        mismatches: $mismatches
        summary: (if (($mismatches | length) == 0) {
            $"All ($checks | length) artifacts verified OK"
        } else {
            $"($mismatches | length) of ($checks | length) artifacts FAILED verification"
        })
    } | to json
}

def "main" [] {
    {
        tool: "lsd"
        version: $LSD_VERSION
        description: "Linux→BSD Stomper Deploy — QEMU trampoline installer for cloud providers that only support Linux"
        schema_version: $SCHEMA_VERSION
        subcommands: {
            catalog:  "List supported (provider, base, arch) tuples as JSON"
            schema:   "Emit JSON Schema for lsd.toml manifests"
            describe: "describe <manifest.toml> — structured plan: provider, installer URL, IMDS endpoint, warnings"
            build:    "build <manifest.toml> [--out <dir>] — render bootstrap.sh, bsdinstall.script, and lsd-receipt.json"
            verify:   "verify <manifest.toml> <receipt.json> — recompute and compare artifact hashes"
        }
        ax_first: {
            discovery: "nu lsd.nu catalog"
            schema:    "nu lsd.nu schema"
            cold_start: "Three calls: catalog → schema → describe <manifest> and an LM knows what to feed build"
        }
        license: "BSD-2-Clause"
        reference: "github.com/depenguin-me/depenguin-run (MIT) — generalized, not copied"
    } | to json
}
