#!/usr/bin/env nu
# completions/genoa.nu — Nushell completions for genoa
# Source this file in your config.nu or env.nu:
#   source /path/to/genoa/completions/genoa.nu
# SPDX-License-Identifier: BSD-2-Clause

# Complete manifest file paths
def "nu-complete genoa manifests" [] {
  ls examples/*.toml 2>/dev/null | get name | each { |f| {value: $f, description: ($f | path basename)} }
}

# Complete profile names
def "nu-complete genoa profiles" [] {
  ["uefi" "kboot" "netbsd"]
}

# Complete provider IDs
def "nu-complete genoa providers" [] {
  ["vultr" "linode_akamai" "aws_ec2" "gce_gcp"]
}

# Complete signing tools
def "nu-complete genoa signing-tools" [] {
  ["none" "signify" "minisign"]
}

# Complete backend names for publish
def "nu-complete genoa backends" [] {
  ["gitea" "r2" "s3" "local"]
}

# Complete watch types
def "nu-complete genoa watch-types" [] {
  ["snapshot" "instance"]
}

# ---- External completions for genoa subcommands ----

extern "nu genoa.nu validate" [
  manifest_file: string@"nu-complete genoa manifests"
]

extern "nu genoa.nu build" [
  manifest_file: string@"nu-complete genoa manifests"
  --profile: string@"nu-complete genoa profiles"
  --dry-run
]

extern "nu genoa.nu run" [
  manifest_file: string@"nu-complete genoa manifests"
  --profile: string@"nu-complete genoa profiles"
  --dry-run
  --backend: string@"nu-complete genoa backends"
  --provider: string@"nu-complete genoa providers"
]

extern "nu genoa.nu deploy" [
  manifest_file: string@"nu-complete genoa manifests"
  --provider: string@"nu-complete genoa providers"
  --dry-run
]

extern "nu genoa.nu sign" [
  image_path: string
  --tool: string@"nu-complete genoa signing-tools"
  --dry-run
]

extern "nu genoa.nu watch" [
  resource_id: string
  --type: string@"nu-complete genoa watch-types"
  --until: string
  --timeout: int
  --interval: int
]

extern "nu genoa.nu providers" [
  --id: string@"nu-complete genoa providers"
]

extern "nu genoa.nu snapshot-import" [
  image_url: string
  --dry-run
]

extern "nu genoa.nu deploy-from-snapshot" [
  snapshot_id: string
  --dry-run
]
