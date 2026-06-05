# lib/build.nu — main build dispatch
# Sourced by genoa.nu. Requires: uefi_build, kboot_build, netbsd_build (from profiles/*.nu)
# find_vultr not needed here.

def "main build" [
  manifest_file: string
  --profile: string = "uefi"
  --dry-run
] {
  if not ($manifest_file | path exists) {
    error make {msg: $"manifest file not found: ($manifest_file)"}
  }
  let m = open $manifest_file

  # Fail-closed safety guard: reject shell-injection vectors before any
  # command string is constructed. build does not run `validate`, so this
  # check cannot be bypassed by invoking build directly with a crafted manifest.
  let safety = manifest_safety_check $m
  if not $safety.ok {
    return ({action: "failed", reason: "manifest_safety_check failed", errors: $safety.errors, manifest_path: $manifest_file} | to json --indent 2)
  }

  # CLI --profile flag takes precedence over manifest profile field
  let p = if ($profile | is-not-empty) { $profile } else { $m.profile? | default "uefi" }
  let profile_file = $"profiles/($p).nu"

  # Derive receipt path from manifest basename
  let manifest_basename = ($manifest_file | path basename | str replace --regex '\.[^.]+$' '')

  # Read output_dir from manifest (default ./out) and ensure it exists
  let output_dir = ($m.image?.output_dir? | default "./out")
  ^mkdir -p $output_dir

  # Derive canonical artifact names from manifest fields
  let image_name = ($m.image?.name? | default "genoa")
  let image_version = ($m.image?.version? | default "v0.0.0")
  let image_format = ($m.image?.format? | default "raw")
  let image_filename = $"($image_name)-($image_version).($image_format)"
  let receipt_filename = $"($image_name)-($image_version).receipt.json"

  let image_path = $"($output_dir)/($image_filename)"
  let receipt_path = $"($output_dir)/($receipt_filename)"

  # Remote build dispatch via target.build_host
  let build_host = ($m.target?.build_host? | default "")
  if $build_host != "" {
    let parts = ($build_host | split row ":")
    let ssh_dest = ($parts | first)
    let ssh_port = if ($parts | length) > 1 { $parts | last } else { "22" }
    let remote_manifest = $"/tmp/genoa-remote-($manifest_basename).toml"
    if $dry_run {
      return ({
        action: "would-run"
        build_host: $build_host
        ssh_dest: $ssh_dest
        ssh_port: $ssh_port
        remote_manifest: $remote_manifest
        cmd: $"scp -P ($ssh_port) ($manifest_file) ($ssh_dest):($remote_manifest) && ssh -p ($ssh_port) ($ssh_dest) 'nu ~/genoa/genoa.nu build ($remote_manifest) --profile ($p)'"
        note: "Remote build via target.build_host. Run without --dry-run to execute."
      } | to json --indent 2)
    }
    let scp_result = try {
      ^scp -P $ssh_port $manifest_file $"($ssh_dest):($remote_manifest)" | complete
    } catch { |e|
      return ({action: "failed", step: "scp_manifest", error: $e.msg, build_host: $build_host} | to json --indent 2)
    }
    if $scp_result.exit_code != 0 {
      return ({action: "failed", step: "scp_manifest", stderr: $scp_result.stderr, build_host: $build_host} | to json --indent 2)
    }
    let ssh_result = try {
      ^ssh -p $ssh_port $ssh_dest $"nu ~/genoa/genoa.nu build ($remote_manifest) --profile ($p)" | complete
    } catch { |e|
      return ({action: "failed", step: "ssh_build", error: $e.msg, build_host: $build_host} | to json --indent 2)
    }
    if $ssh_result.exit_code != 0 {
      return ({action: "failed", step: "ssh_build", exit_code: $ssh_result.exit_code, stderr: $ssh_result.stderr} | to json --indent 2)
    }
    let remote_result = try { $ssh_result.stdout | from json } catch { {raw: $ssh_result.stdout} }

    # SCP artifacts back from remote to local output_dir
    let remote_image = $remote_result.image?.path? | default $"./out/($image_filename)"
    let remote_receipt = $"($remote_image | path parse | get parent)/($remote_image | path basename | str replace -r '\\.\\w+$' '.receipt.json')"

    let scp_image = try {
      ^scp -P $ssh_port $"($ssh_dest):($remote_image)" $output_dir | complete
    } catch { |e| {exit_code: -1, stderr: $e.msg} }

    if $scp_image.exit_code != 0 {
      return ({action: "failed", step: "scp_image_back", stderr: $scp_image.stderr, build_host: $build_host, remote_result: $remote_result} | to json --indent 2)
    }

    let scp_receipt = try {
      ^scp -P $ssh_port $"($ssh_dest):($remote_receipt)" $output_dir | complete
    } catch { |e| {exit_code: -1, stderr: $e.msg} }

    # Receipt SCP failure is a warning, not a hard failure — but surface it
    # explicitly so callers can distinguish "receipt copy failed" from
    # "no receipt produced". An empty receipt_path alone is ambiguous.
    let receipt_back = if $scp_receipt.exit_code == 0 {
      $"($output_dir)/($remote_receipt | path basename)"
    } else {
      ""
    }
    let receipt_error = if $scp_receipt.exit_code == 0 { null } else { ($scp_receipt.stderr? | default "receipt scp failed") }

    return ($remote_result | merge {
      build_host: $build_host
      remote: true
      image_path: $"($output_dir)/($remote_image | path basename)"
      receipt_path: $receipt_back
      receipt_error: $receipt_error
    } | to json --indent 2)
  }

  let build_result = if not ($profile_file | path exists) {
    {action: "failed", reason: $"unknown profile: ($p); supported: uefi, kboot, netbsd", profile: $p}
  } else if $p == "kboot" {
    kboot_build $m $dry_run
  } else if $p == "netbsd" {
    netbsd_build $m $dry_run
  } else {
    uefi_build $m $dry_run
  }

  # Both kboot_build and uefi_build return records directly.
  let build_record = $build_result

  # Write receipt file
  let is_freebsd = try { (^uname -s | str trim) == "FreeBSD" } catch { false }
  # Distinct sentinels: PLACEHOLDER_DRY_RUN means "hash intentionally not
  # computed" (dry-run or cross-host build where the image is not local).
  # HASH_COMPUTATION_FAILED means the hash tool ran and genuinely failed — the
  # receipt must not claim a placeholder as if it were a real, deliberate value.
  let image_sha256 = if $dry_run { "PLACEHOLDER_DRY_RUN" } else {
    if $is_freebsd and ($image_path | path exists) {
      try { ^sha256 -q $image_path | str trim } catch { "HASH_COMPUTATION_FAILED" }
    } else {
      "PLACEHOLDER_DRY_RUN"
    }
  }
  let manifest_sha256 = try {
    ^sha256 -q $manifest_file | str trim  # FreeBSD
  } catch {
    try { ^sha256sum $manifest_file | split row " " | first | str trim } catch { (if $dry_run { "PLACEHOLDER_DRY_RUN" } else { "HASH_COMPUTATION_FAILED" }) }
  }

  # Signing step — runs after image write, before receipt
  let signing_cfg = ($m.signing? | default {tool: "none"})
  let sign_result = if (($signing_cfg.tool? | default "none") == "signify") {
    let key_file = ($signing_cfg.key_file? | default "")
    let pub_key_file = ($signing_cfg.public_key_file? | default "")

    if $dry_run {
      {action: "would-sign", tool: "signify", key_file: $key_file, image: $image_path}
    } else if $key_file == "" {
      {action: "failed", step: "signing", error: "signing.key_file is required when tool=signify"}
    } else if not ($key_file | path exists) {
      {action: "failed", step: "signing", error: $"key_file not found: ($key_file)"}
    } else {
      # Locate signify binary
      let signify_bin = if ("/usr/bin/signify" | path exists) { "/usr/bin/signify" }
        else if ("/usr/local/bin/signify" | path exists) { "/usr/local/bin/signify" }
        else if ("/usr/local/bin/signify-ossl" | path exists) { "/usr/local/bin/signify-ossl" }
        else { "" }

      if $signify_bin == "" {
        {action: "failed", step: "signing", error: "signify not found; install signify or signify-ossl"}
      } else {
        # signify -S -s key.sec -m image_file  ->  produces image_file.sig
        let sign_out = try {
          ^$signify_bin -S -s $key_file -m $image_path | complete
        } catch { |e| {exit_code: -1, stderr: $e.msg} }

        if $sign_out.exit_code == 0 {
          {action: "signed", tool: "signify", sig_file: $"($image_path).sig", public_key_file: $pub_key_file}
        } else {
          {action: "failed", step: "signing", stderr: ($sign_out.stderr? | default "signify error")}
        }
      }
    }
  } else {
    {action: "unsigned", tool: "none"}
  }

  let receipt = {
    schema_version: "v1"
    receipt_id: (random uuid)
    built_at: (date now | format date "%Y-%m-%dT%H:%M:%SZ")
    image: {
      name: ($m.image?.name? | default "unknown")
      version: ($m.image?.version? | default "v0.0.0")
      format: ($m.image?.format? | default "raw")
      output_path: $image_path
    }
    build: {
      host: (try { ^uname -n | str trim } catch { "unknown" })
      builder_type: (if $dry_run { "dry-run" } else if $is_freebsd { "genoa-local" } else { "genoa-crosshost" })
      os_version: ($m.target?.os_version? | default "unknown")
      arch: ($m.target?.arch? | default "unknown")
      genoa_version: "v0.1.0"
      profile: $p
      dry_run: $dry_run
    }
    agent: {
      name: ($m.agent?.name? | default "unknown")
      version: ($m.agent?.version? | default "v0.0.0")
      install_path: ($m.agent?.install_path? | default "/usr/local/bin/agent")
    }
    hashes: {
      image_sha256: $image_sha256
      manifest_sha256: $manifest_sha256
      manifest_path: $manifest_file
    }
    signing: $sign_result
    claims: (do {
      let claim_status = if $dry_run { "unverified" } else if $is_freebsd { "verified" } else { "unverified" }
      [
        {
          claim: $"image sha256 is ($image_sha256)"
          executor: "sh"
          probe: $"openssl dgst -sha256 -r ($image_path) | awk '{print $1}'"
          expect: $image_sha256
          status: $claim_status
        }
        {
          claim: $"manifest sha256 is ($manifest_sha256)"
          executor: "sh"
          probe: $"openssl dgst -sha256 -r ($manifest_file) | awk '{print $1}'"
          expect: $manifest_sha256
          status: "verified"
        }
        {
          claim: $"agent name is ($m.agent?.name? | default "unknown")"
          executor: "nu"
          probe: $"nu genoa.nu describe ($manifest_file) | from json | get agent | get name"
          expect: ($m.agent?.name? | default "unknown")
          status: "asserted"
        }
        {
          claim: $"image format is ($m.image?.format? | default "raw")"
          executor: "sh"
          probe: $"file ($image_path)"
          expect: ($m.image?.format? | default "raw")
          status: $claim_status
        }
        {
          claim: $"target os is ($m.target?.os? | default "freebsd")"
          executor: "nu"
          probe: $"nu genoa.nu describe ($manifest_file) | from json | get target | get os"
          expect: ($m.target?.os? | default "freebsd")
          status: "asserted"
        }
      ]
    })
  }

  $receipt | save --force $receipt_path

  # Return build plan with receipt_path appended
  $build_record | merge {receipt_path: $receipt_path} | to json --indent 2
}
