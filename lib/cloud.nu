# lib/cloud.nu — find_vultr helper + Vultr cloud ops subcommands
# Sourced by genoa.nu. This module defines find_vultr which is used by
# deploy.nu, system.nu, and cloud.nu itself — source order in genoa.nu matters.

# Locate the vultr CLI binary: checks Homebrew path first, then PATH.
def find_vultr [] {
  let brew = "/opt/homebrew/bin/vultr"
  if ($brew | path exists) { return $brew }
  let in_path = (which vultr | get 0?.path? | default null)
  $in_path
}

def "main snapshots" [
  --provider: string = "vultr"
] {
  let vultr_bin = find_vultr
  if $vultr_bin == null {
    return ({action: "failed", reason: "vultr CLI not found"} | to json --indent 2)
  }
  let raw = try {
    ^$vultr_bin snapshot list --output json | from json
  } catch { |e|
    return ({action: "failed", reason: $"vultr snapshot list failed: ($e.msg)"} | to json --indent 2)
  }
  let snaps = ($raw.snapshots? | default [] | each { |s|
    let size_bytes = ($s.size? | default 0 | into float)
    let size_gb = (($size_bytes / 1073741824.0) | math round --precision 1)
    {
      id:           ($s.id?           | default "")
      description:  ($s.description?  | default "")
      status:       ($s.status?       | default "")
      size_gb:      $size_gb
      date_created: ($s.date_created? | default "")
    }
  })
  {
    action:    "snapshots"
    provider:  $provider
    snapshots: $snaps
    count:     ($snaps | length)
  } | to json --indent 2
}

def "main snapshot-import" [
  image_url: string
  --description: string = ""
  --dry-run
] {
  if $dry_run {
    return ({
      action:   "would-run"
      provider: "vultr"
      url:      $image_url
      cmd:      $"vultr snapshot create-url --url ($image_url) --description ($description)"
    } | to json --indent 2)
  }
  let vultr_bin = find_vultr
  if $vultr_bin == null {
    return ({action: "failed", reason: "vultr CLI not found"} | to json --indent 2)
  }
  let raw = try {
    ^$vultr_bin snapshot create-url --url $image_url --description $description --output json | from json
  } catch { |e|
    return ({action: "failed", reason: $"vultr snapshot create-url failed: ($e.msg)", url: $image_url} | to json --indent 2)
  }
  let snap_id = ($raw.snapshot?.id? | default "")
  {
    action:      "snapshot-import-queued"
    snapshot_id: $snap_id
    status:      "pending"
    url:         $image_url
  } | to json --indent 2
}

def "main snapshot-status" [
  snapshot_id: string
] {
  let vultr_bin = find_vultr
  if $vultr_bin == null {
    return ({action: "failed", reason: "vultr CLI not found"} | to json --indent 2)
  }
  let raw = try {
    ^$vultr_bin snapshot get $snapshot_id --output json | from json
  } catch { |e|
    return ({action: "failed", reason: $"vultr snapshot get failed: ($e.msg)", id: $snapshot_id} | to json --indent 2)
  }
  let s = ($raw.snapshot? | default {})
  let size_bytes = ($s.size? | default 0 | into float)
  let size_gb = (($size_bytes / 1073741824.0) | math round --precision 1)
  {
    action:      "snapshot-status"
    id:          $snapshot_id
    status:      ($s.status?      | default "")
    size_gb:     $size_gb
    description: ($s.description? | default "")
  } | to json --indent 2
}

def "main instances" [
  --provider: string = "vultr"
  --all
] {
  let vultr = find_vultr
  if $vultr == null {
    return ({action: "failed", reason: "vultr CLI not found", provider: $provider} | to json --indent 2)
  }

  let raw = try {
    ^$vultr instance list --output json | from json
  } catch { |e|
    return ({action: "failed", reason: $e.msg, provider: $provider} | to json --indent 2)
  }

  let all_instances = ($raw.instances? | default [])
  let filtered = if $all {
    $all_instances
  } else {
    $all_instances | where { |i| ($i.label? | default "") | str contains "smolbsd" }
  }

  let result = ($filtered | each { |i|
    {
      id:           ($i.id?           | default "")
      label:        ($i.label?        | default "")
      status:       ($i.status?       | default "")
      power:        ($i.power_status? | default "")
      ip:           ($i.main_ip?      | default "")
      plan:         ($i.plan?         | default "")
      region:       ($i.region?       | default "")
      os:           ($i.os?           | default "")
      date_created: ($i.date_created? | default "")
    }
  })

  {action: "instances" provider: $provider count: ($result | length) instances: $result} | to json --indent 2
}

# ---------------------------------------------------------------------------
# watch — poll snapshot or instance until target status is reached
# ---------------------------------------------------------------------------
def "main watch" [
  resource_id: string           # Vultr snapshot ID or instance ID
  --type: string = "snapshot"   # "snapshot" | "instance"
  --until: string = "complete"  # target status ("complete", "active", "running")
  --timeout: int = 300          # max seconds to wait (default 5 min)
  --interval: int = 15          # poll interval in seconds
  --provider: string = "vultr"
] {
  let vultr = find_vultr
  if $vultr == null {
    return ({action: "failed", reason: "vultr CLI not found"} | to json --indent 2)
  }

  let started = (date now | into int)
  mut polls = 0
  mut current_status = "unknown"
  mut reached = false

  loop {
    $polls = $polls + 1
    let now = (date now | into int)
    let elapsed = ($now - $started) / 1_000_000_000  # nanoseconds to seconds

    # Poll the resource
    $current_status = if $type == "snapshot" {
      try {
        let s = (^$vultr snapshot get $resource_id --output json | from json)
        $s.snapshot?.status? | default "unknown"
      } catch { "error" }
    } else {
      try {
        let i = (^$vultr instance get $resource_id --output json | from json)
        $i.instance?.power_status? | default "unknown"
      } catch { "error" }
    }

    print -e $"  [($polls)] ($resource_id | str substring 0..8)... status=($current_status) elapsed=($elapsed)s"

    if $current_status == $until {
      $reached = true
      break
    }

    if $elapsed >= $timeout {
      break
    }

    ^sleep ($interval | into string)
  }

  let total_elapsed = ((date now | into int) - $started) / 1_000_000_000

  {
    action:          "watch"
    resource_id:     $resource_id
    type:            $type
    final_status:    $current_status
    reached_target:  $reached
    target:          $until
    polls:           $polls
    elapsed_seconds: $total_elapsed
    timed_out:       (not $reached)
  } | to json --indent 2
}

def "main versions" [
  --gitea-url: string = "http://10.0.2.230:3001"
  --repo: string = "string/genoa"
] {
  let api_url = $"($gitea_url)/api/v1/repos/($repo)/releases"

  let releases = try {
    ^curl -sf $api_url | from json
  } catch { |e|
    return ({action: "failed", reason: $"Gitea API error: ($e.msg)", gitea_url: $gitea_url} | to json --indent 2)
  }

  let versions = ($releases | each { |r|
    let assets = ($r.assets? | default [] | each { |a|
      {
        name:    ($a.name? | default "")
        size_mb: (($a.size? | default 0) / 1048576 | math round --precision 1)
        url:     ($a.browser_download_url? | default "")
      }
    })
    {
      tag:          ($r.tag_name? | default "")
      name:         ($r.name? | default "")
      published_at: ($r.published_at? | default "")
      assets:       $assets
    }
  })

  {
    action:    "versions"
    gitea_url: $gitea_url
    repo:      $repo
    count:     ($versions | length)
    versions:  $versions
  } | to json --indent 2
}
