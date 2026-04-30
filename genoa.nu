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
  print "Commands: catalog  schema  describe  build  deploy  publish  verify  run"
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
