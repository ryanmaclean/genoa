# Linode rescue + dd deploy adapter
# Path 3: rescue mode + dd — officially documented by Linode
# Bypasses ext3/ext4 requirement entirely by writing raw bytes directly to /dev/sda

def check-linode-cli [] {
  if ($env.PATH | split row (char esep) | any { |p| ($p | path join "linode-cli" | path exists) }) {
    return "linode-cli"
  }

  if ("/opt/homebrew/bin/linode-cli" | path exists) {
    return "/opt/homebrew/bin/linode-cli"
  }

  null
}

export def linode_deploy [manifest: record, image_path: string] {
  let linode_cli = check-linode-cli
  let image_name = (if ("name" in $manifest) { $manifest.name } else { "genoa-freebsd" })
  let region = (if ("region" in $manifest) { $manifest.region } else { "us-east" })
  let image_type = (if ("type" in $manifest) { $manifest.type } else { "g6-nanossd-1" })
  let image_url = (if ("image_url" in $manifest) { $manifest.image_url } else { "" })

  # Verify image exists
  let image_exists = $image_path | path exists

  if (not $image_exists) {
    return {
      action: "failed"
      error: $"Image file not found: ($image_path)"
      step: 1
    }
  }

  let image_sha256 = if ($nu.os-info.name == "macos") {
    (^shasum -a 256 $image_path | str trim | split column " " | get column1.0)
  } else {
    (^sha256sum $image_path | str trim | split column " " | get column1.0)
  }

  let linode_version = if ($linode_cli != null) {
    try {
      ^$linode_cli version | str trim
    } catch {
      "unknown"
    }
  } else {
    "not installed"
  }

  # Build the deployment plan as documented in RL1-REPORT
  let steps = [
    {
      step: 1
      action: "would-run"
      command: "linode-cli linodes create"
      description: "Create a raw Linode with unformatted disk (bypasses ext3/ext4 requirement)"
      args: {
        type: $image_type
        region: $region
        image: "linode/debian12"
        label: $"($image_name)-temp"
      }
      notes: [
        "Create disk as RAW/unformatted, NOT ext3/ext4"
        "This avoids the image upload filesystem requirement"
        "Linode returns instance ID and root_pass"
      ]
      response_fields: ["id" "disk_id" "root_password"]
    }
    {
      step: 2
      action: "would-run"
      command: "linode-cli linodes rescue"
      description: "Boot into Finnix rescue mode"
      args: {
        linode_id: "<id-from-step-1>"
        disk_id: "<disk_id-from-step-1>"
      }
      notes: [
        "Rescue mode boots Finnix (Debian-based live system)"
        "No filesystem check enforced in rescue mode"
        "SSH will be available after boot"
      ]
    }
    {
      step: 3
      action: "manual"
      description: "SSH to rescue console (LISH or direct)"
      notes: [
        "SSH to root@<linode-public-ip> using root_pass from step 1"
        "Or use GLISH (graphical) console from Cloud Manager"
        "Once in rescue: passwd to set a real password, then: service ssh start"
      ]
      example_cmd: "ssh root@<linode-ip>"
    }
    {
      step: 4
      action: "would-run"
      command: "curl + sha256sum (in rescue)"
      description: "Verify image before writing"
      script: $"curl -fSL ($image_url).sha256 | sha256sum -c -"
      notes: [
        "Always verify before dd to prevent corrupted writes"
        "Image URL must be accessible from rescue environment"
        "SHA256 file format: <hash>  <filename>"
      ]
    }
    {
      step: 5
      action: "would-run"
      command: "curl | dd (in rescue)"
      description: "Stream image and write to /dev/sda"
      script: $"curl -fSL ($image_url) | dd of=/dev/sda bs=4M conv=fsync status=progress"
      notes: [
        "Stream directly to disk — no temp file needed"
        "bs=4M: 4 MiB block size for performance"
        "conv=fsync: force sync to disk"
        "status=progress: show bytes written"
      ]
    }
    {
      step: 6
      action: "would-run"
      command: "sync + blockdev (in rescue)"
      description: "Ensure disk writes complete"
      script: "sync && blockdev --rereadpt /dev/sda 2>/dev/null || true"
      notes: [
        "sync: flush all buffers"
        "blockdev --rereadpt: re-read partition table (may fail harmlessly)"
        "Next step will reboot into the new OS"
      ]
    }
    {
      step: 7
      action: "would-run"
      command: "linode-cli linodes config-update"
      description: "Configure Direct Disk boot (critical for BSD)"
      args: {
        linode_id: "<id-from-step-1>"
        config_id: "<config-id>"
        kernel: "linode/direct-disk"
        helpers: {
          network: false
          modules_dep: false
          updatedb_disabled: false
        }
      }
      notes: [
        "Direct Disk mode uses the MBR/GPT bootloader directly"
        "Disable all helpers — BSD has its own configuration"
        "Get config_id from: linode-cli linodes configs-list <linode-id>"
      ]
    }
    {
      step: 8
      action: "would-run"
      command: "linode-cli linodes boot"
      description: "Reboot into the new BSD OS"
      args: {
        linode_id: "<id-from-step-1>"
      }
      notes: [
        "Instance boots into the newly written image"
        "First boot may take 1-2 minutes"
      ]
    }
  ]

  let warnings = [
    {
      severity: "warning"
      name: "no-backup-service"
      description: "Linode Backup Service does not support non-ext filesystems"
      impact: "Manual backups via snapshots only"
    }
    {
      severity: "warning"
      name: "no-password-reset"
      description: "Cloud Manager password reset does not work for BSD"
      impact: "Use SSH keys; set password during initial image config"
    }
    {
      severity: "critical"
      name: "serial-console-required"
      description: "Ensure comconsole at 115200 baud in /boot/loader.conf"
      impact: "Without this, LISH console access will not work"
      example_config: "console=\"comconsole,vidconsole\""
    }
    {
      severity: "warning"
      name: "raw-disk-only"
      description: "Disks must be created as RAW format in Cloud Manager"
      impact: "The ext3/ext4 requirement applies only to image uploads — not to raw disks"
    }
  ]

  return {
    provider: "linode"
    path: "Path 3: Rescue + dd (officially documented)"
    manifest: $manifest
    image_name: $image_name
    image_path: $image_path
    image_sha256: $image_sha256
    image_size_bytes: (ls $image_path | get 0.size)
    linode_cli_version: $linode_version
    plan: {
      steps: $steps
      warnings: $warnings
      notes: [
        "Requires linode-cli installed and LINODE_TOKEN set"
        "SSH access to rescue environment required for step 3"
        "Genoa publish step must complete before deployment"
        "This path is officially documented by Linode for FreeBSD (Install FreeBSD on Linode guide)"
        "ZFS, UFS2, or any BSD filesystem works (no ext3/ext4 requirement for raw disks)"
      ]
    }
  }
}
