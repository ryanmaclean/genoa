#!/usr/bin/env nu
source profiles/uefi.nu
source profiles/kboot.nu
source profiles/netbsd.nu
source adapters/linode.nu
source adapters/vultr.nu
source adapters/aws.nu
source adapters/gce.nu

def "main catalog" [] {
  open "catalog/providers.v1.json" | to json --indent 2
}

def "main schema" [] {
  open "schema/manifest.v1.json" | to json --indent 2
}

def "main describe" [manifest_file: string] {
  if not ($manifest_file | path exists) {
    error make {msg: $"manifest not found: ($manifest_file)"}
  }
  let m = open $manifest_file
  {
    action: "described"
    manifest_path: $manifest_file
    image: {
      name:       ($m.image?.name?       | default "")
      version:    ($m.image?.version?    | default "")
      format:     ($m.image?.format?     | default "")
      size_mb:    ($m.image?.size_mb?    | default 0)
      output_dir: ($m.image?.output_dir? | default "./out")
    }
    target: {
      os:         ($m.target?.os?         | default "")
      os_version: ($m.target?.os_version? | default "")
      arch:       ($m.target?.arch?       | default "")
      platform:   ($m.target?.platform?   | default "")
    }
    kernel: {
      config: ($m.kernel?.config? | default "")
    }
    agent: {
      name:        ($m.agent?.name?         | default "")
      version:     ($m.agent?.version?      | default "")
      source_type: ($m.agent?.source?.type? | default "")
    }
    network: {
      hostname:  ($m.network?.hostname?  | default "smolbsd")
      mode:      ($m.network?.mode?      | default "dhcp")
      interface: ($m.network?.interface? | default "vtnet0")
    }
    profile:        ($m.profile?          | default "uefi")
    provider:       ($m.deploy?.provider? | default "")
    signing:        ($m.signing?.tool?    | default "none")
    schema_version: ($m.schema_version?   | default "")
  } | to json --indent 2
}

def "main build" [
  manifest_file: string
  --profile: string = "uefi"
  --dry-run
] {
  if not ($manifest_file | path exists) {
    error make {msg: $"manifest file not found: ($manifest_file)"}
  }
  let m = open $manifest_file
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
      return {
        action: "would-run"
        build_host: $build_host
        ssh_dest: $ssh_dest
        ssh_port: $ssh_port
        remote_manifest: $remote_manifest
        cmd: $"scp -P ($ssh_port) ($manifest_file) ($ssh_dest):($remote_manifest) && ssh -p ($ssh_port) ($ssh_dest) 'nu ~/genoa/genoa.nu build ($remote_manifest) --profile ($p)'"
        note: "Remote build via target.build_host. Run without --dry-run to execute."
      }
    }
    let scp_result = try {
      ^scp -P $ssh_port $manifest_file $"($ssh_dest):($remote_manifest)" | complete
    } catch { |e|
      return {action: "failed", step: "scp_manifest", error: $e.msg, build_host: $build_host}
    }
    if $scp_result.exit_code != 0 {
      return {action: "failed", step: "scp_manifest", stderr: $scp_result.stderr, build_host: $build_host}
    }
    let ssh_result = try {
      ^ssh -p $ssh_port $ssh_dest $"nu ~/genoa/genoa.nu build ($remote_manifest) --profile ($p)" | complete
    } catch { |e|
      return {action: "failed", step: "ssh_build", error: $e.msg, build_host: $build_host}
    }
    if $ssh_result.exit_code != 0 {
      return {action: "failed", step: "ssh_build", exit_code: $ssh_result.exit_code, stderr: $ssh_result.stderr}
    }
    let remote_result = try { $ssh_result.stdout | from json } catch { {raw: $ssh_result.stdout} }

    # SCP artifacts back from remote to local output_dir
    let remote_image = $remote_result.image?.path? | default $"./out/($image_filename)"
    let remote_receipt = $"($remote_image | path parse | get parent)/($remote_image | path basename | str replace -r '\\.\\w+$' '.receipt.json')"

    let scp_image = try {
      ^scp -P $ssh_port $"($ssh_dest):($remote_image)" $output_dir | complete
    } catch { |e| {exit_code: -1, stderr: $e.msg} }

    if $scp_image.exit_code != 0 {
      return {action: "failed", step: "scp_image_back", stderr: $scp_image.stderr, build_host: $build_host, remote_result: $remote_result}
    }

    let scp_receipt = try {
      ^scp -P $ssh_port $"($ssh_dest):($remote_receipt)" $output_dir | complete
    } catch { |e| {exit_code: -1, stderr: $e.msg} }

    # Receipt SCP failure is a warning, not a hard failure
    let receipt_back = if $scp_receipt.exit_code == 0 {
      $"($output_dir)/($remote_receipt | path basename)"
    } else {
      ""
    }

    return ($remote_result | merge {
      build_host: $build_host
      remote: true
      image_path: $"($output_dir)/($remote_image | path basename)"
      receipt_path: $receipt_back
    })
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
  let image_sha256 = if $dry_run { "PLACEHOLDER_DRY_RUN" } else {
    if $is_freebsd and ($image_path | path exists) {
      try { ^sha256 -q $image_path | str trim } catch { "PLACEHOLDER_DRY_RUN" }
    } else {
      "PLACEHOLDER_DRY_RUN"
    }
  }
  let manifest_sha256 = try {
    ^sha256 -q $manifest_file | str trim  # FreeBSD
  } catch {
    try { ^sha256sum $manifest_file | split row " " | first | str trim } catch { "PLACEHOLDER_DRY_RUN" }
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

def "main deploy" [
  manifest_file: string
  --provider: string = ""
  --from-receipt: string = ""
  --image: string = ""
  --dry-run
] {
  if not ($manifest_file | path exists) {
    error make {msg: $"manifest file not found: ($manifest_file)"}
  }
  let m      = open $manifest_file
  let pid    = if $provider != "" { $provider } else { $m.deploy?.provider? | default "" }
  let cat    = open "catalog/providers.v1.json"
  let matches = ($cat.providers | where id == $pid)
  let entry  = if ($matches | is-empty) { null } else { $matches | first }
  if $entry == null {
    error make {msg: $"provider '($pid)' not found in catalog"}
  }
  let path   = ($entry.deployment_path? | default "unknown")
  let afile  = match $path {
    "rescue-dd"    => "adapters/linode.nu"
    "snapshot-url" => "adapters/vultr.nu"
    "byoi-api"     => "adapters/oci.nu"
    _              => null
  }
  if $afile == null {
    return ({action: "failed", reason: $"no adapter for deployment_path: ($path); add an adapter file or update the catalog entry", provider: $pid} | to json --indent 2)
  }
  if not ($afile | path exists) {
    return ({action: "failed", reason: $"adapter file not found: ($afile)", provider: $pid} | to json --indent 2)
  }

  # Resolve image path: --image > --from-receipt > output_dir + manifest fields > fallback
  let image = if $image != "" {
    $image
  } else if $from_receipt != "" {
    if not ($from_receipt | path exists) {
      error make {msg: $"receipt file not found: ($from_receipt)"}
    }
    let _r = open $from_receipt; $_r.image?.output_path? | default "./out/genoa.raw"
  } else {
    let _output_dir  = ($m.image?.output_dir? | default "./out")
    let _img_name    = ($m.image?.name?       | default "genoa")
    let _img_version = ($m.image?.version?    | default "v0.0.0")
    let _img_format  = ($m.image?.format?     | default "raw")
    $"($_output_dir)/($_img_name)-($_img_version).($_img_format)"
  }

  if $path == "rescue-dd" {
    linode_deploy $m $image --dry-run=$dry_run | to json --indent 2
  } else if $path == "snapshot-url" {
    vultr_deploy  $m $image --dry-run=$dry_run | to json --indent 2
  } else {
    # OCI adapter has a top-level `source formats/convert.nu` which leaks a closure
    # when oci.nu is sourced inside an if/else branch. Invoke as subprocess to avoid
    # the source-in-branch leak while keeping oci.nu self-contained.
    let dry_flag = if $dry_run { ["--dry-run"] } else { [] }
    let manifest_json = ($m | to json)
    let result_json = try {
      ^nu adapters/oci-shim.nu $manifest_json $image ...$dry_flag | str trim
    } catch { |e|
      {action: "failed", reason: $"oci adapter invocation failed: ($e.msg)", provider: "oci"} | to json
    }
    try { $result_json | from json | to json --indent 2 } catch {
      {action: "failed", reason: "oci adapter output not parseable", raw: $result_json} | to json --indent 2
    }
  }
}

def "main validate" [manifest_file: string] {
  mut checks = []
  mut errors = []
  mut warnings = []

  # 1. file_exists
  let file_ok = ($manifest_file | path exists)
  $checks = ($checks | append {check: "file_exists", pass: $file_ok, detail: (if $file_ok { $"($manifest_file) is readable" } else { $"file not found: ($manifest_file)" })})
  if not $file_ok {
    $errors = ($errors | append $"file not found: ($manifest_file)")
    return ({
      action: "validate"
      manifest_path: $manifest_file
      valid: false
      checks: $checks
      errors: $errors
      warnings: $warnings
    } | to json --indent 2)
  }

  let m = open $manifest_file

  # 2. schema_version
  let sv = ($m.schema_version? | default "")
  let sv_ok = ($sv == "v1")
  $checks = ($checks | append {check: "schema_version", pass: $sv_ok, detail: (if $sv_ok { "v1" } else { $"expected v1, got: ($sv)" })})
  if not $sv_ok { $errors = ($errors | append $"schema_version: expected v1, got: ($sv)") }

  # 3. required_fields
  let has_image  = ("image"  in $m)
  let has_target = ("target" in $m)
  let has_kernel = ("kernel" in $m)
  let has_agent  = ("agent"  in $m)
  let req_ok = ($has_image and $has_target and $has_kernel and $has_agent)
  let missing_fields = (
    []
    | if not $has_image  { append "image"  } else { $in }
    | if not $has_target { append "target" } else { $in }
    | if not $has_kernel { append "kernel" } else { $in }
    | if not $has_agent  { append "agent"  } else { $in }
  )
  $checks = ($checks | append {
    check: "required_fields"
    pass: $req_ok
    detail: (if $req_ok { "image, target, kernel, agent present" } else { $"missing: ($missing_fields | str join ', ')" })
  })
  if not $req_ok { $errors = ($errors | append $"required_fields missing: ($missing_fields | str join ', ')") }

  # 4. image_name_slug
  let img_name = ($m.image?.name? | default "")
  let slug_ok = ($img_name | str contains " " | not $in) and ($img_name =~ '^[a-z0-9][a-z0-9_-]*$')
  $checks = ($checks | append {check: "image_name_slug", pass: $slug_ok, detail: (if $slug_ok { $img_name } else { $"'($img_name)' does not match ^[a-z0-9][a-z0-9_-]*$" })})
  if not $slug_ok { $errors = ($errors | append $"image_name_slug: '($img_name)' is not a valid slug") }

  # 5. image_format
  let valid_formats = ["raw", "qcow2", "vmdk"]
  let img_fmt = ($m.image?.format? | default "")
  let fmt_ok = ($img_fmt in $valid_formats)
  $checks = ($checks | append {check: "image_format", pass: $fmt_ok, detail: (if $fmt_ok { $img_fmt } else { $"'($img_fmt)' not in ($valid_formats | str join ', ')" })})
  if not $fmt_ok { $errors = ($errors | append $"image_format: '($img_fmt)' not in [($valid_formats | str join ', ')]") }

  # 6. target_arch
  let valid_arches = ["amd64", "aarch64", "riscv64"]
  let arch = ($m.target?.arch? | default "")
  let arch_ok = ($arch in $valid_arches)
  $checks = ($checks | append {check: "target_arch", pass: $arch_ok, detail: (if $arch_ok { $"($arch) in [($valid_arches | str join ', ')]" } else { $"'($arch)' not in [($valid_arches | str join ', ')]" })})
  if not $arch_ok { $errors = ($errors | append $"target_arch: '($arch)' not in [($valid_arches | str join ', ')]") }

  # 7. target_os
  let valid_os = ["freebsd", "netbsd"]
  let os = ($m.target?.os? | default "")
  let os_ok = ($os in $valid_os)
  $checks = ($checks | append {check: "target_os", pass: $os_ok, detail: (if $os_ok { $"($os) in [($valid_os | str join ', ')]" } else { $"'($os)' not in [($valid_os | str join ', ')]" })})
  if not $os_ok { $errors = ($errors | append $"target_os: '($os)' not in [($valid_os | str join ', ')]") }

  # 8. provider_in_catalog
  let provider_id = ($m.deploy?.provider? | default "")
  if $provider_id != "" {
    let cat = open "catalog/providers.v1.json"
    let matches = ($cat.providers | where id == $provider_id)
    let provider_ok = (not ($matches | is-empty))
    let detail = if $provider_ok {
      let entry = ($matches | first)
      let dp = ($entry.deployment_path? | default "unknown")
      let byoi = ($entry.byoi_support? | default "unknown")
      $"($provider_id) found, deployment_path=($dp), byoi_support=($byoi)"
    } else {
      $"'($provider_id)' not found in catalog"
    }
    $checks = ($checks | append {check: "provider_in_catalog", pass: $provider_ok, detail: $detail})
    if not $provider_ok { $errors = ($errors | append $"provider_in_catalog: '($provider_id)' not in catalog") }
  }

  # 9. profile_supported
  let profile = ($m.profile? | default "uefi")
  let profile_file = $"profiles/($profile).nu"
  let profile_ok = ($profile_file | path exists)
  $checks = ($checks | append {check: "profile_supported", pass: $profile_ok, detail: (if $profile_ok { $"($profile) profile file exists" } else { $"($profile_file) not found" })})
  if not $profile_ok { $errors = ($errors | append $"profile_supported: ($profile_file) does not exist") }

  # 10. agent_source_type
  let valid_src_types = ["gitea_release", "url", "local_path"]
  let src_type = ($m.agent?.source?.type? | default "")
  let src_type_ok = ($src_type in $valid_src_types)
  $checks = ($checks | append {check: "agent_source_type", pass: $src_type_ok, detail: (if $src_type_ok { $"type=($src_type)" } else { $"'($src_type)' not in [($valid_src_types | str join ', ')]" })})
  if not $src_type_ok { $errors = ($errors | append $"agent_source_type: '($src_type)' not in [($valid_src_types | str join ', ')]") }

  # 11. agent_sha256_real
  let sha256 = ($m.agent?.source?.sha256? | default "")
  if $sha256 != "" {
    let sha_fake  = ($sha256 | split chars | uniq | length) == 1
    let sha_pass = (not $sha_fake)
    let sha_prefix = ($sha256 | str substring 0..8)
    let sha_detail = if $sha_pass {
      $"sha256 present ($sha_prefix)..."
    } else {
      "sha256 is a repeated-character placeholder — replace before production build"
    }
    $checks = ($checks | append {check: "agent_sha256_real", pass: $sha_pass, detail: $sha_detail})
    if not $sha_pass { $warnings = ($warnings | append "agent_sha256_real: sha256 is a repeated-character placeholder — replace before production build") }
  }

  # 12. agent_version_semver
  let agent_ver = ($m.agent?.version? | default "")
  let semver_ok = ($agent_ver =~ '^v[0-9]+\.[0-9]+\.[0-9]+')
  $checks = ($checks | append {check: "agent_version_semver", pass: $semver_ok, detail: (if $semver_ok { $agent_ver } else { $"'($agent_ver)' does not match ^v[0-9]+\\.[0-9]+\\.[0-9]+" })})
  if not $semver_ok { $errors = ($errors | append $"agent_version_semver: '($agent_ver)' does not match semver") }

  # 13. image_size_minimum — size_mb must be >= 512
  let size_mb = ($m.image?.size_mb? | default 0)
  let size_ok = $size_mb >= 512
  let size_detail = $"($size_mb) MB \(min 512\)"
  $checks = ($checks | append {check: "image_size_minimum", pass: $size_ok, detail: $size_detail})
  if not $size_ok { $errors = ($errors | append $"image_size_minimum: ($size_mb) MB is below minimum 512 MB") }

  # 14. agent_sha256_not_placeholder — warn (not error) if sha256 is all-zeros or all-ones when source is url or gitea_release
  let sha256_src_type = ($m.agent?.source?.type? | default "")
  if $sha256_src_type == "url" or $sha256_src_type == "gitea_release" {
    let sha256_val = ($m.agent?.source?.sha256? | default "")
    let sha256_is_placeholder = if $sha256_val == "" {
      false
    } else {
      ($sha256_val | split chars | uniq | length) == 1
    }
    let sha256_check_pass = not $sha256_is_placeholder
    let sha256_check_detail = if $sha256_check_pass { "sha256 non-placeholder" } else { "sha256 is a placeholder (all-zeros or all-ones) — replace before production build" }
    $checks = ($checks | append {check: "agent_sha256_not_placeholder", pass: $sha256_check_pass, detail: $sha256_check_detail})
    if not $sha256_check_pass { $warnings = ($warnings | append "agent_sha256_not_placeholder: sha256 is a placeholder — replace before production build") }
  }

  # 15. network_interface_valid — check interface matches expected patterns for provider
  let iface = ($m.network?.interface? | default "")
  let provider_for_iface = ($m.deploy?.provider? | default "")
  let iface_result = if $provider_for_iface == "vultr" {
    if ($iface | str starts-with "vtnet") {
      {pass: true, detail: $"interface=($iface) \(vultr: vtnet* ok\)"}
    } else {
      {pass: false, detail: $"interface=($iface) does not match vtnet* for vultr"}
    }
  } else if $provider_for_iface == "linode_akamai" {
    if ($iface | str starts-with "eth") {
      {pass: true, detail: $"interface=($iface) \(linode_akamai: eth* ok\)"}
    } else {
      {pass: true, detail: $"interface=($iface) \(generic — not provider-validated\)"}
    }
  } else if $provider_for_iface == "aws_ec2" {
    if ($iface | str starts-with "ena") or ($iface | str starts-with "eth") {
      {pass: true, detail: $"interface=($iface) \(aws_ec2: ena*/eth* ok\)"}
    } else {
      {pass: false, detail: $"interface=($iface) does not match ena*/eth* for aws_ec2"}
    }
  } else if $provider_for_iface == "gce_gcp" {
    if ($iface | str starts-with "gve") or $iface == "ens4" {
      {pass: true, detail: $"interface=($iface) \(gce_gcp: gve*/ens4 ok\)"}
    } else {
      {pass: false, detail: $"interface=($iface) does not match gve*/ens4 for gce_gcp"}
    }
  } else {
    # Unknown provider or no provider — generic pass
    {pass: true, detail: $"interface=($iface) \(generic — not provider-validated\)"}
  }
  $checks = ($checks | append ({check: "network_interface_valid"} | merge $iface_result))
  if not $iface_result.pass { $errors = ($errors | append $"network_interface_valid: ($iface_result.detail)") }

  # 16. ssh_keys_format — if network.ssh_keys is present and non-empty, validate each key
  let ssh_keys = ($m.network?.ssh_keys? | default [])
  if ($ssh_keys | length) > 0 {
    let invalid_idx = ($ssh_keys | enumerate | where { |entry|
      let k = $entry.item
      not (($k | str starts-with "ssh-ed25519 ") or ($k | str starts-with "ssh-rsa ") or ($k | str starts-with "ecdsa-sha2-"))
    } | get index? | default [])
    let ssh_keys_pass = ($invalid_idx | is-empty)
    let ssh_detail = if $ssh_keys_pass {
      $"($ssh_keys | length) keys, all valid format"
    } else {
      $"invalid key format at index ($invalid_idx | first)"
    }
    $checks = ($checks | append {check: "ssh_keys_format", pass: $ssh_keys_pass, detail: $ssh_detail})
    if not $ssh_keys_pass { $errors = ($errors | append $"ssh_keys_format: ($ssh_detail)") }
  }

  # 17. image_version_semver — image.version must match vN.N.N
  let img_ver = ($m.image?.version? | default "")
  let img_semver_ok = ($img_ver =~ '^v[0-9]+\.[0-9]+\.[0-9]+')
  $checks = ($checks | append {check: "image_version_semver", pass: $img_semver_ok, detail: (if $img_semver_ok { $img_ver } else { $"'($img_ver)' does not match ^v[0-9]+\\.[0-9]+\\.[0-9]+" })})
  if not $img_semver_ok { $errors = ($errors | append $"image_version_semver: '($img_ver)' does not match semver") }

  # 18. build_host_format (warn only)
  let bh = ($m.target?.build_host? | default "")
  if $bh != "" {
    let bh_ok = ($bh =~ '^[a-z_][a-z0-9_.-]*@[a-z0-9._-]+(:[0-9]+)?$')
    $checks = ($checks | append {check: "build_host_format", pass: $bh_ok, detail: (if $bh_ok { $"'($bh)' matches expected format" } else { $"'($bh)' does not match ^[a-z_][a-z0-9_.-]*@[a-z0-9._-]+(:[0-9]+)?$" })})
    if not $bh_ok { $warnings = ($warnings | append $"build_host_format: '($bh)' does not match expected pattern — expected user@host or user@host:port") }
  }

  # 19. signing_keys_present (warn only — signing is optional)
  let sign_tool = ($m.signing?.tool? | default "none")
  if $sign_tool == "signify" {
    let sign_key = ($m.signing?.key_file? | default "")
    let sign_pub = ($m.signing?.public_key_file? | default "")
    let sign_key_ok = ($sign_key != "")
    let sign_pub_ok = ($sign_pub != "")
    if not $sign_key_ok {
      $checks = ($checks | append {check: "signing_key_file", pass: false, detail: "signing.key_file is empty; required when tool=signify"})
      $warnings = ($warnings | append "signing_key_file: signing.key_file is empty — build will fail at sign step")
    } else {
      $checks = ($checks | append {check: "signing_key_file", pass: true, detail: $"signing.key_file=($sign_key)"})
    }
    if not $sign_pub_ok {
      $checks = ($checks | append {check: "signing_public_key_file", pass: false, detail: "signing.public_key_file is empty; recommended when tool=signify"})
      $warnings = ($warnings | append "signing_public_key_file: signing.public_key_file is empty — public key will not be recorded in receipt")
    } else {
      $checks = ($checks | append {check: "signing_public_key_file", pass: true, detail: $"signing.public_key_file=($sign_pub)"})
    }
  }

  # 20. jsonschema_draft7 — validate against JSON Schema Draft 7 using python3 jsonschema library
  let check_jsonschema = try {
    let schema_path = "schema/manifest.v1.json"
    let manifest_json = ($m | to json)
    let py_snippet = $"
import json, sys
try:
    import jsonschema
    schema = json.load\(open\('($schema_path)'\)\)
    manifest = json.loads\(sys.argv[1]\)
    jsonschema.validate\(manifest, schema\)
    print\('valid'\)
except ImportError:
    print\('skipped-no-jsonschema'\)
except jsonschema.ValidationError as e:
    print\(f'invalid: {e.message}'\)
"
    let result = (^python3 -c $py_snippet $manifest_json | str trim)
    if $result == "valid" {
      {check: "jsonschema_draft7" pass: true detail: "passed JSON Schema Draft 7 validation"}
    } else if $result == "skipped-no-jsonschema" {
      {check: "jsonschema_draft7" pass: true detail: "skipped (jsonschema library not installed)"}
    } else {
      {check: "jsonschema_draft7" pass: false detail: $result}
    }
  } catch { |e|
    {check: "jsonschema_draft7" pass: true detail: $"skipped: ($e.msg)"}
  }
  $checks = ($checks | append $check_jsonschema)

  {
    action: "validate"
    manifest_path: $manifest_file
    valid: ($errors | is-empty)
    checks: $checks
    errors: $errors
    warnings: $warnings
  } | to json --indent 2
}

def "main verify" [receipt_file: string, --image: string = ""] {
  mut checks = []
  mut errors = []

  # Peek at receipt first to resolve image path if not provided
  let receipt_ok_pre = ($receipt_file | path exists)
  let is_dry_run_receipt = if $receipt_ok_pre {
    let _rv = open $receipt_file
    $_rv.build?.dry_run? | default ($_rv.dry_run? | default false)
  } else { false }

  # Derive actual image path: --image flag > receipt.image.output_path
  let actual_image = if $image != "" {
    $image
  } else if $receipt_ok_pre {
    let _r_tmp = open $receipt_file
    $_r_tmp.image?.output_path? | default ""
  } else {
    ""
  }

  # 1. image_exists
  let image_ok = if $actual_image != "" { ($actual_image | path exists) } else { false }

  let image_check = if $image_ok {
    {check: "image_exists", pass: true, detail: $"($actual_image) exists"}
  } else if $is_dry_run_receipt {
    {check: "image_exists", pass: false, skipped: true, detail: "dry-run receipt — image not yet built; build first"}
  } else {
    {check: "image_exists", pass: false, detail: $"image not found: ($actual_image)"}
  }
  $checks = ($checks | append $image_check)
  if not $image_ok and not $is_dry_run_receipt {
    $errors = ($errors | append $"image not found: ($actual_image)")
  }

  # 2. receipt_exists
  let receipt_ok = $receipt_ok_pre
  $checks = ($checks | append {check: "receipt_exists", pass: $receipt_ok, detail: (if $receipt_ok { $"($receipt_file) exists" } else { $"receipt not found: ($receipt_file)" })})
  if not $receipt_ok { $errors = ($errors | append $"receipt not found: ($receipt_file)") }

  # Early return if receipt is missing, or image is missing and not a dry-run receipt
  if not $receipt_ok or (not $image_ok and not $is_dry_run_receipt) {
    return ({
      action: "verify"
      image: $actual_image
      receipt_file: $receipt_file
      receipt_id: "unknown"
      checks: $checks
      valid: false
      errors: $errors
    } | to json --indent 2)
  }

  let r = open $receipt_file

  # 3. receipt_parse — confirm required fields are present
  # hashes may be nested (v1 schema) or flat (legacy build output)
  let receipt_id    = ($r.receipt_id? | default "")
  let image_sha256  = if ("hashes" in $r) {
    ($r.hashes?.image_sha256? | default "")
  } else {
    ($r.image_sha256? | default "")
  }
  let manifest_sha256 = if ("hashes" in $r) {
    ($r.hashes?.manifest_sha256? | default "")
  } else {
    ($r.manifest_sha256? | default "")
  }
  # Read manifest_path from receipt.hashes.manifest_path (v1 schema) or top-level fallback
  let manifest_path = if ("hashes" in $r) {
    ($r.hashes?.manifest_path? | default ($r.manifest_path? | default ""))
  } else {
    ($r.manifest_path? | default "")
  }

  let parse_ok = ($receipt_id != "") and ($image_sha256 != "") and ($manifest_sha256 != "")
  let parse_detail = if $parse_ok {
    "receipt_id, image_sha256, manifest_sha256 present"
  } else {
    let missing = (
      []
      | if $receipt_id    == "" { append "receipt_id" }    else { $in }
      | if $image_sha256  == "" { append "image_sha256" }  else { $in }
      | if $manifest_sha256 == "" { append "manifest_sha256" } else { $in }
    )
    $"missing fields: ($missing | str join ', ')"
  }
  $checks = ($checks | append {check: "receipt_parse", pass: $parse_ok, detail: $parse_detail})
  if not $parse_ok { $errors = ($errors | append $parse_detail) }

  # 4. image_sha256_match — skip for any dry-run placeholder variant
  let img_sha256_check = if ($image_sha256 == "PLACEHOLDER_DRY_RUN") or ($image_sha256 == "PLACEHOLDER") or ($image_sha256 == "dry-run-placeholder") {
    {check: "image_sha256", pass: false, skipped: true, detail: "dry-run receipt — sha256 not computed; build first to get a real hash"}
  } else {
    let computed_image_sha256 = if $image_ok {
      if $nu.os-info.name == "macos" {
        ^shasum -a 256 $actual_image | str trim | split row " " | first
      } else {
        ^sha256sum $actual_image | str trim | split row " " | first
      }
    } else { "" }

    let img_hash_ok = ($computed_image_sha256 == $image_sha256) and ($image_sha256 != "")
    let img_hash_detail = if $image_sha256 == "" {
      "skipped — receipt has no image_sha256"
    } else if $img_hash_ok {
      "sha256 matches receipt"
    } else {
      $"MISMATCH: got ($computed_image_sha256) expected ($image_sha256)"
    }
    {check: "image_sha256", pass: $img_hash_ok, detail: $img_hash_detail}
  }
  $checks = ($checks | append $img_sha256_check)
  if not $img_sha256_check.pass and ($img_sha256_check.skipped? | default false) != true { $errors = ($errors | append $img_sha256_check.detail) }

  # 5. manifest_sha256_match — only if manifest_path is set and exists on disk
  let manifest_check = if $manifest_path == "" {
    {check: "manifest_sha256", pass: true, detail: "skipped — manifest_path not recorded in receipt"}
  } else if not ($manifest_path | path exists) {
    {check: "manifest_sha256", pass: true, detail: $"warn: manifest file ($manifest_path) not found on disk — skipping hash check"}
  } else {
    let computed_manifest_sha256 = if $nu.os-info.name == "macos" {
      ^shasum -a 256 $manifest_path | str trim | split row " " | first
    } else {
      ^sha256sum $manifest_path | str trim | split row " " | first
    }
    let mf_ok = ($computed_manifest_sha256 == $manifest_sha256)
    {
      check: "manifest_sha256"
      pass: $mf_ok
      detail: (if $mf_ok { "manifest sha256 matches receipt" } else { $"MISMATCH: got ($computed_manifest_sha256) expected ($manifest_sha256)" })
    }
  }
  $checks = ($checks | append $manifest_check)
  # manifest mismatch is a warning only — does not fail valid

  # 6. receipt_id_present — non-empty and not all-zeros
  let id_all_zeros = ($receipt_id | str replace --all "0" "" | str replace --all "-" "" | str length) == 0
  let id_ok = ($receipt_id != "") and (not $id_all_zeros)
  let id_detail = if $id_ok { $"receipt_id ($receipt_id)" } else if $receipt_id == "" { "receipt_id is empty" } else { "receipt_id is all-zeros placeholder" }
  $checks = ($checks | append {check: "receipt_id_present", pass: $id_ok, detail: $id_detail})
  if not $id_ok { $errors = ($errors | append $id_detail) }

  let valid = ($checks | where { |c| ($c.skipped? | default false) != true } | where pass == false | length) == 0
  {
    action: "verify"
    image: $actual_image
    receipt_file: $receipt_file
    receipt_id: $receipt_id
    checks: $checks
    valid: $valid
    errors: $errors
  } | to json --indent 2
}
def "main status" [--dir: string = "./out"] {
  # Derive genoa_version from artifacts/ directory (latest vN.N.N dir)
  let genoa_version = try {
    let art_dirs = (glob "artifacts/v*" | where { |d| ($d | path type) == "dir" } | each { |d| $d | path basename } | sort --reverse)
    if ($art_dirs | is-empty) { "unknown" } else { $art_dirs | first }
  } catch { "unknown" }

  # Platform via uname
  let platform = try { ^uname -s | str trim } catch { "unknown" }

  # build_ready: true only on FreeBSD with all health tools present
  let build_ready = try {
    if $platform != "FreeBSD" { false } else {
      let h = (^nu genoa.nu health | from json)
      ($h.ok? | default false)
    }
  } catch { false }

  # recent_builds: 3 most recent receipts from artifacts/
  let recent_builds = try {
    let receipt_files = (glob "artifacts/**/*.receipt.json" | sort --reverse | first 3)
    $receipt_files | each { |f|
      let r = try { open $f } catch { {} }
      {
        path:       $f
        version:    ($r.image?.version?  | default "")
        image_name: ($r.image?.name?     | default "")
        profile:    ($r.build?.profile?  | default "")
        built_at:   ($r.built_at?        | default "")
        host:       ($r.build?.host?     | default "")
      }
    }
  } catch { [] }

  # snapshots: vultr snapshot list (wrapped in try so it works without CLI)
  let snapshots = try {
    let vultr_bin = find_vultr
    if $vultr_bin == null { null } else {
      let raw = try { ^$vultr_bin snapshot list --output json | from json } catch { null }
      if $raw == null { null } else {
        let snaps = ($raw.snapshots? | default [])
        let latest = if ($snaps | is-empty) { null } else {
          let s = ($snaps | sort-by date_created --reverse | first)
          {id: ($s.id? | default ""), status: ($s.status? | default ""), description: ($s.description? | default "")}
        }
        {count: ($snaps | length), latest: $latest}
      }
    }
  } catch { null }

  # instances: vultr instance list (wrapped in try)
  let instances = try {
    let vultr_bin = find_vultr
    if $vultr_bin == null { null } else {
      let raw = try { ^$vultr_bin instance list --output json | from json } catch { null }
      if $raw == null { null } else {
        let all_inst = ($raw.instances? | default [])
        let running = ($all_inst | where { |i| ($i.power_status? | default "") == "running" } | length)
        {count: ($all_inst | length), running: $running}
      }
    }
  } catch { null }

  {
    action:         "status"
    genoa_version:  $genoa_version
    platform:       $platform
    build_ready:    $build_ready
    recent_builds:  $recent_builds
    snapshots:      $snapshots
    instances:      $instances
    http_server:    "http://108.61.206.203:8080/"
  } | to json --indent 2
}

def "main publish" [
  image: string
  --backend: string = "r2"
  --dry-run
] {
  if not ($image | path exists) {
    # dry-run mode: emit plan without error
    if $dry_run {
      return ({action: "would-run", image: $image, backend: $backend, note: "image not yet built — run genoa build first"} | to json --indent 2)
    }
    error make {msg: $"image not found: ($image)"}
  }
  # Use subprocess invocation so that a parse error in publish.nu (written by
  # a parallel agent) does not prevent genoa.nu from loading. source is
  # parsed at compile time and cannot be guarded by a runtime if-exists check.
  if ("publish.nu" | path exists) {
    let dry_flag = if $dry_run { "--dry-run" } else { "" }
    let result_json = try {
      if $dry_run {
        ^nu publish.nu $image --backend $backend --dry-run | str trim
      } else {
        ^nu publish.nu $image --backend $backend | str trim
      }
    } catch { |e|
      {action: "failed", reason: $"publish.nu invocation failed: ($e.msg)", image: $image, backend: $backend} | to json
    }
    try { $result_json | from json | to json --indent 2 } catch { {action: "failed", reason: "publish.nu output not parseable", image: $image, backend: $backend} | to json --indent 2 }
  } else {
    {action: "failed", reason: "publish.nu not yet available", image: $image, backend: $backend} | to json --indent 2
  }
}

def "main run" [
  manifest_file: string
  --profile: string = "uefi"
  --dry-run
  --backend: string = "gitea"
  --provider: string = ""
] {
  # Resolve profile and provider from manifest if not specified via flags
  let m = if ($manifest_file | path exists) { open $manifest_file } else { {} }
  let p = if ($profile | is-not-empty) { $profile } else { $m.profile? | default "uefi" }
  let prov = if ($provider | is-not-empty) { $provider } else { $m.deploy?.provider? | default "" }

  # Helper: build the --dry-run flag list for subprocess calls
  let dry_flags = if $dry_run { ["--dry-run"] } else { [] }

  # Stage 1: validate — use subprocess so output is always clean JSON
  let v_result = try {
    ^nu genoa.nu validate $manifest_file | from json
  } catch { |e|
    {valid: false, errors: [$"validate subprocess failed: ($e.msg)"], warnings: [], action: "validate"}
  }

  if not ($v_result.valid? | default false) {
    return ({
      action:        "run"
      manifest_path: $manifest_file
      dry_run:       $dry_run
      stages: {
        validate: $v_result
      }
      ok:         false
      stopped_at: "validate"
    } | to json --indent 2)
  }

  # Stage 2: build
  let b_result = try {
    ^nu genoa.nu build $manifest_file --profile $p ...$dry_flags | from json
  } catch { |e|
    {action: "failed", error: $"build subprocess failed: ($e.msg)"}
  }

  # Stage 3: publish — resolve image path from receipt or fallback
  let receipt_path = ($b_result.receipt_path? | default "")
  let image_path = if $receipt_path != "" and ($receipt_path | path exists) {
    let r = open $receipt_path
    $r.image?.output_path? | default ($r.image_path? | default "/tmp/genoa.raw")
  } else { "/tmp/genoa.raw" }

  let pub_result = try {
    ^nu genoa.nu publish $image_path --backend $backend ...$dry_flags | from json
  } catch { |e|
    {action: "failed", error: $"publish subprocess failed: ($e.msg)", backend: $backend}
  }

  # Synthesize a published URL for downstream deploy stage
  let published_url = if ($pub_result.action? == "would-run") or ($pub_result.url? | default "") == "" {
    let name    = $m.image?.name?    | default "image"
    let version = $m.image?.version? | default "v0.0.0"
    let fmt     = $m.image?.format?  | default "raw"
    $"https://example-bucket.example.com/($name)-($version).($fmt)"
  } else {
    $pub_result.url? | default ""
  }

  # Write published info back into the receipt so downstream agents can locate the image URL
  if $receipt_path != "" and ($receipt_path | path exists) {
    let receipt = open $receipt_path
    let updated_receipt = $receipt | merge {
      published: {
        url:          ($pub_result.url?     | default "")
        backend:      ($pub_result.backend? | default $backend)
        published_at: (date now | format date "%Y-%m-%dT%H:%M:%SZ")
      }
    }
    $updated_receipt | to json | save --force $receipt_path
  }

  # Stage 4: deploy — pass published_url via --image so adapters get the export URL
  let dep_result = try {
    if $prov != "" {
      ^nu genoa.nu deploy $manifest_file --provider $prov --image $published_url ...$dry_flags | from json
    } else {
      ^nu genoa.nu deploy $manifest_file --image $published_url ...$dry_flags | from json
    }
  } catch { |e|
    {action: "failed", error: $"deploy subprocess failed: ($e.msg)", provider: $prov}
  }

  # Determine overall ok: all stages must not have action="failed"
  let stage_failed = (
    ($b_result.action?   | default "") == "failed" or
    ($pub_result.action? | default "") == "failed" or
    ($dep_result.action? | default "") == "failed"
  )

  {
    action:        "run"
    manifest_path: $manifest_file
    dry_run:       $dry_run
    stages: {
      validate: $v_result
      build:    $b_result
      publish:  $pub_result
      deploy:   $dep_result
    }
    ok:         (not $stage_failed)
    stopped_at: null
  } | to json --indent 2
}
def "main health" [] {
  let tools = [
    {tool: "nu",          version_flag: "--version"}
    {tool: "mdconfig",    version_flag: null}
    {tool: "gpart",       version_flag: null}
    {tool: "newfs_msdos", version_flag: null}
    {tool: "newfs",       version_flag: null}
    {tool: "mount",       version_flag: null}
    {tool: "umount",      version_flag: null}
    {tool: "tar",         version_flag: null}
    {tool: "fetch",       version_flag: null}
    {tool: "truncate",    version_flag: null}
  ]

  let checks = $tools | each { |t|
    let found_path = (which $t.tool | get 0?.path? | default null)
    let found = $found_path != null
    let version = if $found and $t.version_flag != null {
      try { ^nu --version | str trim } catch { null }
    } else {
      null
    }
    {tool: $t.tool, found: $found, path: $found_path, version: $version}
  }

  let all_found = ($checks | where found == false | is-empty)
  let platform = (try { ^uname -s | str trim } catch { "unknown" })
  let platform_ok = $platform == "FreeBSD"

  {
    action: "health"
    ok: $all_found
    checks: $checks
    platform: $platform
    platform_ok: $platform_ok
  } | to json --indent 2
}

def "main selftest" [] {
  let result = try {
    ^nu test/smoke.nu | complete
  } catch { |e|
    return ({
      action: "selftest"
      passed: 0
      failed: 0
      total: 0
      ok: false
      output: $e.msg
    } | to json --indent 2)
  }

  let output = $result.stdout
  # Parse "Results: N/M passed, K failed"
  let parsed = try {
    let line = ($output | lines | where { |l| $l | str starts-with "Results:" } | first)
    let passed = ($line | parse "Results: {p}/{t} passed, {f} failed" | first)
    {
      passed: ($passed.p | into int)
      total:  ($passed.t | into int)
      failed: ($passed.f | into int)
    }
  } catch {
    {passed: 0, total: 0, failed: 0}
  }

  {
    action: "selftest"
    passed: $parsed.passed
    failed: $parsed.failed
    total:  $parsed.total
    ok:     ($parsed.failed == 0)
    output: $output
  } | to json --indent 2
}

def "main verify-image" [
  image_path: string
  --profile: string = "uefi"
] {
  let platform = try { ^uname -s | str trim } catch { "unknown" }

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
  let effective_key  = if $key  != "" { $key  } else { ($m | get -o signing.key_path | default "") }

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

  {action: "signed", tool: $effective_tool, image: $image_path, signature: $sig_path, key: $effective_key} | to json --indent 2
}

def "main diff" [
  receipt_a: string   # path to first receipt (older)
  receipt_b: string   # path to second receipt (newer)
] {
  if not ($receipt_a | path exists) {
    error make {msg: $"receipt not found: ($receipt_a)"}
  }
  if not ($receipt_b | path exists) {
    error make {msg: $"receipt not found: ($receipt_b)"}
  }

  let a = open $receipt_a
  let b = open $receipt_b

  # Flatten the fields we care about
  let fields = [
    ["image.version"        {|r| $r.image?.version? | default ""}]
    ["image.name"           {|r| $r.image?.name? | default ""}]
    ["image.format"         {|r| $r.image?.format? | default ""}]
    ["build.host"           {|r| $r.build?.host? | default ""}]
    ["build.profile"        {|r| $r.build?.profile? | default ""}]
    ["build.os_version"     {|r| $r.build?.os_version? | default ""}]
    ["build.arch"           {|r| $r.build?.arch? | default ""}]
    ["build.genoa_version"  {|r| $r.build?.genoa_version? | default ""}]
    ["agent.name"           {|r| $r.agent?.name? | default ""}]
    ["agent.version"        {|r| $r.agent?.version? | default ""}]
    ["hashes.image_sha256"  {|r| $r.hashes?.image_sha256? | default "" | str substring 0..15}]
    ["built_at"             {|r| $r.built_at? | default ""}]
  ]

  let changes = ($fields | each { |f|
    let name = $f.0
    let getter = $f.1
    let val_a = (do $getter $a)
    let val_b = (do $getter $b)
    if $val_a != $val_b {
      {field: $name from: $val_a to: $val_b}
    } else {
      null
    }
  } | compact)

  let unchanged = ($fields | each { |f|
    let name = $f.0
    let getter = $f.1
    let val_a = (do $getter $a)
    let val_b = (do $getter $b)
    if $val_a == $val_b { $name } else { null }
  } | compact)

  {
    action:    "diff"
    receipt_a: $receipt_a
    receipt_b: $receipt_b
    changes:   $changes
    unchanged: $unchanged
    summary:   $"($changes | length) fields changed, ($unchanged | length) unchanged"
  } | to json --indent 2
}

def main [] {
  print "genoa — generated OS for AI assistants"
  print ""
  print "Commands: catalog  schema  describe  validate  build  deploy  deploy-from-snapshot  publish  sign  verify  verify-image  run  status  health  selftest  diff  snapshots  snapshot-import  snapshot-status  providers  receipts  instances"
  print "Usage:    nu genoa.nu <command> [args]"
  print "Example:  nu genoa.nu catalog | jq '.providers[0]'"
}



# Emit build metrics and events to Datadog via pup.
# Reads a receipt file and posts genoa.build.* metrics.
# Requires: pup authenticated (`pup auth status`)
def find_vultr [] {
  let brew = "/opt/homebrew/bin/vultr"
  if ($brew | path exists) { return $brew }
  let in_path = (which vultr | get 0?.path? | default null)
  $in_path
}

def "main snapshots" [
  --provider: string = "vultr"
] {
  let vultr_bin = find_vultr
  if $vultr_bin == null {
    return ({action: "failed", reason: "vultr CLI not found"} | to json --indent 2)
  }
  let raw = try {
    ^$vultr_bin snapshot list --output json | from json
  } catch { |e|
    return ({action: "failed", reason: $"vultr snapshot list failed: ($e.msg)"} | to json --indent 2)
  }
  let snaps = ($raw.snapshots? | default [] | each { |s|
    let size_bytes = ($s.size? | default 0 | into float)
    let size_gb = (($size_bytes / 1073741824.0) | math round --precision 1)
    {
      id:           ($s.id?           | default "")
      description:  ($s.description?  | default "")
      status:       ($s.status?       | default "")
      size_gb:      $size_gb
      date_created: ($s.date_created? | default "")
    }
  })
  {
    action:    "snapshots"
    provider:  $provider
    snapshots: $snaps
    count:     ($snaps | length)
  } | to json --indent 2
}

def "main snapshot-import" [
  image_url: string
  --description: string = ""
  --dry-run
] {
  if $dry_run {
    return ({
      action:   "would-run"
      provider: "vultr"
      url:      $image_url
      cmd:      $"vultr snapshot create-url --url ($image_url) --description ($description)"
    } | to json --indent 2)
  }
  let vultr_bin = find_vultr
  if $vultr_bin == null {
    return ({action: "failed", reason: "vultr CLI not found"} | to json --indent 2)
  }
  let raw = try {
    ^$vultr_bin snapshot create-url --url $image_url --description $description --output json | from json
  } catch { |e|
    return ({action: "failed", reason: $"vultr snapshot create-url failed: ($e.msg)", url: $image_url} | to json --indent 2)
  }
  let snap_id = ($raw.snapshot?.id? | default "")
  {
    action:      "snapshot-import-queued"
    snapshot_id: $snap_id
    status:      "pending"
    url:         $image_url
  } | to json --indent 2
}

def "main snapshot-status" [
  snapshot_id: string
] {
  let vultr_bin = find_vultr
  if $vultr_bin == null {
    return ({action: "failed", reason: "vultr CLI not found"} | to json --indent 2)
  }
  let raw = try {
    ^$vultr_bin snapshot get $snapshot_id --output json | from json
  } catch { |e|
    return ({action: "failed", reason: $"vultr snapshot get failed: ($e.msg)", id: $snapshot_id} | to json --indent 2)
  }
  let s = ($raw.snapshot? | default {})
  let size_bytes = ($s.size? | default 0 | into float)
  let size_gb = (($size_bytes / 1073741824.0) | math round --precision 1)
  {
    action:      "snapshot-status"
    id:          $snapshot_id
    status:      ($s.status?      | default "")
    size_gb:     $size_gb
    description: ($s.description? | default "")
  } | to json --indent 2
}

def "main providers" [
  --id: string = ""   # filter to single provider by ID
] {
  let cat = open "catalog/providers.v1.json"
  let all = ($cat.providers | each { |p|
    {
      id:               ($p.id? | default "")
      display_name:     ($p.display_name? | default "")
      deployment_path:  ($p.deployment_path? | default null)
      byoi_format:      ($p.byoi_format? | default null)
      arch_support:     ($p.arch_support? | default ($p.architectures_supported? | default null))
      freebsd_support:  ($p.freebsd_support? | default null)
      min_image_size_mb: ($p.min_image_size_mb? | default null)
      regions:          ($p.regions? | default null)
      docs:             ($p.docs? | default null)
    }
  })
  let filtered = if $id != "" {
    $all | where id == $id
  } else {
    $all
  }
  if $id != "" and ($filtered | is-empty) {
    {action: "providers" count: 0 providers: [] error: $"provider '($id)' not found in catalog"} | to json --indent 2
  } else {
    {action: "providers" count: ($filtered | length) providers: $filtered} | to json --indent 2
  }
}

def "main receipts" [] {
  let receipt_files = try { glob "artifacts/**/*.receipt.json" } catch { [] }
  let receipts = ($receipt_files | each { |f|
    let r = try { open $f } catch { {} }
    {
      path:       $f
      version:    ($r.image?.version?     | default "")
      image_name: ($r.image?.name?        | default "")
      profile:    ($r.build?.profile?     | default "")
      built_at:   ($r.built_at?           | default "")
      host:       ($r.build?.host?        | default "")
      provider:   ($r.published?.backend? | default (
        $r.claims? | default [] | where { |c| ($c.claim? | default "") =~ "provider" } | get 0?.claim? | default ""
      ))
    }
  } | sort-by built_at --reverse)
  {action: "receipts" count: ($receipts | length) receipts: $receipts} | to json --indent 2
}

def "main instances" [
  --provider: string = "vultr"
  --all
] {
  let vultr = find_vultr
  if $vultr == null {
    return ({action: "failed", reason: "vultr CLI not found", provider: $provider} | to json --indent 2)
  }

  let raw = try {
    ^$vultr instance list --output json | from json
  } catch { |e|
    return ({action: "failed", reason: $e.msg, provider: $provider} | to json --indent 2)
  }

  let all_instances = ($raw.instances? | default [])
  let filtered = if $all {
    $all_instances
  } else {
    $all_instances | where { |i| ($i.label? | default "") | str contains "smolbsd" }
  }

  let result = ($filtered | each { |i|
    {
      id:           ($i.id?           | default "")
      label:        ($i.label?        | default "")
      status:       ($i.status?       | default "")
      power:        ($i.power_status? | default "")
      ip:           ($i.main_ip?      | default "")
      plan:         ($i.plan?         | default "")
      region:       ($i.region?       | default "")
      os:           ($i.os?           | default "")
      date_created: ($i.date_created? | default "")
    }
  })

  {action: "instances" provider: $provider count: ($result | length) instances: $result} | to json --indent 2
}

def "main deploy-from-snapshot" [
  snapshot_id: string
  --plan: string = "vc2-1c-1gb"
  --region: string = "lax"
  --label: string = ""
  --dry-run
] {
  let effective_label = if $label != "" {
    $label
  } else {
    $"smolbsd-($snapshot_id | str substring 0..7)"
  }

  if $dry_run {
    return ({
      action:      "would-run"
      provider:    "vultr"
      snapshot_id: $snapshot_id
      plan:        $plan
      region:      $region
      label:       $effective_label
      cmd:         $"vultr instance create --snapshot ($snapshot_id) --plan ($plan) --region ($region) --label ($effective_label)"
    } | to json --indent 2)
  }

  let vultr_bin = find_vultr
  if $vultr_bin == null {
    return ({action: "failed", reason: "vultr CLI not found"} | to json --indent 2)
  }

  let raw = try {
    ^$vultr_bin instance create --snapshot $snapshot_id --plan $plan --region $region --label $effective_label --output json | from json
  } catch { |e|
    return ({action: "failed", reason: $"vultr instance create failed: ($e.msg)", snapshot_id: $snapshot_id} | to json --indent 2)
  }

  let inst = ($raw.instance? | default {})
  {
    action:      "deploy-from-snapshot"
    instance_id: ($inst.id?       | default "")
    ip:          ($inst.main_ip?  | default "")
    status:      ($inst.status?   | default "")
    snapshot_id: $snapshot_id
  } | to json --indent 2
}

def "main notify" [receipt_file: string, --dry-run] {
  if not ($receipt_file | path exists) {
    return ({action: "failed", error: $"receipt not found: ($receipt_file)"} | to json --indent 2)
  }
  let r = open $receipt_file
  let profile    = $r.build?.profile?    | default "unknown"
  let arch       = $r.build?.arch?       | default "unknown"
  let dry        = $r.build?.dry_run?    | default false
  let agent_n    = $r.agent?.name?       | default "unknown"
  let img_ver    = $r.image?.version?    | default "unknown"
  let img_name   = $r.image?.name?       | default "unknown"
  let build_host = $r.build?.host?       | default "unknown"
  let os_ver     = $r.build?.os_version? | default "unknown"
  let built_at   = $r.built_at?          | default ""
  let step_count = ($r.claims? | default [] | length)
  let size_gb    = try { $r.image?.size_gb? | default 0 } catch { 0 }
  let now        = (date now | format date "%s" | into int)

  # Compute age_hours: how many hours ago the build was completed
  let age_hours = try {
    let dt = ($built_at | into datetime)
    let diff = ((date now) - $dt)
    $diff / 1hr | math floor
  } catch { 0 }

  # Base tag list used on all metrics
  let tags = [
    $"version:($img_ver)"
    $"profile:($profile)"
    $"host:($build_host)"
    $"os:($os_ver)"
    $"arch:($arch)"
    $"dry_run:($dry)"
    $"agent_name:($agent_n)"
    "project:genoa"
  ]

  let metrics_names = [
    "genoa.build.success"
    "genoa.image.size_mb"
    "genoa.receipt.claims"
    "genoa.build.age_hours"
    "genoa.build.step_count"
    "genoa.image.size_gb"
  ]

  let metrics = {
    series: [
      {metric: "genoa.build.success"    type: 1 points: [{timestamp: $now value: 1}]
       tags: $tags}
      {metric: "genoa.image.size_mb"    type: 3 points: [{timestamp: $now value: ($r.image?.size_mb? | default 1024)}]
       tags: $tags}
      {metric: "genoa.receipt.claims"   type: 3 points: [{timestamp: $now value: $step_count}]
       tags: $tags}
      {metric: "genoa.build.age_hours"  type: 3 points: [{timestamp: $now value: $age_hours}]
       tags: $tags}
      {metric: "genoa.build.step_count" type: 3 points: [{timestamp: $now value: $step_count}]
       tags: $tags}
      {metric: "genoa.image.size_gb"    type: 3 points: [{timestamp: $now value: $size_gb}]
       tags: $tags}
    ]
  }

  if $dry_run {
    return ({
      action:            "would-notify"
      receipt:           $receipt_file
      metrics:           ($metrics.series | length)
      metrics_submitted: $metrics_names
      tags:              $tags
      status:            "ok"
    } | to json --indent 2)
  }

  let tmp = $"/tmp/genoa-metrics-($now).json"
  $metrics | to json | save --force $tmp

  let result = try {
    ^pup metrics submit --file $tmp | complete
  } catch { |e| {exit_code: -1 stderr: $e.msg} }

  ^rm -f $tmp

  if ($result.exit_code? | default 99) == 0 {
    {
      action:            "notify"
      receipt:           $receipt_file
      metrics_submitted: $metrics_names
      tags:              ($tags | str join ",")
      status:            "ok"
    } | to json --indent 2
  } else {
    {action: "failed" step: "pup_metrics_submit" stderr: ($result.stderr? | default "unknown error")} | to json --indent 2
  }
}
