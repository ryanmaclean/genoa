#!/usr/bin/env nu
# genoa — AX-first FreeBSD/NetBSD cloud image CLI. Nu 0.111.0+. All output: JSON.
source profiles/uefi.nu
source profiles/kboot.nu
source profiles/netbsd.nu
source adapters/linode.nu
source adapters/vultr.nu
source adapters/aws.nu
source adapters/gce.nu
source adapters/digitalocean.nu

# lib/ modules — source order matters: cloud.nu defines find_vultr used by deploy.nu and system.nu
source lib/cloud.nu
source lib/validate.nu
source lib/build.nu
source lib/deploy.nu
source lib/artifacts.nu
source lib/system.nu
source lib/signing.nu
source lib/suggest.nu

def "main catalog" [] {
  let cat = open "catalog/providers.v1.json"
  {
    action:         "catalog"
    schema_version: ($cat.schema_version? | default "1.0.0")
    provider_count: ($cat.providers | length)
    providers:      $cat.providers
  } | to json --indent 2
}

def "main schema" [] {
  let s = open "schema/manifest.v1.json"
  {
    action:      "schema"
    title:       ($s.title? | default "")
    description: ($s.description? | default "")
    schema_url:  ($s."$id"? | default "")
    properties:  ($s.properties? | columns | default [])
    required:    ($s.required? | default [])
  } | to json --indent 2
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
def main [] {
  print "genoa — Nushell CLI for building FreeBSD/NetBSD cloud images"
  print "Usage: nu genoa.nu <subcommand> [options]"
  print ""
  print "Discovery:"
  print "  catalog           List all provider catalog entries"
  print "  schema            Show manifest JSON schema"
  print "  providers         Query catalog with optional --id filter"
  print "  describe          Introspect a manifest file"
  print ""
  print "Validation & Build:"
  print "  validate          Validate a manifest (20 checks + JSON Schema)"
  print "  build             Build a cloud image (--profile uefi|kboot|netbsd, --dry-run)"
  print "  suggest           AI-powered manifest generation from natural language (--model, --dry-run)"
  print "  run               Full validate→build→publish→deploy pipeline"
  print ""
  print "Image Management:"
  print "  sign              Sign an image (--tool signify|minisign|none, --dry-run)"
  print "  verify-image      Mount and check loader.conf/rc.conf inside an image"
  print "  diff              Compare two build receipts field by field"
  print ""
  print "Publishing & Deploy:"
  print "  publish           Upload image (--backend gitea|r2|s3|local, --dry-run)"
  print "  deploy            Deploy to cloud provider (--provider, --dry-run)"
  print "  deploy-from-snapshot  Launch Vultr instance from existing snapshot"
  print "  clone-instance    Clone a Vultr instance"
  print ""
  print "Vultr Ops:"
  print "  snapshots         List Vultr snapshots"
  print "  snapshot-import   Import image URL as Vultr snapshot (--dry-run)"
  print "  snapshot-status   Get Vultr snapshot status"
  print "  instances         List Vultr instances (--all)"
  print "  watch             Poll snapshot/instance until target status"
  print ""
  print "Artifacts:"
  print "  receipts          List all build receipts in artifacts/"
  print "  versions          List published Gitea releases"
  print ""
  print "System:"
  print "  health            Check all 10 required tools + platform readiness"
  print "  selftest          Run smoke test suite, return structured JSON"
  print "  notify            Submit build metrics to Datadog"
  print "  status            Full system state (platform, snapshots, instances, builds)"
  print ""
  print "Run any subcommand with --dry-run to see what it would do without side effects."
  print "Schema: schema/manifest.v1.json | Catalog: catalog/providers.v1.json"
}


