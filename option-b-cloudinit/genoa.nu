#!/usr/bin/env nu
# genoa.nu — cloud-init image baker CLI (Option B)
# AX-first: catalog → schema → describe → build in ≤3 tool calls cold-start
#
# Usage:
#   nu genoa.nu catalog
#   nu genoa.nu schema
#   nu genoa.nu describe <manifest.toml>
#   nu genoa.nu build <manifest.toml> [--target qcow2|aws|gcp|do|pi|raw] [--dry-run]
#   nu genoa.nu verify <image-path> <attestation.json>
#
# License: BSD-2-Clause
# Requires: nushell >= 0.111

const GENOA_VERSION = "0.1.0"
const SCHEMA_VERSION = "v1"
const BUILD_TYPE = "https://genoa.dev/image-build/v1"
const PREDICATE_TYPE = "https://genoa.dev/image-build/v1"

# ─── Catalog ──────────────────────────────────────────────────────────────────
# List all supported (base, arch, target) tuples as JSON.
# AX-first: this is the discovery endpoint — one call tells an agent everything
# it can build.
def "main catalog" [] {
  {
    schema: "https://genoa.dev/catalog/v1"
    genoa_version: $GENOA_VERSION
    description: "Supported (base, arch, target) tuples for genoa image builds"
    entries: [
      { base: "alpine-3.20",      arch: "aarch64", targets: ["pi", "qcow2", "raw"],        status: "supported", template: "templates/osbuild/alpine-aarch64.json.tera" }
      { base: "alpine-3.20",      arch: "x86_64",  targets: ["qcow2", "aws", "gcp", "raw"], status: "supported", template: "templates/osbuild/alpine-aarch64.json.tera" }
      { base: "debian-bookworm",  arch: "x86_64",  targets: ["qcow2", "aws", "gcp", "do", "raw"], status: "supported", template: "templates/osbuild/debian-amd64.json.tera" }
      { base: "debian-bookworm",  arch: "aarch64", targets: ["pi", "qcow2", "raw"],        status: "planned",   template: null }
      { base: "ubuntu-noble",     arch: "x86_64",  targets: ["qcow2", "aws", "gcp", "do"], status: "planned",   template: null }
      { base: "ubuntu-noble",     arch: "aarch64", targets: ["pi", "qcow2"],               status: "planned",   template: null }
      { base: "fedora-40",        arch: "x86_64",  targets: ["qcow2", "aws"],              status: "planned",   template: null }
    ]
    stack_components: ["datadog_agent", "ollama", "ii_agent", "ac_client"]
    cloud_init_datasources: ["NoCloud", "Ec2", "GCE", "DigitalOcean"]
    rejected_tools: [
      { name: "HashiCorp Packer", reason: "BUSL-1.1 — non-free for commercial use" }
      { name: "mkosi",            reason: "LGPL-2.1 — copyleft" }
      { name: "debian live-build", reason: "GPL-3 — copyleft" }
      { name: "SUSE kiwi-ng",    reason: "GPL-3 — copyleft" }
      { name: "cloud-localds",   reason: "GPL-3 — copyleft; genoa builds NoCloud ISOs natively" }
    ]
  } | to json --indent 2
}

# ─── Schema ───────────────────────────────────────────────────────────────────
# Print the JSON Schema for genoa manifests.
# AX-first: after catalog, this gives an agent the full type system.
def "main schema" [
  --attestation  # Print the attestation schema instead of the manifest schema
] {
  let script_dir = ($env.CURRENT_FILE | path dirname)
  let schema_file = if $attestation {
    $script_dir | path join "schema/attestation.v1.json"
  } else {
    $script_dir | path join "schema/manifest.v1.json"
  }
  if not ($schema_file | path exists) {
    error make { msg: $"GENOA_ERROR: schema file not found: ($schema_file)" }
  }
  open --raw $schema_file
}

# ─── Describe ─────────────────────────────────────────────────────────────────
# Parse a manifest, validate it, and emit a full structured build plan with hashes.
# AX-first: after describe, an agent has everything needed to call build.
def "main describe" [
  manifest_path: path  # Path to the TOML manifest file
] {
  let script_dir = ($env.CURRENT_FILE | path dirname)
  let result = load_and_validate $manifest_path $script_dir
  if $result.valid == false {
    error make { msg: $"GENOA_ERROR: manifest validation failed\n($result.errors | to json)" }
  }
  let manifest = $result.manifest
  let manifest_text = open --raw $manifest_path
  let manifest_hash = $"sha256:($manifest_text | hash sha256)"

  # Render templates to get their hashes
  let ud_template_path = $script_dir | path join "templates/cloud-init/user-data.tera"
  let template_text = if ($ud_template_path | path exists) { open --raw $ud_template_path } else { "" }
  let template_hash = $"sha256:($template_text | hash sha256)"

  # Determine which osbuild template applies
  let base = $manifest.image.base
  let arch = $manifest.image.arch
  let osbuild_template = select_osbuild_template $base $arch $script_dir
  let osbuild_template_text = if ($osbuild_template.path | path exists) { open --raw $osbuild_template.path } else { "" }
  let osbuild_hash = $"sha256:($osbuild_template_text | hash sha256)"

  # Determine available targets
  let configured_targets = if ($manifest | get -o targets | is-not-empty) {
    $manifest.targets | columns | where { |t|
      let enabled = ($manifest.targets | get $t | get -o enabled)
      $enabled == true or $enabled == null
    }
  } else {
    []
  }

  {
    schema: "https://genoa.dev/describe/v1"
    genoa_version: $GENOA_VERSION
    manifest_id: $manifest.genoa.manifest_id
    manifest_hash: $manifest_hash
    manifest_path: ($manifest_path | path expand)
    valid: true
    plan: {
      base: $base
      arch: $arch
      hostname: ($manifest.image | get -o hostname | default $manifest.genoa.manifest_id)
      configured_targets: $configured_targets
      stack: {
        datadog_agent: ($manifest.stack | get -o datadog_agent.enabled | default false)
        ollama:        ($manifest.stack | get -o ollama.enabled | default false)
        ii_agent:      ($manifest.stack | get -o ii_agent.enabled | default false)
        ac_client:     ($manifest.stack | get -o ac_client.enabled | default false)
      }
      secrets_backend: ($manifest | get -o secrets.backend | default "env")
      secret_refs: (collect_secret_refs $manifest)
    }
    hashes: {
      manifest:         $manifest_hash
      user_data_template: $template_hash
      osbuild_template: $osbuild_hash
    }
    osbuild_template: $osbuild_template
    cloud_init_template: $ud_template_path
    build_commands: (build_commands_for $manifest $configured_targets)
    next_step: "nu genoa.nu build <manifest.toml> --target <target> [--dry-run]"
  } | to json --indent 2
}

# ─── Build ────────────────────────────────────────────────────────────────────
# Render templates, produce osbuild manifest, generate cloud-init seed, and
# (unless --dry-run) invoke osbuild to produce the image.
def "main build" [
  manifest_path: path             # Path to the TOML manifest file
  --target: string = "qcow2"      # Output target: qcow2, aws, gcp, do, pi, raw
  --dry-run                       # Render and validate; print would-run commands without executing
  --output-dir: path = "dist"     # Output directory for rendered files and images
] {
  let script_dir = ($env.CURRENT_FILE | path dirname)
  let result = load_and_validate $manifest_path $script_dir
  if $result.valid == false {
    error make { msg: $"GENOA_ERROR: manifest validation failed\n($result.errors | to json --indent 2)" }
  }
  let manifest = $result.manifest
  let manifest_text = open --raw $manifest_path
  let manifest_hash = ($manifest_text | hash sha256)
  let manifest_id = $manifest.genoa.manifest_id

  print $"genoa ($GENOA_VERSION) — building ($manifest_id) for target ($target)"

  # Validate target is configured
  let targets_rec = $manifest | get -o targets
  let target_config = if $targets_rec != null {
    $targets_rec | get -o $target
  } else { null }
  if $target_config == null {
    print $"WARN: target '($target)' not configured in manifest — using defaults"
  }

  # Build context for template rendering
  let ctx = build_context $manifest $manifest_hash $target

  # Resolve secrets (env backend only in this phase)
  let ctx_with_secrets = resolve_secrets $ctx $manifest

  # ── Render user-data ───────────────────────────────────────────────────────
  let ud_template_path = $script_dir | path join "templates/cloud-init/user-data.tera"
  print $"  Rendering cloud-init user-data from ($ud_template_path)"
  let rendered_user_data = render_template $ud_template_path $ctx_with_secrets

  # ── Render osbuild manifest ────────────────────────────────────────────────
  let osbuild_info = select_osbuild_template $manifest.image.base $manifest.image.arch $script_dir
  let rendered_osbuild = render_template $osbuild_info.path $ctx_with_secrets

  # ── Compute hashes ─────────────────────────────────────────────────────────
  let user_data_hash = $"sha256:($rendered_user_data | hash sha256)"
  let osbuild_hash = $"sha256:($rendered_osbuild | hash sha256)"
  let ud_template_text = open --raw $ud_template_path
  let template_hash = $"sha256:($ud_template_text | hash sha256)"

  # ── Write outputs ──────────────────────────────────────────────────────────
  let build_dir = $script_dir | path join $"($output_dir)/($manifest_id)-($target)"

  if not $dry_run {
    mkdir $build_dir
    $rendered_user_data | save --force ($build_dir | path join "user-data")
    $rendered_osbuild | save --force ($build_dir | path join "osbuild-manifest.json")

    # Build meta-data with unique instance-id derived from manifest hash
    let instance_id = $"genoa-($manifest_hash | str substring 0..11)"
    let meta_data = $"instance-id: ($instance_id)\nlocal-hostname: ($ctx_with_secrets.hostname)\n"
    $meta_data | save --force ($build_dir | path join "meta-data")

    print $"  Written: ($build_dir)/user-data"
    print $"  Written: ($build_dir)/osbuild-manifest.json"
    print $"  Written: ($build_dir)/meta-data"

    # Generate stub SBOM
    let sbom = generate_stub_sbom $manifest_id $manifest_hash
    let sbom_path = $build_dir | path join "sbom.spdx.json"
    $sbom | to json --indent 2 | save --force $sbom_path
    let sbom_hash = $"sha256:(open --raw $sbom_path | hash sha256)"

    # Build seed ISO
    print "  Building cloud-init seed ISO..."
    let seed_result = (^nu ($script_dir | path join "seed-iso/build.nu")
      --user-data ($build_dir | path join "user-data")
      --manifest-id $manifest_id
      --manifest-hash $manifest_hash
      --output-dir ($build_dir | path join "seed")
    ) | complete
    if $seed_result.exit_code != 0 {
      print $"  WARN: seed ISO build: ($seed_result.stderr)"
    }
    let seed_layout = $seed_result.stdout | from json
    let seed_hash = $"sha256:($rendered_user_data | hash sha256)"

    # Generate and write attestation
    let attestation = build_attestation {
      manifest_id: $manifest_id
      manifest_hash: $"sha256:($manifest_hash)"
      osbuild_hash: $osbuild_hash
      user_data_hash: $user_data_hash
      template_hash: $template_hash
      sbom_hash: $sbom_hash
      target: $target
      build_dir: $build_dir
    }
    let attest_path = $build_dir | path join "attestation.json"
    $attestation | to json --indent 2 | save --force $attest_path
    print $"  Written: ($attest_path)"

    # Emit osbuild invocation command
    print ""
    print "  ── osbuild invocation (would-run) ────────────────────────────────────"
    print $"  sudo osbuild \\"
    print $"    --store /var/cache/osbuild \\"
    print $"    --output-dir ($build_dir) \\"
    print $"    --export ($target) \\"
    print $"    ($build_dir)/osbuild-manifest.json"
    print "  (osbuild requires root + container runtime; stubbed)"
    print ""

    # Emit cloud upload command if applicable
    emit_upload_command $target $manifest $manifest_id $build_dir

    print $"genoa build complete: ($manifest_id) → ($build_dir)"
    {
      status: "success"
      manifest_id: $manifest_id
      target: $target
      build_dir: $build_dir
      attestation: $attest_path
      hashes: {
        manifest: $"sha256:($manifest_hash)"
        user_data: $user_data_hash
        osbuild: $osbuild_hash
        sbom: $sbom_hash
      }
    } | to json --indent 2
  } else {
    # Dry-run: print everything, execute nothing
    print ""
    print "  ══ DRY RUN — no files written, no commands executed ══"
    print ""
    print "  ── Rendered user-data (first 40 lines) ───────────────────────────────"
    $rendered_user_data | lines | first 40 | str join "\n" | print
    print "  [... truncated ...]"
    print ""
    print "  ── Would invoke osbuild ──────────────────────────────────────────────"
    print $"  sudo osbuild \\"
    print $"    --store /var/cache/osbuild \\"
    print $"    --output-dir ($build_dir) \\"
    print $"    --export ($target) \\"
    print $"    ($build_dir)/osbuild-manifest.json"
    print ""
    emit_upload_command $target $manifest $manifest_id $build_dir

    {
      status: "dry-run"
      manifest_id: $manifest_id
      target: $target
      rendered_user_data_lines: ($rendered_user_data | lines | length)
      rendered_osbuild_bytes: ($rendered_osbuild | str length)
      hashes: {
        manifest: $"sha256:($manifest_hash)"
        user_data: $user_data_hash
        osbuild: $osbuild_hash
        template: $template_hash
      }
    } | to json --indent 2
  }
}

# ─── Verify ───────────────────────────────────────────────────────────────────
# Recompute hashes against an attestation and report any mismatches.
def "main verify" [
  image_path: path         # Path to the built image or build directory
  attestation_path: path   # Path to attestation.json
] {
  if not ($attestation_path | path exists) {
    error make { msg: $"GENOA_ERROR: attestation file not found: ($attestation_path)" }
  }

  let attestation = open --raw $attestation_path | from json
  let predicate = $attestation.predicate
  let build_config = $predicate.buildConfig

  let results = []
  mut mismatches = []
  mut checks = []

  # Verify manifest hash if the manifest file is accessible
  let manifest_ref = ($attestation.predicate | get -o materials) | where { |m| $m.uri | str contains "manifest" } | first 1
  if ($manifest_ref | length) > 0 {
    let expected_manifest_hash = $manifest_ref.0.digest.sha256
    $checks = ($checks | append {
      check: "manifest_material"
      expected: $"sha256:($expected_manifest_hash)"
      note: "manifest hash from materials list"
      result: "skipped — manifest file path not provided; provide manifest path to fully verify"
    })
  }

  # Verify osbuild manifest hash if build dir exists
  let build_dir = if ($image_path | path type) == "dir" { $image_path } else { $image_path | path dirname }
  let osbuild_manifest_path = $build_dir | path join "osbuild-manifest.json"
  if ($osbuild_manifest_path | path exists) {
    let actual_hash = $"sha256:(open --raw $osbuild_manifest_path | hash sha256)"
    let expected_hash = $build_config.osbuild_manifest_hash
    let passed = $actual_hash == $expected_hash
    if not $passed { $mismatches = ($mismatches | append "osbuild_manifest_hash") }
    $checks = ($checks | append {
      check: "osbuild_manifest_hash"
      expected: $expected_hash
      actual: $actual_hash
      passed: $passed
    })
  }

  # Verify user-data hash
  let ud_path = $build_dir | path join "user-data"
  if ($ud_path | path exists) {
    let actual_hash = $"sha256:(open --raw $ud_path | hash sha256)"
    let expected_hash = $build_config.cloud_init_seed_hash
    let passed = $actual_hash == $expected_hash
    if not $passed { $mismatches = ($mismatches | append "cloud_init_seed_hash") }
    $checks = ($checks | append {
      check: "cloud_init_seed_hash"
      expected: $expected_hash
      actual: $actual_hash
      passed: $passed
    })
  }

  # Verify trust field is present and declared
  let trust = $predicate | get -o trust
  let trust_check = if $trust != null {
    { check: "trust_declared", level: $trust.level, signed_by: $trust.signed_by, passed: true }
  } else {
    $mismatches = ($mismatches | append "trust_missing")
    { check: "trust_declared", passed: false, note: "trust field missing from attestation" }
  }
  $checks = ($checks | append $trust_check)

  # Verify SBOM hash if present
  let sbom_path = $build_dir | path join "sbom.spdx.json"
  if ($sbom_path | path exists) and ($build_config | get -o sbom_hash | is-not-empty) {
    let actual_hash = $"sha256:(open --raw $sbom_path | hash sha256)"
    let expected_hash = $build_config.sbom_hash
    let passed = $actual_hash == $expected_hash
    if not $passed { $mismatches = ($mismatches | append "sbom_hash") }
    $checks = ($checks | append {
      check: "sbom_hash"
      expected: $expected_hash
      actual: $actual_hash
      passed: $passed
    })
  }

  let overall_passed = ($mismatches | length) == 0

  {
    schema: "https://genoa.dev/verify/v1"
    attestation_path: ($attestation_path | path expand)
    image_path: ($image_path | path expand)
    manifest_id: ($attestation.predicate.builder | get -o id | default "unknown")
    overall: (if $overall_passed { "PASS" } else { "FAIL" })
    mismatches: $mismatches
    checks: $checks
    trust: $trust
    predicate_type: ($attestation | get -o predicateType | default "unknown")
  } | to json --indent 2
}

# ─── Internal helpers ─────────────────────────────────────────────────────────

def load_and_validate [manifest_path: path, script_dir: path] {
  if not ($manifest_path | path exists) {
    return { valid: false, errors: [$"manifest file not found: ($manifest_path)"], manifest: null }
  }

  let manifest = try {
    open $manifest_path
  } catch {
    return { valid: false, errors: ["failed to parse TOML manifest"], manifest: null }
  }

  mut errors = []

  # Required top-level keys
  for key in ["genoa", "image", "stack"] {
    if ($manifest | get -o $key) == null {
      $errors = ($errors | append $"missing required key: ($key)")
    }
  }

  # genoa section
  let genoa = $manifest | get -o genoa
  if $genoa != null {
    if ($genoa | get -o schema_version) != "v1" {
      $errors = ($errors | append "genoa.schema_version must be 'v1'")
    }
    if ($genoa | get -o manifest_id | is-empty) {
      $errors = ($errors | append "genoa.manifest_id is required")
    }
  }

  # image section
  let image = $manifest | get -o image
  if $image != null {
    let valid_bases = ["alpine-3.20", "debian-bookworm", "ubuntu-noble", "fedora-40"]
    let base = $image | get -o base | default ""
    if not ($valid_bases | any { |b| $b == $base }) {
      $errors = ($errors | append $"image.base '($base)' not in supported list: ($valid_bases | str join ', ')")
    }
    let valid_arches = ["aarch64", "x86_64", "armv7l"]
    let arch = $image | get -o arch | default ""
    if not ($valid_arches | any { |a| $a == $arch }) {
      $errors = ($errors | append $"image.arch '($arch)' not in supported list: ($valid_arches | str join ', ')")
    }
  }

  # Secret refs — flag patterns that look like inlined API/token secrets
  # Note: SSH public keys (ssh-ed25519 AAAAC3...) are allowed in ssh_authorized_keys fields
  let manifest_str = open --raw $manifest_path
  # Only flag patterns that appear in value position (= "...") not in ssh_authorized_keys lists
  let suspicious_patterns = ["sk-ant-", "sk-proj-", "dapi-", "xoxb-", "ghp_", "ANTHROPIC_API_KEY: "]
  for pattern in $suspicious_patterns {
    if ($manifest_str | str contains $pattern) {
      $errors = ($errors | append $"SECURITY: manifest may contain inline secret matching pattern '($pattern)' — use secret_ref fields instead")
    }
  }

  { valid: (($errors | length) == 0), errors: $errors, manifest: $manifest }
}

def select_osbuild_template [base: string, arch: string, script_dir: path] {
  let template_map = {
    "alpine-3.20-aarch64": "templates/osbuild/alpine-aarch64.json.tera"
    "alpine-3.20-x86_64":  "templates/osbuild/alpine-aarch64.json.tera"  # reuse with arch override
    "debian-bookworm-x86_64": "templates/osbuild/debian-amd64.json.tera"
    "debian-bookworm-aarch64": "templates/osbuild/debian-amd64.json.tera" # planned
  }
  let key = $"($base)-($arch)"
  let rel_path = $template_map | get -o $key | default "templates/osbuild/debian-amd64.json.tera"
  let abs_path = $script_dir | path join $rel_path
  { key: $key, path: $abs_path, relative: $rel_path }
}

def build_context [manifest: record, manifest_hash: string, target: string] {
  let image = $manifest.image
  let stack = $manifest.stack
  let dd = $stack | get -o datadog_agent
  let ollama = $stack | get -o ollama
  let ii = $stack | get -o ii_agent
  let ac = $stack | get -o ac_client

  {
    manifest_id:    $manifest.genoa.manifest_id
    generated_at:   (date now | format date "%Y-%m-%dT%H:%M:%SZ")
    hostname:       ($image | get -o hostname | default $manifest.genoa.manifest_id)
    locale:         ($image | get -o locale | default "en_US.UTF-8")
    timezone:       ($image | get -o timezone | default "UTC")
    target:         $target
    disk_size_gb:   (let tr = ($manifest | get -o targets); if $tr != null { $tr | get -o $target | default {} | get -o disk_size_gb | default 10 } else { 10 })
    compress:       (let tr = ($manifest | get -o targets); if $tr != null { $tr | get -o $target | default {} | get -o compress | default false } else { false })
    boot_partition_size_mb: (let tr = ($manifest | get -o targets); if $tr != null { $tr | get -o $target | default {} | get -o boot_partition_size_mb | default 256 } else { 256 })

    # Stack flags
    dd_enabled:     ($dd | get -o enabled | default false)
    dd_site:        ($dd | get -o site | default "datadoghq.com")
    dd_tags:        ($dd | get -o tags | default [])
    dd_api_key_secret_ref: ($dd | get -o api_key_secret_ref | default "DD_API_KEY")

    ollama_enabled:  ($ollama | get -o enabled | default false)
    ollama_version:  ($ollama | get -o version | default "latest")
    ollama_host:     ($ollama | get -o host | default "0.0.0.0:11434")
    ollama_models:   ($ollama | get -o models | default [])

    ii_agent_enabled:          ($ii | get -o enabled | default false)
    ii_agent_version:          ($ii | get -o version | default "latest")
    ii_agent_backend:          ($ii | get -o backend | default "anthropic")
    ii_agent_api_key_secret_ref: ($ii | get -o api_key_secret_ref | default "ANTHROPIC_API_KEY")

    ac_client_enabled:  ($ac | get -o enabled | default false)
    ac_client_version:  ($ac | get -o version | default "latest")

    users:          ($manifest | get -o users | default [])
    extra_packages: ($stack | get -o extra_packages | default [])
    extra_files:    ($stack | get -o extra_files | default [])

    # For osbuild templates
    base:  $manifest.image.base
    arch:  $manifest.image.arch
    root_fs_uuid: "44444444-4444-4444-4444-444444444444"
  }
}

def resolve_secrets [ctx: record, manifest: record] {
  # Only env backend implemented in v1; others are phase-2
  let backend = $manifest | get -o secrets.backend | default "env"
  if $backend != "env" {
    print $"WARN: secrets backend '($backend)' is phase-2; falling back to env"
  }
  # For env backend, secret_ref values map directly to env var names.
  # We do NOT inline them — they remain as {{secret:REF}} placeholders in
  # the rendered template so the cloud-init runtime can resolve them.
  # The context just carries the ref names for template substitution.
  $ctx
}

# Minimal template renderer — handles {{variable}} and basic {% for %} / {% if %}
# For production, phase-2 will shell out to a proper Tera binary (MIT).
def render_template [template_path: path, ctx: record] {
  if not ($template_path | path exists) {
    return $"# TEMPLATE NOT FOUND: ($template_path)\n"
  }
  mut text = open --raw $template_path

  # Simple variable substitution for scalar values
  for key in ($ctx | columns) {
    let val = $ctx | get $key
    let val_str = match ($val | describe | str replace -r ' .*' '') {
      "bool"   => (if $val { "true" } else { "false" })
      "int"    => ($val | into string)
      "float"  => ($val | into string)
      "string" => $val
      _        => ($val | to json)
    }
    $text = ($text | str replace --all $"{{ ($key) }}" $val_str)
    $text = ($text | str replace --all $"{{($key)}}" $val_str)
  }

  # Handle {{ var | default(value="x") }} — substitute known context keys in filtered form
  # Strategy: for each context key, replace "{{ key | default(...) }}" patterns using
  # exact prefix/suffix matching (avoids interpolated-string regex issues in nu)
  for key in ($ctx | columns) {
    let val = $ctx | get $key
    let val_str = match ($val | describe | str replace -r ' .*' '') {
      "bool"   => (if $val { "true" } else { "false" })
      "int"    => ($val | into string)
      "float"  => ($val | into string)
      "string" => $val
      _        => ""
    }
    if ($val_str | is-not-empty) {
      # Replace "{{ key | default(value=..." patterns — scan and replace line by line
      $text = ($text | lines | each { |line|
        if ($line | str contains $"{{ ($key) | default") {
          # Line has a filtered reference to this key — replace entire {{ ... }} with value
          $line | str replace -r '\{\{[^}]+\}\}' $val_str
        } else {
          $line
        }
      } | str join "\n")
    }
  }
  # Strip any remaining unresolved {{ var | filter }} expressions
  $text = ($text | str replace --all -r '\{\{\s*\w[\w.]*\s*\|[^}]*\}\}' '')

  # Handle lower filter
  $text = ($text | str replace --all "{{ compress | default(value=false) | lower }}" (if ($ctx | get -o compress | default false) { "true" } else { "false" }))
  $text = ($text | str replace --all "{{ false | lower }}" "false")
  $text = ($text | str replace --all "{{ true | lower }}" "true")

  # Expand user loop (simplified — emit placeholder section)
  if ($ctx.users | length) > 0 {
    mut user_block = ""
    for user in $ctx.users {
      $user_block = $user_block + $"  - name: ($user.name)\n"
      $user_block = $user_block + $"    gecos: ($user | get -o gecos | default $user.name)\n"
      $user_block = $user_block + $"    shell: ($user | get -o shell | default '/bin/bash')\n"
      $user_block = $user_block + $"    sudo: \"($user | get -o sudo | default 'ALL=(ALL) NOPASSWD:ALL')\"\n"
      $user_block = $user_block + $"    lock_passwd: true\n"
      let keys = $user | get -o ssh_authorized_keys | default []
      if ($keys | length) > 0 {
        $user_block = $user_block + "    ssh_authorized_keys:\n"
        for key in $keys {
          $user_block = $user_block + $"      - ($key)\n"
        }
      }
    }
    # Replace the for loop block with rendered user block
    $text = ($text | str replace -r '(?s)\{%\s*for user in users\s*%\}.*?\{%\s*endfor\s*%\}' $user_block)
  } else {
    $text = ($text | str replace -r '(?s)\{%\s*for user in users\s*%\}.*?\{%\s*endfor\s*%\}' '')
  }

  # Expand ollama models loop
  if ($ctx.ollama_models | length) > 0 {
    mut model_block = ""
    for model in $ctx.ollama_models {
      $model_block = $model_block + $"  - [\"sh\", \"-c\", \"ollama pull ($model) || true\"]\n"
    }
    $text = ($text | str replace -r '(?s)\{%\s*for model in ollama_models\s*%\}.*?\{%\s*endfor\s*%\}' $model_block)
  } else {
    $text = ($text | str replace -r '(?s)\{%\s*for model in ollama_models\s*%\}.*?\{%\s*endfor\s*%\}' '')
  }

  # Handle dd_tags loop
  if ($ctx.dd_tags | length) > 0 {
    mut tags_block = ""
    for tag in $ctx.dd_tags {
      $tags_block = $tags_block + $"        - \"($tag)\"\n"
    }
    $text = ($text | str replace -r '(?s)\{%\s*for tag in dd_tags.*?\s*%\}.*?\{%\s*endfor\s*%\}' $tags_block)
  } else {
    $text = ($text | str replace -r '(?s)\{%\s*for tag in dd_tags.*?\s*%\}.*?\{%\s*endfor\s*%\}' '')
  }

  # Handle extra_packages loop
  if ($ctx.extra_packages | length) > 0 {
    mut pkg_block = ""
    for pkg in $ctx.extra_packages {
      $pkg_block = $pkg_block + $"  - ($pkg)\n"
    }
    $text = ($text | str replace -r '(?s)\{%\s*for pkg in extra_packages.*?\s*%\}.*?\{%\s*endfor\s*%\}' $pkg_block)
  } else {
    $text = ($text | str replace -r '(?s)\{%\s*for pkg in extra_packages.*?\s*%\}.*?\{%\s*endfor\s*%\}' '')
  }

  # Strip remaining unresolved loops/conditionals (graceful degradation)
  $text = ($text | str replace -r '(?s)\{%[^%]*%\}' '')

  # Strip remaining unresolved {{ }} variables (leave secret placeholders intact)
  $text = ($text | str replace -r '\{\{(?!secret:)[^}]*\}\}' '')

  $text
}

def collect_secret_refs [manifest: record] {
  mut refs = []
  let dd = $manifest.stack | get -o datadog_agent
  if ($dd | get -o api_key_secret_ref | is-not-empty) { $refs = ($refs | append { ref: ($dd.api_key_secret_ref), component: "datadog_agent" }) }
  let ii = $manifest.stack | get -o ii_agent
  if ($ii | get -o api_key_secret_ref | is-not-empty) { $refs = ($refs | append { ref: ($ii.api_key_secret_ref), component: "ii_agent" }) }
  for user in ($manifest | get -o users | default []) {
    if ($user | get -o ssh_keys_secret_ref | is-not-empty) { $refs = ($refs | append { ref: $user.ssh_keys_secret_ref, component: $"users.($user.name)" }) }
  }
  $refs
}

def build_commands_for [manifest: record, targets: list] {
  $targets | each { |t|
    $"nu genoa.nu build ($manifest.genoa.manifest_id) --target ($t) --dry-run"
  }
}

def generate_stub_sbom [manifest_id: string, manifest_hash: string] {
  {
    SPDXID: "SPDXRef-DOCUMENT"
    spdxVersion: "SPDX-2.3"
    creationInfo: {
      created: (date now | format date "%Y-%m-%dT%H:%M:%SZ")
      creators: [$"Tool: genoa-($GENOA_VERSION)"]
    }
    name: $"genoa-($manifest_id)"
    dataLicense: "CC0-1.0"
    documentNamespace: $"https://genoa.dev/sbom/($manifest_id)/($manifest_hash)"
    placeholder: true
    note: "Stub SBOM — run 'syft <image> -o spdx-json' for real SBOM (syft: Apache-2.0)"
    packages: [
      {
        SPDXID: "SPDXRef-genoa-manifest"
        name: $manifest_id
        versionInfo: "1.0"
        downloadLocation: "NOASSERTION"
        filesAnalyzed: false
        externalRefs: [
          {
            referenceCategory: "OTHER"
            referenceType: "genoa-manifest-hash"
            referenceLocator: $"sha256:($manifest_hash)"
          }
        ]
      }
    ]
  }
}

def build_attestation [args: record] {
  let now = (date now | format date "%Y-%m-%dT%H:%M:%SZ")
  {
    "_type": "https://in-toto.io/Statement/v1"
    predicateType: $PREDICATE_TYPE
    subject: [
      {
        name: $args.target
        digest: { sha256: ($args.manifest_hash | str replace "sha256:" "") }
      }
    ]
    predicate: {
      buildType: $BUILD_TYPE
      builder: {
        id: $"genoa-cli/v($GENOA_VERSION)"
        version: $GENOA_VERSION
        environment: {
          nu_version: (version | get version)
          platform: $nu.os-info.name
        }
      }
      buildConfig: {
        manifest_hash: $args.manifest_hash
        osbuild_manifest_hash: $args.osbuild_hash
        cloud_init_seed_hash: $args.user_data_hash
        sbom_hash: $args.sbom_hash
        template_hash: $args.template_hash
      }
      metadata: {
        buildStartedOn: $now
        buildFinishedOn: $now
        reproducible: false
        completeness: {
          parameters: true
          environment: true
          materials: true
        }
      }
      materials: [
        {
          uri: $"genoa://manifest/($args.manifest_id)"
          digest: { sha256: ($args.manifest_hash | str replace "sha256:" "") }
          mediaType: "application/toml"
        }
      ]
      trust: {
        level: "self-signed"
        signed_by: ""
        policy: "genoa/self-build/v1"
      }
      sbom: {
        format: "spdx-json"
        uri: ($args.build_dir | path join "sbom.spdx.json")
        placeholder: true
      }
    }
  }
}

def emit_upload_command [target: string, manifest: record, manifest_id: string, build_dir: path] {
  match $target {
    "aws" => {
      let region = $manifest | get -o targets.aws.region | default "us-east-1"
      let ami_name = $manifest | get -o targets.aws.ami_name | default $"genoa-($manifest_id)"
      print "  ── AWS AMI registration (would-run) ──────────────────────────────────"
      print $"  aws ec2 import-snapshot --region ($region) \\"
      print $"    --description '($ami_name)' \\"
      print $"    --disk-container Format=RAW,UserBucket={S3Bucket=$AWS_S3_BUCKET,S3Key=($manifest_id).raw}"
      print $"  # Then: aws ec2 register-image --name ($ami_name) ..."
      print "  (stubbed — provide AWS credentials and S3 bucket)"
      print ""
    }
    "gcp" => {
      let project = $manifest | get -o targets.gcp.project_id | default "$GCP_PROJECT"
      print "  ── GCP image import (would-run) ──────────────────────────────────────"
      print $"  gcloud compute images import ($manifest_id) \\"
      print $"    --project ($project) \\"
      print $"    --source-file ($build_dir)/($manifest_id)-debian-bookworm-amd64.qcow2 \\"
      print $"    --os debian-12"
      print "  (stubbed — provide GCP credentials)"
      print ""
    }
    "do" => {
      print "  ── DigitalOcean snapshot (would-run) ─────────────────────────────────"
      print $"  doctl compute image create ($manifest_id) \\"
      print $"    --region ($manifest | get -o targets.do.region | default 'nyc3') \\"
      print $"    --image-url https://$DO_SPACES_BUCKET.nyc3.digitaloceanspaces.com/($manifest_id).raw"
      print "  (stubbed — provide DO credentials)"
      print ""
    }
    _ => {}
  }
}

# ─── Main dispatcher ──────────────────────────────────────────────────────────
def main [] {
  print "genoa v0.1.0 — cloud-init image baker (Option B)"
  print ""
  print "Commands:"
  print "  nu genoa.nu catalog                        # List supported (base, arch, target) tuples"
  print "  nu genoa.nu schema                         # JSON Schema for manifests"
  print "  nu genoa.nu schema --attestation           # JSON Schema for attestations"
  print "  nu genoa.nu describe <manifest.toml>       # Validate and plan a build"
  print "  nu genoa.nu build <manifest.toml>          # Build image (--target, --dry-run)"
  print "  nu genoa.nu verify <image> <attest.json>   # Verify attestation hashes"
  print ""
  print "AX quickstart (3 calls):"
  print "  1. nu genoa.nu catalog"
  print "  2. nu genoa.nu schema"
  print "  3. nu genoa.nu describe examples/ai-assistant-edge.toml"
}
