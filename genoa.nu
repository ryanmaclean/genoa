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
    source adapters/linode.nu; linode_deploy $m $image --dry-run=$dry_run
  } else if $path == "snapshot-url" {
    source adapters/vultr.nu;  vultr_deploy  $m $image --dry-run=$dry_run
  } else {
    source adapters/oci.nu;    oci_deploy    $m $image --dry-run=$dry_run
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
  mut checks = []
  mut errors = []

  # 1. image_exists
  let image_ok = ($image | path exists)
  # Peek at receipt to detect dry-run before deciding how to treat a missing image
  let receipt_ok_pre = ($receipt_file | path exists)
  let is_dry_run_receipt = if $receipt_ok_pre {
    (open $receipt_file).dry_run? | default false
  } else { false }

  let image_check = if $image_ok {
    {check: "image_exists", pass: true, detail: $"($image) exists"}
  } else if $is_dry_run_receipt {
    {check: "image_exists", pass: true, detail: $"dry-run receipt — image not yet built: ($image)"}
  } else {
    {check: "image_exists", pass: false, detail: $"image not found: ($image)"}
  }
  $checks = ($checks | append $image_check)
  if not $image_ok and not $is_dry_run_receipt {
    $errors = ($errors | append $"image not found: ($image)")
  }

  # 2. receipt_exists
  let receipt_ok = $receipt_ok_pre
  $checks = ($checks | append {check: "receipt_exists", pass: $receipt_ok, detail: (if $receipt_ok { $"($receipt_file) exists" } else { $"receipt not found: ($receipt_file)" })})
  if not $receipt_ok { $errors = ($errors | append $"receipt not found: ($receipt_file)") }

  # Early return if receipt is missing, or image is missing and not a dry-run receipt
  if not $receipt_ok or (not $image_ok and not $is_dry_run_receipt) {
    return {
      action: "verify"
      image: $image
      receipt_file: $receipt_file
      receipt_id: "unknown"
      checks: $checks
      valid: false
      errors: $errors
    }
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
  let manifest_path = if ("hashes" in $r) {
    # v1 schema: manifest path is top-level in image or in a manifest_path field
    ($r.manifest_path? | default "")
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

  # 4. image_sha256_match — compute sha256 of the image file
  let img_sha256_check = if $image_sha256 == "dry-run-placeholder" {
    {check: "image_sha256", pass: true, detail: "dry-run receipt — sha256 not computed; skipping"}
  } else {
    let computed_image_sha256 = if $image_ok {
      if $nu.os-info.name == "macos" {
        ^shasum -a 256 $image | str trim | split row " " | first
      } else {
        ^sha256sum $image | str trim | split row " " | first
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
  if not $img_sha256_check.pass { $errors = ($errors | append $img_sha256_check.detail) }

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

  {
    action: "verify"
    image: $image
    receipt_file: $receipt_file
    receipt_id: $receipt_id
    checks: $checks
    valid: ($errors | is-empty)
    errors: $errors
  }
}

def "main status" [] {
  # Find all receipt files in current dir and subdirs (max depth 2)
  let receipts = try { ls **/*.receipt.json | get name } catch { [] }

  # Also check ./out/ directory
  let out_receipts = if ("out" | path exists) {
    try { ls out/*.receipt.json | get name } catch { [] }
  } else { [] }

  let all_receipts = ($receipts | append $out_receipts | uniq)

  if ($all_receipts | is-empty) {
    return {
      action: "status"
      receipts_found: 0
      message: "No receipts found. Run `genoa build <manifest>` to create one."
      tip: "Receipts are written as <manifest-basename>.receipt.json after each build."
    }
  }

  let parsed = $all_receipts | each { |path|
    let r = try { open $path } catch { null }
    if $r == null { return {path: $path, status: "unreadable"} }
    {
      path: $path
      receipt_id: ($r.receipt_id? | default "unknown")
      image_path: ($r.image_path? | default "unknown")
      image_exists: ($r.image_path? | default "" | path exists)
      profile: ($r.profile? | default "unknown")
      built_at: ($r.built_at? | default "unknown")
      dry_run: ($r.dry_run? | default false)
      manifest_path: ($r.manifest_path? | default "unknown")
      sha256_placeholder: (($r.image_sha256? | default "") == "dry-run-placeholder")
    }
  }

  let real_builds = ($parsed | where dry_run == false)
  let dry_runs = ($parsed | where dry_run == true)
  let images_on_disk = ($parsed | where image_exists == true)

  {
    action: "status"
    receipts_found: ($all_receipts | length)
    real_builds: ($real_builds | length)
    dry_runs: ($dry_runs | length)
    images_on_disk: ($images_on_disk | length)
    receipts: $parsed
    next_steps: (if ($real_builds | is-empty) {
      ["No real builds yet. Run: nu genoa.nu build <manifest.toml>"]
    } else if ($images_on_disk | is-empty) {
      ["Images not found at recorded paths. They may have been moved or deleted."]
    } else {
      ["Images ready. Run: nu genoa.nu deploy <manifest.toml> to deploy."]
    })
  }
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
  # Extract published URL from pub_result
  let published_url = $pub_result | get url? | default ""
  # 3. deploy — pass published_url via --image so the Vultr adapter gets export_url
  let dep_result = if $published_url != "" {
    (main deploy $manifest_file --provider $provider --image $published_url --dry-run=$dry_run)
  } else {
    (main deploy $manifest_file --provider $provider --dry-run=$dry_run)
  }
  # Return combined pipeline result
  {
    pipeline: "build→publish→deploy"
    build:   $build_result
    publish: $pub_result
    published_url: $published_url
    deploy:  $dep_result
  }
}

def main [] {
  print "genoa — generated OS for AI assistants"
  print ""
  print "Commands: catalog  schema  describe  validate  build  deploy  publish  verify  run  status"
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
def verify [i: string, r: string] { main verify $i $r }
