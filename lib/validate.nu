# lib/validate.nu — manifest validation + receipt verify
# Sourced by genoa.nu. No cross-module sources.

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
  let os_for_iface = ($m.target?.os? | default "freebsd")
  let iface_result = if $provider_for_iface == "vultr" {
    if ($iface | str starts-with "vtnet") {
      {pass: true, detail: $"interface=($iface) \(vultr: vtnet* ok\)"}
    } else if ($iface | str starts-with "vioif") and $os_for_iface == "netbsd" {
      # NetBSD uses vioif* for virtio NICs instead of vtnet*
      {pass: true, detail: $"interface=($iface) \(vultr/netbsd: vioif* ok\)"}
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
