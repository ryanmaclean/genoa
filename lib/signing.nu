# lib/signing.nu — main sign, main verify-image
# Sourced by genoa.nu.

def "main sign" [
  image_path: string
  --key: string = ""
  --tool: string = ""
  --manifest: string = ""
  --dry-run
] {
  # Resolve tool and key from manifest if not overridden by CLI flags
  let m = if $manifest != "" and ($manifest | path exists) {
    open $manifest
  } else {
    {}
  }
  let effective_tool = if $tool != "" { $tool } else { ($m | get -o signing.tool | default "none") }
  # Schema + build.nu use signing.key_file; accept signing.key_path as a legacy alias.
  let effective_key  = if $key  != "" { $key  } else { ($m | get -o signing.key_file | default ($m | get -o signing.key_path | default "")) }

  if $effective_tool == "none" {
    return ({action: "unsigned", tool: "none", image: $image_path} | to json --indent 2)
  }

  # Validate tool name
  if $effective_tool != "signify" and $effective_tool != "minisign" {
    return ({action: "failed", reason: $"unknown signing tool: ($effective_tool). valid: signify minisign none"} | to json --indent 2)
  }

  let binary_name = $effective_tool
  let sig_ext = if $effective_tool == "signify" { "sig" } else { "minisig" }
  let sig_path = $"($image_path).($sig_ext)"
  let sign_cmd = if $effective_tool == "signify" {
    $"signify -S -s ($effective_key) -m ($image_path)"
  } else {
    $"minisign -S -s ($effective_key) -m ($image_path)"
  }

  if $dry_run {
    return ({action: "would-run", tool: $effective_tool, cmd: $sign_cmd, signature_path: $sig_path, image: $image_path} | to json --indent 2)
  }

  # Validate key exists
  if $effective_key == "" or not ($effective_key | path exists) {
    return ({action: "failed", reason: $"signing key not found: ($effective_key)", tool: $effective_tool} | to json --indent 2)
  }

  # Validate image exists
  if not ($image_path | path exists) {
    return ({action: "failed", reason: $"image not found: ($image_path)", tool: $effective_tool} | to json --indent 2)
  }

  # Locate the signing binary
  let bin_paths = ["/usr/bin" "/usr/local/bin" "/opt/homebrew/bin"]
  let found_bin = ($bin_paths | each { |p| $"($p)/($binary_name)" } | where { |p| ($p | path exists) } | get 0?)
  let bin = if $found_bin != null { $found_bin } else { $binary_name }

  let result = try {
    ^$bin -S -s $effective_key -m $image_path | complete
  } catch { |e|
    return ({action: "failed", reason: $e.msg, tool: $effective_tool} | to json --indent 2)
  }

  if $result.exit_code != 0 {
    return ({action: "failed", reason: ($result.stderr? | default "signing tool returned non-zero exit"), tool: $effective_tool, exit_code: $result.exit_code} | to json --indent 2)
  }

  # Exit 0 does not guarantee the signature artifact was written (disk full,
  # parent-dir permissions). Confirm the .sig/.minisig file actually exists.
  if not ($sig_path | path exists) {
    return ({action: "failed", reason: "signature_file_not_created", tool: $effective_tool, signature_path: $sig_path} | to json --indent 2)
  }

  {action: "signed", tool: $effective_tool, image: $image_path, signature: $sig_path, key: $effective_key} | to json --indent 2
}

def "main verify-image" [
  image_path: string
  --profile: string = "uefi"
  --dry-run                    # dry-run: return planned checks without mounting image
] {
  let platform = try { ^uname -s | str trim } catch { "unknown" }

  if $dry_run {
    return ({
      action:     "verify-image"
      image_path: $image_path
      profile:    $profile
      dry_run:    true
      planned_checks: ["loader_conf_present" "loader_conf_vfs_root" "rc_conf_present" "rc_conf_sshd_enable" "agent_dir_present"]
      checks:     ["loader_conf_present" "loader_conf_vfs_root" "rc_conf_present" "rc_conf_sshd_enable" "agent_dir_present"]
      note:       "dry-run: would mount image and check these files"
    } | to json --indent 2)
  }

  if $platform != "FreeBSD" {
    return ({action: "verify-image" image_path: $image_path profile: $profile
            ok: false skipped: true platform: $platform
            reason: $"verify-image requires FreeBSD \(mdconfig/mount\)"} | to json --indent 2)
  }

  if not ($image_path | path exists) {
    return ({action: "verify-image" image_path: $image_path ok: false
            error: $"image not found: ($image_path)"} | to json --indent 2)
  }

  # Attach image
  let md_dev = try {
    ^mdconfig -a -t vnode -f $image_path -o readonly | str trim
  } catch { |e|
    return ({action: "verify-image" ok: false error: $"mdconfig failed: ($e.msg)"} | to json --indent 2)
  }

  # Mount
  let mount_result = try {
    ^mount -o ro $"/dev/($md_dev)p2" /mnt
    "ok"
  } catch { |e|
    ^mdconfig -d -u ($md_dev | str replace "md" "")
    return ({action: "verify-image" ok: false error: $"mount failed: ($e.msg)"} | to json --indent 2)
  }

  # Run checks
  let checks = [
    (do {
      let p = "/mnt/boot/loader.conf"
      let exists = $p | path exists
      if $exists {
        let sz = (ls $p | get size.0 | into int)
        {check: "loader_conf_present" pass: true detail: $"found, ($sz) bytes"}
      } else {
        {check: "loader_conf_present" pass: false detail: "not found"}
      }
    })
    (do {
      let p = "/mnt/boot/loader.conf"
      if ($p | path exists) {
        let content = open --raw $p
        let has_vfs = ($content | str contains "vfs.root.mountfrom")
        if $has_vfs {
          let line = ($content | lines | where { |l| $l | str starts-with "vfs.root.mountfrom" } | get 0? | default "")
          {check: "loader_conf_vfs_root" pass: true detail: ($line | str trim)}
        } else {
          {check: "loader_conf_vfs_root" pass: false detail: "vfs.root.mountfrom not found in loader.conf"}
        }
      } else {
        {check: "loader_conf_vfs_root" pass: false detail: "loader.conf missing"}
      }
    })
    (do {
      let p = "/mnt/etc/rc.conf"
      let exists = $p | path exists
      if $exists {
        let sz = (ls $p | get size.0 | into int)
        {check: "rc_conf_present" pass: true detail: $"found, ($sz) bytes"}
      } else {
        {check: "rc_conf_present" pass: false detail: "not found"}
      }
    })
    (do {
      let p = "/mnt/etc/rc.conf"
      if ($p | path exists) {
        let content = open --raw $p
        let has_sshd = ($content | str contains "sshd_enable=\"YES\"")
        if $has_sshd {
          {check: "rc_conf_sshd_enable" pass: true detail: "sshd_enable=\"YES\""}
        } else {
          {check: "rc_conf_sshd_enable" pass: false detail: "sshd_enable=YES not found in rc.conf"}
        }
      } else {
        {check: "rc_conf_sshd_enable" pass: false detail: "rc.conf missing"}
      }
    })
    (do {
      let p = "/mnt/usr/local/bin"
      let exists = $p | path exists
      {check: "agent_dir_present" pass: $exists detail: (if $exists { "/usr/local/bin/ exists" } else { "/usr/local/bin/ missing" })}
    })
  ]

  let ok = ($checks | where pass == false | length) == 0

  # Cleanup
  try { ^umount /mnt } catch {}
  try { ^mdconfig -d -u ($md_dev | str replace "md" "") } catch {}

  {
    action: "verify-image"
    image_path: $image_path
    profile: $profile
    checks: $checks
    ok: $ok
    platform: $platform
  } | to json --indent 2
}
