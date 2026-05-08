#!/usr/bin/env nu
# profiles/uefi.nu — UEFI image profile for genoa
# Purpose: Build minimal FreeBSD images that boot via UEFI (loader.efi).
# Bootloader: FreeBSD loader.efi (BSD-2-Clause) — vendorable.
# Partitions: ESP 512M FAT32 (p1) + freebsd-ufs remainder UFS2 (p2).
# Targets: amd64 (BOOTX64.EFI) and aarch64 (BOOTAA64.EFI).
#
# All destructive steps carry action="would-run".
# action="real" steps execute their logic unconditionally.
# dry_run is always honoured — never touch system state without --execute (not yet wired).
#
# License: BSD-2-Clause
# SPDX-License-Identifier: BSD-2-Clause

# ---------------------------------------------------------------------------
# run_step — execute a would-run step when on FreeBSD with dry_run=false
# Returns the step unchanged if dry_run=true or not on FreeBSD.
# Returns action="ran" or action="failed" with exit_code/output fields.
# Steps with multiple cmds must join them into a single cmd before calling.
# ---------------------------------------------------------------------------
def run_step [step: record, dry_run: bool] {
    let is_freebsd = try { (^uname -s | str trim) == "FreeBSD" } catch { false }
    if $dry_run or not $is_freebsd {
        return $step
    }
    let result = try {
        let out = ^sh -c $step.cmd | complete
        if $out.exit_code == 0 {
            $step | merge {action: "ran", exit_code: 0, output: ($out.stdout | str trim)}
        } else {
            $step | merge {action: "failed", exit_code: $out.exit_code, stderr: ($out.stderr | str trim)}
        }
    } catch { |e|
        $step | merge {action: "failed", exit_code: -1, error: $e.msg}
    }
    $result
}

# ---------------------------------------------------------------------------
# validate_manifest — step 1 (real)
# Check required manifest fields and return a structured result record.
# ---------------------------------------------------------------------------
def validate_manifest [m: record] {
    let errors = []

    let errors = if "image" not-in $m {
        $errors | append "missing: image"
    } else { $errors }

    let errors = if "target" not-in $m {
        $errors | append "missing: target"
    } else { $errors }

    let errors = if "target" in $m and "arch" not-in $m.target {
        $errors | append "missing: target.arch"
    } else { $errors }

    {valid: (($errors | length) == 0), errors: $errors}
}

# ---------------------------------------------------------------------------
# resolve_agent_url — helper used by step 2 (real)
# Build the download URL for the agent binary without fetching it.
# ---------------------------------------------------------------------------
def resolve_agent_url [manifest: record] {
    let agent = $manifest | get agent? | default {}
    let name = $agent | get name? | default ""
    if $name == "ii-agent" {
        let repo = $agent | get source? | get repo? | default "studio/ii-agent"
        let tag  = $agent | get source? | get tag?  | default "latest"
        let asset = $agent | get source? | get asset? | default "ii-agent"
        $"http://gitea.local:3000/($repo)/releases/download/($tag)/($asset)"
    } else if $name == "" {
        null
    } else {
        let url = $agent | get source? | get url? | default null
        $url
    }
}

# ---------------------------------------------------------------------------
# render_loader_conf — step 10 (real)
# Substitute Tera variables and return the rendered string.
# (Full Tera engine not available in Nushell; we substitute manually.)
# ---------------------------------------------------------------------------
def render_loader_conf [manifest: record] {
    let hostname     = $manifest | get network? | get hostname? | default ($manifest | get image? | get name? | default "freebsd")
    let console_speed = $manifest | get boot? | get console_speed? | default 115200
    let kern_hz      = $manifest | get boot? | get kern_hz? | default 100

    let tmpl_path = ([($env.PWD) "templates" "uefi" "loader.conf.tera"] | path join)
    let tmpl = if ($tmpl_path | path exists) {
        open --raw $tmpl_path
    } else {
        # Inline fallback — matches templates/uefi/loader.conf.tera exactly
        "hint.hostname.0=\"{{ hostname }}\"\ncomconsole_speed=\"{{ console_speed }}\"\nconsole=\"comconsole,vidconsole\"\nboot_multicons=\"YES\"\nboot_serial=\"YES\"\nkern.hz={{ kern_hz }}\nvfs.root.mountfrom=\"ufs:/dev/gpt/rootfs\"\nkern.vty=vt\nautoboot_delay=\"3\"\nif_ena_load=\"YES\"\ngve_load=\"YES\"\n"
    }

    $tmpl
        | str replace --all "{{ hostname }}" $hostname
        | str replace --all "{{ console_speed }}" ($console_speed | into string)
        | str replace --all "{{ kern_hz }}" ($kern_hz | into string)
}

# ---------------------------------------------------------------------------
# render_rc_conf — step 11 (real)
# ---------------------------------------------------------------------------
def render_rc_conf [manifest: record] {
    let hostname      = $manifest | get network? | get hostname? | default ($manifest | get image? | get name? | default "freebsd")
    # Prefer rc_service.name (underscored) for the rc.conf variable; fall back to agent.name with hyphens replaced
    let agent_raw     = $manifest | get agent? | get name? | default "agent"
    let agent_name    = $manifest | get agent? | get rc_service? | get name? | default ($agent_raw | str replace --all "-" "_")
    let agent_enabled = $manifest | get agent? | get rc_service? | get enabled? | default true

    let tmpl_path = ([($env.PWD) "templates" "uefi" "rc.conf.tera"] | path join)
    let tmpl = if ($tmpl_path | path exists) {
        open --raw $tmpl_path
    } else {
        "hostname=\"{{ hostname }}\"\nifconfig_DEFAULT=\"DHCP\"\nsshd_enable=\"YES\"\nntpd_enable=\"YES\"\nntpd_sync_on_start=\"YES\"\ngrowfs_enable=\"YES\"\nvirtio_random_load=\"YES\"\n{{ agent_name }}_enable=\"{{ agent_enabled }}\"\n"
    }

    # Handle the {% if agent_enabled %} block manually
    let agent_enable_str = if $agent_enabled { "YES" } else { "NO" }
    let agent_line = if $agent_enabled {
        $"($agent_name)_enable=\"YES\""
    } else {
        $"# ($agent_name)_enable=\"NO\"  # agent disabled in manifest"
    }

    $tmpl
        | str replace --all "{{ hostname }}" $hostname
        | str replace --all "{{ agent_name }}" $agent_name
        | str replace --all "{{ agent_enabled }}" $agent_enable_str
        | str replace --all $"{% if agent_enabled %}($agent_name)_enable=\"YES\"{% else %}# ($agent_name)_enable=\"NO\"  # agent disabled in manifest{% endif %}" $agent_line
}

# ---------------------------------------------------------------------------
# uefi_build — public entry point
# Receipt writing is handled by genoa.nu main build after this function returns.
# ---------------------------------------------------------------------------
export def uefi_build [manifest: record, dry_run: bool = false] {
    # ── step 1: validate_manifest (real) ───────────────────────────────────
    let validation = validate_manifest $manifest

    # ── step 2: resolve_artifacts (real — build URL, don't fetch) ──────────
    let agent_url = resolve_agent_url $manifest

    # ── step 10: render loader.conf (real) ─────────────────────────────────
    let loader_conf_rendered = render_loader_conf $manifest

    # ── step 11: render rc.conf (real) ─────────────────────────────────────
    let rc_conf_rendered = render_rc_conf $manifest

    # ── step 13: write authorized_keys to temp file (real) ─────────────────
    let ssh_keys = $manifest | get network? | get ssh_keys? | default []
    let authorized_keys_path = $"/tmp/genoa-authorized-keys-($manifest | get image? | get name? | default 'unknown')"
    if ($ssh_keys | length) > 0 {
        $ssh_keys | str join "\n" | save --force $authorized_keys_path
    }

    # ── step 13b: install authorized_keys into image (would-run) ───────────
    let ssh_keys_tmp = $authorized_keys_path
    let step13b = if ($ssh_keys | length) > 0 {
        run_step {
            step: "13b"
            label: "install_ssh_keys"
            action: "would-run"
            cmd: $"mkdir -p /mnt/rootfs/root/.ssh && cp ($ssh_keys_tmp) /mnt/rootfs/root/.ssh/authorized_keys && chmod 600 /mnt/rootfs/root/.ssh/authorized_keys && chmod 700 /mnt/rootfs/root/.ssh"
            description: $"Install SSH authorized_keys from manifest network.ssh_keys \(($ssh_keys | length) keys\)."
        } $dry_run
    } else {
        {
            step: "13b"
            label: "install_ssh_keys"
            action: "skipped"
            description: "No ssh_keys in manifest; authorized_keys not installed."
        }
    }
    if ($step13b | get action? | default "") == "failed" {
        return {action: "build-failed", failed_step: $step13b.label, exit_code: $step13b.exit_code, detail: $step13b}
    }

    # Arch-dependent EFI filename
    let arch = $manifest | get target? | get arch? | default "amd64"
    let efi_filename = if $arch == "aarch64" { "BOOTaa64.EFI" } else { "BOOTx64.EFI" }

    # Derived image fields
    let image_name    = $manifest | get image? | get name? | default "unknown"
    let image_version = $manifest | get image? | get version? | default "v0.0.0"
    let image_size    = $manifest | get image? | get size_mb? | default 20480
    let _out_dir      = ($manifest.image?.output_dir? | default "./out")
    let output_image  = $"($_out_dir)/($image_name)-($image_version).raw"
    # Pre-build as string to avoid Nu 0.111.0 bug: ($int)M inside $"..." is parsed as filesize
    let image_size_arg = ($image_size | into string) + "M"
    let hostname     = $manifest | get network? | get hostname? | default $image_name
    let agent_name   = $manifest | get agent? | get name? | default ""
    let os_version   = $manifest | get target? | get os_version? | default "15.0-RELEASE"
    let os_arch      = if $arch == "aarch64" { "arm64" } else { $arch }

    # ── step 3: create_disk_image ───────────────────────────────────────────
    let step3 = run_step {
        step: 3
        label: "create_disk_image"
        action: "would-run"
        cmd: $"rm -f ($output_image) && truncate -s ($image_size_arg) ($output_image)"
        description: $"Create ($image_size) MiB raw disk image at ($output_image)."
    } $dry_run
    if $step3.action == "failed" {
        return {action: "build-failed", failed_step: $step3.label, exit_code: $step3.exit_code, detail: $step3}
    }

    # ── step 3b: attach_mdconfig ────────────────────────────────────────────
    let step3b = if $dry_run {
        {step: "3b" label: "attach_mdconfig" action: "would-run"
         cmd: $"mdconfig -a -t vnode -f ($output_image)"
         description: "Attach raw image as md(4) vnode device for gpart/newfs/mount."}
    } else {
        let md_unit = try { ^mdconfig -a -t vnode -f $output_image | str trim } catch { |e| "" }
        if $md_unit == "" {
            {step: "3b" label: "attach_mdconfig" action: "failed"
             exit_code: 1 cmd: $"mdconfig -a -t vnode -f ($output_image)" stderr: "mdconfig returned empty"}
        } else {
            {step: "3b" label: "attach_mdconfig" action: "ran"
             exit_code: 0 cmd: $"mdconfig -a -t vnode -f ($output_image)"
             md_unit: $md_unit md_dev: $"/dev/($md_unit)"}
        }
    }
    if $step3b.action == "failed" {
        return {action: "build-failed" failed_step: $step3b.label exit_code: 1 detail: $step3b}
    }
    let md_unit = if $dry_run { "md0" } else { $step3b.md_unit }
    let md_dev  = $"/dev/($md_unit)"

    # ── step 4: partition_gpt ───────────────────────────────────────────────
    # Multiple cmds joined with && so failure of any sub-command stops the chain
    let step4_cmds = [
        $"gpart create -s gpt ($md_dev)"
        $"gpart add -t efi    -s 128M -l esp    ($md_dev)"
        $"gpart add -t freebsd-ufs    -l rootfs ($md_dev)"
    ]
    let step4 = run_step {
        step: 4
        label: "partition_gpt"
        action: "would-run"
        cmd: ($step4_cmds | str join " && ")
        cmds: $step4_cmds
        description: "Create GPT; add ESP (512 MiB FAT32) + freebsd-ufs (remainder)."
        layout: {
            p1: {type: "efi",         size: "512M", label: "esp",    purpose: "EFI System Partition"}
            p2: {type: "freebsd-ufs", size: "remainder", label: "rootfs", purpose: "FreeBSD UFS2 root"}
        }
    } $dry_run
    if $step4.action == "failed" {
        return {action: "build-failed", failed_step: $step4.label, exit_code: $step4.exit_code, detail: $step4}
    }

    # ── step 5: format_esp ──────────────────────────────────────────────────
    let step5 = run_step {
        step: 5
        label: "format_esp"
        action: "would-run"
        cmd: $"newfs_msdos -F 16 -L ESP ($md_dev)p1"
        description: "Format ESP partition as FAT32."
    } $dry_run
    if $step5.action == "failed" {
        return {action: "build-failed", failed_step: $step5.label, exit_code: $step5.exit_code, detail: $step5}
    }

    # ── step 6: install_efi_loader ──────────────────────────────────────────
    let step6_cmds = [
        $"mount -t msdosfs ($md_dev)p1 /mnt/esp"
        $"mkdir -p /mnt/esp/EFI/BOOT"
        $"cp /boot/loader.efi /mnt/esp/EFI/BOOT/($efi_filename)"
        "umount /mnt/esp"
    ]
    let step6 = run_step {
        step: 6
        label: "install_efi_loader"
        action: "would-run"
        cmd: ($step6_cmds | str join " && ")
        cmds: $step6_cmds
        description: $"Copy loader.efi to ESP/EFI/BOOT/($efi_filename) for ($arch) UEFI fallback path. License: BSD-2-Clause."
        efi_binary: $efi_filename
        arch: $arch
    } $dry_run
    if $step6.action == "failed" {
        return {action: "build-failed", failed_step: $step6.label, exit_code: $step6.exit_code, detail: $step6}
    }

    # ── step 7: format_rootfs ───────────────────────────────────────────────
    let step7 = run_step {
        step: 7
        label: "format_rootfs"
        action: "would-run"
        cmd: $"newfs -U ($md_dev)p2"
        description: "Format rootfs partition as UFS2 with soft-updates (-U)."
    } $dry_run
    if $step7.action == "failed" {
        return {action: "build-failed", failed_step: $step7.label, exit_code: $step7.exit_code, detail: $step7}
    }

    # ── step 8: extract_base ────────────────────────────────────────────────
    let step8_cmds = [
        $"mount ($md_dev)p2 /mnt/rootfs"
        $"tar -xf /usr/freebsd-dist/base.txz -C /mnt/rootfs"
    ]
    let step8 = run_step {
        step: 8
        label: "extract_base"
        action: "would-run"
        cmd: ($step8_cmds | str join " && ")
        cmds: $step8_cmds
        description: $"Extract FreeBSD ($os_version) base.txz to mounted rootfs."
    } $dry_run
    if $step8.action == "failed" {
        return {action: "build-failed", failed_step: $step8.label, exit_code: $step8.exit_code, detail: $step8}
    }

    # ── step 9: extract_kernel ──────────────────────────────────────────────
    let step9 = run_step {
        step: 9
        label: "extract_kernel"
        action: "would-run"
        cmd: $"tar -xf /usr/freebsd-dist/kernel.txz -C /mnt/rootfs"
        description: $"Extract FreeBSD ($os_version) kernel.txz to mounted rootfs."
    } $dry_run
    if $step9.action == "failed" {
        return {action: "build-failed", failed_step: $step9.label, exit_code: $step9.exit_code, detail: $step9}
    }

    # ── step 8b: reinstall_efi_loader_from_base ─────────────────────────────
    # Override the buildworld loader.efi with the one from base.txz.
    # base.txz extracts /boot/loader.efi into the rootfs; this version
    # matches the kernel exactly and has no buildworld EFI device paths.
    let step8b_cmds = [
        $"mount -t msdosfs ($md_dev)p1 /mnt/esp"
        $"cp /mnt/rootfs/boot/loader.efi /mnt/esp/EFI/BOOT/($efi_filename)"
        "umount /mnt/esp"
    ]
    let step8b = run_step {
        step: "8b"
        label: "reinstall_efi_loader_from_base"
        action: "would-run"
        cmd: ($step8b_cmds | str join " && ")
        cmds: $step8b_cmds
        description: $"Replace buildworld loader.efi with version from base.txz at /mnt/rootfs/boot/loader.efi — ensures loader and kernel are same build."
        efi_binary: $efi_filename
    } $dry_run
    if $step8b.action == "failed" {
        return {action: "build-failed", failed_step: $step8b.label, exit_code: $step8b.exit_code, detail: $step8b}
    }

    # ── step 9b: write_loader_conf ──────────────────────────────────────────
    # Write rendered loader.conf directly via Nu save — avoids heredoc quoting issues.
    let step9b = if $dry_run {
        {step: "9b" label: "write_loader_conf" action: "would-run"
         description: "Write loader.conf to /mnt/rootfs/boot/loader.conf"
         output_path: "/mnt/rootfs/boot/loader.conf"
         preview: ($loader_conf_rendered | str substring 0..120)}
    } else {
        try {
            $loader_conf_rendered | save --force "/mnt/rootfs/boot/loader.conf"
            {step: "9b" label: "write_loader_conf" action: "ran" exit_code: 0
             description: "Wrote loader.conf to /mnt/rootfs/boot/loader.conf"
             output_path: "/mnt/rootfs/boot/loader.conf"}
        } catch { |e|
            {step: "9b" label: "write_loader_conf" action: "failed" exit_code: 1
             stderr: $e.msg}
        }
    }
    if $step9b.action == "failed" {
        return {action: "build-failed", failed_step: $step9b.label, exit_code: 1, detail: $step9b}
    }

    # ── step 9c: write_rc_conf ───────────────────────────────────────────────
    # Write rendered rc.conf directly via Nu save — avoids heredoc quoting issues.
    let step9c = if $dry_run {
        {step: "9c" label: "write_rc_conf" action: "would-run"
         description: "Write rc.conf to /mnt/rootfs/etc/rc.conf"
         output_path: "/mnt/rootfs/etc/rc.conf"
         preview: ($rc_conf_rendered | str substring 0..120)}
    } else {
        try {
            $rc_conf_rendered | save --force "/mnt/rootfs/etc/rc.conf"
            {step: "9c" label: "write_rc_conf" action: "ran" exit_code: 0
             description: "Wrote rc.conf to /mnt/rootfs/etc/rc.conf"
             output_path: "/mnt/rootfs/etc/rc.conf"}
        } catch { |e|
            {step: "9c" label: "write_rc_conf" action: "failed" exit_code: 1
             stderr: $e.msg}
        }
    }
    if $step9c.action == "failed" {
        return {action: "build-failed", failed_step: $step9c.label, exit_code: 1, detail: $step9c}
    }

    # ── step 12: inject_agent ───────────────────────────────────────────────
    let step12_cmds = if ($agent_name | is-empty) { [] } else { [
        "mkdir -p /mnt/rootfs/usr/local/bin /mnt/rootfs/usr/local/etc/rc.d"
        $"cp ./out/($agent_name) /mnt/rootfs/usr/local/bin/($agent_name)"
        $"chmod 755 /mnt/rootfs/usr/local/bin/($agent_name)"
        $"cp ./rc.d/($agent_name) /mnt/rootfs/usr/local/etc/rc.d/($agent_name)"
        $"chmod 755 /mnt/rootfs/usr/local/etc/rc.d/($agent_name)"
    ]}
    let step12_cmd = if ($step12_cmds | is-empty) { "true" } else { ($step12_cmds | str join " && ") }
    let step12 = run_step {
        step: 12
        label: "inject_agent"
        action: "would-run"
        cmd: $step12_cmd
        cmds: $step12_cmds
        description: $"Copy ($agent_name) binary and rc.d service script into rootfs."
        agent_name: $agent_name
        agent_url: $agent_url
    } $dry_run
    if $step12.action == "failed" {
        return {action: "build-failed", failed_step: $step12.label, exit_code: $step12.exit_code, detail: $step12}
    }

    # ── step 14: cloud_init_clean ───────────────────────────────────────────
    let step14_cmds = [
        "rm -rf /mnt/rootfs/var/db/cloudinit"
        "rm -rf /mnt/rootfs/tmp/cloud-init"
    ]
    let step14 = run_step {
        step: 14
        label: "cloud_init_clean"
        action: "would-run"
        cmd: ($step14_cmds | str join " && ")
        cmds: $step14_cmds
        description: "Remove stale cloud-init state to prevent instance-id reuse on first boot."
    } $dry_run
    if $step14.action == "failed" {
        return {action: "build-failed", failed_step: $step14.label, exit_code: $step14.exit_code, detail: $step14}
    }

    # ── step 15: umount_and_compact ─────────────────────────────────────────
    let step15_cmds = [
        "umount /mnt/rootfs"
        "sync"
    ]
    let step15 = run_step {
        step: 15
        label: "umount_and_compact"
        action: "would-run"
        cmd: ($step15_cmds | str join " && ")
        cmds: $step15_cmds
        description: "Unmount rootfs; sync image to disk. (mkuzip optional for compressed images.)"
    } $dry_run
    if $step15.action == "failed" {
        return {action: "build-failed", failed_step: $step15.label, exit_code: $step15.exit_code, detail: $step15}
    }

    # ── step 15b: detach_mdconfig ───────────────────────────────────────────
    let step15b = run_step {
        step: "15b"
        label: "detach_mdconfig"
        action: "would-run"
        cmd: $"mdconfig -d -u ($md_unit)"
        description: $"Detach md(4) device ($md_dev) from image file."
    } $dry_run
    if $step15b.action == "failed" {
        # Non-fatal — log but continue
    }

    # Receipt is written by genoa.nu main build after the profile returns.
    # emit_receipt was removed from this profile (D2 cleanup).

    {
        schema_version: "v1"
        profile: "uefi"
        dry_run: $dry_run
        validation: $validation
        steps: [
            # ── 1. validate_manifest (real) ─────────────────────────────────
            {
                step: 1
                label: "validate_manifest"
                action: "real"
                description: "Validate required manifest fields."
                result: $validation
            }

            # ── 2. resolve_artifacts (real) ──────────────────────────────────
            {
                step: 2
                label: "resolve_artifacts"
                action: "real"
                description: "Build agent binary URL from gitea.local. No network call."
                agent_url: $agent_url
            }

            # ── 3. create_disk_image ─────────────────────────────────────────
            $step3

            # ── 3b. attach_mdconfig ──────────────────────────────────────────
            $step3b

            # ── 4. partition_gpt ─────────────────────────────────────────────
            $step4

            # ── 5. format_esp ────────────────────────────────────────────────
            $step5

            # ── 6. install_efi_loader ────────────────────────────────────────
            $step6

            # ── 7. format_rootfs ─────────────────────────────────────────────
            $step7

            # ── 8. extract_base ──────────────────────────────────────────────
            $step8

            # ── 9. extract_kernel ────────────────────────────────────────────
            $step9

            # ── 8b. reinstall_efi_loader_from_base ──────────────────────────
            $step8b

            # ── 9b. write_loader_conf ────────────────────────────────────────
            $step9b

            # ── 9c. write_rc_conf ────────────────────────────────────────────
            $step9c

            # ── 10. configure_loader (real — rendered content; written in step 9b) ─
            {
                step: 10
                label: "configure_loader"
                action: "real"
                description: "Render templates/uefi/loader.conf.tera → written to disk in step 9b."
                output_path: "/mnt/rootfs/boot/loader.conf"
                preview: ($loader_conf_rendered | str substring 0..120)
            }

            # ── 11. configure_rc (real — rendered content; written in step 9c) ──
            {
                step: 11
                label: "configure_rc"
                action: "real"
                description: "Render templates/uefi/rc.conf.tera → written to disk in step 9c."
                output_path: "/mnt/rootfs/etc/rc.conf"
                preview: ($rc_conf_rendered | str substring 0..120)
            }

            # ── 12. inject_agent ──────────────────────────────────────────────
            $step12

            # ── 13. inject_ssh_keys (real) ─────────────────────────────────────
            {
                step: 13
                label: "inject_ssh_keys"
                action: "real"
                description: "Write SSH authorized_keys from manifest.network.ssh_keys to temp file."
                key_count: ($ssh_keys | length)
                temp_path: $authorized_keys_path
                target_path: "/mnt/rootfs/root/.ssh/authorized_keys"
                note: (if ($ssh_keys | length) > 0 {
                    $"($ssh_keys | length) keys written to ($authorized_keys_path)"
                } else {
                    "No ssh_keys in manifest; authorized_keys not written."
                })
            }

            # ── 13b. install_ssh_keys ──────────────────────────────────────────
            $step13b

            # ── 14. cloud_init_clean ──────────────────────────────────────────
            $step14

            # ── 15. umount_and_compact ────────────────────────────────────────
            $step15

            # ── 15b. detach_mdconfig ──────────────────────────────────────────
            $step15b
        ]
    }
}
