# SPDX-License-Identifier: Apache-2.0
# GCE (Google Compute Engine) custom image deploy adapter (stub)
# Path: package disk.raw as .tar.gz -> upload to GCS -> gcloud compute images create -> create instance

def check-gcloud-cli [] {
  if ("/usr/local/bin/gcloud" | path exists) {
    return "/usr/local/bin/gcloud"
  }

  if ($env.PATH | split row (char esep) | any { |p| ($p | path join "gcloud" | path exists) }) {
    return "gcloud"
  }

  null
}

export def gce_deploy [manifest: record, dry_run: bool = false] {
  if $dry_run {
    return {
      action: "would-run"
      provider: "gce_gcp"
      steps: ["package-disk-raw", "upload-to-gcs", "create-image", "create-instance"]
      note: "Image file must be named disk.raw inside tar.gz"
    }
  }

  # Real run: not yet implemented
  {
    action: "not-implemented"
    provider: "gce_gcp"
    note: "GCE deploy requires gcloud configured project"
  }
}
