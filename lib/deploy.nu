# lib/deploy.nu — main deploy, main deploy-from-snapshot, main clone-instance
# Sourced by genoa.nu. Requires: find_vultr (from lib/cloud.nu, sourced before this),
# linode_deploy, vultr_deploy (from adapters/).

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

  # Fail-closed safety guard: reject shell-injection vectors (callback/custom
  # image URLs, hostname, output_dir, names) before adapters interpolate them.
  let safety = manifest_safety_check $m
  if not $safety.ok {
    return ({action: "failed", reason: "manifest_safety_check failed", errors: $safety.errors, manifest_path: $manifest_file} | to json --indent 2)
  }

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
    "ami-import"   => "adapters/aws.nu"
    "custom-image" => "adapters/gce.nu"
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
  } else if $pid == "digitalocean" {
    digitalocean_deploy $m $image --dry-run=$dry_run | to json --indent 2
  } else if $pid == "aws_ec2" {
    aws_deploy $m $image --dry-run=$dry_run | to json --indent 2
  } else if $pid == "gce_gcp" or $pid == "gcp" {
    gce_deploy $m $image --dry-run=$dry_run | to json --indent 2
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

def "main clone-instance" [
  source_instance_id: string  # ID of existing Vultr instance to clone
  --label: string = ""        # label for the new instance (default: "clone-<source_id_prefix>")
  --region: string = ""       # region for new instance; uses source region if empty
  --dry-run
] {
  let vultr = find_vultr
  if $vultr == null {
    return ({action: "failed", reason: "vultr CLI not found"} | to json --indent 2)
  }

  # Fetch source instance details
  let source_raw = try {
    ^$vultr instance get $source_instance_id --output json | from json
  } catch { |e|
    return ({
      action: "failed"
      reason: $"vultr instance get failed: ($e.msg)"
      source_id: $source_instance_id
      provider: "vultr"
    } | to json --indent 2)
  }

  let source = ($source_raw.instance? | default {})
  let plan       = ($source.plan?   | default "vc2-1c-1gb")
  let src_region = ($source.region? | default "ewr")
  let os_id      = ($source.os_id?  | default 0)
  let eff_region = if $region != "" { $region } else { $src_region }
  let eff_label  = if $label  != "" { $label  } else { $"clone-($source_instance_id | str substring 0..8)" }

  if $dry_run {
    return ({
      action:    "would-run"
      source_id: $source_instance_id
      plan:      $plan
      region:    $eff_region
      os_id:     $os_id
      label:     $eff_label
      provider:  "vultr"
    } | to json --indent 2)
  }

  let raw = try {
    ^$vultr instance create --plan $plan --region $eff_region --os $os_id --label $eff_label --output json | from json
  } catch { |e|
    return ({
      action:    "failed"
      reason:    $"vultr instance create failed: ($e.msg)"
      source_id: $source_instance_id
      provider:  "vultr"
    } | to json --indent 2)
  }

  let inst = ($raw.instance? | default {})
  {
    action:      "clone-instance"
    source_id:   $source_instance_id
    instance_id: ($inst.id?       | default "")
    ip:          ($inst.main_ip?  | default "")
    status:      ($inst.status?   | default "")
    plan:        $plan
    region:      $eff_region
    label:       $eff_label
    provider:    "vultr"
  } | to json --indent 2
}
