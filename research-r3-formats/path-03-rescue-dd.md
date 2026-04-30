# Path 3: Rescue + dd

**Priority: 3 — universal automatable fallback, Tier 1 trampoline**

## Summary

Boot the provider's rescue Linux environment (a minimal OS booted from provider
infrastructure, not from the VPS disk). From rescue, fetch the genoa raw image
and `dd` it directly to the VPS's block device. Then reboot into the freshly
written OS.

**No QEMU. No nested virtualization. No manual console steps.**
This is the universal fallback for any provider that offers a rescue mode.

## Works for

| Provider | Rescue access | Notes |
|----------|--------------|-------|
| Hetzner Cloud | `hcloud server enable-rescue` + reboot | Linux rescue, /dev/sda or /dev/vda |
| OVHcloud | netboot rescue in OVH console/API | |
| Scaleway | `scw instance server action rescue-reboot` | |
| Vultr | API: `POST /v2/instances/{id}/boot` with `RESCUE` mode | |
| DigitalOcean | Recovery console (limited) | No full rescue, use Path 0 |
| Hetzner Dedicated | IPMI rescue boot | |
| Equinix Metal | `packet rescue` via API | |
| Linode | `linode-cli linodes rescue` | |
| IONOS | Rescue system in IONOS console | |
| Exoscale | Instance reset / rescue | |

## Required capabilities

- Provider API access to enable rescue mode and reboot
- Genoa image hosted at an HTTPS URL (from `genoa publish` — see `publish-step.md`)
- No requirement for QEMU or nested virtualization
- **No iPXE dependency** — rescue boot is handled entirely by the provider

## Procedure

```sh
# 1. Enable rescue mode (provider-specific; Hetzner example)
hcloud server enable-rescue --type linux64 $SERVER_ID
hcloud server reboot $SERVER_ID

# 2. Wait for rescue boot (poll SSH or sleep 30s)

# 3. SSH into rescue and run:
ssh root@$SERVER_IP << 'RESCUE'
set -euo pipefail

IMAGE_URL="https://pub.genoa.example.com/genoa-freebsd-20260430.raw"
IMAGE_SHA256="abc123..."  # from genoa publish --manifest
TARGET="/dev/sda"  # or /dev/vda — detect from lsblk

# Verify before writing
curl -fSL "${IMAGE_URL}.sha256" | sha256sum -c -

# Stream directly — no temp file needed if image fits in RAM differently
curl -fSL "$IMAGE_URL" | dd of="$TARGET" bs=4M conv=fsync status=progress

# Sync and verify
sync
blockdev --rereadpt "$TARGET" 2>/dev/null || true

RESCUE

# 4. Disable rescue mode and reboot into new OS
hcloud server reboot $SERVER_ID
```

## The sha256 verification pattern

Never dd without verification. Pattern:

```sh
# Atomic: fetch and verify in one pipeline
curl -fSL "$IMAGE_URL" \
  | tee >(sha256sum > /tmp/got.sha256) \
  | dd of="$TARGET" bs=4M conv=fsync status=progress

# Compare
echo "$EXPECTED_SHA256  -" | diff - /tmp/got.sha256
```

Or use a pre-download-verify pattern if rescue has enough RAM/disk.

## Block device detection

Rescue kernels expose the disk as `/dev/sda` (virtio-scsi) or `/dev/vda`
(virtio-blk) depending on provider. Detection:

```sh
TARGET=$(lsblk -dpno NAME,TYPE | awk '$2=="disk" {print $1; exit}')
```

## Limitations

1. **Image size vs. rescue RAM**: If streaming, no RAM limit issue. If writing
   to a tmp file in tmpfs, rescue usually has 4–32 GiB RAM. Genoa images should
   stay under 4 GiB to be safe.

2. **Rescue availability**: A few providers don't offer rescue (some managed
   Kubernetes node pools, some container platforms). For those, use Path 0.

3. **No cloud-init / IMDS injection**: After dd, the OS boots with the exact
   state of the image. Cloud-specific config (SSH keys, hostname, IMDS access)
   must be pre-baked into the image OR handled by Path 4 (rescue + chroot fixup).

4. **Disk is overwritten**: All existing data on the target device is destroyed.
   No rollback. Ensure the right device is targeted.

## Implementation effort

**Medium.** Genoa-deploy needs to:
1. Implement per-provider "enable rescue + reboot" API calls (Hetzner, Scaleway, etc.)
2. Wait for rescue SSH to become available (poll with timeout)
3. Run the dd script over SSH
4. Implement "disable rescue + reboot" calls
5. Wait for the genoa OS to boot and verify

The rescue script itself is ~20 lines of shell. The provider adapter layer
(enable/disable rescue, SSH wait) is the larger effort.

## License traps

- `dd`, `curl`, `sha256sum`: all BSD/MIT/GPL userland in the rescue Linux —
  we invoke these on the rescue system, not in genoa-deploy's binary. Clean.
- **No iPXE** — rescue boot is handled by the provider's own infrastructure.
- SSH client in genoa-deploy: use `openssh` (BSD-style) or Rust `ssh2` crate
  (MIT, wraps libssh2 MIT). Do NOT use paramiko (LGPL).

## References

- Hetzner rescue: https://docs.hetzner.com/cloud/servers/rescue-mode/
- Scaleway rescue: https://www.scaleway.com/en/docs/compute/instances/how-to/use-boot-modes/
- Vultr rescue: https://www.vultr.com/docs/vultr-rescue-system/
- Linode rescue: https://www.linode.com/docs/guides/rescue-and-rebuild/
- Equinix Metal rescue: https://deploy.equinix.com/developers/docs/metal/operating-systems/rescue-mode/
