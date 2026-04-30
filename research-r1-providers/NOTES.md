# Research Notes — Surprises, Gotchas, and BSD-Friendly Intelligence

Generated: 2026-04-30 | Research agent: R1

---

## Dead Vendors and Status Changes

### Equinix Metal — Sunsets June 30, 2026
Equinix Metal (formerly Packet.net) pioneered API-driven bare metal cloud and was a gold standard for custom OS deployment. It is actively being shut down. No new commercial sales. All servers permanently deleted post-sunset. This was one of the few providers with FreeBSD as a managed stock OS AND full bare metal access. The ecosystem is migrating to Hivelocity, Latitude.sh, phoenixNAP, and Oxide Computer.

### RootBSD — Absorbed by NetActuate
RootBSD was founded by FreeBSD experts specifically to offer FreeBSD hosting. It is now part of NetActuate. The brand is dead; whether NetActuate carries forward the BSD competency is unverified.

### Hetzner Mac mini — Discontinued
Hetzner offered M1 Mac mini dedicated servers and quietly discontinued them. The `mac-mini-m1` product page still exists but cannot be ordered. Not upgradeable for existing customers.

### Joyent → MNX (Not Defunct)
Joyent was acquired by Samsung in 2016 and became an internal organization, ending external cloud sales. SmartOS and Triton DataCenter were NOT killed — they were spun out to MNX Solutions in April 2022 and remain under active development. MNX operates the MNX Public Cloud using Triton. This is easy to confuse with a shutdown. Joyent is dead; MNX/Triton is alive.

---

## BSD-Friendly Small Fish Worth Knowing

### ARP Networks (arpnetworks.com)
Oldest continuously operating FreeBSD and OpenBSD VPS specialist in the market. Since 2008. KVM/QEMU with Ceph storage backend. Native IPv6 block per customer. Allows custom kernel compilation (rare). OpenZFS supported. Full hardware virtualization. Not cheap but deeply BSD-competent.

### Tornado VPS (tornadovps.com)
Xen-based VPS since 2005. One of very few surviving Xen-hypervisor providers. Actively maintains FreeBSD 14.2, OpenBSD 7.8, and NetBSD 10.1 as of late 2025. Technically adept audience expected. FreeBSD as pre-built image; OpenBSD and NetBSD via netboot install. Quirk: NetBSD only supported under HVM, not paravirtual (PV) mode.

### BoxyBSD (boxybsd.com)
Free (no credit card) BSD-family VPS for learning. Runs FreeBSD, OpenBSD, NetBSD, DragonFlyBSD, and Solaris-family. Proxmox/KVM backend. Distributed globally (Canada, France, Germany, Netherlands, Japan, Singapore, USA, Italy, Ukraine). Presented at credativ Virtualization Gathering December 2025 — actively maintained. Not for production. Excellent for testing genoa image compatibility across BSD species.

### OrionVM (orionvm.com)
Australian wholesale IaaS with genuine FreeBSD as first-class citizen. FreeBSD templates with live network interface attach/detach, IP assignment, SSH key injection. OpenZFS configured by default on FreeBSD templates. Active company (new chairman March 2025). AI infrastructure pivot underway. API-driven.

### BuyVM / Frantech (buyvm.net)
Long-running budget VPS with FreeBSD, OpenBSD, NetBSD, and DragonFlyBSD templates on KVM. DDoS protection included. Locations: Las Vegas, New York, Luxembourg. No public API (Stallion panel). Good for cost-sensitive BSD deployments. Template versions may be older (verify before deploying).

### bsd-cloud-image.org
Not a provider but a community resource: pre-built qcow2 cloud images for FreeBSD, OpenBSD, NetBSD, and DragonFlyBSD. Cloud-init enabled. UFS and ZFS variants. Suitable for importing to any qcow2-accepting provider (Scaleway, OCI, OVHcloud, etc.). Maintained by Gonéri Le Bouder.

---

## License Traps for genoa Tooling

### QEMU — GPL-2.0
QEMU is the universal VM image manipulator and hypervisor. It is GPL-2.0. genoa MUST invoke QEMU as an external subprocess, never link against its libraries or vendor its source. This is fine for a deploy tool — `exec qemu-img convert` is not a GPL violation. Do not attempt to embed or fork QEMU code.

### libvirt — LGPL-2.1
The libvirt C library is LGPL-2.1. Dynamic linking is permitted under LGPL without triggering copyleft. genoa can use libvirt bindings via dynamic link (e.g., libvirt-go which is LGPL). Do not statically link libvirt.

### MNX/Triton/SmartOS Stack — CDDL + MPL-2.0
SmartOS OS components are CDDL-licensed (Common Development and Distribution License). CDDL is a copyleft license incompatible with GPL and arguably not MIT/BSD-compatible for static linking. genoa cannot vendor SmartOS components. Invoking the Triton API over HTTP is fine; shipping CDDL code is not.

### OCI CLI — Apache-2.0 (SAFE)
Safe to invoke as external tool. Oracle's CLI is Apache-2.0.

### AWS CLI v2 — Apache-2.0 (SAFE)
Safe to invoke as external tool.

### Azure CLI (`az`) — MIT (SAFE)
Safe to invoke.

### gcloud — Apache-2.0 (SAFE)
Safe to invoke.

### bsdec2-image-upload (cperciva) — BSD-2-Clause (SAFE TO VENDOR)
The FreeBSD EC2 image upload tool by Colin Percival. BSD-2-Clause. Safe to vendor or link against if needed. Used for pushing FreeBSD images to AWS.

### hcloud-upload-image — MIT (SAFE TO VENDOR)
Community tool for Hetzner Cloud raw image upload. MIT licensed. Safe to incorporate.

### Northflank/Railway/Render CLIs — MIT (SAFE)
Irrelevant for genoa (container-only platforms) but clean licenses.

---

## Key Technical Gotchas Per Provider

### Scaleway: EFI-only for Imported Images
Any image imported to Scaleway MUST support EFI boot. A BIOS-only (CSM/legacy) image WILL fail to boot. FreeBSD UEFI support has been solid since FreeBSD 11, but older images built for BIOS-only environments will not work. genoa must ensure the image has a working EFI stub or GRUB with EFI target when building for Scaleway.

### Azure: VHD Fixed-Size Only
Azure accepts VHD (Virtual Hard Disk) in fixed-size format only. Dynamic VHDs are rejected. VHDX (the modern Hyper-V format) is also rejected for upload despite being the native format for Hyper-V. Conversion step required: `qemu-img convert -f qcow2 -O vpc -o subformat=fixed image.qcow2 image.vhd`. genoa adapter must include this conversion.

### AWS: ARM64 Import NOT Supported via VM Import/Export
The AWS VM Import/Export service explicitly does not support ARM64 image import. For FreeBSD aarch64, the correct approach is to use the official FreeBSD AMIs published by the FreeBSD Release Engineering team, retrievable from SSM Parameter Store: `/aws/service/freebsd/aarch64/base/ufs/14.3/RELEASE`. Do not attempt to import aarch64 images via VM Import/Export.

### OCI: FreeBSD Requires Emulated Mode
FreeBSD on OCI must launch in "emulated mode" (not paravirtualized). Paravirtualized mode requires Linux kernel 3.4+. genoa must set the `launchOptions.launchMode` to `EMULATED` when importing FreeBSD images to OCI.

### Akamai/Linode: ext3/ext4 Filesystem Requirement
Linode's custom image upload requires ext3 or ext4 filesystem. FreeBSD uses UFS2 or ZFS natively. Workarounds exist (use a small ext4 partition with kloader, or use mfsbsd) but are complex and fragile. The 6 GB uncompressed maximum is also very tight for a useful FreeBSD deployment. Akamai officially does not support FreeBSD — use Vultr, BuyVM, or ARP Networks instead.

### DigitalOcean: FreeBSD Dropped July 2022
DigitalOcean removed FreeBSD from their managed OS catalog permanently in July 2022. Custom image upload (raw, qcow2, vhdx, vdi, vmdk) is available and FreeBSD CAN be run, but requires `bsd-cloudinit` for proper cloud integration (SSH key injection, networking). genoa adapter must include bsd-cloudinit in any DigitalOcean FreeBSD image.

### Hetzner Cloud: No Official Image Upload
Hetzner Cloud has no API endpoint for uploading disk images. The workaround (`hcloud-upload-image`) creates a temporary server, boots a rescue system, dd's the image over the disk, then takes a snapshot. This is clever but slow (depends on disk size), requires an active server (billed during process), and is not officially supported. Hetzner could break this at any time. Risk: medium.

### GCP: FreeBSD Images in Non-Default Project
GCP FreeBSD images are NOT in the standard public image project. They are in `freebsd-org-cloud-dev`, maintained by the FreeBSD community. To list them: `gcloud compute images list --project freebsd-org-cloud-dev --no-standard-images`. genoa must hardcode this project reference for FreeBSD image discovery on GCP.

### Cloud-init on FreeBSD: Now Tier 1 Supported
As of FreeBSD 14.1 (mid-2024), cloud-init elevated FreeBSD to Tier 1 platform support. `nuageinit` (Lua-based, in base system) provides cloud-init datasource compatibility natively in FreeBSD. The `bsd-cloudinit` package (Python-based, older) is still available for providers that need the older compatibility. This means genoa-generated images should use nuageinit for FreeBSD 14.1+ and bsd-cloudinit as fallback for older or specific providers.

### Colin Percival's "How to Support FreeBSD on Your Cloud" (Nov 2025)
Key guidance from a primary FreeBSD cloud maintainer: cloud providers need (1) sponsored accounts for FreeBSD RE team, (2) documented image format requirements, (3) a human liaison, (4) weekly deployment testing, (5) advance notice on hardware transitions, (6) BSD-licensed custom drivers. This is useful context for genoa's provider outreach strategy — providers missing these elements will have fragile FreeBSD support.

---

## Architectural Surprises

### Koyeb and Fly.io: Docker-Only but VM-Backed
Both Koyeb and Fly.io use Firecracker microVMs internally but expose only a Docker interface. This is architecturally interesting — a BSD image theoretically could run as a Firecracker guest — but neither provider exposes this. The user-facing API accepts only OCI container images. These platforms chose to sacrifice flexibility for simplicity.

### MNX/Triton: Unique Zone + KVM Hybrid
MNX Triton is the only provider using SmartOS/illumos zones as the primary compute primitive alongside KVM VMs. Zones (OS-level containers on illumos) provide near-bare-metal performance without hardware virtualization overhead. FreeBSD cannot run as a zone (illumos-only OS), but can run as a KVM guest inside Triton. Unique capability: each zone has a full ZFS dataset with copy-on-write cloning for fast provisioning.

### Equinix Metal's iPXE Model is Ideal for genoa's Philosophy
The Equinix Metal custom iPXE approach was architecturally ideal for genoa: provide a URL to a bootable iPXE script, and any OS (BSD, Linux, custom unikernel) can be deployed without format conversion or provider-side image import. The sunset of this service removes one of the cleanest deployment paths for arbitrary OS images at bare metal. Hivelocity's iPXE support is the closest current alternative.

### Apple Silicon Tier: No BSD Path (Yet)
FreeBSD's aarch64 port (arm64) runs well on QEMU emulating Apple Silicon, and experimentally on real Apple Silicon hardware via m1n1 bootloader. However, no commercial Apple Silicon hosting provider supports non-macOS guests. The Apple licensing agreement for commercial use requires running macOS on the hardware. This is a hard blocker for the foreseeable future.

---

## Providers Not Covered (Potential Future Research)

- **Latitude.sh** — bare metal cloud, emerging Equinix Metal alternative, API-driven
- **Oxide Computer** — on-premises bare metal cloud, API-driven, BSD-friendly culture
- **Cherry Servers** — European bare metal, custom OS via iPXE
- **DataPacket** — bare metal, iPXE, data center in US/EU
- **Leaseweb** — Dutch provider with dedicated servers and custom OS
- **Fasthosts / IONOS** — European VPS with custom image support
- **Netcup** — German provider, KVM VPS, custom ISO
- **VEXXHOST** — OpenStack-based cloud (similar to OVHcloud Public Cloud)
- **CloudSigma** — Swiss provider, custom image upload, raw/qcow2
- **Memset** — UK provider, FreeBSD historically supported
- **Tilaa** — Dutch KVM VPS
- **Greenhost** — Netherlands, FreeBSD VPS, sustainability focus
- **OpenMetal** — OpenStack dedicated cloud
