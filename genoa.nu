#!/usr/bin/env nu

def "main catalog" [] {
  open "catalog/providers.v1.json"
}

def "main schema" [] {
  open "schema/manifest.v1.json"
}

def "main describe" [manifest_file: string] {
  if not ($manifest_file | path exists) {
    error make {msg: $"manifest file not found: ($manifest_file)"}
  }
  let m = open $manifest_file
  {
    action: "describe"
    manifest_path: $manifest_file
    image_name:    ($m.image?.name?    | default "unknown")
    image_version: ($m.image?.version? | default "unknown")
    target_os:     ($m.target?.os?     | default "unknown")
    target_arch:   ($m.target?.arch?   | default "unknown")
    profile:       ($m.profile?        | default "uefi")
    provider:      ($m.deploy?.provider? | default "none")
    status: "parsed"
  }
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
  let p = ($m.profile? | default $profile)
  let profile_file = $"profiles/($p).nu"

  # Derive receipt path from manifest basename
  let manifest_basename = ($manifest_file | path basename | str replace --regex '\.[^.]+$' '')

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
    return ($remote_result | merge {build_host: $build_host, remote: true})
  }

  let receipt_path = $"($manifest_basename).receipt.json"

  # Derive image_path from manifest or use default
  let image_path = ($m.image?.output_path? | default $"/tmp/genoa-($manifest_basename).raw")

  let manifest_content = open $manifest_file

  let build_result = if not ($profile_file | path exists) {
    {action: "stub", reason: $"($p) profile not yet implemented", profile: $p}
  } else if $p == "kboot" {
    source profiles/kboot.nu
    kboot_build $m $dry_run
  } else {
    source profiles/uefi.nu
    uefi_build $m $dry_run
  }

  # Parse build_result — kboot_build returns a JSON string, others return records.
  # Use try/catch to handle both cases without shadowing the built-in describe.
  let build_record = try {
    $build_result | from json
  } catch {
    $build_result
  }

  # Write receipt file
  let receipt = {
    schema_version: "1"
    receipt_id: (random uuid)
    image_path: $image_path
    image_sha256: "dry-run-placeholder"
    manifest_path: $manifest_file
    manifest_sha256: ($manifest_content | to json | hash sha256)
    profile: $p
    built_at: (date now | format date "%Y-%m-%dT%H:%M:%SZ")
    dry_run: $dry_run
  }

  $receipt | save --force $receipt_path

  # Return build plan with receipt_path appended
  $build_record | merge {receipt_path: $receipt_path}
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
    return {action: "stub", reason: $"no adapter for deployment_path: ($path)", provider: $pid}
  }
  if not ($afile | path exists) {
    return {action: "stub", reason: $"($afile) not found", provider: $pid}
  }

  # Resolve image path: --image > --from-receipt > manifest field > default
  let image = if $image != "" {
    $image
  } else if $from_receipt != "" {
    if not ($from_receipt | path exists) {
      error make {msg: $"receipt file not found: ($from_receipt)"}
    }
    (open $from_receipt).image_path
  } else {
    ($m.image?.output_path? | default "/tmp/genoa.raw")
  }

  if $path == "rescue-dd" {
    source adapters/linode.nu; linode_deploy $m $image
  } else if $path == "snapshot-url" {
    source adapters/vultr.nu;  vultr_deploy  $m $image
  } else {
    source adapters/oci.nu;    oci_deploy    $m $image
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
    return {
      action: "validate"
      manifest_path: $manifest_file
      valid: false
      checks: $checks
      errors: $errors
      warnings: $warnings
    }
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
  let valid_formats = ["raw", "qcow2", "vmdk", "iso"]
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
    let all_zeros = ($sha256 | str replace --all "0" "" | str length) == 0
    let sha_pass = (not $all_zeros)
    let sha_prefix = ($sha256 | str substring 0..8)
    let sha_detail = if $sha_pass {
      $"sha256 present ($sha_prefix)..."
    } else {
      "sha256 is all-zeros placeholder — replace before production build"
    }
    $checks = ($checks | append {check: "agent_sha256_real", pass: $sha_pass, detail: $sha_detail})
    if not $sha_pass { $warnings = ($warnings | append "agent_sha256_real: sha256 is all-zeros placeholder — replace before production build") }
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

  {
    action: "validate"
    manifest_path: $manifest_file
    valid: ($errors | is-empty)
    checks: $checks
    errors: $errors
    warnings: $warnings
  }
}

def "main verify" [image: string, receipt_file: string] {
  if not ($image | path exists) {
    error make {msg: $"image not found: ($image)"}
  }
  if not ($receipt_file | path exists) {
    error make {msg: $"receipt not found: ($receipt_file)"}
  }
  let r = open $receipt_file
  {action: "verify", image: $image, receipt_id: ($r.receipt_id? | default "unknown")}
}

def "main publish" [
  image: string
  --backend: string = "r2"
  --dry-run
] {
  if not ($image | path exists) {
    # dry-run mode: emit plan without error
    if $dry_run {
      return {action: "would-run", image: $image, backend: $backend, note: "image not yet built — run genoa build first"}
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
      {action: "stub", reason: $"publish.nu invocation failed: ($e.msg)", image: $image, backend: $backend} | to json
    }
    try { $result_json | from json } catch { {action: "stub", reason: "publish.nu output not parseable", image: $image, backend: $backend} }
  } else {
    {action: "stub", reason: "publish.nu not yet available", image: $image, backend: $backend}
  }
}

def "main run" [
  manifest_file: string
  --provider: string = ""
  --backend: string = "r2"
  --dry-run
] {
  # 1. build
  let build_result = (main build $manifest_file --dry-run=$dry_run)
  # 2. publish (uses receipt from build)
  let receipt_path = ($build_result | get receipt_path? | default "")
  let image_path = if $receipt_path != "" and ($receipt_path | path exists) {
    (open $receipt_path).image_path
  } else { "/tmp/genoa.raw" }
  let pub_result = (main publish $image_path --backend $backend --dry-run=$dry_run)
  # 3. deploy
  let dep_result = (main deploy $manifest_file --provider $provider --dry-run=$dry_run)
  # Return combined pipeline result
  {
    pipeline: "build→publish→deploy"
    build:   $build_result
    publish: $pub_result
    deploy:  $dep_result
  }
}

def main [] {
  print "genoa — generated OS for AI assistants"
  print ""
  print "Commands: catalog  schema  describe  validate  build  deploy  publish  verify  run"
  print "Usage:    nu genoa.nu <command> [args]"
  print "Example:  nu genoa.nu catalog | jq '.[\"providers\"][0]'"
}

# --- legacy bare defs (keep for source-import compatibility) ---

def catalog [] {
  open "catalog/providers.v1.json"
}

def schema [] { open "schema/manifest.v1.json" }
def describe [f: string] { if not ($f | path exists) { error make {msg: $"not found: ($f)"} }; open $f }
def build [f: string] { {action: "stub", note: "use: nu genoa.nu build <manifest>"} }
def deploy [f: string, p: string] { {action: "stub", note: "use: nu genoa.nu deploy <manifest> --provider <id>"} }
def verify [i: string, r: string] { {action: "stub"} }
