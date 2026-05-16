# Linode rescue + dd deploy adapter
# Path 3: rescue mode + dd — officially documented by Linode
# Bypasses ext3/ext4 requirement entirely by writing raw bytes directly to /dev/sda
# SPDX-License-Identifier: BSD-2-Clause

# linode_rescue_plan — returns the full rescue-dd deployment plan as a structured record.
# Callers pass the manifest and image_url (from a publish receipt); sha256 is optional.
export def linode_rescue_plan [
  manifest: record
  image_url: string
  --sha256: string = ""   # expected SHA256 of the image (from receipt); leave empty if unknown
] {
  let linode_id = ($manifest | get deploy?.linode_id? | default null)
  let region    = ($manifest | get deploy?.region?    | default "us-east")
  let hostname  = ($manifest | get network?.hostname? | default "smolbsd")

  let sha256_val = if $sha256 == "" { "" } else { $sha256 }

  let verify_cmd = if $sha256_val == "" {
    "# sha256 not available yet — fill in from receipt after publish"
  } else {
    $"echo '($sha256_val)  /dev/sda' | sha256sum -c"
  }

  {
    action:           "rescue-dd-plan"
    provider:         "linode_akamai"
    method:           "rescue-dd"
    linode_id:        $linode_id
    region:           $region
    hostname:         $hostname
    image_url:        $image_url
    rescue_boot_cmd:  (if $linode_id != null {
                         $"linode-cli linodes rescue ($linode_id)"
                       } else {
                         "linode-cli linodes rescue <linode_id>"
                       })
    rescue_ssh_note:  "SSH into rescue: ssh root@<linode-ip> (use Lish console if SSH unavailable)"
    dd_cmd:           $"wget -O - ($image_url) | dd of=/dev/sda bs=1M status=progress"
    verify_cmd:       $verify_cmd
    reboot_cmd:       (if $linode_id != null {
                         $"linode-cli linodes reboot ($linode_id)"
                       } else {
                         "linode-cli linodes reboot <linode_id>"
                       })
    wait_ssh_note:    $"ssh root@<linode-ip> — expect FreeBSD login prompt for ($hostname)"
    steps: [
      "1. Boot Linode into rescue mode via Linode Manager or CLI"
      "2. SSH into rescue environment (or use Lish console)"
      $"3. Run: wget -O - ($image_url) | dd of=/dev/sda bs=1M status=progress"
      "4. Verify SHA256 of /dev/sda matches receipt"
      "5. Reboot Linode back into normal mode"
      "6. Wait 60-90 seconds for FreeBSD to boot"
      "7. SSH as root (key from manifest.network.ssh_keys)"
    ]
    note: "Linode rescue mode uses a minimal Debian (Finnix) environment. Image must be served via HTTP/HTTPS. dd writes directly to /dev/sda (raw disk, no partition table needed for genoa images)."
  }
}

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
    # Use image_url from manifest if available; otherwise construct a placeholder
    let effective_image_url = if $image_url != "" {
      $image_url
    } else {
      $"https://<your-image-host>/($image_name).raw"
    }

    let rescue_plan = (linode_rescue_plan $manifest $effective_image_url)

    return {
      action:         "would-run"
      provider:       "linode_akamai"
      method:         "rescue-dd"
      linode_id:      ($rescue_plan | get linode_id)
      steps:          [
        "boot-linode-into-rescue-mode"
        "ssh-into-rescue-environment"
        "wget-image-to-dev-sda"
        "verify-sha256"
        "reboot-linode"
        "wait-for-boot"
        "verify-ssh"
      ]
      rescue_dd_cmd:  ($rescue_plan | get dd_cmd)
      rescue_plan:    $rescue_plan
      note:           "Linode rescue mode uses a minimal Debian environment. Image must be served via HTTP (not HTTPS with self-signed). dd writes directly to /dev/sda (raw disk, no partition table needed)."
      warnings: [
        "no-backup-service: Linode Backup Service does not support non-ext filesystems"
        "no-password-reset: Cloud Manager password reset does not work for BSD"
        "serial-console-required: ensure comconsole at 115200 baud in /boot/loader.conf"
      ]
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
