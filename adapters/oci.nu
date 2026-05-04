# BSD 2-Clause License
# Copyright (c) 2026 genoa contributors
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.

# OCI BYOI qcow2 deploy adapter
# Path: convert raw → qcow2 → upload to Object Storage → import as custom image → launch instance
# oci-cli is UPL-1.0 — invoked as external subprocess only, never linked or vendored.

source formats/convert.nu

export def oci_deploy [
  manifest: record
  image_path: string
  --dry-run        # Return the deployment plan without executing any steps
] {
  let dry_run = $dry_run

  # ── Step 0 — credential and tool check ────────────────────────────────────
  let oci_cli = if ("/opt/homebrew/bin/oci" | path exists) { "/opt/homebrew/bin/oci" }
                else if ((which oci | length) > 0) { "oci" }
                else { null }
  let oci_config = ($env.HOME | path join ".oci" "config")

  # When dry-run, skip credential check and return the plan
  if $dry_run {
    let image_name = $manifest.image?.name? | default "genoa-freebsd"
    let compartment_id = $manifest.deploy?.oci_compartment_id? | default ""
    let bucket = $manifest.deploy?.oci_bucket? | default "genoa-images"
    let namespace = $manifest.deploy?.oci_namespace? | default "<oci_namespace>"
    let subnet_id = $manifest.deploy?.oci_subnet_id? | default "<subnet-id>"
    let shape = $manifest.deploy?.oci_shape? | default "VM.Standard.A1.Flex"
    let qcow2_path = if ($image_path | str ends-with ".qcow2") {
      $image_path
    } else {
      $image_path | str replace --regex '\.[^.]+$' '.qcow2'
    }
    let object_name = ($qcow2_path | path basename)

    return {
      provider: "oci"
      dry_run: true
      path: "Path 0: BYOI (qcow2 via Object Storage)"
      manifest: $manifest
      image_path: $image_path
      qcow2_path: $qcow2_path
      plan: {
        steps: [
          {
            step: 0
            action: "would-run"
            description: "Credential and tool check"
            checks: [
              "oci CLI present at /opt/homebrew/bin/oci or on PATH"
              $"~/.oci/config exists at ($oci_config)"
            ]
          }
          {
            step: 1
            action: "would-run"
            command: "convert_to_qcow2"
            description: "Convert image to qcow2 format if not already qcow2"
            args: { input: $image_path, output: $qcow2_path }
            notes: ["qemu-img is GPL-2 — invoked as external subprocess only"]
            would_run: $"qemu-img convert -O qcow2 -c ($image_path) ($qcow2_path)"
          }
          {
            step: 2
            action: "would-run"
            command: "oci os object put"
            description: "Upload qcow2 to OCI Object Storage"
            args: { namespace: $namespace, bucket_name: $bucket, file: $qcow2_path, name: $object_name }
            would_run: $"oci os object put --namespace ($namespace) --bucket-name ($bucket) --file ($qcow2_path) --name ($object_name)"
          }
          {
            step: 3
            action: "would-run"
            command: "oci compute image import from-object"
            description: "Import qcow2 as OCI custom image"
            args: {
              namespace: $namespace
              bucket_name: $bucket
              name: $object_name
              compartment_id: $compartment_id
              display_name: $image_name
              source_image_type: "QCOW2"
            }
            would_run: $"oci compute image import from-object --namespace ($namespace) --bucket-name ($bucket) --name ($object_name) --compartment-id ($compartment_id) --display-name ($image_name) --source-image-type QCOW2"
          }
          {
            step: 4
            action: "would-run"
            command: "poll oci compute image get"
            description: "Poll image import status until AVAILABLE (max 40 × 30s = 20 min)"
            args: { wait_for_state: "AVAILABLE", poll_interval_sec: 30, max_polls: 40 }
            would_run: "oci compute image get --image-id <image-id>"
          }
          {
            step: 5
            action: "would-run"
            command: "oci compute instance launch"
            description: "Launch instance from imported image"
            args: {
              compartment_id: $compartment_id
              image_id: "<image-id-from-step-3>"
              shape: $shape
              subnet_id: $subnet_id
              display_name: $image_name
            }
            would_run: $"oci compute instance launch --compartment-id ($compartment_id) --image-id <image-id> --shape ($shape) --subnet-id ($subnet_id) --display-name ($image_name)"
          }
        ]
        notes: [
          "Requires oci-cli installed and ~/.oci/config configured"
          "oci-cli is UPL-1.0 (invoked as subprocess only)"
          "Object Storage bucket must exist and be writable"
          "deploy.oci_namespace, deploy.oci_compartment_id, and deploy.oci_subnet_id are required"
          "VCN and subnet must be configured before instance launch"
        ]
      }
    }
  }

  # ── Live execution path ────────────────────────────────────────────────────

  if $oci_cli == null {
    return {action: "failed", reason: "oci CLI not found — install: pip3 install oci-cli", provider: "oci"}
  }
  if not ($oci_config | path exists) {
    return {action: "failed", reason: $"OCI config not found at ($oci_config) — run: oci setup config", provider: "oci"}
  }

  # ── Step 1 — convert to qcow2 if needed ───────────────────────────────────
  let qcow2_path = if ($image_path | str ends-with ".qcow2") {
    $image_path
  } else {
    let out = ($image_path | str replace --regex '\.[^.]+$' '.qcow2')
    let conv = convert_to_qcow2 $image_path $out false
    if $conv.action == "failed" or $conv.action == "stub" {
      return {action: "failed", step: "convert_to_qcow2", detail: $conv}
    }
    $out
  }

  # ── Step 2 — upload to Object Storage ─────────────────────────────────────
  let namespace = $manifest.deploy?.oci_namespace? | default ""
  if $namespace == "" {
    return {action: "failed", reason: "deploy.oci_namespace required for OCI BYOI", provider: "oci"}
  }
  let bucket = $manifest.deploy?.oci_bucket? | default "genoa-images"
  let object_name = ($qcow2_path | path basename)

  let upload_out = try {
    ^$oci_cli os object put --namespace $namespace --bucket-name $bucket --file $qcow2_path --name $object_name | complete
  } catch { |e| return {action: "failed", step: "upload_image", error: $e.msg} }
  if $upload_out.exit_code != 0 {
    return {action: "failed", step: "upload_image", exit_code: $upload_out.exit_code, stderr: $upload_out.stderr}
  }

  # ── Step 3 — import as Custom Image ───────────────────────────────────────
  let compartment_id = $manifest.deploy?.oci_compartment_id? | default ""
  if $compartment_id == "" {
    return {action: "failed", reason: "deploy.oci_compartment_id required for OCI image import", provider: "oci"}
  }
  let image_name = $manifest.image?.name? | default "genoa-freebsd"

  let os_raw = $manifest.target?.os? | default "freebsd"
  let os_display = if $os_raw == "netbsd" { "NetBSD" } else { "FreeBSD" }
  let os_version_raw = $manifest.target?.os_version? | default "15"
  let os_version_short = $os_version_raw | split row "." | first

  let import_result = try {
    ^$oci_cli compute image import from-object --namespace $namespace --bucket-name $bucket --name $object_name --compartment-id $compartment_id --display-name $image_name --source-image-type QCOW2 --operating-system $os_display --operating-system-version $os_version_short | from json
  } catch { |e| return {action: "failed", step: "import_image", error: $e.msg} }

  let image_id = $import_result.data?.id? | default null
  if $image_id == null {
    return {action: "failed", step: "import_image", detail: $import_result}
  }

  # ── Step 4 — poll until import complete (max 40 × 30s = 20 min) ───────────
  mut img_state = "IMPORTING"
  mut poll = 0
  while $img_state != "AVAILABLE" and $poll < 40 {
    ^sleep 30sec
    let img = try {
      ^$oci_cli compute image get --image-id $image_id | from json
    } catch {
      {data: {"lifecycle-state": "UNKNOWN"}}
    }
    $img_state = $img.data?."lifecycle-state"? | default "UNKNOWN"
    $poll = $poll + 1
    if $img_state == "DELETED" or $img_state == "FAILED" {
      return {action: "failed", step: "poll_import", image_id: $image_id, state: $img_state}
    }
  }
  if $img_state != "AVAILABLE" {
    return {action: "failed", step: "poll_import", reason: "timed_out", image_id: $image_id}
  }

  # ── Step 5 — launch instance ───────────────────────────────────────────────
  let av_domain = $manifest.deploy?.oci_availability_domain? | default ""
  if $av_domain == "" {
    return {action: "failed", reason: "deploy.oci_availability_domain required for OCI instance launch (e.g. 'Uocm:US-ASHBURN-AD-1')", provider: "oci"}
  }
  let subnet_id = $manifest.deploy?.oci_subnet_id? | default ""
  if $subnet_id == "" {
    return {action: "failed", reason: "deploy.oci_subnet_id required", provider: "oci"}
  }
  let shape = $manifest.deploy?.oci_shape? | default "VM.Standard.A1.Flex"

  let launch_result = try {
    ^$oci_cli compute instance launch --compartment-id $compartment_id --image-id $image_id --shape $shape --subnet-id $subnet_id --display-name $image_name --availability-domain $av_domain | from json
  } catch { |e| return {action: "failed", step: "launch_instance", error: $e.msg} }

  # ── Success ────────────────────────────────────────────────────────────────
  {
    action: "deployed"
    provider: "oci"
    image_id: $image_id
    instance_id: ($launch_result.data?.id? | default "unknown")
    instance_state: ($launch_result.data?."lifecycle-state"? | default "PROVISIONING")
    shape: $shape
    compartment_id: $compartment_id
    qcow2_path: $qcow2_path
  }
}
