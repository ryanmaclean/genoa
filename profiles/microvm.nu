#!/usr/bin/env nu
# profiles/microvm.nu — direct-kernel (PVH) microVM artifact profile (genoa #1)
# SPDX-License-Identifier: BSD-2-Clause
#
# Packages a PRE-BUILT boot artifact — smolfire's one-ELF SMOLFIRE kernel
# (kernel + embedded /rescue MFS root, no root disk) or a NetBSD 11
# netbsd-MICROVM kernel — together with independently hashable writable
# state disks (FFS / LFS / HAMMER2). The OS/runtime build itself belongs to
# smolfire (ownership rule); genoa owns packaging, hashes, launch plans and
# the receipt.
#
# Execution model:
#   - every step carries an argv list (never a sh -c string), so manifest
#     values cannot become shell syntax;
#   - dry-run: all steps are "would-run", nothing touches disk;
#   - real: boot artifact copy/fetch + hash works on any host; a state disk
#     is formatted only when its build tools are present on THIS host. If
#     not, the step is "requires-host" and the build fails closed — a disk
#     that was not built is never reported with a hash.

# Run one argv step (or plan it in dry-run). Returns the step record with
# action ran|failed|would-run.
def microvm_run [step: record, dry_run: bool] {
  if $dry_run { return ($step | merge {action: "would-run"}) }
  let argv = $step.argv
  let out = try {
    run-external ($argv | first) ...($argv | skip 1) | complete
  } catch { |e| {exit_code: -1, stdout: "", stderr: $e.msg} }
  if $out.exit_code == 0 {
    $step | merge {action: "ran", exit_code: 0}
  } else {
    $step | merge {action: "failed", exit_code: $out.exit_code, stderr: ($out.stderr | str trim)}
  }
}

# ELF magic check: 0x7f 'E' 'L' 'F'
def microvm_is_elf [path: string] {
  try { (open --raw $path | bytes at 0..3) == 0x[7f 45 4c 46] } catch { false }
}

# Plan the argv sequence that formats one state disk image on this host.
# Returns {tools: [..], host_os: [..], cmds: [[argv]..], notes: string}.
def microvm_statefs_plan [disk: record, target_os: string, img: string] {
  let fs = $disk.fs
  let size_mb = $disk.size_mb
  let label = ($disk.label? | default "")
  let journal = ($disk.journal? | default false)
  match $fs {
    "ffs" => {
      # makefs builds an FFS image from a directory without mdconfig/vnd or
      # root: available on FreeBSD and NetBSD. version=2 = UFS2/FFSv2.
      let opts = (["version=2"]
        | if $label != "" { append $"label=($label)" } else { $in }
        | if $journal and $target_os == "freebsd" { append "softupdates=1" } else { $in })
      {
        tools: ["makefs"]
        host_os: ["FreeBSD", "NetBSD"]
        cmds: [["makefs", "-t", "ffs", "-s", $"($size_mb)m", "-o", ($opts | str join ","), $img, "@EMPTYDIR@"]]
        notes: (if $journal {
          if $target_os == "netbsd" { "journal=true: WAPBL is enabled at mount time (mount -o log)" } else { "journal=true: soft updates set by makefs; SU+J needs tunefs -j enable on first attach" }
        } else { "" })
      }
    }
    "lfs" => {
      # LFS has no makefs backend: format through a vnd(4) device on NetBSD.
      {
        tools: ["dd", "vndconfig", "newfs_lfs"]
        host_os: ["NetBSD"]
        cmds: [
          ["dd", "if=/dev/zero", $"of=($img)", "bs=1m", $"count=($size_mb)"]
          ["vndconfig", "-c", "vnd0", $img]
          ["newfs_lfs", "/dev/rvnd0d"]
          ["vndconfig", "-u", "vnd0"]
        ]
        notes: "requires root on a NetBSD build host (vnd0 must be free); label not supported by LFS"
      }
    }
    "hammer2" => {
      {
        tools: ["truncate", "newfs_hammer2"]
        host_os: ["FreeBSD", "NetBSD", "DragonFly"]
        cmds: [
          ["truncate", "-s", $"($size_mb)m", $img]
          (["newfs_hammer2"] | if $label != "" { append ["-L", $label] } else { $in } | append $img)
        ]
        notes: "out-of-tree HAMMER2 userland (newfs_hammer2) required on the build host"
      }
    }
    _ => {
      {tools: [], host_os: [], cmds: [], notes: $"fs=($fs) cannot be built for target os ($target_os)", unsupported: true}
    }
  }
}

export def microvm_build [manifest: record, dry_run: bool = false] {
  let name     = ($manifest.image?.name? | default "genoa-microvm")
  let version  = ($manifest.image?.version? | default "v0.0.0")
  let out_dir  = ($manifest.image?.output_dir? | default "./out")
  let os       = ($manifest.target?.os? | default "freebsd")
  let arch     = ($manifest.target?.arch? | default "amd64")
  let elf_path = $"($out_dir)/($name)-($version).elf"
  let art      = ($manifest.kernel?.artifact? | default {})
  let boot     = ($manifest.boot? | default {})
  let vmms     = ($boot.vmm? | default ["qemu-microvm"])
  let mem_mb   = ($boot.memory_mb? | default 512)
  let vcpus    = ($boot.vcpus? | default 1)
  let cmdline  = ($boot.cmdline? | default "")
  let rootfs   = ($manifest.rootfs? | default {type: "embedded"})
  let host_os  = (try { ^uname -s | str trim } catch { "unknown" })

  mut steps = []

  # ── 1. resolve_boot_artifact ───────────────────────────────────────────
  let atype = ($art.type? | default "")
  let s1 = if $atype == "local_path" {
    let src = ($art.path? | default "")
    if (not $dry_run) and (not ($src | path exists)) {
      {step: 1, label: "resolve_boot_artifact", action: "failed", error: $"kernel.artifact.path not found: ($src)", argv: ["cp", $src, $elf_path]}
    } else {
      microvm_run {step: 1, label: "resolve_boot_artifact", argv: ["cp", $src, $elf_path], source: $src} $dry_run
    }
  } else if $atype == "url" {
    let url = ($art.url? | default "")
    let fetcher = if (find_bin "curl") != null { ["curl", "-fsSL", "-o", $elf_path, $url] } else { ["fetch", "-o", $elf_path, $url] }
    microvm_run {step: 1, label: "resolve_boot_artifact", argv: $fetcher, source: $url} $dry_run
  } else {
    {step: 1, label: "resolve_boot_artifact", action: "failed", error: "kernel.artifact.type must be local_path or url"}
  }
  $steps = ($steps | append ($s1 | merge {cmd: ($s1.argv? | default [] | str join " ")}))
  if $s1.action == "failed" {
    return {schema_version: "v1", profile: "microvm", dry_run: $dry_run, action: "build-failed", failed_step: "resolve_boot_artifact", steps: $steps, image_path: $elf_path}
  }

  # ── 2. verify_boot_artifact (ELF magic + pinned sha256) ────────────────
  let pinned = ($art.sha256? | default "")
  let s2 = if $dry_run {
    {step: 2, label: "verify_boot_artifact", action: "would-run", pinned_sha256: (if $pinned == "" { null } else { $pinned })}
  } else {
    let is_elf = (microvm_is_elf $elf_path)
    let got = (sha256_file $elf_path)
    let size = (ls $elf_path | first | get size | into int)
    if not $is_elf {
      {step: 2, label: "verify_boot_artifact", action: "failed", error: "boot artifact is not an ELF file (bad magic)", sha256: $got}
    } else if $pinned != "" and $pinned != $got {
      {step: 2, label: "verify_boot_artifact", action: "failed", error: $"sha256 mismatch: pinned ($pinned) got ($got)", sha256: $got}
    } else {
      {step: 2, label: "verify_boot_artifact", action: "ran", sha256: $got, size_bytes: $size, pinned: ($pinned != "")}
    }
  }
  $steps = ($steps | append $s2)
  if $s2.action == "failed" {
    return {schema_version: "v1", profile: "microvm", dry_run: $dry_run, action: "build-failed", failed_step: "verify_boot_artifact", steps: $steps, image_path: $elf_path}
  }
  let boot_sha = ($s2.sha256? | default "PLACEHOLDER_DRY_RUN")
  let boot_size = ($s2.size_bytes? | default null)

  # ── 3. resolve_rootfs ──────────────────────────────────────────────────
  let rtype = ($rootfs.type? | default "embedded")
  let rootfs_out = if $rtype == "image" { $"($out_dir)/($name)-($version).rootfs" } else { null }
  let s3 = if $rtype == "embedded" {
    {step: 3, label: "resolve_rootfs", action: "skipped", note: "rootfs embedded in the kernel ELF — no root disk"}
  } else {
    let src = ($rootfs.path? | default "")
    if (not $dry_run) and (not ($src | path exists)) {
      {step: 3, label: "resolve_rootfs", action: "failed", error: $"rootfs.path not found: ($src)"}
    } else {
      let r = (microvm_run {step: 3, label: "resolve_rootfs", argv: ["cp", $src, $rootfs_out]} $dry_run)
      if $r.action == "ran" {
        let got = (sha256_file $rootfs_out)
        let pin = ($rootfs.sha256? | default "")
        if $pin != "" and $pin != $got {
          $r | merge {action: "failed", error: $"rootfs sha256 mismatch: pinned ($pin) got ($got)"}
        } else { $r | merge {sha256: $got} }
      } else { $r }
    }
  }
  $steps = ($steps | append $s3)
  if $s3.action == "failed" {
    return {schema_version: "v1", profile: "microvm", dry_run: $dry_run, action: "build-failed", failed_step: "resolve_rootfs", steps: $steps, image_path: $elf_path}
  }

  # ── 4. build_state_disks ───────────────────────────────────────────────
  let disks = ($manifest.state_disks? | default [])
  let default_devs = if $os == "netbsd" { ["ld0", "ld1", "ld2", "ld3", "ld4", "ld5", "ld6", "ld7"] } else { ["vtbd0", "vtbd1", "vtbd2", "vtbd3", "vtbd4", "vtbd5", "vtbd6", "vtbd7"] }
  mut disk_records = []
  mut failed_disk: any = null
  for d in ($disks | enumerate) {
    let disk = $d.item
    let img = $"($out_dir)/($name)-($version).state-($disk.name).img"
    let plan = (microvm_statefs_plan $disk $os $img)
    let missing_tools = ($plan.tools | where { |t| (find_bin $t) == null })
    let host_ok = ($host_os in $plan.host_os)
    let uuid_decl = ($disk.uuid? | default "")
    let base = {
      name: $disk.name
      fs: $disk.fs
      size_mb: $disk.size_mb
      label: ($disk.label? | default null)
      uuid: (if $uuid_decl != "" { $uuid_decl } else { random uuid })
      uuid_source: (if $uuid_decl != "" { "manifest" } else { "genoa-generated" })
      device: ($disk.device? | default ($default_devs | get $d.index))
      mountpoint: ($disk.mountpoint? | default "/state")
      journal: ($disk.journal? | default false)
      path: $img
      tools: $plan.tools
      notes: $plan.notes
    }
    let rec = if ($plan.unsupported? | default false) {
      $base | merge {action: "failed", sha256: null, error: $plan.notes}
    } else if $dry_run {
      $base | merge {action: "would-run", sha256: "PLACEHOLDER_DRY_RUN", argv: $plan.cmds}
    } else if (not $host_ok) or (not ($missing_tools | is-empty)) {
      $base | merge {action: "requires-host", sha256: null, argv: $plan.cmds, required_host_os: $plan.host_os, missing_tools: $missing_tools,
        error: $"state disk ($disk.name) fs=($disk.fs) must be built on ($plan.host_os | str join '/') with ($plan.tools | str join ', '); this host is ($host_os)"}
    } else {
      let empty_dir = (^mktemp -d | str trim)
      mut ran = []
      mut fail: any = null
      for argv in $plan.cmds {
        let a = ($argv | each { |x| if $x == "@EMPTYDIR@" { $empty_dir } else { $x } })
        let r = (microvm_run {step: 4, label: $"state_disk_($disk.name)", argv: $a} false)
        $ran = ($ran | append $r)
        if $r.action == "failed" { $fail = $r; break }
      }
      ^rm -rf $empty_dir
      if $fail != null {
        $base | merge {action: "failed", sha256: null, argv: $plan.cmds, error: ($fail.stderr? | default "state disk command failed")}
      } else {
        $base | merge {action: "ran", sha256: (sha256_file $img), size_bytes: (ls $img | first | get size | into int), argv: $plan.cmds}
      }
    }
    $disk_records = ($disk_records | append $rec)
    if ($rec.action in ["failed", "requires-host"]) and ($failed_disk == null) { $failed_disk = $rec }
  }
  $steps = ($steps | append {step: 4, label: "build_state_disks", action: (if $dry_run { "would-run" } else if $failed_disk != null { "failed" } else { "ran" }), count: ($disk_records | length), plans: ($disk_records | each { |r| {name: $r.name, action: $r.action, argv: ($r.argv? | default [])} })})

  # ── 5. launch_plans (firecracker config + qemu microvm argv) ───────────
  let drives = ($disk_records | each { |r| {drive_id: $r.name, path_on_host: $r.path, is_root_device: false, is_read_only: false} })
  let fc_boot = ({kernel_image_path: $elf_path, boot_args: $cmdline}
    | if $rootfs_out != null { merge {initrd_path: $rootfs_out} } else { $in })
  let firecracker = if "firecracker" in $vmms {
    {"boot-source": $fc_boot, drives: $drives, "machine-config": {vcpu_count: $vcpus, mem_size_mib: $mem_mb}}
  } else { null }
  let qemu_bin = if $arch == "amd64" { "qemu-system-x86_64" } else { "qemu-system-aarch64" }
  let qemu = if "qemu-microvm" in $vmms {
    (["-M", "microvm", "-m", $"($mem_mb)M", "-smp", ($vcpus | into string), "-kernel", $elf_path]
      | if $cmdline != "" { append ["-append", $cmdline] } else { $in }
      | if $rootfs_out != null { append ["-initrd", $rootfs_out] } else { $in }
      | append ($disk_records | each { |r| ["-drive", $"id=($r.name),file=($r.path),format=raw,if=none", "-device", $"virtio-blk-device,drive=($r.name)"] } | flatten)
      | append ["-display", "none", "-serial", "mon:stdio", "-no-reboot"]
      | prepend $qemu_bin)
  } else { null }
  let fc_path = $"($out_dir)/($name)-($version).firecracker.json"
  if (not $dry_run) and $firecracker != null and $failed_disk == null {
    $firecracker | to json --indent 2 | save --force $fc_path
  }
  $steps = ($steps | append {step: 5, label: "launch_plans", action: (if $dry_run or $failed_disk != null { "would-run" } else { "ran" }), firecracker_config: (if $firecracker != null { $fc_path } else { null }), note: "accelerator (-accel kvm|hvf) is chosen by the runner, not recorded here"})

  let action = if $failed_disk != null { "build-failed" } else if $dry_run { "planned" } else { "built" }
  {
    schema_version: "v1"
    profile: "microvm"
    dry_run: $dry_run
    action: $action
    failed_step: (if $failed_disk != null { $"state_disk_($failed_disk.name)" } else { null })
    error: (if $failed_disk != null { $failed_disk.error? | default null } else { null })
    image_path: $elf_path
    boot: {
      mode: ($boot.mode? | default "direct-kernel")
      protocol: ($boot.protocol? | default "pvh")
      vmm: $vmms
      cmdline: $cmdline
      memory_mb: $mem_mb
      vcpus: $vcpus
      ready_marker: ($boot.ready_marker? | default null)
      root_disk: false
      kernel_config: ($manifest.kernel?.config? | default "")
      kernel_version: ($art.version? | default null)
      artifact_source: ($art.path? | default ($art.url? | default ""))
      artifact_sha256: $boot_sha
      artifact_size_bytes: $boot_size
      rootfs: {
        type: $rtype
        path: $rootfs_out
        sha256: (if $rtype == "embedded" { null } else { $s3.sha256? | default "PLACEHOLDER_DRY_RUN" })
        device: ($rootfs.device? | default null)
      }
    }
    state_disks: ($disk_records | reject -o argv tools)
    launch: {
      firecracker: $firecracker
      firecracker_config_path: (if $firecracker != null { $fc_path } else { null })
      qemu_microvm: $qemu
    }
    steps: $steps
  }
}
