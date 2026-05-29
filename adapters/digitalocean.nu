# SPDX-License-Identifier: BSD-2-Clause
# DigitalOcean custom-image deploy adapter
# Path: import raw image from URL -> custom image -> droplet

def find_doctl [] { find_bin "doctl" }

export def digitalocean_deploy [
  manifest: record
  image_path: string
  --dry-run
] {
  let region   = ($manifest | get deploy?.region? | default "nyc3")
  let size     = ($manifest | get deploy?.size?   | default "s-1vcpu-1gb")
  let image_url = if ("image_url" in $manifest) {
    $manifest.image_url
  } else if ($image_path | str starts-with "https://") {
    $image_path
  } else {
    ""
  }
  let img_name = ($manifest | get image?.name? | default "genoa-freebsd")
  let distro   = "FreeBSD"

  if $dry_run {
    let effective_url = if $image_url != "" {
      $image_url
    } else {
      $"https://<your-image-host>/($img_name).raw.gz"
    }
    return {
      action:      "would-run"
      provider:    "digitalocean"
      method:      "custom-image"
      region:      $region
      size:        $size
      image_url:   $effective_url
      steps: [
        "import-custom-image-from-url"
        "wait-image-available"
        "create-droplet-from-image"
        "wait-droplet-active"
        "verify-ssh"
      ]
      import_cmd:  $"doctl compute image create ($img_name) --image-url ($effective_url) --region ($region) --image-distribution FreeBSD"
      droplet_cmd: $"doctl compute droplet create ($img_name) --image <image-id> --size ($size) --region ($region)"
      note:        "DigitalOcean custom images must be raw/qcow2/vmdk, gzip/bz2/xz compressed OK. Image must be <100GB. FreeBSD is community-supported."
      warnings: [
        "custom-image-import-can-take-minutes"
        "freebsd-needs-bsd-cloudinit-or-DO-agent-disabled"
      ]
    }
  }

  # Live path
  let doctl = find_doctl
  if $doctl == null {
    return {action: "failed", reason: "doctl CLI not found — install: brew install doctl", provider: "digitalocean"}
  }
  if $image_url == "" {
    return {action: "failed", reason: "image_url required for DigitalOcean custom-image import (publish first, then pass via manifest.image_url or --image https://...)", provider: "digitalocean"}
  }

  # Step 1: import custom image
  let import_result = try {
    ^$doctl compute image create $img_name --image-url $image_url --region $region --image-distribution FreeBSD --output json | from json
  } catch { |e|
    return {action: "failed", step: "import_image", error: $e.msg, provider: "digitalocean"}
  }

  let image_id = ($import_result | get 0?.id? | default null)
  if $image_id == null {
    return {action: "failed", step: "import_image", detail: $import_result, provider: "digitalocean"}
  }

  {
    action:      "image-import-started"
    provider:    "digitalocean"
    image_id:    $image_id
    image_name:  $img_name
    region:      $region
    next_steps: [
      $"Wait for image ($image_id) status=available: doctl compute image get ($image_id)"
      $"Create droplet: doctl compute droplet create ($img_name) --image ($image_id) --size ($size) --region ($region) --ssh-keys <key-id>"
    ]
    note: "Custom image import is async — poll status before creating droplet"
  }
}
