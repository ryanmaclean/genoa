# OCI BYOI qcow2 deploy adapter
# Path 0: convert raw → qcow2 → upload to Object Storage → import as custom image

source /Users/studio/genoa/formats/convert.nu

def check-oci-cli [] {
  if ($env.PATH | split row (char esep) | any { |p| ($p | path join "oci" | path exists) }) {
    return "oci"
  }

  if ("/opt/homebrew/bin/oci" | path exists) {
    return "/opt/homebrew/bin/oci"
  }

  null
}

export def oci_deploy [manifest: record, image_path: string] {
  # oci-cli is UPL-1.0 — invoked as external subprocess only
  let oci_cli = check-oci-cli
  let image_name = (if ("name" in $manifest) { $manifest.name } else { "genoa-freebsd" })
  let compartment_id = (if ("compartment_id" in $manifest) { $manifest.compartment_id } else { "" })
  let bucket_name = (if ("bucket_name" in $manifest) { $manifest.bucket_name } else { "genoa-images" })
  let os_version = (if ("os_version" in $manifest) { $manifest.os_version } else { "15.0" })

  # Verify image exists
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

  let oci_version = if ($oci_cli != null) {
    try {
      ^$oci_cli --version | str trim
    } catch {
      "unknown"
    }
  } else {
    "not installed"
  }

  # Step 1: Convert raw to qcow2
  let qcow2_path = ($image_path | path dirname) + "/" + (($image_path | path basename) | str replace ".raw" "") + ".qcow2"

  # Build the deployment plan
  let steps = [
    {
      step: 1
      action: "would-run"
      command: "qemu-img convert"
      description: "Convert raw image to qcow2 format"
      args: {
        format_in: "raw"
        format_out: "qcow2"
        compression: true
        input: $image_path
        output: $qcow2_path
      }
      notes: [
        "qemu-img is GPL-2 — invoked as external subprocess only"
        "Compression reduces upload size (important for OCI)"
      ]
      would_run: "qemu-img convert -O qcow2 -c image.raw image.qcow2"
    }
    {
      step: 2
      action: "would-run"
      command: "oci os object put"
      description: "Upload qcow2 to OCI Object Storage"
      args: {
        bucket_name: $bucket_name
        file: $qcow2_path
        object_name: $"($image_name).qcow2"
      }
      notes: [
        "Requires OCI_CLI_AUTH=api_key or environment auth configured"
        "Object Storage must be in same tenancy as compute compartment"
      ]
      would_run: $"oci os object put --bucket-name ($bucket_name) --file ($qcow2_path) --object-name ($image_name).qcow2"
    }
    {
      step: 3
      action: "would-run"
      command: "oci compute image import from-object"
      description: "Import qcow2 as custom OCI compute image"
      args: {
        compartment_id: $compartment_id
        bucket_name: $bucket_name
        object_name: $"($image_name).qcow2"
        display_name: $"($image_name)-20260430"
        operating_system: "FreeBSD"
        operating_system_version: $os_version
      }
      notes: [
        "Operating system must be set to FreeBSD"
        "launch_mode can be PARAVIRTUALIZED or EMULATED"
      ]
      would_run: $"oci compute image import from-object --compartment-id ($compartment_id) --bucket-name ($bucket_name) --object-name ($image_name).qcow2 --display-name ($image_name) --operating-system FreeBSD --operating-system-version ($os_version)"
    }
    {
      step: 4
      action: "would-run"
      command: "polling"
      description: "Poll image import status until AVAILABLE"
      args: {
        poll_command: "oci compute image get --image-id <image-id>"
        wait_for_state: "AVAILABLE"
      }
      notes: [
        "Import time typically 10-30 minutes depending on image size"
        "Poll interval: 30-60 seconds"
        "Max wait: 2 hours"
      ]
      would_run: "oci compute image get --image-id <image-id> --query 'data.{lifecycle_state:\"lifecycle-state\",size:\"size-in-mbs\"}'"
    }
    {
      step: 5
      action: "would-run"
      command: "oci compute instance launch"
      description: "Launch instance from imported image"
      args: {
        image_id: "<image-id-from-step-3>"
        shape: "VM.Standard.A1.Flex"
        compartment_id: $compartment_id
        display_name: $"($image_name)-instance"
      }
      notes: [
        "Shape options: VM.Standard.A1.Flex, VM.Standard.E5.Flex, etc."
        "Ensure VCN and subnet are configured"
        "SSH key required for access"
      ]
      would_run: $"oci compute instance launch --image-id <image-id> --shape VM.Standard.A1.Flex --compartment-id ($compartment_id) --display-name ($image_name)-instance --subnet-id <subnet-id> --ssh-authorized-keys-file ~/.ssh/id_rsa.pub"
    }
  ]

  return {
    provider: "oci"
    path: "Path 0: BYOI (qcow2 via Object Storage)"
    manifest: $manifest
    image_name: $image_name
    image_path: $image_path
    image_sha256: $image_sha256
    image_size_bytes: (ls $image_path | get 0.size)
    qcow2_path: $qcow2_path
    oci_cli_version: $oci_version
    plan: {
      steps: $steps
      notes: [
        "Requires oci-cli installed and OCI_CLI_AUTH configured"
        "oci-cli is UPL-1.0 (licensed, invoked as subprocess only)"
        "Object Storage bucket must exist and be writable"
        "Compartment ID must be the target compute compartment"
        "VCN and subnet must be configured before instance launch"
      ]
    }
  }
}
