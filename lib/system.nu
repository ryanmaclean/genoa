# lib/system.nu — main health, main selftest, main notify, main status
# Sourced by genoa.nu. Requires: find_vultr (from lib/cloud.nu, sourced before this).

def "main health" [] {
  let tools = [
    {tool: "nu",          version_flag: "--version"}
    {tool: "mdconfig",    version_flag: null}
    {tool: "gpart",       version_flag: null}
    {tool: "newfs_msdos", version_flag: null}
    {tool: "newfs",       version_flag: null}
    {tool: "mount",       version_flag: null}
    {tool: "umount",      version_flag: null}
    {tool: "tar",         version_flag: null}
    {tool: "fetch",       version_flag: null}
    {tool: "truncate",    version_flag: null}
  ]

  let checks = $tools | each { |t|
    let found_path = (which $t.tool | get 0?.path? | default null)
    let found = $found_path != null
    let version = if $found and $t.version_flag != null {
      try { ^nu --version | str trim } catch { null }
    } else {
      null
    }
    {tool: $t.tool, found: $found, path: $found_path, version: $version}
  }

  let all_found = ($checks | where found == false | is-empty)
  let platform = (try { ^uname -s | str trim } catch { "unknown" })
  let platform_ok = $platform == "FreeBSD"

  {
    action: "health"
    ok: $all_found
    checks: $checks
    platform: $platform
    platform_ok: $platform_ok
  } | to json --indent 2
}

def "main selftest" [] {
  let result = try {
    ^nu test/smoke.nu | complete
  } catch { |e|
    return ({
      action: "selftest"
      passed: 0
      failed: 0
      total: 0
      ok: false
      output: $e.msg
    } | to json --indent 2)
  }

  let output = $result.stdout
  # Parse "Results: N/M passed, K failed"
  let parsed = try {
    let line = ($output | lines | where { |l| $l | str starts-with "Results:" } | first)
    let passed = ($line | parse "Results: {p}/{t} passed, {f} failed" | first)
    {
      passed: ($passed.p | into int)
      total:  ($passed.t | into int)
      failed: ($passed.f | into int)
    }
  } catch {
    {passed: 0, total: 0, failed: 0}
  }

  {
    action: "selftest"
    passed: $parsed.passed
    failed: $parsed.failed
    total:  $parsed.total
    ok:     ($parsed.failed == 0)
    output: $output
  } | to json --indent 2
}

def "main notify" [receipt_file: string, --dry-run] {
  if not ($receipt_file | path exists) {
    return ({action: "failed", error: $"receipt not found: ($receipt_file)"} | to json --indent 2)
  }
  let r = open $receipt_file
  let profile    = $r.build?.profile?    | default "unknown"
  let arch       = $r.build?.arch?       | default "unknown"
  let dry        = $r.build?.dry_run?    | default false
  let agent_n    = $r.agent?.name?       | default "unknown"
  let img_ver    = $r.image?.version?    | default "unknown"
  let img_name   = $r.image?.name?       | default "unknown"
  let build_host = $r.build?.host?       | default "unknown"
  let os_ver     = $r.build?.os_version? | default "unknown"
  let built_at   = $r.built_at?          | default ""
  let step_count = ($r.claims? | default [] | length)
  let size_gb    = try { $r.image?.size_gb? | default 0 } catch { 0 }
  let now        = (date now | format date "%s" | into int)

  # Compute age_hours: how many hours ago the build was completed
  let age_hours = try {
    let dt = ($built_at | into datetime)
    let diff = ((date now) - $dt)
    $diff / 1hr | math floor
  } catch { 0 }

  # Base tag list used on all metrics
  let tags = [
    $"version:($img_ver)"
    $"profile:($profile)"
    $"host:($build_host)"
    $"os:($os_ver)"
    $"arch:($arch)"
    $"dry_run:($dry)"
    $"agent_name:($agent_n)"
    "project:genoa"
  ]

  let metrics_names = [
    "genoa.build.success"
    "genoa.image.size_mb"
    "genoa.receipt.claims"
    "genoa.build.age_hours"
    "genoa.build.step_count"
    "genoa.image.size_gb"
  ]

  let metrics = {
    series: [
      {metric: "genoa.build.success"    type: 1 points: [{timestamp: $now value: 1}]
       tags: $tags}
      {metric: "genoa.image.size_mb"    type: 3 points: [{timestamp: $now value: ($r.image?.size_mb? | default 1024)}]
       tags: $tags}
      {metric: "genoa.receipt.claims"   type: 3 points: [{timestamp: $now value: $step_count}]
       tags: $tags}
      {metric: "genoa.build.age_hours"  type: 3 points: [{timestamp: $now value: $age_hours}]
       tags: $tags}
      {metric: "genoa.build.step_count" type: 3 points: [{timestamp: $now value: $step_count}]
       tags: $tags}
      {metric: "genoa.image.size_gb"    type: 3 points: [{timestamp: $now value: $size_gb}]
       tags: $tags}
    ]
  }

  if $dry_run {
    return ({
      action:            "would-notify"
      receipt:           $receipt_file
      metrics:           ($metrics.series | length)
      metrics_submitted: $metrics_names
      tags:              $tags
      status:            "ok"
    } | to json --indent 2)
  }

  let tmp = $"/tmp/genoa-metrics-($now).json"
  $metrics | to json | save --force $tmp

  let result = try {
    ^pup metrics submit --file $tmp | complete
  } catch { |e| {exit_code: -1 stderr: $e.msg} }

  # Capture the submission result first, then attempt cleanup. Wrap rm in
  # try/catch so a cleanup failure can never mask the real submission outcome.
  try { ^rm -f $tmp } catch { |e| null }

  if ($result.exit_code? | default 99) == 0 {
    {
      action:            "notify"
      receipt:           $receipt_file
      metrics_submitted: $metrics_names
      tags:              ($tags | str join ",")
      status:            "ok"
    } | to json --indent 2
  } else {
    {action: "failed" step: "pup_metrics_submit" stderr: ($result.stderr? | default "unknown error")} | to json --indent 2
  }
}

def "main status" [--dir: string = "./out", --dry-run] {
  if $dry_run {
    return ({
      action:   "status"
      dry_run:  true
      note:     "dry-run: would query platform, artifacts, Vultr snapshots, and Vultr instances"
      planned_checks: ["platform" "genoa_version" "build_ready" "recent_builds" "snapshots" "instances"]
    } | to json --indent 2)
  }

  # Derive genoa_version from artifacts/ directory (latest vN.N.N dir)
  let genoa_version = try {
    let art_dirs = (glob "artifacts/v*" | where { |d| ($d | path type) == "dir" } | each { |d| $d | path basename } | sort --reverse)
    if ($art_dirs | is-empty) { "unknown" } else { $art_dirs | first }
  } catch { "unknown" }

  # Platform via uname
  let platform = try { ^uname -s | str trim } catch { "unknown" }

  # build_ready: true only on FreeBSD with all health tools present
  let build_ready = try {
    if $platform != "FreeBSD" { false } else {
      let h = (^nu genoa.nu health | from json)
      ($h.ok? | default false)
    }
  } catch { false }

  # recent_builds: 3 most recent receipts from artifacts/
  let recent_builds = try {
    let receipt_files = (glob "artifacts/**/*.receipt.json" | sort --reverse | first 3)
    $receipt_files | each { |f|
      let r = try { open $f } catch { {} }
      {
        path:       $f
        version:    ($r.image?.version?  | default "")
        image_name: ($r.image?.name?     | default "")
        profile:    ($r.build?.profile?  | default "")
        built_at:   ($r.built_at?        | default "")
        host:       ($r.build?.host?     | default "")
      }
    }
  } catch { [] }

  # snapshots: vultr snapshot list (wrapped in try so it works without CLI)
  let snapshots = try {
    let vultr_bin = find_vultr
    if $vultr_bin == null { null } else {
      let raw = try { ^$vultr_bin snapshot list --output json | from json } catch { null }
      if $raw == null { null } else {
        let snaps = ($raw.snapshots? | default [])
        let latest = if ($snaps | is-empty) { null } else {
          let s = ($snaps | sort-by date_created --reverse | first)
          {id: ($s.id? | default ""), status: ($s.status? | default ""), description: ($s.description? | default "")}
        }
        {count: ($snaps | length), latest: $latest}
      }
    }
  } catch { null }

  # instances: vultr instance list (wrapped in try)
  let instances = try {
    let vultr_bin = find_vultr
    if $vultr_bin == null { null } else {
      let raw = try { ^$vultr_bin instance list --output json | from json } catch { null }
      if $raw == null { null } else {
        let all_inst = ($raw.instances? | default [])
        let running = ($all_inst | where { |i| ($i.power_status? | default "") == "running" } | length)
        {count: ($all_inst | length), running: $running}
      }
    }
  } catch { null }

  {
    action:         "status"
    genoa_version:  $genoa_version
    platform:       $platform
    build_ready:    $build_ready
    recent_builds:  $recent_builds
    snapshots:      $snapshots
    instances:      $instances
    http_server:    "http://108.61.206.203:8080/"
  } | to json --indent 2
}
