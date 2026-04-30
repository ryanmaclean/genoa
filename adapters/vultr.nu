# Vultr snapshot-from-URL deploy adapter
# Path 1: publish image to URL → POST /v2/snapshots/create-from-url → poll until ready

def check-vultr-cli [] {
  if ($env.PATH | split row (char esep) | any { |p| ($p | path join "vultr-cli" | path exists) }) {
    return "vultr-cli"
  }

  if ("/opt/homebrew/bin/vultr-cli" | path exists) {
    return "/opt/homebrew/bin/vultr-cli"
  }

  null
}

export def vultr_deploy [manifest: record, image_path: string] {
  let vultr_cli = check-vultr-cli
  let image_name = (if ("name" in $manifest) { $manifest.name } else { "genoa-freebsd" })
  let image_url = (if ("image_url" in $manifest) { $manifest.image_url } else { "" })
  let region = (if ("region" in $manifest) { $manifest.region } else { "ewr" })
  let plan = (if ("plan" in $manifest) { $manifest.plan } else { "vc2-1c-1gb" })

  # Step 1: Verify image exists and get sha256
  let image_exists = $image_path | path exists

  if (not $image_exists) {
    return {
      action: "failed"
      error: $"Image file not found: ($image_path)"
      step: 1
    }
  }

  let image_sha256 = if ($nu.os-info.name == "macos") {
    (^shasum -a 256 $image_path | str trim | split column " " | get column1.0)
  } else {
    (^sha256sum $image_path | str trim | split column " " | get column1.0)
  }

  # Step 2: Return plan with would-run steps
  let steps = [
    {
      step: 1
      action: "would-run"
      note: "Genoa publish step required (not automated by this adapter)"
      description: "Publish raw image to HTTPS URL"
      example: "genoa publish --backend r2 --file genoa-freebsd.raw"
      output: "image_url (e.g., https://pub.genoa.example.com/genoa-freebsd-20260430.raw)"
    }
    {
      step: 2
      action: "would-run"
      command: "vultr-cli snapshot create-from-url"
      description: "Create snapshot from URL"
      args: {
        url: $image_url
        description: $image_name
      }
      curl_equivalent: $"curl -X POST 'https://api.vultr.com/v2/snapshots/create-from-url' -H 'Authorization: Bearer $VULTR_API_KEY' -H 'Content-Type: application/json' -d '{\"url\": \"($image_url)\", \"description\": \"($image_name)\"}'"
      response_fields: ["snapshot.id" "snapshot.status"]
    }
    {
      step: 3
      action: "would-run"
      command: "polling"
      description: "Poll snapshot status until complete"
      curl_equivalent: $"curl -X GET 'https://api.vultr.com/v2/snapshots/<snapshot-id>' -H 'Authorization: Bearer $VULTR_API_KEY'"
      timeout_seconds: 3600
      poll_interval_seconds: 10
    }
    {
      step: 4
      action: "would-run"
      command: "vultr-cli instance create"
      description: "Launch instance from snapshot"
      args: {
        snapshot_id: "<snapshot-id-from-step-3>"
        region: $region
        plan: $plan
      }
      curl_equivalent: $"curl -X POST 'https://api.vultr.com/v2/instances' -H 'Authorization: Bearer $VULTR_API_KEY' -H 'Content-Type: application/json' -d '{\"region\": \"($region)\", \"plan\": \"($plan)\", \"snapshot_id\": \"<snapshot-id>\"}'"
    }
  ]

  let vultr_version = if ($vultr_cli != null) {
    try {
      ^$vultr_cli version | str trim
    } catch {
      "unknown"
    }
  } else {
    "not installed"
  }

  return {
    provider: "vultr"
    path: "Path 1: Snapshot from URL"
    manifest: $manifest
    image_name: $image_name
    image_path: $image_path
    image_sha256: $image_sha256
    image_size_bytes: (ls $image_path | get 0.size)
    vultr_cli_version: $vultr_version
    plan: {
      steps: $steps
      notes: [
        "Requires vultr-cli installed or API calls via curl"
        "VULTR_API_KEY environment variable must be set"
        "Snapshot creation time: typically 5-30 minutes"
        "Raw image format is compatible without conversion"
        "No publish step is automated; genoa publish must complete first"
      ]
    }
  }
}
