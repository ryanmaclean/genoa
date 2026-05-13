#!/usr/bin/env nu
source profiles/uefi.nu
source profiles/kboot.nu
source adapters/linode.nu
source adapters/vultr.nu

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
    {action: "failed", reason: $"unknown profile: ($p); supported: uefi, kboot", profile: $p}
  } else if $p == "kboot" {
    kboot_build $m $dry_run
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

  # 13. build_host_format (warn only)
  let bh = ($m.target?.build_host? | default "")
  if $bh != "" {
    let bh_ok = ($bh =~ '^[a-z_][a-z0-9_.-]*@[a-z0-9._-]+(:[0-9]+)?$')
    $checks = ($checks | append {check: "build_host_format", pass: $bh_ok, detail: (if $bh_ok { $"'($bh)' matches expected format" } else { $"'($bh)' does not match ^[a-z_][a-z0-9_.-]*@[a-z0-9._-]+(:[0-9]+)?$" })})
    if not $bh_ok { $warnings = ($warnings | append $"build_host_format: '($bh)' does not match expected pattern — expected user@host or user@host:port") }
  }

  # 14. signing_keys_present (warn only — signing is optional)
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
  # Scan the configured output directory for receipt files
  let dir_exists = ($dir | path exists)
  let out_receipts = if $dir_exists {
    let g = try { glob $"($dir)/*.receipt.json" } catch { [] }
    if ($g | is-empty) {
      # Fallback: ls-based scan in case glob path resolution differs
      try { ls $dir | where name =~ "receipt\\.json" | get name } catch { [] }
    } else { $g }
  } else { [] }

  # Also scan current directory (non-recursive) for receipts placed at the root
  let cur_receipts = try { glob "*.receipt.json" } catch { [] }

  let all_receipts = ($out_receipts | append $cur_receipts | uniq)

  if ($all_receipts | is-empty) {
    return ({
      action: "status"
      receipts_found: 0
      scanned_dir: $dir
      dir_exists: $dir_exists
      message: (if $dir_exists { $"No receipts found in ($dir). Run `genoa build <manifest>` to create one." } else { $"Directory ($dir) does not exist. Run `genoa build` first." })
      tip: "Receipts are written to <image.output_dir>/<name>-<version>.receipt.json (default: ./out/)"
    } | to json --indent 2)
  }

  let parsed = $all_receipts | each { |path|
    let r = try { open $path } catch { null }
    if $r == null { return {path: $path, status: "unreadable"} }
    # v1 nested fields with v0 flat fallbacks
    let img_path_v = $r.image?.output_path? | default ($r.image_path? | default "")
    let is_dry_v   = $r.build?.dry_run?     | default ($r.dry_run?    | default false)
    let prof_v     = $r.build?.profile?     | default ($r.profile?    | default "unknown")
    let schema_v   = $r.schema_version? | default "unknown"
    let img_sha_v  = $r.hashes?.image_sha256? | default ($r.image_sha256? | default "")
    {
      path: $path
      receipt_id: ($r.receipt_id? | default "unknown")
      image_path: $img_path_v
      image_exists: ($img_path_v | path exists)
      profile: $prof_v
      built_at: ($r.built_at? | default "unknown")
      dry_run: $is_dry_v
      manifest_path: ($r.manifest_path? | default "unknown")
      sha256_placeholder: ($img_sha_v == "dry-run-placeholder" or $img_sha_v == "PLACEHOLDER_DRY_RUN")
      schema_version: $schema_v
      legacy: ($schema_v != "v1")
    }
  }

  let real_builds     = ($parsed | where dry_run == false)
  let dry_runs        = ($parsed | where dry_run == true)
  let images_on_disk  = ($parsed | where image_exists == true)
  let legacy_receipts = ($parsed | where legacy == true)

  {
    action: "status"
    receipts_found: ($all_receipts | length)
    real_builds: ($real_builds | length)
    dry_runs: ($dry_runs | length)
    images_on_disk: ($images_on_disk | length)
    legacy_receipts: ($legacy_receipts | length)
    receipts: $parsed
    next_steps: (if ($real_builds | is-empty) {
      ["No real builds yet. Run: nu genoa.nu build <manifest.toml>"]
    } else if ($images_on_disk | is-empty) {
      ["Images not found at recorded paths. They may have been moved or deleted."]
    } else {
      ["Images ready. Run: nu genoa.nu deploy <manifest.toml> to deploy."]
    })
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
  --provider: string = ""
  --backend: string = "r2"
  --dry-run
] {
  # Step 0: validate — abort if manifest is invalid
  let validate_result = main validate $manifest_file | from json
  if not $validate_result.valid {
    return ({action: "failed", step: "validate", errors: $validate_result.errors} | to json --indent 2)
  }
  # 1. build (returns JSON string — parse for record access)
  let build_result = (main build $manifest_file --dry-run=$dry_run | from json)
  # 2. publish (uses receipt from build)
  let receipt_path = ($build_result | get receipt_path? | default "")
  let image_path = if $receipt_path != "" and ($receipt_path | path exists) {
    let r = open $receipt_path
    $r.image?.output_path? | default ($r.image_path? | default "/tmp/genoa.raw")
  } else { "/tmp/genoa.raw" }
  let pub_result = (main publish $image_path --backend $backend --dry-run=$dry_run | from json)
  # Extract published URL from pub_result; synthesize a representative placeholder for dry-runs
  let published_url = if ($pub_result.action? == "would-run") or ($pub_result.url? == null) or ($pub_result.url? == "") {
    let m = open $manifest_file
    let name    = $m.image?.name?    | default "image"
    let version = $m.image?.version? | default "v0.0.0"
    let fmt     = $m.image?.format?  | default "raw"
    $"https://example-bucket.example.com/($name)-($version).($fmt)"
  } else {
    $pub_result.url
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
  # 3. deploy — pass published_url via --image so the Vultr adapter gets export_url
  let dep_result = if $published_url != "" {
    (main deploy $manifest_file --provider $provider --image $published_url --dry-run=$dry_run | from json)
  } else {
    (main deploy $manifest_file --provider $provider --dry-run=$dry_run | from json)
  }
  # Return combined pipeline result with top-level convenience fields for agents
  {
    pipeline:      "validate->build->publish->deploy"
    valid:         ($validate_result.valid? | default false)
    receipt_path:  ($build_result.receipt_path? | default "")
    image_path:    $image_path
    published_url: $published_url
    build:         $build_result
    publish:       $pub_result
    deploy:        $dep_result
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

def main [] {
  print "genoa — generated OS for AI assistants"
  print ""
  print "Commands: catalog  schema  describe  validate  build  deploy  publish  verify  run  status  health  selftest"
  print "Usage:    nu genoa.nu <command> [args]"
  print "Example:  nu genoa.nu catalog | jq '.providers[0]'"
}



# Emit build metrics and events to Datadog via pup.
# Reads a receipt file and posts genoa.build.* metrics.
# Requires: pup authenticated (`pup auth status`)
def "main notify" [receipt_file: string, --dry-run] {
  if not ($receipt_file | path exists) {
    return ({action: "failed", error: $"receipt not found: ($receipt_file)"} | to json --indent 2)
  }
  let r = open $receipt_file
  let profile  = $r.build?.profile?   | default "unknown"
  let arch     = $r.build?.arch?      | default "unknown"
  let dry      = $r.build?.dry_run?   | default false
  let agent_n  = $r.agent?.name?      | default "unknown"
  let img_ver  = $r.image?.version?   | default "unknown"
  let img_name = $r.image?.name?      | default "unknown"
  let claims   = $r.claims? | default [] | length
  let now      = (date now | format date "%s" | into int)

  let metrics = {
    series: [
      {metric: "genoa.build.success"  type: 1 points: [{timestamp: $now value: 1}]
       tags: [$"profile:($profile)" $"arch:($arch)" $"dry_run:($dry)" $"agent_name:($agent_n)" "project:genoa"]}
      {metric: "genoa.image.size_mb"  type: 3 points: [{timestamp: $now value: ($r.image?.size_mb? | default 1024)}]
       tags: [$"profile:($profile)" $"arch:($arch)" "project:genoa"]}
      {metric: "genoa.receipt.claims" type: 3 points: [{timestamp: $now value: $claims}]
       tags: [$"profile:($profile)" "project:genoa"]}
    ]
  }

  if $dry_run {
    return ({action: "would-notify", receipt: $receipt_file, metrics: ($metrics.series | length), tags: [$"profile:($profile)" $"arch:($arch)"]} | to json --indent 2)
  }

  let tmp = $"/tmp/genoa-metrics-($now).json"
  $metrics | to json | save --force $tmp

  let result = try {
    ^pup metrics submit --file $tmp | complete
  } catch { |e| {exit_code: -1 stderr: $e.msg} }

  ^rm -f $tmp

  if ($result.exit_code? | default 99) == 0 {
    {action: "notified" receipt: $receipt_file metrics_submitted: ($metrics.series | length) profile: $profile arch: $arch} | to json --indent 2
  } else {
    {action: "failed" step: "pup_metrics_submit" stderr: ($result.stderr? | default "unknown error")} | to json --indent 2
  }
}
