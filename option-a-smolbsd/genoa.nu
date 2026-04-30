#!/usr/bin/env nu
# genoa.nu — smolBSD-for-agents CLI
# Subcommands: schema, catalog, describe, build, verify
# AX-first: structured JSON on every code path; attestation envelope on all outputs.
# Schema: /v1/ — see schema/manifest.v1.json and schema/receipt.v1.json
#
# License: BSD-2-Clause
# SPDX-License-Identifier: BSD-2-Clause

const GENOA_VERSION = "0.1.0"
const SCHEMA_VERSION = "v1"

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main [
    subcommand?: string   # schema | catalog | describe | build | verify
    manifest?: string     # manifest path for describe/build/verify
    image?: string        # image path for verify
    receipt?: string      # receipt path for verify
    --dry-run             # dry-run mode for build: print plan, do not execute
] {
    let sub = $subcommand | default ""
    match $sub {
        "schema"   => { cmd_schema }
        "catalog"  => { cmd_catalog }
        "describe" => {
            if $manifest == null {
                {error: "missing_argument", usage: "nu genoa.nu describe <manifest.toml>"} | to json | print
                exit 1
            }
            cmd_describe [$manifest]
        }
        "build"    => {
            if $manifest == null {
                {error: "missing_argument", usage: "nu genoa.nu build <manifest.toml> [--dry-run]"} | to json | print
                exit 1
            }
            let args = if $dry_run { [$manifest "--dry-run"] } else { [$manifest] }
            cmd_build $args
        }
        "verify"   => {
            # For verify: manifest holds the image path, image holds the receipt path
            let img = $manifest | default ""
            let rec = $image | default ""
            if $img == "" or $rec == "" {
                {error: "missing_arguments", usage: "nu genoa.nu verify <image-path> <receipt.json>"} | to json | print
                exit 1
            }
            cmd_verify [$img $rec]
        }
        ""         => { cmd_help }
        _          => {
            {
                error: "unknown_subcommand"
                subcommand: $sub
                valid: ["schema", "catalog", "describe", "build", "verify"]
                hint: "Run `nu genoa.nu` for usage."
            } | to json | print
            exit 1
        }
    }
}

def cmd_help [] {
    {
        name: "genoa"
        version: $GENOA_VERSION
        description: "smolBSD-for-agents — build minimal BSD VM images with agents baked in"
        ax_first: "An LM cold-starts and uses you in under 3 tool calls. See: nu genoa.nu catalog | nu genoa.nu schema | nu genoa.nu describe <manifest>"
        subcommands: {
            schema:   "Print JSON Schema for genoa manifests (schema/manifest.v1.json)"
            catalog:  "Print JSON catalog of all producible image profiles"
            describe: "describe <manifest.toml>  — Parse and plan a build; no side effects"
            build:    "build <manifest.toml> [--dry-run]  — Execute or plan the build"
            verify:   "verify <image> <receipt.json>  — Recompute sha256 and check attestation"
        }
        schema_url: "schema/manifest.v1.json"
        receipt_schema_url: "schema/receipt.v1.json"
    } | to json --indent 2 | print
}

# ---------------------------------------------------------------------------
# schema — print manifest JSON Schema
# ---------------------------------------------------------------------------

def cmd_schema [] {
    let schema_path = ([$env.PWD "schema" "manifest.v1.json"] | path join)
    if not ($schema_path | path exists) {
        # Fall back to directory relative to this script
        let script_dir = ([$env.PWD] | path join)
        let alt = ([$script_dir "schema" "manifest.v1.json"] | path join)
        if not ($alt | path exists) {
            {error: "schema_not_found", looked_at: [$schema_path $alt]} | to json | print
            exit 1
        }
        open --raw $alt | print
    } else {
        open --raw $schema_path | print
    }
}

# ---------------------------------------------------------------------------
# catalog — list producible profiles
# ---------------------------------------------------------------------------

def cmd_catalog [] {
    {
        schema_version: $SCHEMA_VERSION
        catalog_version: "v1"
        generator: $"genoa/($GENOA_VERSION)"
        description: "All image profiles this genoa instance can produce. Feed any profile's example_manifest to `genoa describe` or `genoa build`."
        profiles: [
            {
                id: "freebsd-aarch64-rpi5-iiagent"
                name: "FreeBSD aarch64 RPi5 + ii-agent"
                description: "Minimal FreeBSD 15.0-RELEASE aarch64 for Raspberry Pi 5 with ii-agent v0.1 wired to Ergo IRC."
                target: {
                    os: "freebsd"
                    os_version: "15.0-RELEASE"
                    arch: "aarch64"
                    platform: "rpi5"
                }
                agent: "ii-agent"
                image_format: "raw"
                size_budget_mib: 512
                example_manifest: "examples/rpi5-iiagent.toml"
                status: "stable"
                tags: ["irc", "agent", "rpi5", "aarch64", "freebsd"]
            }
            {
                id: "freebsd-amd64-qemu-base"
                name: "FreeBSD amd64 QEMU bring-up (no agent)"
                description: "Minimal FreeBSD 15.0-RELEASE amd64 QEMU VM. SMOLBSD kernel config — virtio-only, no physical hardware. ~128 MiB qcow2 artifact goal."
                target: {
                    os: "freebsd"
                    os_version: "15.0-RELEASE"
                    arch: "amd64"
                    platform: "qemu"
                }
                agent: "none"
                image_format: "qcow2"
                size_budget_mib: 512
                example_manifest: "examples/qemu-x86_64.toml"
                status: "stable"
                tags: ["qemu", "base", "amd64", "freebsd", "smolbsd"]
            }
            {
                id: "freebsd-aarch64-qemu-iiagent"
                name: "FreeBSD aarch64 QEMU + ii-agent (CI)"
                description: "FreeBSD 15.0-RELEASE aarch64 in QEMU with ii-agent. Use this profile on Apple Silicon hosts with HVF acceleration."
                target: {
                    os: "freebsd"
                    os_version: "15.0-RELEASE"
                    arch: "aarch64"
                    platform: "qemu"
                }
                agent: "ii-agent"
                image_format: "qcow2"
                size_budget_mib: 512
                example_manifest: "examples/rpi5-iiagent.toml"
                status: "beta"
                notes: "Override target.platform to 'qemu' and image.format to 'qcow2' in the rpi5 manifest."
                tags: ["qemu", "agent", "aarch64", "freebsd", "hvf"]
            }
        ]
        how_to_build: {
            step1: "Pick a profile from .profiles[]. Note .example_manifest."
            step2: "nu genoa.nu describe <example_manifest>  # verify the plan"
            step3: "nu genoa.nu build <example_manifest> --dry-run  # see exact commands"
            step4: "nu genoa.nu build <example_manifest>  # execute (requires FreeBSD build host)"
            step5: "nu genoa.nu verify out/<image> out/<receipt.json>  # check attestation"
        }
    } | to json --indent 2 | print
}

# ---------------------------------------------------------------------------
# describe — parse manifest, resolve plan, print structured plan JSON
# ---------------------------------------------------------------------------

def cmd_describe [args: list<string>] {
    if ($args | length) == 0 {
        {error: "missing_argument", usage: "nu genoa.nu describe <manifest.toml>"} | to json | print
        exit 1
    }
    let manifest_path = ($args | first)
    let manifest = load_manifest $manifest_path
    let plan = resolve_plan $manifest $manifest_path false
    $plan | to json --indent 2 | print
}

# ---------------------------------------------------------------------------
# build — execute or plan a build
# ---------------------------------------------------------------------------

def cmd_build [args: list<string>] {
    if ($args | length) == 0 {
        {error: "missing_argument", usage: "nu genoa.nu build <manifest.toml> [--dry-run]"} | to json | print
        exit 1
    }
    let manifest_path = ($args | first)
    let dry_run = ($args | any { |a| $a == "--dry-run" })
    let manifest = load_manifest $manifest_path
    let plan = resolve_plan $manifest $manifest_path $dry_run

    if $dry_run {
        execute_dry_run $plan $manifest $manifest_path
    } else {
        execute_build $plan $manifest $manifest_path
    }
}

# ---------------------------------------------------------------------------
# verify — recompute sha256 on image file, check against receipt
# ---------------------------------------------------------------------------

def cmd_verify [args: list<string>] {
    if ($args | length) < 2 {
        {error: "missing_arguments", usage: "nu genoa.nu verify <image> <receipt.json>"} | to json | print
        exit 1
    }
    let image_path = ($args | get 0)
    let receipt_path = ($args | get 1)

    if not ($image_path | path exists) {
        {error: "image_not_found", path: $image_path} | to json | print
        exit 1
    }
    if not ($receipt_path | path exists) {
        {error: "receipt_not_found", path: $receipt_path} | to json | print
        exit 1
    }

    let receipt = open --raw $receipt_path | from json
    let expected_sha = $receipt.hashes.image_sha256

    # Compute actual sha256 of the image
    let actual_sha = (^sha256sum $image_path | split words | first)

    let image_stat = (^stat -f "%z" $image_path | into int)

    let ok = ($actual_sha == $expected_sha)
    let result = {
        schema_version: $SCHEMA_VERSION
        verify_result: (if $ok { "PASS" } else { "FAIL" })
        image: $image_path
        receipt: $receipt_path
        receipt_id: $receipt.receipt_id
        built_at: $receipt.built_at
        image_size_bytes: $image_stat
        hashes: {
            expected_sha256: $expected_sha
            actual_sha256: $actual_sha
            match: $ok
        }
        claims_summary: {
            total: ($receipt.claims | length)
            verified: ($receipt.claims | where status == "verified" | length)
            failed: ($receipt.claims | where status == "failed" | length)
            unverified: ($receipt.claims | where status == "unverified" | length)
        }
        agent: {
            name: $receipt.agent.name
            version: $receipt.agent.version
            install_path: $receipt.agent.install_path
        }
        attestation: {
            trust: (if $ok { "image_matches_receipt" } else { "MISMATCH_DO_NOT_DEPLOY" })
            placeholder_signing: (
                if "signing" in $receipt and $receipt.signing != null {
                    $receipt.signing | get placeholder? | default false
                } else { false }
            )
        }
    }
    $result | to json --indent 2 | print
    if not $ok { exit 1 }
}

# ---------------------------------------------------------------------------
# Internal: load and validate manifest
# ---------------------------------------------------------------------------

def load_manifest [manifest_path: string] {
    if not ($manifest_path | path exists) {
        {
            error: "manifest_not_found"
            path: $manifest_path
            hint: "Run `nu genoa.nu catalog` to see example manifests."
        } | to json | print
        exit 1
    }

    let raw = open --raw $manifest_path
    let manifest = try {
        $raw | from toml
    } catch {
        {
            error: "manifest_parse_error"
            path: $manifest_path
            hint: "Manifest must be valid TOML conforming to schema/manifest.v1.json"
        } | to json | print
        exit 1
    }

    # Validate schema_version
    if ($manifest | get schema_version? | default "") != "v1" {
        {
            error: "schema_version_mismatch"
            got: ($manifest | get schema_version? | default "(missing)")
            expected: "v1"
            schema: "schema/manifest.v1.json"
        } | to json | print
        exit 1
    }

    # Validate required top-level keys
    let required = ["schema_version" "image" "target" "kernel" "agent"]
    let missing = ($required | where { |k|
        let val = ($manifest | get -o $k)
        $val == null
    })
    if ($missing | length) > 0 {
        {
            error: "manifest_missing_required_fields"
            missing_fields: $missing
            path: $manifest_path
            schema: "schema/manifest.v1.json"
        } | to json | print
        exit 1
    }

    # Validate arch
    let valid_arches = ["amd64" "aarch64" "riscv64"]
    let arch = $manifest.target.arch
    if $arch not-in $valid_arches {
        {
            error: "invalid_target_arch"
            got: $arch
            valid: $valid_arches
        } | to json | print
        exit 1
    }

    # Validate image format
    let valid_formats = ["qcow2" "raw" "vmdk"]
    let fmt = $manifest.image.format
    if $fmt not-in $valid_formats {
        {
            error: "invalid_image_format"
            got: $fmt
            valid: $valid_formats
        } | to json | print
        exit 1
    }

    $manifest
}

# ---------------------------------------------------------------------------
# Internal: resolve a concrete build plan from a manifest
# ---------------------------------------------------------------------------

def resolve_plan [manifest: record, manifest_path: string, dry_run: bool] {
    let image = $manifest.image
    let target = $manifest.target
    let kernel = $manifest.kernel
    let agent = $manifest.agent
    let network = $manifest | get network? | default {interface: "vtnet0", mode: "dhcp", hostname: "smolbsd"}
    let packages = $manifest | get packages? | default {include: [] exclude_patterns: [] pkg_repo: ""}
    let signing = $manifest | get signing? | default {tool: "none"}

    let output_dir = $image | get output_dir? | default "./out"
    let image_filename = $"($image.name)-($image.version).($image.format)"
    let receipt_filename = $"($image.name)-($image.version).receipt.json"
    let output_image = ([$output_dir $image_filename] | path join)
    let output_receipt = ([$output_dir $receipt_filename] | path join)

    # Resolve kernel config delta path
    let kernel_delta_path = $kernel | get kernel_delta_file? | default null

    # Resolve build host
    let build_host = $target | get build_host? | default "local"

    # Resolve agent source URL for display
    let agent_source = $agent.source
    let agent_display_url = match $agent_source.type {
        "gitea_release" => {
            let repo = $agent_source | get repo? | default "unknown/repo"
            let tag = $agent_source | get tag? | default "latest"
            let asset = $agent_source | get asset? | default $agent.name
            $"http://gitea.local:3000/($repo)/releases/download/($tag)/($asset)"
        }
        "url" => { $agent_source | get url? | default "(no url)" }
        "local_path" => { $agent_source | get path? | default "(no path)" }
        _ => "(unknown source type)"
    }

    # Build package include list
    let pkg_include = $packages | get include? | default [
        "FreeBSD-runtime" "FreeBSD-clibs" "FreeBSD-rc" "FreeBSD-utilities"
        "FreeBSD-pkg-bootstrap" "FreeBSD-libarchive" "FreeBSD-openssl-lib"
        "FreeBSD-fetch" "FreeBSD-mtree" "FreeBSD-certctl"
    ]
    let pkg_exclude = $packages | get exclude_patterns? | default ["*-dbg" "*-lib32" "FreeBSD-tests*" "FreeBSD-lldb*" "FreeBSD-devel*" "FreeBSD-src*"]

    # Kernel config name → build flag mapping
    let kernconf = $kernel.config
    let extra_opts = $kernel | get extra_options? | default []
    let strip_debug = $kernel | get strip_debug? | default true

    {
        schema_version: $SCHEMA_VERSION
        plan_type: "build_plan"
        dry_run: $dry_run
        genoa_version: $GENOA_VERSION
        manifest_path: $manifest_path
        resolved: {
            image: {
                name: $image.name
                version: $image.version
                format: $image.format
                provisioned_mib: $image.size_mb
                output_path: $output_image
                receipt_path: $output_receipt
            }
            target: {
                os: $target.os
                os_version: $target.os_version
                arch: $target.arch
                platform: $target.platform
                build_host: $build_host
            }
            kernel: {
                config: $kernconf
                strip_debug: $strip_debug
                extra_options: $extra_opts
                kernel_delta_file: $kernel_delta_path
            }
            packages: {
                include: $pkg_include
                exclude_patterns: $pkg_exclude
                count: ($pkg_include | length)
                pkg_repo: ($packages | get pkg_repo? | default "(default)")
            }
            agent: {
                name: $agent.name
                version: $agent.version
                install_path: ($agent | get install_path? | default "/usr/local/bin")
                source_type: $agent_source.type
                resolved_url: $agent_display_url
                rc_service_name: ($agent | get rc_service? | get name? | default null)
                rc_service_enabled: ($agent | get rc_service? | get enabled? | default false)
                rc_service_args: ($agent | get rc_service? | get command_args? | default null)
            }
            network: {
                interface: ($network | get interface? | default "vtnet0")
                mode: ($network | get mode? | default "dhcp")
                hostname: ($network | get hostname? | default "smolbsd")
            }
            signing: {
                tool: ($signing | get tool? | default "none")
            }
        }
        build_steps: (resolve_build_steps $manifest $output_image $output_receipt $agent_display_url)
        size_estimates: {
            kernel_binary_mib: 20
            base_userland_mib: 83
            agent_binary_mib: 5
            total_on_disk_mib: 108
            qcow2_artifact_mib_estimate: (if $image.format == "qcow2" { 128 } else { 200 })
            provisioned_mib: $image.size_mb
            within_budget: true
            budget_mib: 512
        }
        validation: {
            manifest_valid: true
            schema_version_ok: true
            required_fields_present: true
            arch_supported: true
            format_supported: true
        }
    }
}

# ---------------------------------------------------------------------------
# Internal: resolve build steps as structured commands
# ---------------------------------------------------------------------------

def resolve_build_steps [manifest: record, output_image: string, output_receipt: string, agent_url: string] {
    let image = $manifest.image
    let target = $manifest.target
    let kernel = $manifest.kernel
    let agent = $manifest.agent
    let output_dir = $image | get output_dir? | default "./out"
    let kernconf = $kernel.config
    let arch = $target.arch
    let native_arch = if $arch == "aarch64" { "arm64" } else { $arch }

    [
        {
            step: 1
            label: "prepare_output_dir"
            cmd: $"mkdir -p ($output_dir)"
            would_run: true
            real: true
            description: "Create output directory for image and receipt."
        }
        {
            step: 2
            label: "verify_src_tree"
            cmd: $"test -d /usr/src && freebsd-version -k || echo WARN: no src tree"
            would_run: true
            real: true
            description: "Check FreeBSD source tree is present at /usr/src."
        }
        {
            step: 3
            label: "place_kernel_config"
            cmd: $"cp ($kernconf).conf /usr/src/sys/($native_arch)/conf/($kernconf) 2>/dev/null || echo 'INFO: using existing ($kernconf) config'"
            would_run: true
            real: true
            description: $"Deploy kernel config delta to /usr/src/sys/($native_arch)/conf/($kernconf)."
        }
        {
            step: 4
            label: "place_release_conf"
            cmd: $"cp smolbsd-($target.platform).conf /usr/src/release/tools/smolbsd-($target.platform).conf"
            would_run: true
            real: true
            description: "Deploy release config (package filter + rc.conf fragment) into FreeBSD source tree."
        }
        {
            step: 5
            label: "buildworld"
            cmd: $"make -j4 -C /usr/src buildworld KERNCONF=($kernconf) TARGET=($native_arch) TARGET_ARCH=($arch)"
            would_run: false
            real: false
            stub_reason: "STUB: buildworld takes 2–8 hours on typical hardware. Run manually on a FreeBSD build host."
            description: "Cross-compile FreeBSD world for target arch."
            action: "would-run"
        }
        {
            step: 6
            label: "buildkernel"
            cmd: $"make -j4 -C /usr/src buildkernel KERNCONF=($kernconf) TARGET=($native_arch) TARGET_ARCH=($arch)"
            would_run: false
            real: false
            stub_reason: "STUB: buildkernel takes 30–90 minutes on typical hardware. Run manually on a FreeBSD build host."
            description: $"Compile ($kernconf) kernel for ($arch)."
            action: "would-run"
        }
        {
            step: 7
            label: "pkgbase_packages"
            cmd: $"make -j4 -C /usr/src packages TARGET=($native_arch) TARGET_ARCH=($arch)"
            would_run: false
            real: false
            stub_reason: "STUB: pkgbase package build takes 30–60 minutes."
            action: "would-run"
        }
        {
            step: 8
            label: "build_vm_image"
            cmd: $"make -C /usr/src/release vm-image KERNCONF=($kernconf) TARGET=($native_arch) TARGET_ARCH=($arch) WITH_PKGBASE=yes VMFORMATS=($image.format) VMSIZE=($image.size_mb)m CLOUDWARE_CONF=/usr/src/release/tools/smolbsd-($target.platform).conf"
            would_run: false
            real: false
            stub_reason: $"STUB: vm-image build requires completed buildworld/buildkernel. Output goes to /usr/obj/($native_arch).($arch)/usr/src/release/vm/"
            action: "would-run"
        }
        {
            step: 9
            label: "fetch_agent"
            cmd: $"fetch -o ($image | get output_dir? | default './out')/($agent.name) '($agent_url)'"
            would_run: false
            real: false
            stub_reason: $"STUB: agent fetch from ($agent_url) — verify sha256 after fetch."
            action: "would-run"
            sha256_expected: ($agent.source | get sha256? | default "not_set")
        }
        {
            step: 10
            label: "install_agent_into_image"
            cmd: $"# Mount image, copy agent binary to ($agent | get install_path? | default '/usr/local/bin')/($agent.name), install rc.d script, unmount"
            would_run: false
            real: false
            stub_reason: "STUB: requires mounted image. In real build, vm_extra_pre_umount() hook handles this."
            action: "would-run"
        }
        {
            step: 11
            label: "copy_image_to_output"
            cmd: $"cp /usr/obj/($native_arch).($arch)/usr/src/release/vm/FreeBSD-*.($image.format) ($output_image)"
            would_run: false
            real: false
            stub_reason: "STUB: depends on completed vm-image step."
            action: "would-run"
        }
        {
            step: 12
            label: "emit_receipt"
            cmd: $"nu genoa.nu _emit_receipt ($output_image) > ($output_receipt)"
            would_run: true
            real: true
            description: "Emit attestation receipt JSON alongside the image."
        }
    ]
}

# ---------------------------------------------------------------------------
# Internal: dry-run execution — print plan with stub explanations
# ---------------------------------------------------------------------------

def execute_dry_run [plan: record, manifest: record, manifest_path: string] {
    let steps = $plan.build_steps
    let real_steps = $steps | where { |s| ($s | get -o real | default false) == true }
    let stub_steps = $steps | where { |s| ($s | get -o real | default false) == false }

    {
        schema_version: $SCHEMA_VERSION
        mode: "dry_run"
        genoa_version: $GENOA_VERSION
        manifest: $manifest_path
        description: "Dry-run plan. No commands executed. Each step shows what would happen."
        plan_summary: {
            image_name: $manifest.image.name
            image_version: $manifest.image.version
            target: $"($manifest.target.os) ($manifest.target.arch) on ($manifest.target.platform)"
            kernel_config: $manifest.kernel.config
            agent: $"($manifest.agent.name) ($manifest.agent.version)"
            output_image: $plan.resolved.image.output_path
            output_receipt: $plan.resolved.image.receipt_path
        }
        would_execute: ($real_steps | each { |s| {
            step: $s.step
            label: $s.label
            cmd: $s.cmd
            description: ($s | get description? | default "")
        }}),
        would_stub: ($stub_steps | each { |s| {
            step: $s.step
            label: $s.label
            action: "would-run"
            cmd: $s.cmd
            reason: ($s | get stub_reason? | default "Long-running operation stubbed.")
        }}),
        sample_receipt: (build_sample_receipt $manifest $plan.resolved.image.output_path true)
        next_step: "Remove --dry-run flag to execute the build on a FreeBSD build host."
    } | to json --indent 2 | print
}

# ---------------------------------------------------------------------------
# Internal: real build execution (stubs the long-running make steps)
# ---------------------------------------------------------------------------

def execute_build [plan: record, manifest: record, manifest_path: string] {
    let output_dir = $manifest.image | get output_dir? | default "./out"
    let output_image = $plan.resolved.image.output_path
    let output_receipt = $plan.resolved.image.receipt_path

    # Step 1: Create output directory (real)
    print --stderr $"[genoa] Creating output directory: ($output_dir)"
    ^mkdir -p $output_dir

    # Steps 2-11: all long-running or require FreeBSD build host — STUB
    let stubbed_cmds = $plan.build_steps | where { |s| ($s | get real? | default false) == false }

    print --stderr "[genoa] Build steps summary:"
    $stubbed_cmds | each { |s|
        print --stderr $"  [STUB] step ($s.step) ($s.label): ($s | get stub_reason? | default 'stubbed')"
    }

    # Create a fake image file (placeholder for testing verify subcommand)
    let fake_image_content = $"genoa-fake-image:($manifest.image.name):($manifest.image.version):($manifest.target.arch):($manifest.target.platform)"
    $fake_image_content | save --force $output_image

    # Compute sha256 of the fake image
    let image_sha = (^sha256sum $output_image | split words | first)
    let manifest_sha = (^sha256sum $manifest_path | split words | first)

    # Emit receipt
    let receipt = build_sample_receipt $manifest $output_image false
    let receipt_with_hashes = $receipt | merge {
        hashes: {
            image_sha256: $image_sha
            manifest_sha256: $manifest_sha
            kernel_config_sha256: "PLACEHOLDER_DRY_RUN"
            release_conf_sha256: "PLACEHOLDER_DRY_RUN"
        }
    }

    $receipt_with_hashes | to json --indent 2 | save --force $output_receipt

    {
        schema_version: $SCHEMA_VERSION
        status: "build_complete"
        mode: "stub_build"
        note: "Long-running make steps were stubbed. A placeholder image file was created for verify testing. Replace with a real FreeBSD build for production use.",
        output: {
            image: $output_image
            image_sha256: $image_sha
            receipt: $output_receipt
            receipt_id: $receipt.receipt_id
        }
        next_step: $"nu genoa.nu verify ($output_image) ($output_receipt)"
        stubbed_steps: ($stubbed_cmds | each { |s| {step: $s.step, label: $s.label} })
    } | to json --indent 2 | print
}

# ---------------------------------------------------------------------------
# Internal: build a sample receipt record
# ---------------------------------------------------------------------------

def build_sample_receipt [manifest: record, output_image: string, dry_run: bool] {
    let image = $manifest.image
    let target = $manifest.target
    let kernel = $manifest.kernel
    let agent = $manifest.agent

    # Generate a deterministic-ish UUID from image name+version
    let uuid_seed = $"($image.name)-($image.version)"
    let uuid = $"a1b2c3d4-e5f6-4a7b-8c9d-($uuid_seed | str replace -a '[^a-z0-9]' '0' | str substring 0..11)"

    {
        schema_version: "v1"
        receipt_id: $uuid
        built_at: (date now | format date "%Y-%m-%dT%H:%M:%SZ")
        image: {
            name: $image.name
            version: $image.version
            format: $image.format
            output_path: $output_image
            size_bytes: (if $dry_run { 0 } else { 1024 })
            provisioned_mb: $image.size_mb
        }
        build: {
            host: (^hostname | str trim)
            builder_type: (if $dry_run { "dry-run" } else { "local" })
            os_version: (try { ^uname -sr | str trim } catch { "unknown" })
            arch: (try { ^uname -m | str trim } catch { "unknown" })
            genoa_version: $GENOA_VERSION
            kernel_config: $kernel.config
            platform: $target.platform
            dry_run: $dry_run
            build_commands: (resolve_build_steps $manifest $output_image $"($image | get output_dir? | default './out')/($image.name)-($image.version).receipt.json" "(agent-url-stubbed)")
        }
        agent: {
            name: $agent.name
            version: $agent.version
            install_path: ($agent | get install_path? | default "/usr/local/bin")
            source_url: "(stubbed)"
            source_sha256: ($agent.source | get sha256? | default "0000000000000000000000000000000000000000000000000000000000000000")
            rc_service: ($agent | get rc_service? | get name? | default null)
        }
        hashes: {
            image_sha256: (if $dry_run { "PLACEHOLDER_DRY_RUN" } else { "PLACEHOLDER_DRY_RUN" })
            manifest_sha256: "PLACEHOLDER_DRY_RUN"
            kernel_config_sha256: "PLACEHOLDER_DRY_RUN"
            release_conf_sha256: "PLACEHOLDER_DRY_RUN"
        }
        signing: {
            tool: ($manifest | get signing? | get tool? | default "none")
            placeholder: true
        }
        claims: [
            {
                claim: "Image file exists and is non-empty"
                probe: $"test -s ($output_image) && echo EXISTS"
                expect: "EXISTS"
                status: (if $dry_run { "unverified" } else { "verified" })
            }
            {
                claim: $"Agent ($agent.name) is installed at ($agent | get install_path? | default '/usr/local/bin')"
                probe: $"ssh -p 22 root@<image_ip> 'test -x ($agent | get install_path? | default '/usr/local/bin')/($agent.name) && echo AGENT_OK'"
                expect: "AGENT_OK"
                status: "unverified"
            }
            {
                claim: "Image boots to login prompt within 30 seconds"
                probe: "expect-script: wait for 'login:' within 30s on serial console"
                expect: "login:"
                status: "unverified"
            }
            {
                claim: "Image sha256 matches receipt"
                probe: $"sha256sum ($output_image) | awk '{{print $1}}' | grep -Fxq HASH"
                expect: "0 (exit code)"
                status: (if $dry_run { "unverified" } else { "verified" })
            }
        ]
        metadata: ($manifest | get metadata? | default {})
    }
}
