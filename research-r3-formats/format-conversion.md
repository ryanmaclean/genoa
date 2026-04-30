# Format Conversion Commentary

## Source: raw → everything

Genoa-A produces a `.raw` GPT disk image with an ESP and OS-native EFI loader.
`qemu-img convert` is the workhorse for all conversions. It is **GPL-2.0-only** but
invoked as an external subprocess — the copyleft does not propagate across the
exec() boundary. Never link against libqemu.

---

## Priority matrix

| Format | Cloud consumers | Needed? | Complexity |
|--------|----------------|---------|-----------|
| raw | DO, Hetzner (rescue), Linode, Vultr, bare-metal | YES — always keep | trivial |
| gce-tar | GCP | YES for GCP | low (cp + tar) |
| vhd-fixed | Azure | YES for Azure | medium (MB alignment critical) |
| vmdk-streamOptimized | vSphere, VMware Cloud | YES for VMware | medium |
| ami (via raw) | AWS | YES for AWS | high (S3 + async import) |
| qcow2 | OpenStack, Proxmox | YES for self-hosted | low |
| ova | vSphere (enterprise), VirtualBox | low priority | high (OVF XML authoring) |
| vhdx | Azure Gen2 | deferred — vhd-fixed covers Gen1 first | medium |
| vmdk-monolithic | VirtualBox local | dev-only | low |
| vdi | VirtualBox local | dev-only | low |

---

## Quirk deep-dives

### VHD alignment for Azure

Azure's VHD validation rejects images whose virtual size is not a multiple of
1,048,576 bytes (1 MiB). The 512-byte VHD footer is appended *after* the data
region — so the image file size is `aligned_data_size + 512`.

```
aligned = math.ceil(raw_bytes / 1048576) * 1048576
qemu-img resize image.raw ${aligned}
qemu-img convert -f raw -O vpc -o subformat=fixed image.raw image.vhd
```

Reference: https://docs.microsoft.com/en-us/azure/virtual-machines/linux/create-upload-generic

### VMDK subformat confusion

`qemu-img` defaults to `monolithicSparse` when `-O vmdk` is given with no
`-o subformat`. vSphere's import API requires `streamOptimized`. Always pass
`-o subformat=streamOptimized` explicitly.

The VMDK descriptor line `adapterType = "ide"` (qemu-img default) causes
warnings on ESXi. Patch the descriptor to `lsiLogic` for production images.

### OVA tar ordering

The OVF spec (DSP0243) requires the OVF descriptor to be the first file in the
tar archive. GNU tar and bsdtar both respect insertion order — add `.ovf` first:

```
tar -cf image.ova --format=ustar descriptor.ovf disk.vmdk disk.mf
```

Failure to order correctly produces "Invalid OVA" errors in vSphere.

### GCE disk naming

Google Cloud's image importer looks for a file named **exactly** `disk.raw`
inside the `.tar.gz`. Any other name causes the import to fail with a cryptic
"no disk found" error. Always rename before tarring.

### AMI: import-image vs import-snapshot

`ec2 import-image` handles the full lifecycle but has OS restrictions and may
inject AWS-specific tools. For BSDs:

- Use `ec2 import-snapshot` to register raw sectors as an EBS snapshot
- Then `ec2 register-image` to create an AMI from that snapshot
- `bsdec2-image-upload` (BSD-2-Clause) automates this: https://github.com/freebsd/bsdec2-image-upload

### qcow2 reproducibility

`qemu-img convert` embeds a creation timestamp in the qcow2 header. Two
conversions of the same source produce different hashes. For content-addressed
publishing (IPFS, sha256-pinned manifests), always hash the `.raw` source, not
derived formats.

---

## License summary

| Tool | License | Safe? | Notes |
|------|---------|-------|-------|
| qemu-img | GPL-2.0-only | YES (exec boundary) | Never vendor or link |
| bsdec2-image-upload | BSD-2-Clause | YES | Preferred for AWS/FreeBSD |
| aws-cli | Apache-2.0 | YES | |
| gcloud CLI | Apache-2.0 | YES | |
| azure-cli | MIT | YES | |
| iPXE | GPL-2.0 | **NO** | Explicitly rejected — no path may depend on it |

