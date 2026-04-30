# SPDX-License-Identifier: BSD-2-Clause
# Copyright (c) 2025, Ryan MacLean
#
# genoa publish — upload a local image to a hosting backend and return a
# signed HTTPS URL + sha256.  The URL is what `genoa deploy --provider vultr`
# consumes (Vultr snapshot-from-url requires a public HTTP URL).
#
# Backends: r2 | s3 | gitea | local

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

# Resolve a CLI tool: check /opt/homebrew/bin first, then PATH.
# Returns the full path string, or null if not found.
def find_tool [name: string] {
  let brew_path = $"/opt/homebrew/bin/($name)"
  if ($brew_path | path exists) {
    return $brew_path
  }
  let found = (
    $env.PATH
    | split row (char esep)
    | each { |p| $p | path join $name }
    | where { |fp| $fp | path exists }
    | get 0?
  )
  $found
}

# ---------------------------------------------------------------------------
# Public: file_sha256
# ---------------------------------------------------------------------------

# Compute the SHA-256 hex digest of a file.  Always executes for real.
export def file_sha256 [path: string]: nothing -> string {
  # macOS ships shasum; Linux ships sha256sum.  Fall back to nu built-in.
  let shasum    = find_tool "shasum"
  let sha256sum = find_tool "sha256sum"

  if $shasum != null {
    # shasum -a 256 prints "<hex>  <filename>" (two-space separator)
    let out = (^$shasum -a 256 $path | str trim)
    $out | split column "  " | get column0.0
  } else if $sha256sum != null {
    # sha256sum prints "<hex>  <filename>" or "<hex> *<filename>"
    let out = (^$sha256sum $path | str trim)
    $out | split column " " | get column0.0
  } else {
    # Nushell built-in — always available
    open --raw $path | hash sha256
  }
}

# ---------------------------------------------------------------------------
# Backend: r2
# ---------------------------------------------------------------------------

def publish_r2 [image_path: string, dry_run: bool] {
  let bucket   = if ("GENOA_R2_BUCKET" in $env) { $env.GENOA_R2_BUCKET } else { "genoa-images" }
  let acct_id  = if ("CLOUDFLARE_ACCOUNT_ID" in $env) { $env.CLOUDFLARE_ACCOUNT_ID } else { "" }
  let endpoint = $"https://($acct_id).r2.cloudflarestorage.com"
  let filename = ($image_path | path basename)
  let key      = $"images/($filename)"
  let s3_uri   = $"s3://($bucket)/($key)"

  let upload_cmd  = $"aws s3 cp ($image_path) ($s3_uri) --endpoint-url ($endpoint)"
  let presign_cmd = $"aws s3 presign ($s3_uri) --expires-in 604800 --endpoint-url ($endpoint)"

  if $dry_run {
    return {
      action:  "would-run"
      cmd:     $"($upload_cmd) && ($presign_cmd)"
      backend: "r2"
      image:   $image_path
    }
  }

  let aws = find_tool "aws"
  if $aws == null {
    error make {msg: "r2 backend: 'aws' CLI not found (install via: brew install awscli)"}
  }

  let sha256 = file_sha256 $image_path
  let size   = (ls $image_path | get size.0 | into int)

  run-external $aws "s3" "cp" $image_path $s3_uri "--endpoint-url" $endpoint

  let url = (
    run-external $aws "s3" "presign" $s3_uri "--expires-in" "604800" "--endpoint-url" $endpoint
    | str trim
  )

  let expires_at = (date now) + 7day

  {
    url:        $url
    sha256:     $sha256
    size_bytes: $size
    backend:    "r2"
    expires_at: ($expires_at | format date "%Y-%m-%dT%H:%M:%SZ")
  }
}

# ---------------------------------------------------------------------------
# Backend: s3
# ---------------------------------------------------------------------------

def publish_s3 [image_path: string, dry_run: bool] {
  let bucket   = if ("GENOA_S3_BUCKET" in $env) { $env.GENOA_S3_BUCKET } else { "" }
  let filename = ($image_path | path basename)
  let key      = $"images/($filename)"
  let s3_uri   = $"s3://($bucket)/($key)"

  let upload_cmd  = $"aws s3 cp ($image_path) ($s3_uri)"
  let presign_cmd = $"aws s3 presign ($s3_uri) --expires-in 604800"

  if $dry_run {
    return {
      action:  "would-run"
      cmd:     $"($upload_cmd) && ($presign_cmd)"
      backend: "s3"
      image:   $image_path
    }
  }

  let aws = find_tool "aws"
  if $aws == null {
    error make {msg: "s3 backend: 'aws' CLI not found (install via: brew install awscli)"}
  }

  let sha256 = file_sha256 $image_path
  let size   = (ls $image_path | get size.0 | into int)

  run-external $aws "s3" "cp" $image_path $s3_uri

  let url = (
    run-external $aws "s3" "presign" $s3_uri "--expires-in" "604800"
    | str trim
  )

  let expires_at = (date now) + 7day

  {
    url:        $url
    sha256:     $sha256
    size_bytes: $size
    backend:    "s3"
    expires_at: ($expires_at | format date "%Y-%m-%dT%H:%M:%SZ")
  }
}

# ---------------------------------------------------------------------------
# Backend: gitea
# ---------------------------------------------------------------------------

def publish_gitea [image_path: string, dry_run: bool] {
  let filename   = ($image_path | path basename)
  let size_bytes = if ($image_path | path exists) {
    (ls $image_path | get size.0 | into int)
  } else {
    0
  }
  let tag        = $"genoa-(date now | format date '%Y%m%d')"
  let gitea_base = "https://gitea.local:3000/studio/genoa"
  let url        = $"($gitea_base)/releases/download/($tag)/($filename)"

  let create_cmd = $"tea releases create --tag ($tag) --title 'genoa image'"
  let upload_cmd = $"tea releases asset upload --tag ($tag) ($image_path)"

  if ($size_bytes > 100_000_000) {
    print $"WARNING: image size (($size_bytes)) bytes exceeds Gitea default 100 MB limit — upload may fail"
  }

  if $dry_run {
    return {
      action:  "would-run"
      cmd:     $"($create_cmd) && ($upload_cmd)"
      backend: "gitea"
      image:   $image_path
      url:     $url
    }
  }

  let tea = find_tool "tea"
  if $tea == null {
    error make {msg: "gitea backend: 'tea' CLI not found (install via: brew install tea)"}
  }

  let sha256     = file_sha256 $image_path
  let expires_at = (date now) + 7day

  run-external $tea "releases" "create" "--tag" $tag "--title" "genoa image"
  run-external $tea "releases" "asset" "upload" "--tag" $tag $image_path

  {
    url:        $url
    sha256:     $sha256
    size_bytes: $size_bytes
    backend:    "gitea"
    expires_at: ($expires_at | format date "%Y-%m-%dT%H:%M:%SZ")
  }
}

# ---------------------------------------------------------------------------
# Backend: local
# ---------------------------------------------------------------------------

def publish_local [image_path: string, dry_run: bool] {
  print "WARNING: local backend — not accessible from cloud providers"

  let filename = ($image_path | path basename)
  let dir      = ($image_path | path dirname)
  let url      = $"http://localhost:8765/($filename)"
  let cmd      = $"python3 -m http.server 8765 --directory ($dir)"

  if $dry_run {
    return {
      action:  "would-run"
      cmd:     $cmd
      backend: "local"
      url:     $url
      warning: "local backend — not accessible from cloud providers"
    }
  }

  let sha256 = file_sha256 $image_path
  let size   = (ls $image_path | get size.0 | into int)

  # Start server detached in background; caller terminates when done.
  ^bash -c $"cd ($dir) && python3 -m http.server 8765 &"

  {
    url:        $url
    sha256:     $sha256
    size_bytes: $size
    backend:    "local"
    expires_at: null
    warning:    "local backend — not accessible from cloud providers"
  }
}

# ---------------------------------------------------------------------------
# Public: publish_image
# ---------------------------------------------------------------------------

# Upload a local image to a hosting backend and return a signed HTTPS URL.
# The returned record is consumed by `genoa deploy --provider vultr`.
#
# Returns: {url, sha256, size_bytes, backend, expires_at}
export def publish_image [
  image_path: string        # local path to .raw or .qcow2
  --backend: string = "r2"  # r2 | s3 | gitea | local
  --dry-run
]: nothing -> record {
  let valid_backends = ["r2" "s3" "gitea" "local"]
  if not ($backend in $valid_backends) {
    error make {msg: $"unknown backend '($backend)' — valid: ($valid_backends | str join ', ')"}
  }

  if not $dry_run {
    if not ($image_path | path exists) {
      error make {msg: $"image not found: ($image_path)"}
    }
    let ext = ($image_path | path parse | get extension)
    if $ext not-in ["raw" "qcow2" "img" "vmdk"] {
      print $"WARNING: unexpected extension '.($ext)' — expected .raw or .qcow2"
    }
  }

  match $backend {
    "r2"    => { publish_r2    $image_path $dry_run }
    "s3"    => { publish_s3    $image_path $dry_run }
    "gitea" => { publish_gitea $image_path $dry_run }
    "local" => { publish_local $image_path $dry_run }
    _       => { error make {msg: $"unreachable backend: ($backend)"} }
  }
}

# ---------------------------------------------------------------------------
# Public: publish_catalog
# ---------------------------------------------------------------------------

# List all backends and their actual readiness based on the current environment.
# Returns a list of records — machine-parseable, no prose.
export def publish_catalog []: nothing -> list<record> {
  # --- r2 ---
  let r2_env_missing = (
    ["CLOUDFLARE_ACCOUNT_ID" "R2_ACCESS_KEY_ID" "R2_SECRET_ACCESS_KEY"]
    | where { |v| not ($v in $env) }
  )
  let r2_tool_missing = if (find_tool "aws") == null { ["aws CLI"] } else { [] }
  let r2_missing = ($r2_env_missing | append $r2_tool_missing)

  # --- s3 ---
  let s3_env_missing = (
    ["AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "GENOA_S3_BUCKET"]
    | where { |v| not ($v in $env) }
  )
  let s3_tool_missing = if (find_tool "aws") == null { ["aws CLI"] } else { [] }
  let s3_missing = ($s3_env_missing | append $s3_tool_missing)

  # --- gitea ---
  let gitea_tool_missing  = if (find_tool "tea") == null { ["tea CLI"] } else { [] }
  let gitea_token_missing = if not ("GITEA_TOKEN" in $env) { ["GITEA_TOKEN"] } else { [] }
  let gitea_missing = ($gitea_tool_missing | append $gitea_token_missing)

  # --- local ---
  # python3 is the only requirement; always present on macOS
  let local_missing = if (find_tool "python3") == null { ["python3"] } else { [] }

  [
    {backend: "r2",    ready: ($r2_missing    | is-empty), missing: $r2_missing}
    {backend: "s3",    ready: ($s3_missing    | is-empty), missing: $s3_missing}
    {backend: "gitea", ready: ($gitea_missing | is-empty), missing: $gitea_missing}
    {
      backend: "local"
      ready:   ($local_missing | is-empty)
      missing: $local_missing
      warning: "not accessible from cloud providers"
    }
  ]
}
