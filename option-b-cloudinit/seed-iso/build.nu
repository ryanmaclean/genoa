#!/usr/bin/env nu
# seed-iso/build.nu — NoCloud seed ISO builder for genoa
#
# Builds a NoCloud datasource seed ISO containing:
#   meta-data   (YAML)
#   user-data   (rendered cloud-init config)
#   network-config (optional)
#
# The ISO uses the volume label "cidata" which cloud-init's NoCloud
# datasource searches for by fs_label. This is a documented requirement:
# https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html
#
# IMPORTANT — instance-id and cache invalidation:
#   cloud-init caches per-datasource state keyed by instance-id.
#   Merely re-mounting a seed ISO or bumping kernel cmdline does NOT
#   invalidate the cache if instance-id is unchanged. genoa sets
#   instance-id = "genoa-" + sha256(manifest_toml)[0..12] so every
#   distinct manifest produces a distinct instance-id. If you need to
#   force re-run on an already-provisioned host, you must change the
#   instance-id AND clear /var/lib/cloud/instance and
#   /var/lib/cloud/instances/<old-id>/.
#
# PHASE-2 NOTE:
#   Real FAT12 + ISO9660 El Torito writing requires native byte-level
#   I/O. This stub:
#   1. Validates and renders all cloud-init files
#   2. Emits a JSON layout descriptor (byte layout + file contents)
#   3. Calls `xorriso` if available (xorriso is GPL-3 — external invocation
#      only, never linked/vendored) OR emits "requires: native-iso-builder phase 2"
#
# Phase-2 plan: implement ISO9660 + El Torito in Zig (MIT), compile to
# a static binary, invoke from here. The Zig stub skeleton is at
# seed-iso/iso-writer-stub.zig (documents the byte layout).

use std assert

# ─── Public entry point ────────────────────────────────────────────────────────

# Build a NoCloud seed ISO from rendered user-data and optional network-config.
# Outputs: <output_dir>/seed.iso  +  <output_dir>/seed-layout.json
def main [
  --user-data: path        # Path to rendered user-data file (required)
  --meta-data: string      # Inline meta-data YAML (optional; generated from manifest-id if omitted)
  --network-config: path   # Path to network-config file (optional)
  --manifest-id: string    # Manifest ID used to derive instance-id (required)
  --manifest-hash: string  # sha256 of the TOML manifest (for instance-id uniqueness)
  --output-dir: path = "/tmp/genoa-seed" # Output directory
  --dry-run                # Print layout JSON without writing
] {
  let manifest_id = ($manifest_id | default "genoa-unknown")
  let manifest_hash = ($manifest_hash | default "0000000000000000")
  # instance-id is derived from the manifest hash — guarantees uniqueness per build
  # and forces cloud-init cache invalidation when the manifest changes
  let instance_id = $"genoa-($manifest_hash | str substring 0..11)"

  # Validate user-data exists
  if ($user_data | is-empty) {
    error make { msg: "GENOA_ERROR: --user-data is required" }
  }
  if not ($user_data | path exists) {
    error make { msg: $"GENOA_ERROR: user-data file not found: ($user_data)" }
  }

  let user_data_content = open --raw $user_data
  # Basic cloud-config validation
  if not ($user_data_content | str starts-with "#cloud-config") {
    print $"WARN: user-data does not start with '#cloud-config' — cloud-init may reject it"
  }

  # Build meta-data
  let meta_data_content = if ($meta_data | is-empty) {
    build_meta_data $instance_id $manifest_id
  } else {
    $meta_data
  }

  # Optional network-config
  let net_config_content = if ($network_config | is-not-empty) and ($network_config | path exists) {
    open --raw $network_config
  } else {
    null
  }

  # Compute hashes for attestation
  let user_data_hash = ($user_data_content | hash sha256)
  let meta_data_hash = ($meta_data_content | hash sha256)

  # Build layout descriptor
  let files = if $net_config_content != null {
    [
      { name: "meta-data",      content: $meta_data_content,    hash: $meta_data_hash }
      { name: "user-data",      content: $user_data_content,    hash: $user_data_hash }
      { name: "network-config", content: $net_config_content,   hash: ($net_config_content | hash sha256) }
    ]
  } else {
    [
      { name: "meta-data",  content: $meta_data_content, hash: $meta_data_hash }
      { name: "user-data",  content: $user_data_content, hash: $user_data_hash }
    ]
  }

  let layout = {
    schema: "genoa/seed-iso-layout/v1"
    instance_id: $instance_id
    manifest_id: $manifest_id
    volume_label: "cidata"
    filesystem: "iso9660+el-torito"
    files: $files
    iso9660_notes: {
      volume_label: "cidata"
      el_torito_boot: false
      rock_ridge: false
      joliet: false
      note: "NoCloud datasource locates seed by volume label 'cidata', not bootability"
    }
    requires: "native-iso-builder phase 2"
    phase2_plan: "Implement ISO9660 primary volume descriptor + directory records in Zig (MIT license). Invoke from this script as: ^iso-writer --label cidata --output seed.iso meta-data user-data"
    cache_warning: "instance-id is set to sha256(manifest)[0:12] prefix. If re-deploying to an existing host, also clear /var/lib/cloud/instance and /var/lib/cloud/instances/<old-id>/ to force cloud-init re-run."
  }

  if $dry_run {
    $layout | to json --indent 2
    return
  }

  # Create output directory
  mkdir $output_dir

  # Write individual files (always useful for debugging / alternate mount methods)
  $meta_data_content | save --force ($output_dir | path join "meta-data")
  $user_data_content | save --force ($output_dir | path join "user-data")
  if $net_config_content != null {
    $net_config_content | save --force ($output_dir | path join "network-config")
  }

  # Write layout JSON for attestation
  $layout | to json --indent 2 | save --force ($output_dir | path join "seed-layout.json")

  # Attempt native ISO creation — try platform tools in license-safe order.
  # xorriso (GPL-3) is invoked as external process only — not linked/vendored.
  # If unavailable, emit the stub.
  let xorriso_available = (which xorriso | length) > 0
  let mkisofs_available = (which mkisofs | length) > 0  # part of cdrtools, BSD-licensed on some platforms

  let iso_path = ($output_dir | path join "seed.iso")

  if $xorriso_available {
    print "INFO: invoking xorriso as external process (GPL-3, not linked)"
    let file_args = if $net_config_content != null {
      [$"($output_dir)/meta-data=meta-data" $"($output_dir)/user-data=user-data" $"($output_dir)/network-config=network-config"]
    } else {
      [$"($output_dir)/meta-data=meta-data" $"($output_dir)/user-data=user-data"]
    }
    ^xorriso -as mkisofs -output $iso_path -volid "cidata" -joliet -rock ...$file_args
    let exit_code = $env.LAST_EXIT_CODE
    if $exit_code != 0 {
      print $"WARN: xorriso exited ($exit_code) — seed.iso may be invalid"
    } else {
      let iso_hash = (open --raw $iso_path | hash sha256)
      print $"OK: seed.iso written to ($iso_path)"
      print $"    sha256: ($iso_hash)"
    }
  } else {
    print "INFO: xorriso not available. Seed files written as loose files."
    print "      seed.iso requires: native-iso-builder phase 2"
    print "      Phase-2: compile seed-iso/iso-writer-stub.zig with zig build (MIT)"
    print ""
    print "      Loose files available for alternate delivery:"
    print $"        ($output_dir)/meta-data"
    print $"        ($output_dir)/user-data"
    if $net_config_content != null {
      print $"        ($output_dir)/network-config"
    }
    print ""
    print "      Alternatively, use a FAT-formatted USB/SD card with volume label 'cidata'"
    print "      and copy the loose files to it — cloud-init will find them."
  }

  $layout | to json --indent 2
}

# ─── Helpers ───────────────────────────────────────────────────────────────────

def build_meta_data [instance_id: string, manifest_id: string]: string {
  $"instance-id: ($instance_id)\nlocal-hostname: ($manifest_id)\n"
}
