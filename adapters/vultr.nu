# SPDX-License-Identifier: BSD-2-Clause
# Vultr snapshot-from-URL deploy adapter
# Path: publish image to HTTPS URL → POST /v2/snapshots/create-from-url → poll → create instance

def check-vultr-cli [] {
  if ("/opt/homebrew/bin/vultr" | path exists) {
    return "/opt/homebrew/bin/vultr"
  }

  if ("/opt/homebrew/bin/vultr-cli" | path exists) {
    return "/opt/homebrew/bin/vultr-cli"
  }

  if ($env.PATH | split row (char esep) | any { |p| ($p | path join "vultr" | path exists) }) {
    return "vultr"
  }

  if ($env.PATH | split row (char esep) | any { |p| ($p | path join "vultr-cli" | path exists) }) {
    return "vultr-cli"
  }

  null
}

export def vultr_deploy [
  manifest: record
  image_path: string
  --dry-run
] {
  let image_name = $manifest.image?.name? | default "genoa-freebsd"
  let region = if ("deploy" in $manifest and "region" in $manifest.deploy) {
    $manifest.deploy.region
  } else if ("region" in $manifest) {
    $manifest.region
  } else {
    "ewr"
  }
  let plan = if ("deploy" in $manifest and "plan" in $manifest.deploy) {
    $manifest.deploy.plan
  } else if ("plan" in $manifest) {
    $manifest.plan
  } else {
    "vc2-1c-1gb"
  }

  # Dry-run: return plan without credentials or API calls
  if $dry_run {
    let image_url_resolved = if ("image" in $manifest and "export_url" in $manifest.image) {
      $manifest.image.export_url
    } else if ($image_path | str starts-with "https://") {
      $image_path
    } else {
      ""
    }

    return {
      action: "would-run"
      provider: "vultr"
      dry_run: true
      image_name: $image_name
      image_url: $image_url_resolved
      region: $region
      plan: $plan
      steps: [
        {
          step: 1
          action: "would-run"
          command: "vultr-cli snapshot create-url --url <url>"
          description: "Create snapshot from HTTPS URL"
          args: { url: $image_url_resolved, description: $image_name }
        }
        {
          step: 2
          action: "would-run"
          command: "poll"
          description: "Poll snapshot status until complete (max 30 min)"
          poll_interval_seconds: 30
          max_iterations: 60
        }
        {
          step: 3
          action: "would-run"
          command: "vultr-cli instance create"
          description: "Launch instance from snapshot"
          args: { region: $region, plan: $plan, snapshot: "<snap_id>" }
        }
      ]
    }
  }

  # --- Credential and tool checks ---
  let api_key = if "VULTR_API_KEY" in $env { $env.VULTR_API_KEY } else { "" }
  let vultr_cli = check-vultr-cli

  if $api_key == "" {
    return {action: "failed", reason: "VULTR_API_KEY not set", provider: "vultr"}
  }
  if $vultr_cli == null {
    return {action: "failed", reason: "vultr-cli not found — install: brew install vultr-cli", provider: "vultr"}
  }

  # --- Pre-flight balance check ---
  let account = try {
    ^$vultr_cli account info --output json | from json
  } catch { null }

  if $account != null {
    let balance = ($account.account?.balance? | default 0)
    let pending = ($account.account?.pending_charges? | default 0)
    if $balance == 0 and $pending > 0 {
      return ({
        action: "failed"
        reason: $"Vultr account balance is $0 with \$($pending) pending charges — add payment method to continue"
        balance: $balance
        pending_charges: $pending
        provider: "vultr"
      } | to json --indent 2)
    }
  }

  # --- Image URL resolution ---
  let image_url = if ("image" in $manifest and "export_url" in $manifest.image) {
    $manifest.image.export_url
  } else if ($image_path | str starts-with "https://") {
    $image_path
  } else {
    return {
      action: "failed"
      reason: "image_url_required"
      provider: "vultr"
      detail: "Vultr snapshot-from-URL requires an HTTPS URL. Run `genoa publish` first to get a URL, then pass it via manifest.image.export_url or --image https://..."
    }
  }

  # --- Step 1: Create snapshot from URL ---
  let snap_result = try {
    ^$vultr_cli snapshot create-url --url $image_url --description $image_name -o json | from json
  } catch { |e|
    return {action: "failed", step: "create_snapshot", error: $e.msg, provider: "vultr"}
  }

  let snap_id = $snap_result.snapshot?.id? | default ""
  if $snap_id == "" {
    return {action: "failed", step: "create_snapshot", detail: $snap_result, provider: "vultr"}
  }

  # --- Step 2: Poll until complete (max 60 × 30s = 30 min) ---
  mut snap_status = "pending"
  mut poll_count = 0
  while $snap_status != "complete" and $poll_count < 60 {
    ^sleep 30
    let poll = try {
      ^$vultr_cli snapshot get $snap_id -o json | from json
    } catch {
      {snapshot: {status: "unknown"}}
    }
    $snap_status = $poll.snapshot?.status? | default "unknown"
    $poll_count = $poll_count + 1
    if $snap_status == "error" {
      return {
        action: "failed"
        step: "poll_snapshot"
        snap_id: $snap_id
        status: "error"
        provider: "vultr"
      }
    }
  }
  if $snap_status != "complete" {
    return {
      action: "failed"
      step: "poll_snapshot"
      reason: "timed_out"
      snap_id: $snap_id
      provider: "vultr"
    }
  }

  # --- Step 3: Create instance from snapshot ---
  let instance_raw = try {
    ^$vultr_cli instance create --region $region --plan $plan --snapshot $snap_id -o json | complete
  } catch { |e|
    return {
      action: "failed"
      step: "create_instance"
      error: $e.msg
      snap_id: $snap_id
      provider: "vultr"
    }
  }

  if ($instance_raw.exit_code? | default 0) != 0 {
    let stderr_out = ($instance_raw.stderr? | default "")
    let stdout_out = ($instance_raw.stdout? | default "")
    let combined   = $"($stderr_out) ($stdout_out)"
    if ($combined | str contains "Unauthorized") or ($combined | str contains "500") {
      return ({
        action: "failed"
        reason: "Vultr API error — check account balance (pending_charges may exceed balance)"
        exit_code: 500
        provider: "vultr"
      } | to json --indent 2)
    }
    return {
      action: "failed"
      step: "create_instance"
      exit_code: ($instance_raw.exit_code? | default -1)
      error: $combined
      snap_id: $snap_id
      provider: "vultr"
    }
  }

  let instance_result = try {
    $instance_raw.stdout | from json
  } catch { |e|
    return {
      action: "failed"
      step: "create_instance_parse"
      error: $e.msg
      snap_id: $snap_id
      provider: "vultr"
    }
  }

  # --- Success ---
  {
    action: "deployed"
    provider: "vultr"
    snapshot_id: $snap_id
    instance_id: ($instance_result.instance?.id? | default "unknown")
    instance_ip: ($instance_result.instance?.main_ip? | default "pending")
    region: $region
    plan: $plan
    image_url: $image_url
  }
}
