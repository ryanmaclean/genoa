# Decision Tree: genoa-deploy Path Selection

## How to read this

Given `(provider, arch, os)`, walk the tree to get a recommended path.
The Graphviz source is in `decision-tree.dot` — render with `dot -Tsvg decision-tree.dot -o decision-tree.svg`.

---

## Worked examples

| Provider | Arch | OS | Path | Rationale |
|----------|------|----|------|-----------|
| AWS EC2 | amd64 | FreeBSD | **Path 0** via `bsdec2-image-upload` | AWS has full VM Import API. `bsdec2-image-upload` (BSD-2-Clause) handles FreeBSD AMI lifecycle end-to-end including aki/snapshot registration. |
| AWS EC2 | amd64 | NetBSD | **Path 0** via `aws ec2 import-snapshot` + `register-image` | VM Import accepts raw. ENA driver must be compiled into NetBSD kernel beforehand. |
| Google Cloud | amd64 | FreeBSD | **Path 0** via `gcloud compute images create` | GCE accepts gce-tar (disk.raw in tar.gz). FreeBSD virtio drivers in mainline. UEFI_COMPATIBLE flag required. |
| Google Cloud | aarch64 | FreeBSD | **Path 0** via `gcloud compute images create` | GCE ARM (T2A instances) supports UEFI. Same gce-tar format. FreeBSD aarch64 support since 12.0. |
| Azure | amd64 | FreeBSD | **Path 0** via `az disk create` | Azure accepts vhd-fixed. Must pre-align to 1 MiB. Generation 2 VMs prefer VHDX. |
| DigitalOcean | amd64 | FreeBSD | **Path 0** via `doctl compute image create` | DO custom images API accepts raw via URL or direct upload. Max 100 GiB. |
| Linode / Akamai | amd64 | FreeBSD | **Path 0** via `linode-cli images upload` | Accepts raw or raw.gz. Max 6 GiB compressed. |
| Vultr | aarch64 | NetBSD | **Path 1** via `/v2/snapshots/create-from-url` | Vultr's BYOI API takes a URL. Requires `genoa publish` step first. No direct-upload streaming API. |
| Scaleway | amd64 | FreeBSD | **Path 0** via `scw instance image create` | Scaleway accepts qcow2 via snapshot. Path 4 may be needed for IMDS (non-standard at 169.254.42.42). |
| Hetzner Cloud | aarch64 | FreeBSD | **Path 3** (rescue+dd) | Hetzner Cloud has no image import API. Rescue boot available via `hcloud server enable-rescue`. After dd, BSD agent must query Hetzner IMDS for SSH keys. |
| Hetzner Cloud | aarch64 | FreeBSD (SSH keys from IMDS) | **Path 4** (rescue+chroot) | If BSD agent doesn't yet support Hetzner IMDS at first boot, inject SSH keys during chroot fixup in rescue. |
| Equinix Metal | amd64 | FreeBSD | **Path 3** via Metal rescue mode | Equinix Metal has rescue boot. No BSD image import API. Raw image via HTTPS, dd to nvme/sda. |
| OVHcloud VPS | amd64 | FreeBSD | **Path 3** via OVH netboot rescue | OVH has rescue boot for VPS and dedicated. No BYOI API for VPS tier. |
| OVHcloud Dedicated | amd64 | FreeBSD | **Path 0** via OVH Bring Your Own Image API | OVH dedicated servers have a BYOI API (beta). Verify availability per region. |
| IONOS | amd64 | FreeBSD | **Path 2** (console ISO) or **Path 3** if rescue available | IONOS has KVM console for ISO mount. Rescue boot also available on some plans. |
| Contabo VPS | amd64 | FreeBSD | **Path 2** (console ISO, manual) | Contabo has VNC console. No rescue API. Manual only. |
| MacStadium (Apple Silicon) | aarch64 | FreeBSD | **Special: local VM provision** | macOS host + UTM or VMware Fusion. Not a cloud deploy. Treat as local image provision with raw image passed to UTM. No rescue, no import API. |
| Bare metal Pi 5 | aarch64 | FreeBSD | **Special: dd to SD card** | Not a cloud deployment. `dd if=genoa.raw of=/dev/mmcblk0 bs=4M`. Document separately from genoa-deploy. |
| Firecracker / Fly.io Machines | any | FreeBSD | **OUT OF SCOPE** | Firecracker requires a Linux kernel. Running BSD requires Linux-kernel + BSD-userland which is not the Genoa design target. Flag as unsupported. |
| ProxMox (self-hosted) | amd64 | FreeBSD | **Path 0** via `qm importdisk` / Proxmox API | Proxmox accepts qcow2 or raw. Not a public cloud — operator manages storage directly. |
| OpenStack (self-hosted) | amd64 | FreeBSD | **Path 0** via `openstack image create` | Glance accepts qcow2 or raw. Standard OpenStack image service. |

---

## Special cases not in the tree

### Apple Silicon Mac (MacStadium, Mac colo, Mac Mini Colocation)

No rescue boot. No image import API. The "cloud" is macOS running as the host.

Options:
1. **UTM** (GPL-3 for the app, QEMU-under-the-hood): provide a raw image, UTM
   wraps it in a UTM bundle. Works for dev/test, not production automated deploy.
2. **VMware Fusion** (proprietary): accepts VMDK. Automatable via `vmrun`.
3. **Parallels**: no FreeBSD support.
4. **Direct QEMU** (GPL-2, subprocess): `qemu-system-aarch64 -drive file=genoa.raw,format=raw`.
   Performant on Apple Silicon with QEMU 8.x HVF acceleration.

For production MacStadium fleet deployment, the right model is:
- Ship the raw image out-of-band (scp to host)
- The host launches it via QEMU as a VM
- This is infrastructure management, not genoa-deploy's core responsibility

### Raspberry Pi 5 (bare metal)

```sh
dd if=genoa-freebsd.raw of=/dev/mmcblk0 bs=4M conv=fsync status=progress
```

Document as "SD card write" — a one-liner, not a deployment tool concern.
FreeBSD supports Pi 5 via the `arm64/aarch64` build with UEFI firmware (EDK2).

---

## Path priority table (for implementation ordering)

| Priority | Path | Providers covered | Effort | Notes |
|----------|------|------------------|--------|-------|
| 1 | Path 0: BYOI | AWS, GCP, Azure, DO, Linode, OCI, Scaleway | Medium per provider | Highest ROI — covers all major clouds |
| 2 | Path 3: Rescue+dd | Hetzner, Equinix, OVH, Vultr (fallback), Linode (fallback) | Medium | Universal fallback; covers providers without BYOI |
| 3 | Path 1: Snapshot URL | Vultr, Exoscale, some DO | Medium | Requires publish step; overlaps with Path 0 |
| 4 | Path 4: Rescue+chroot | Same as Path 3 when IMDS fixup needed | Medium-high | Variant of Path 3; implement when BSD IMDS agent gaps are known |
| 5 | Path 2: Console ISO | Hetzner (manual), IONOS, Contabo | Low (no code) | Document as operator manual procedure |
| 6 | Path 5: kexec | None reliably | Very high / abandoned | Research only, not v1 |
