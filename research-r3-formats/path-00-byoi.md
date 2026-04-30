# Path 0: BYOI Direct Upload (Bring Your Own Image)

**Priority: 1 (highest) — cleanest, most automatable**

## Summary

The provider exposes an API to register a custom image directly. Genoa uploads
the image (in the provider's required format) and receives an image ID that can
be used to launch instances. No rescue boot, no intermediate OS, no manual steps.

## Works for

| Provider | API / CLI | Required format | Notes |
|----------|-----------|----------------|-------|
| AWS EC2 | `aws ec2 import-snapshot` + `register-image` OR `bsdec2-image-upload` | raw (via S3) | vmimport IAM role required |
| Google Cloud | `gcloud compute images create --source-uri` | gce-tar (disk.raw in .tar.gz in GCS) | |
| Azure | `az image create` / `az disk create --upload` | vhd-fixed or vhdx (page blob) | 1 MiB alignment mandatory |
| DigitalOcean | `doctl compute image create` / API POST /v2/images | raw or qcow2 via HTTPS URL | max 100 GiB |
| Linode / Akamai | `linode-cli images upload` | raw (gzip recommended) | max 6 GiB compressed |
| Vultr | `/v2/snapshots/create-from-url` or `/v2/os` (custom) | raw via URL | See also Path 1 |
| OCI | `oci compute image import from-object` | raw or VMDK via Object Storage | |
| Hetzner Cloud | No BYOI API — **skip this path** | N/A | Use Path 2 or 3 |
| Scaleway | `scw instance image create` | qcow2 via snapshot | |
| Exoscale | `exo compute instance-template register` | raw or qcow2 via URL | |

## Required capabilities

- Object storage write access (S3, GCS, Azure Blob, OCI Object Storage) for providers
  that pull from a URL rather than accept a direct upload stream
- Provider API credentials with image-import permissions
- Async polling: most imports are async (AWS: 15-60 min, GCP: 5-20 min, Azure: varies)

## Per-provider invocation

### AWS (FreeBSD — preferred)
```sh
bsdec2-image-upload \
  --public \
  --bucket genoa-images \
  genoa-freebsd.raw \
  genoa-freebsd-YYYYMMDD \
  "Genoa FreeBSD amd64" \
  us-east-1
# License: BSD-2-Clause
# https://github.com/freebsd/bsdec2-image-upload
```

### AWS (generic via VM Import)
```sh
aws s3 cp genoa.raw s3://genoa-images/genoa.raw
aws ec2 import-snapshot \
  --description "genoa" \
  --disk-container "Format=RAW,UserBucket={S3Bucket=genoa-images,S3Key=genoa.raw}"
# Poll until SnapshotId appears, then register-image
aws ec2 register-image \
  --name "genoa-freebsd-YYYYMMDD" \
  --root-device-name /dev/sda1 \
  --block-device-mappings DeviceName=/dev/sda1,Ebs={SnapshotId=snap-XXXX} \
  --virtualization-type hvm \
  --boot-mode uefi
```

### Google Cloud
```sh
gsutil cp genoa-gce.tar.gz gs://genoa-images/
gcloud compute images create genoa-freebsd-YYYYMMDD \
  --source-uri=gs://genoa-images/genoa-gce.tar.gz \
  --guest-os-features=UEFI_COMPATIBLE,VIRTIO_SCSI_MULTIQUEUE,VIRTIO_NET \
  --family=genoa-freebsd
```

### Azure
```sh
az disk create \
  --resource-group genoa-rg \
  --name genoa-disk \
  --source genoa.vhd \
  --upload-type upload
# (or use az image create --source for managed image)
az image create \
  --resource-group genoa-rg \
  --name genoa-freebsd-YYYYMMDD \
  --source genoa-disk \
  --os-type Linux \
  --hyper-v-generation V2
```

### DigitalOcean
```sh
doctl compute image create genoa-freebsd-YYYYMMDD \
  --region nyc3 \
  --image-url https://genoa.example.com/genoa-freebsd.raw \
  --distribution "FreeBSD"
```

### Linode
```sh
linode-cli images upload \
  --label genoa-freebsd-YYYYMMDD \
  --region us-east \
  --file genoa-freebsd.raw.gz
```

## Implementation effort

**Medium.** Each provider needs a separate upload adapter. The core logic is:
1. Format-convert the raw image to provider's required format
2. Upload to provider object storage (or stream directly)
3. Call provider's import/register API
4. Poll for completion
5. Return image ID

The per-provider adapter surface is small: ~50-100 lines each in a typed
interface. A `genoa image push <provider>` command that dispatches to adapters.

## License traps

- `bsdec2-image-upload`: BSD-2-Clause — clean
- `aws-cli`: Apache-2.0 — clean
- `gcloud`: Apache-2.0 — clean
- `azure-cli`: MIT — clean
- `doctl` (DigitalOcean CLI): Apache-2.0 — clean
- `linode-cli`: BSD-3-Clause — clean
- **qemu-img** (format conversion): GPL-2.0-only — invoke as subprocess only, never link

## iPXE note

This path does NOT use iPXE. No network boot involved.

## References

- AWS VM Import: https://docs.aws.amazon.com/vm-import/latest/userguide/vmimport-image-import.html
- GCE custom images: https://cloud.google.com/compute/docs/import/import-existing-image
- Azure upload: https://docs.microsoft.com/en-us/azure/virtual-machines/upload-generalized-managed
- bsdec2-image-upload: https://github.com/freebsd/bsdec2-image-upload
