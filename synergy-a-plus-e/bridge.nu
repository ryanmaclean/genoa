#!/usr/bin/env nu
# SPDX-License-Identifier: BSD-2-Clause
#
# bridge.nu — A+E synergy bridge
# Reads a unified.toml, calls genoa describe on the [image] section,
# synthesises an lsd manifest from the [deploy] section, calls lsd describe,
# and emits a unified structured JSON plan showing:
#   - A's image build steps
#   - the artifact handoff point (raw .img path + sha256)
#   - E's trampoline steps (adapted for custom_image mode)
#
# Usage:
#   nu bridge.nu plan <unified.toml>
#   nu bridge.nu schema
#   nu bridge.nu version
#
# AX-first: every subcommand emits structured JSON.
# Schema: synergy/v0
#
# Seam documentation (see SYNERGY-REPORT.md for full analysis):
#   A produces: out/image/<name>-<version>.raw  +  out/image/<name>-<version>.receipt.json
#   E consumes: a raw block-device image at an HTTP(S) URL or local path
#   Bridge role: read A's receipt → inject image path + sha256 into E's bootstrap.sh template
#                replacing the mfsBSD ISO fetch with a direct dd of the genoa image.

const BRIDGE_VERSION = "0.1.0"
const GENOA_CLI  = "/Users/studio/genoa/option-a-smolbsd/genoa.nu"
const LSD_CLI    = "/Users/studio/genoa/option-e-lsd/lsd.nu"

# ── Entry point ────────────────────────────────────────────────────────────────

def main [] {
    {
        tool: "bridge"
        version: $BRIDGE_VERSION
        description: "A+E synergy bridge — unifies genoa (image build) + lsd (cloud deploy) into one plan"
        subcommands: {
            plan:    "plan <unified.toml>  — emit a unified JSON plan: A build steps + artifact handoff + E trampoline steps"
            schema:  "schema  — describe the unified.toml format and the two sub-schemas it spans"
            version: "version  — print bridge version"
        }
        seam_summary: {
            a_output: "raw .img file + receipt.json with image_sha256"
            e_input: "URL or path to raw image; bootstrap.sh dd-writes it to the target disk"
            bridge_role: "read A receipt → rewrite E bootstrap template substitution point from mfsBSD ISO fetch to genoa raw image dd"
            substitution_point: "bsdinstall.script DISTRIBUTIONS + BSDINSTALL_DISTSITE replaced by: dd if=<genoa.img> of=/dev/vtbd0 bs=8M"
        }
        ax_discovery: "Three calls: bridge version | bridge schema | bridge plan <unified.toml>"
    } | to json --indent 2 | print
}

def "main version" [] {
    {tool: "bridge", version: $BRIDGE_VERSION, genoa_cli: $GENOA_CLI, lsd_cli: $LSD_CLI} | to json | print
}

def "main schema" [] {
    {
        schema_version: "synergy/v0.1.0"
        description: "unified.toml spans two sub-schemas. bridge.nu splits and routes each section."
        top_level_keys: {
            unified_schema_version: "synergy version string — must start with 'v0'"
            description: "human-readable description of the combined deployment"
        }
        section_a: {
            keys: ["image", "target", "kernel", "packages", "agent", "network", "signing", "metadata"]
            tool: "genoa"
            schema_url: $"file://($GENOA_CLI | path dirname)/schema/manifest.v1.json"
            note: "These keys are passed verbatim to a generated genoa manifest. The [target] here means build target (arch/platform), NOT cloud provider."
        }
        section_e: {
            keys: ["deploy", "deploy.base", "deploy.network", "deploy.trust"]
            tool: "lsd"
            schema_url: $"file://($LSD_CLI | path dirname)/schema/manifest.v1.json"
            note: "deploy.* is translated to an lsd manifest. bridge.nu renames [deploy] → [target], [deploy.base] → [base], etc. The deploy.base.mode field is NEW — not in lsd v1 schema — and drives custom_image vs mfsbsd install strategy."
        }
        conflicts: [
            {
                key: "target"
                a_meaning: "Build target: OS, arch, platform (rpi5/qemu), build_host SSH"
                e_meaning: "Cloud provider, plan (cax11), region — completely different concept"
                resolution: "unified.toml uses [target] for A (genoa convention) and [deploy] for E. bridge.nu translates."
            }
            {
                key: "schema_version / lsd_schema_version"
                a_meaning: "genoa uses schema_version = 'v1' (string const)"
                e_meaning: "lsd uses lsd_schema_version = '1.0.0' (SemVer)"
                resolution: "Different key names avoid collision. No action needed."
            }
            {
                key: "network"
                a_meaning: "NIC interface, DHCP mode, hostname — baked into image rc.conf"
                e_meaning: "SSH keys array, hostname for bsdinstall — written to target disk during install"
                resolution: "Hostname is shared; SSH keys are E-only; NIC interface is A-only. bridge.nu copies hostname into both sections."
            }
            {
                key: "trust (E) / signing (A)"
                a_meaning: "signify signing tool + key paths for the image artifact"
                e_meaning: "mfsBSD ISO sha256 + provenance URL + optional callback"
                resolution: "Different names, different semantics. No collision. In custom_image mode, E's trust.mfs_image_sha256 is replaced by deploy.base.custom_image_sha256 from A's receipt."
            }
        ]
        new_fields_needed: [
            {
                tool: "lsd"
                field: "base.mode"
                type: "string enum: mfsbsd | custom_image"
                purpose: "When custom_image: skip mfsBSD ISO fetch; dd a pre-built raw image to the target disk instead of running bsdinstall"
            }
            {
                tool: "lsd"
                field: "base.custom_image_url"
                type: "string (file:// or https://)"
                purpose: "URL/path to the genoa-produced raw image. Filled by bridge.nu from A's receipt."
            }
            {
                tool: "lsd"
                field: "base.custom_image_sha256"
                type: "string (64 hex chars)"
                purpose: "SHA-256 of the genoa raw image for bootstrap.sh verification. Filled from A's receipt.hashes.image_sha256."
            }
            {
                tool: "genoa"
                field: "image.export_url"
                type: "string (https://)"
                purpose: "Optional: URL where the built image will be hosted, so lsd/bridge can inject it into bootstrap.sh without manual copying."
            }
        ]
    } | to json --indent 2 | print
}

# ── main plan ─────────────────────────────────────────────────────────────────

def "main plan" [unified_path: string] {
    if not ($unified_path | path exists) {
        {error: "unified_manifest_not_found", path: $unified_path} | to json | print
        exit 1
    }

    let unified = open --raw $unified_path | from toml

    # Validate top-level
    let schema_ver = $unified | get unified_schema_version? | default ""
    if not ($schema_ver =~ '^v0') {
        {
            error: "unsupported_unified_schema_version"
            got: $schema_ver
            expected: "v0.x.x"
        } | to json | print
        exit 1
    }

    # ── Step 1: Write a temporary genoa manifest from the unified.toml ──────────
    let tmp_dir = "/tmp/bridge-plan"
    ^mkdir -p $tmp_dir
    let genoa_manifest_path = ([$tmp_dir "genoa-manifest.toml"] | path join)
    write_genoa_manifest $unified $genoa_manifest_path

    # ── Step 2: Call genoa describe (cross-directory invocation) ────────────────
    let genoa_plan = call_genoa_describe $genoa_manifest_path

    # ── Step 3: Synthesise a lsd manifest from [deploy.*] ─────────────────────
    let lsd_manifest_path = ([$tmp_dir "lsd-manifest.toml"] | path join)
    let deploy = $unified | get deploy? | default {}
    write_lsd_manifest $unified $deploy $lsd_manifest_path

    # ── Step 4: Call lsd describe ───────────────────────────────────────────────
    let lsd_plan = call_lsd_describe $lsd_manifest_path

    # ── Step 5: Determine artifact handoff point ─────────────────────────────────
    let image_name = $unified.image.name
    let image_ver  = $unified.image.version
    let image_fmt  = $unified.image.format
    let output_dir = $unified.image | get output_dir? | default "./out/image"
    let image_path = ([$output_dir $"($image_name)-($image_ver).($image_fmt)"] | path join)
    let receipt_path = ([$output_dir $"($image_name)-($image_ver).receipt.json"] | path join)

    let deploy_base = $deploy | get base? | default {}
    let mode = $deploy_base | get mode? | default "mfsbsd"
    let custom_url = $deploy_base | get custom_image_url? | default ""
    let custom_sha = $deploy_base | get custom_image_sha256? | default ""

    let handoff = {
        description: "This is the seam where A's output becomes E's input."
        a_produces: {
            image_file: $image_path
            receipt_file: $receipt_path
            image_sha256: "(computed at build time — read from receipt.hashes.image_sha256)"
        }
        e_consumes: {
            mode: $mode
            note: (if $mode == "custom_image" {
                "bootstrap.sh will dd the genoa raw image directly to the target disk. mfsBSD + bsdinstall are bypassed entirely."
            } else {
                "mfsBSD mode: E uses bsdinstall to install stock FreeBSD. A's image is NOT used. Set deploy.base.mode='custom_image' to enable synergy."
            })
            custom_image_url: (if $custom_url == "" { "(not set — bridge.nu would populate from receipt after genoa build)" } else { $custom_url })
            custom_image_sha256: (if $custom_sha == "" { "(not set — bridge.nu would populate from receipt)" } else { $custom_sha })
            bootstrap_substitution: (if $mode == "custom_image" {
                "Replace: curl mfsBSD ISO + bsdinstall script  →  With: dd if=<image.raw> of=/dev/sda bs=8M conv=fdatasync"
            } else {
                "No substitution — stock mfsBSD install path"
            })
        }
        scp_command_example: $"scp ($image_path) root@rescue-host:/tmp/genoa.img  # then bootstrap.sh dd-writes it"
        lsd_changes_required: [
            "Add base.mode = 'custom_image' support to render_bootstrap and render_bsdinstall"
            "Add base.custom_image_url and base.custom_image_sha256 fields to lsd schema"
            "In custom_image mode: bootstrap.sh fetches+verifies the raw image, dd-writes it, skips QEMU entirely OR uses QEMU to write it safely"
        ]
    }

    # ── Step 6: Compose the unified plan ────────────────────────────────────────
    {
        schema_version: "synergy/v0.1.0"
        bridge_version: $BRIDGE_VERSION
        unified_manifest: $unified_path
        deploy_mode: $mode
        plan: {
            phase_1_image_build: {
                tool: "genoa"
                manifest: $genoa_manifest_path
                description: "Build the FreeBSD raw image with ii-agent baked in. Runs on a FreeBSD build host."
                genoa_plan: $genoa_plan
            }
            artifact_handoff: $handoff
            phase_2_cloud_deploy: {
                tool: "lsd"
                manifest: $lsd_manifest_path
                description: "Deploy the image to a cloud CAX11 instance via rescue boot. Runs from the engineer's workstation or a CI runner."
                lsd_plan: $lsd_plan
                custom_image_delta: (if $mode == "custom_image" {
                    {
                        bootstrap_sh_diff: "fetch_and_verify_iso() is replaced by fetch_and_verify_image() using custom_image_url + custom_image_sha256"
                        boot_mfsbsd_diff: "boot_mfsbsd() is replaced by write_image_to_disk(): dd if=/tmp/genoa.img of=$TARGET_DISK bs=8M conv=fdatasync"
                        bsdinstall_script_diff: "Entire bsdinstall.script is dropped — genoa's image already has rc.conf, SSH keys are injected via cloud-init or a second pass"
                        ssh_key_injection: "SSH keys still need injection. Options: (a) bake them into genoa image via [network.ssh_keys] new field, (b) mount image post-dd and write .ssh/authorized_keys, (c) use provider IMDS at first boot"
                        net_result: "QEMU is still used for safety (writing a live disk from within the OS running on it is dangerous) — QEMU passthrough replaces bsdinstall with a raw dd"
                    }
                } else { null })
            }
        }
        synergy_assessment: {
            composable: "PARTIAL"
            blocker: "E has no 'custom_image' install mode. Its bsdinstall.script always fetches stock .txz from download.freebsd.org. A's image cannot be substituted without patching E."
            easiest_path: "Add 10-20 lines to lsd.nu render_bootstrap() + render_bsdinstall() to handle base.mode='custom_image'. No changes to genoa needed."
            score: 6
        }
    } | to json --indent 2 | print
}

# ── Helpers: write sub-manifests ──────────────────────────────────────────────

def write_genoa_manifest [unified: record, path: string] {
    # Extract only the genoa-relevant keys
    let genoa = {
        schema_version: "v1"
        image:    $unified.image
        target:   $unified.target
        kernel:   $unified.kernel
        packages: ($unified | get packages? | default {})
        agent:    $unified.agent
        network:  $unified.network
        signing:  ($unified | get signing? | default {tool: "none"})
        metadata: ($unified | get metadata? | default {})
    }
    $genoa | to toml | save --force $path
}

def write_lsd_manifest [unified: record, deploy: record, path: string] {
    let deploy_base = $deploy | get base? | default {}
    let deploy_net  = $deploy | get network? | default {}
    let deploy_trust = $deploy | get trust? | default {mfs_image_sha256: "0000000000000000000000000000000000000000000000000000000000000000"}

    # lsd uses "target" for provider/plan/region (different from genoa's "target")
    let lsd = {
        lsd_schema_version: "1.0.0"
        target: {
            provider: ($deploy | get provider? | default "hetzner-cloud")
            plan:     ($deploy | get plan? | default "cax11")
            region:   ($deploy | get region? | default "nbg1")
        }
        base: {
            os:         ($deploy_base | get os? | default $unified.target.os)
            version:    ($deploy_base | get version? | default $unified.target.os_version)
            arch:       ($deploy_base | get arch? | default $unified.target.arch)
            filesystem: ($deploy_base | get filesystem? | default "zfs")
            mfsbsd_url: "https://mfsbsd.vx.sk/files/iso/15/aarch64/mfsbsd-se-15.0-RELEASE-arm64-aarch64.iso"
        }
        network: {
            ssh_keys: ($deploy_net | get ssh_keys? | default ["ssh-ed25519 PLACEHOLDER"])
            hostname: ($deploy_net | get hostname? | default $unified.network.hostname)
            ipv6:     ($deploy_net | get ipv6? | default false)
        }
        trust: $deploy_trust
    }
    $lsd | to toml | save --force $path
}

# ── Helpers: invoke sub-CLIs ─────────────────────────────────────────────────

def call_genoa_describe [manifest_path: string] {
    let result = try {
        ^nu $GENOA_CLI describe $manifest_path | from json
    } catch {
        {
            error: "genoa_describe_failed"
            note: "genoa.nu may require a FreeBSD build host or specific env. Returning structured stub."
            manifest: $manifest_path
            stub: true
            plan_type: "build_plan"
            build_steps: [
                {step: 1, label: "prepare_output_dir",   real: true,  cmd: "mkdir -p ./out/image"}
                {step: 2, label: "verify_src_tree",       real: true,  cmd: "test -d /usr/src && freebsd-version -k"}
                {step: 3, label: "place_kernel_config",   real: true,  cmd: "cp GENERIC.conf /usr/src/sys/arm64/conf/GENERIC"}
                {step: 4, label: "place_release_conf",    real: true,  cmd: "cp smolbsd-qemu.conf /usr/src/release/tools/smolbsd-qemu.conf"}
                {step: 5, label: "buildworld",            real: false, stub_reason: "STUB: 2-8 hours on build host"}
                {step: 6, label: "buildkernel",           real: false, stub_reason: "STUB: 30-90 min on build host"}
                {step: 7, label: "pkgbase_packages",      real: false, stub_reason: "STUB: 30-60 min"}
                {step: 8, label: "build_vm_image",        real: false, stub_reason: "STUB: produces raw image"}
                {step: 9, label: "fetch_agent",           real: false, stub_reason: "STUB: fetch ii-agent binary"}
                {step: 10, label: "install_agent",        real: false, stub_reason: "STUB: mount image, install agent"}
                {step: 11, label: "copy_image_to_output", real: false, stub_reason: "STUB: copy to out/image/"}
                {step: 12, label: "emit_receipt",         real: true,  cmd: "nu genoa.nu _emit_receipt <image> > <receipt.json>"}
            ]
        }
    }
    $result
}

def call_lsd_describe [manifest_path: string] {
    let result = try {
        ^nu $LSD_CLI describe $manifest_path | from json
    } catch {
        {
            error: "lsd_describe_failed"
            note: "lsd.nu describe invocation failed — returning structured stub."
            manifest: $manifest_path
            stub: true
            plan: {
                provider: "hetzner-cloud"
                plan: "cax11"
                region: "nbg1"
                rescue_method: "api-rescue-boot"
                trampoline_strategy: "rescue-qemu-passthrough"
                base_os: "freebsd"
                base_version: "15.0-RELEASE"
                arch: "aarch64"
                filesystem: "zfs"
            }
            next_steps: [
                "1. Activate rescue boot for cax11 in Hetzner Cloud console/API"
                "2. SSH into rescue environment (Debian 12)"
                "3. Run bootstrap.sh (generated by lsd build)"
                "4. Wait 15-45 min for install to complete"
                "5. Hard-reboot into FreeBSD"
            ]
        }
    }
    $result
}
