# Linode rescue + dd deploy adapter
# Path 3: rescue mode + dd — officially documented by Linode
# Bypasses ext3/ext4 requirement entirely by writing raw bytes directly to /dev/sda
# SPDX-License-Identifier: BSD-2-Clause

export def linode_deploy [
  manifest: record
  image_path: string
  --dry-run        # Return the deployment plan without executing any linode-cli calls
] {
  let image_name = ($manifest | get image?.name? | default "genoa-freebsd")
  let region     = ($manifest | get deploy?.region? | default "us-east")
  let plan       = ($manifest | get deploy?.plan?   | default "g6-nanog-1")
  let image_url  = ($manifest | get image_url?      | default "")

  # Dry-run guard FIRST — before any file existence checks
  if $dry_run {
    let image_sha256 = "dry-run-placeholder"
    let steps = [
      {
        step: 1
        action: "create_linode"
        automated: true
        command: "linode-cli linodes create"
        cmd: $"linode-cli linodes create --type ($plan) --region ($region) --no-image --label ($image_name)-temp --json"
        description: "Create a raw Linode with unformatted disk (bypasses ext3/ext4 requirement)"
        args: {
          type: $plan
          region: $region
          image: ""
          label: $"($image_name)-temp"
        }
        notes: [
          "Create disk as RAW/unformatted, NOT ext3/ext4"
          "This avoids the image upload filesystem requirement"
          "Linode returns instance ID"
        ]
        response_fields: ["id"]
      }
      {
        step: 2
        action: "boot_rescue"
        automated: true
        command: "linode-cli linodes rescue"
        cmd: "linode-cli linodes rescue <id-from-step-1> --devices.sda.disk_id=<disk-id> --json"
        description: "Boot into Finnix rescue mode"
        args: {
          linode_id: "<id-from-step-1>"
        }
        notes: [
          "Rescue mode boots Finnix (Debian-based live system)"
          "No filesystem check enforced in rescue mode"
          "SSH will be available after boot"
        ]
      }
      {
        step: 3
        action: "poll_rescue_ready"
        automated: true
        description: "Poll until status=running (max 20 × 15s)"
        command: "linode-cli linodes view"
        cmd: "linode-cli linodes view <id-from-step-1> --json"
        args: {linode_id: "<id-from-step-1>"}
      }
      {
        step: 4
        action: "dd_image"
        automated: false
        manual_reason: "Requires SSH access to rescue shell; cannot automate without pre-provisioned SSH key and IP"
        cmd: $"ssh root@<rescue-ip> 'curl -fsSL ($image_path) | dd of=/dev/sda bs=1M conv=fsync status=progress'"
        note: "SSH into rescue environment and write image to disk — may take 1-2 min after status=running"
      }
      {
        step: 5
        action: "reboot"
        automated: true
        command: "linode-cli linodes reboot"
        cmd: "linode-cli linodes reboot <id-from-step-1> --json"
        note: "Reboot into FreeBSD"
      }
      {
        step: 6
        action: "set_direct_disk_kernel"
        automated: true
        command: "linode-cli linodes config-update"
        cmd: "linode-cli linodes config-update <id-from-step-1> --kernel linode/direct-disk --json"
        description: "Switch to direct disk kernel after reboot"
        args: {
          linode_id: "<id-from-step-1>"
          kernel: "linode/direct-disk"
        }
        notes: [
          "Direct Disk mode uses the MBR/GPT bootloader directly"
          "Disable all helpers — BSD has its own configuration"
        ]
      }
    ]

    let warnings = [
      "no-backup-service: Linode Backup Service does not support non-ext filesystems"
      "no-password-reset: Cloud Manager password reset does not work for BSD"
      "serial-console-required: ensure comconsole at 115200 baud in /boot/loader.conf"
    ]

    return {
      action: "would-run"
      provider: "linode"
      mode: "dry-run"
      strategy: "rescue-dd"
      image_name: $image_name
      image_path: $image_path
      image_sha256: $image_sha256
      plan: {
        steps: $steps
        warnings: $warnings
        notes: [
          "Requires linode-cli installed and LINODE_TOKEN set"
          "SSH access to rescue environment required for manual steps"
          "Genoa publish step must complete before deployment"
          "This path is officially documented by Linode for FreeBSD"
          "ZFS, UFS2, or any BSD filesystem works (no ext3/ext4 requirement for raw disks)"
        ]
      }
    }
  }

  # --- Live deploy path ---

  # Verify image exists (live path only — dry-run skips this)
  if not ($image_path | path exists) {
    return {
      action: "failed"
      error: $"Image file not found: ($image_path)"
      step: 0
      provider: "linode"
    }
  }

  # Step 0 — credential and tool check
  let linode_cli = if ("/opt/homebrew/bin/linode-cli" | path exists) {
    "/opt/homebrew/bin/linode-cli"
  } else if (which linode-cli | length) > 0 {
    "linode-cli"
  } else {
    null
  }

  let api_token = if "LINODE_TOKEN" in $env { $env.LINODE_TOKEN } else { "" }

  if $linode_cli == null {
    return {action: "failed", reason: "linode-cli not found — install: pip3 install linode-cli", provider: "linode"}
  }
  if $api_token == "" {
    return {action: "failed", reason: "LINODE_TOKEN not set", provider: "linode"}
  }

  # Compute sha256 of the image (live path only)
  let image_sha256 = if ($nu.os-info.name == "macos") {
    (^shasum -a 256 $image_path | str trim | split column " " | get column1.0)
  } else {
    (^sha256sum $image_path | str trim | split column " " | get column1.0)
  }

  # Step 1 — create Linode instance (raw unformatted disk)
  let create_result = try {
    ^$linode_cli linodes create --type $plan --region $region --no-image --json | from json
  } catch { |e| return {action: "failed", step: "create_linode", error: $e.msg} }

  let linode_id = $create_result | get 0?.id? | default null
  if $linode_id == null {
    return {action: "failed", step: "create_linode", detail: $create_result}
  }

  # Step 2a — get the disk ID for the raw disk
  let disks_result = try {
    ^$linode_cli linodes disks-list $linode_id --json | from json
  } catch { |e| return {action: "failed", step: "list_disks", linode_id: $linode_id, error: $e.msg} }
  let disk_id = $disks_result | get 0?.id? | default null
  if $disk_id == null {
    return {action: "failed", step: "list_disks", reason: "no disks found on new Linode", detail: $disks_result}
  }

  # Step 2b — boot into rescue mode
  let rescue_result = (^$linode_cli linodes rescue $linode_id $"--devices.sda.disk_id=($disk_id)" --json | complete)
  if $rescue_result.exit_code != 0 {
    return {action: "failed", step: "rescue_boot", linode_id: $linode_id, error: $rescue_result.stderr}
  }

  # Step 3 — wait for rescue mode (poll status, max 20 attempts × 15s = 5 min)
  mut status = "provisioning"
  mut attempts = 0
  while $status != "running" and $attempts < 20 {
    ^sleep 15sec
    let info = try { ^$linode_cli linodes view $linode_id --json | from json } catch { [{status: "unknown"}] }
    $status = $info | get 0?.status? | default "unknown"
    $attempts = $attempts + 1
  }
  if $status != "running" {
    return {action: "failed", step: "wait_rescue", linode_id: $linode_id, status: $status}
  }

  # Steps 4-8 — structured handoff (SSH required; cannot automate without key+IP)
  let rescue_ip = try {
    ^$linode_cli linodes view $linode_id --json | from json | get 0?.ipv4?.0? | default "unknown"
  } catch {
    "unknown"
  }

  return {
    action: "rescue_ready"
    provider: "linode"
    linode_id: $linode_id
    rescue_ip: $rescue_ip
    status: "rescue_boot_complete"
    next_steps: [
      {step: 4, action: "manual_ssh",    cmd: $"ssh root@($rescue_ip)",                                                                           note: "SSH into rescue environment — may take 1-2 min after status=running"}
      {step: 5, action: "manual_verify", cmd: $"curl -fsSL ($image_path) | sha256sum",                                                            note: "Verify image sha256 in rescue shell"}
      {step: 6, action: "manual_dd",     cmd: $"curl -fsSL ($image_path) | dd of=/dev/sda bs=1M conv=fsync status=progress",                      note: "Write image to disk"}
      {step: 7, action: "manual_reboot", cmd: "shutdown -r now",                                                                                   note: "Reboot into FreeBSD"}
    ]
    post_boot: [
      {step: 8, action: "set_kernel",    cmd: $"^$linode_cli linodes config-update ($linode_id) --kernel linode/direct-disk",                     note: "Switch to direct disk kernel after reboot"}
    ]
    warnings: [
      "no-backup-service: Linode Backup Service does not support non-ext filesystems"
      "no-password-reset: Cloud Manager password reset does not work for BSD"
      "serial-console-required: ensure comconsole at 115200 baud in /boot/loader.conf"
    ]
  }
}
