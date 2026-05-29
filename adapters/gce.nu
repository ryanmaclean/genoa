# adapters/gce.nu — GCE (Google Compute Engine) custom-image deploy adapter
# Path: package disk.raw as .tar.gz -> upload to GCS -> gcloud compute images create -> create instance
# SPDX-License-Identifier: Apache-2.0

export def gce_deploy [
  manifest: record
  image_path: string
  --dry-run
] {
  let bucket       = ($manifest | get deploy?.gcs_bucket?    | default "genoa-images")
  let project      = ($manifest | get deploy?.project?       | default "")
  let zone         = ($manifest | get deploy?.zone?          | default "us-central1-a")
  let machine_type = ($manifest | get deploy?.machine_type?  | default "e2-small")
  let arch         = ($manifest | get target?.arch?          | default "amd64")
  let img_name     = ($manifest | get image?.name?           | default "genoa-freebsd")

  # aarch64 note: Tau T2A instances are the supported ARM shape on GCE
  let arch_note = if $arch == "aarch64" {
    "aarch64 images require Tau T2A instance types (e.g. t2a-standard-1). Substitute machine_type accordingly."
  } else {
    ""
  }

  let tar_name         = $"($img_name).tar.gz"
  let tmp_disk_raw     = $"/tmp/disk.raw"
  let tmp_tar          = $"/tmp/($tar_name)"
  let gcs_uri          = $"gs://($bucket)/($tar_name)"

  let package_cmd       = $"cp ($image_path) /tmp/disk.raw && tar -czf ($tmp_tar) -C /tmp disk.raw"
  let upload_cmd        = $"gsutil cp ($tmp_tar) ($gcs_uri)"
  let create_image_cmd  = $"gcloud compute images create ($img_name) --source-uri ($gcs_uri) --guest-os-features UEFI_COMPATIBLE --project ($project)"
  let create_inst_cmd   = $"gcloud compute instances create ($img_name) --image ($img_name) --machine-type ($machine_type) --zone ($zone) --project ($project)"

  if $dry_run {
    let warnings_base = [
      "image-file-inside-tar-must-be-named-disk.raw"
      "gcs-bucket-must-exist-before-upload"
      "gcloud-project-must-be-set-in-manifest.deploy.project"
      "uefi-compatible-guest-os-feature-required-for-uefi-images"
      "freebsd-is-experimental-on-gce-no-official-support"
    ]
    let warnings = if $arch == "aarch64" {
      $warnings_base | append "aarch64-requires-tau-t2a-machine-type"
    } else {
      $warnings_base
    }

    return {
      action:              "would-run"
      provider:            "gce_gcp"
      method:              "custom-image"
      zone:                $zone
      machine_type:        $machine_type
      gcs_bucket:          $bucket
      project:             $project
      steps: [
        "copy-image-to-disk.raw"
        "package-disk.raw-as-tar.gz"
        "upload-tar.gz-to-gcs"
        "gcloud-compute-images-create"
        "gcloud-compute-instances-create"
        "verify-ssh"
      ]
      package_cmd:         $package_cmd
      upload_cmd:          $upload_cmd
      create_image_cmd:    $create_image_cmd
      create_instance_cmd: $create_inst_cmd
      note:                "Image file inside tar.gz MUST be named disk.raw. GCE requires UEFI_COMPATIBLE guest-os-feature for UEFI images. FreeBSD is experimental on GCE; aarch64 uses Tau T2A instances."
      warnings:            $warnings
    }
  }

  # Live path
  let gcloud = find_bin "gcloud"
  if $gcloud == null {
    return {action: "failed", reason: "gcloud CLI not found — install: https://cloud.google.com/sdk/docs/install", provider: "gce_gcp"}
  }
  let gsutil = find_bin "gsutil"
  if $gsutil == null {
    return {action: "failed", reason: "gsutil not found — install Google Cloud SDK: https://cloud.google.com/sdk/docs/install", provider: "gce_gcp"}
  }
  if $project == "" {
    return {action: "failed", reason: "manifest.deploy.project is required for GCE deploy (set it to your GCP project ID)", provider: "gce_gcp"}
  }
  if not ($image_path | path exists) {
    return {action: "failed", reason: $"image not found: ($image_path)", provider: "gce_gcp"}
  }

  # Step 1: copy image to /tmp/disk.raw (GCE requires file named disk.raw inside tar)
  let cp_res = try {
    ^cp $image_path $tmp_disk_raw | complete
  } catch { |e|
    return {action: "failed", step: "copy_disk_raw", error: $e.msg, provider: "gce_gcp"}
  }
  if $cp_res.exit_code != 0 {
    return {action: "failed", step: "copy_disk_raw", stderr: $cp_res.stderr, provider: "gce_gcp"}
  }

  # Step 2: package as disk.raw.tar.gz
  let tar_res = try {
    ^tar -czf $tmp_tar -C /tmp disk.raw | complete
  } catch { |e|
    return {action: "failed", step: "package_tar", error: $e.msg, provider: "gce_gcp"}
  }
  if $tar_res.exit_code != 0 {
    return {action: "failed", step: "package_tar", stderr: $tar_res.stderr, provider: "gce_gcp"}
  }

  # Step 3: upload to GCS
  let upload_res = try {
    ^$gsutil cp $tmp_tar $gcs_uri | complete
  } catch { |e|
    return {action: "failed", step: "gcs_upload", error: $e.msg, provider: "gce_gcp"}
  }
  if $upload_res.exit_code != 0 {
    return {action: "failed", step: "gcs_upload", stderr: $upload_res.stderr, provider: "gce_gcp"}
  }

  # Step 4: create custom image (async — gcloud returns immediately for large images)
  let img_res = try {
    ^$gcloud compute images create $img_name --source-uri $gcs_uri --guest-os-features UEFI_COMPATIBLE --project $project --format json | from json
  } catch { |e|
    return {action: "failed", step: "create_image", error: $e.msg, provider: "gce_gcp"}
  }

  {
    action:        "image-upload-started"
    provider:      "gce_gcp"
    image_name:    $img_name
    gcs_location:  $gcs_uri
    project:       $project
    zone:          $zone
    image_detail:  $img_res
    next_steps: [
      $"Create instance: gcloud compute instances create ($img_name) --image ($img_name) --machine-type ($machine_type) --zone ($zone) --project ($project)"
      $"Check image status: gcloud compute images describe ($img_name) --project ($project)"
    ]
    note: "Image file inside tar.gz MUST be named disk.raw. GCE requires UEFI_COMPATIBLE guest-os-feature for UEFI images. FreeBSD is experimental on GCE; aarch64 uses Tau T2A instances."
  }
}
