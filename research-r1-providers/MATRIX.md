# genoa-deploy Provider Matrix
**Generated:** 2026-04-30  
**Research agent:** R1  
**Schema version:** 1.0.0

Sorted by tier, then provider_id. Machine-readable source: `providers.json`.

Legend:
- BYOI support: `api` = fully automated API path | `console` = manual/console step required | `none` = not supported
- BSD: lists which BSDs are available as stock images (not via BYOI)
- Staleness: `low` = verified within 6 months | `medium` = 6-18 months | `high` = >18 months

---

## Tier 1 — Mainstream Public Clouds

| provider_id | display_name | Hypervisor | Arch | BYOI | Formats | Max GB | ISO Mount | BSD Stock | Boot | IPv6 | Last Verified |
|---|---|---|---|---|---|---|---|---|---|---|---|
| aws | Amazon EC2 | KVM | amd64, aarch64 | api | raw, vmdk, vhd, vhdx, ova | — | none | freebsd | both | yes | [prereqs](https://docs.aws.amazon.com/vm-import/latest/userguide/prerequisites.html) |
| gcp | Google Cloud CE | KVM | amd64, aarch64 | api | raw, vmdk, tar.gz | 2048 | none | freebsd* | both | yes | [import](https://docs.cloud.google.com/compute/docs/import/import-existing-image) |
| azure | Azure VMs | Hyper-V | amd64, aarch64 | api | vhd | — | console | freebsd | both | conditional | [FreeBSD report](https://www.freebsd.org/status/report-2025-01-2025-03/azure/) |
| oci | Oracle Cloud | KVM | amd64, aarch64 | api | qcow2, vmdk | 400 | console | freebsd | both | yes | [BYOI](https://docs.oracle.com/en-us/iaas/Content/Compute/References/bringyourownimage.htm) |
| alicloud | Alibaba Cloud ECS | KVM | amd64, aarch64 | api | raw, qcow2, vhd, vmdk | 500 | console | freebsd | both | yes | [import](https://www.alibabacloud.com/help/en/ecs/user-guide/import-a-custom-image) |
| tencentcloud | Tencent Cloud CVM | KVM | amd64, aarch64 | api | qcow2, vhd, raw, vmdk | 500 | console | freebsd | both | conditional | [import](https://intl.cloud.tencent.com/document/product/213/4945) |
| ibmcloud | IBM Cloud VPC | KVM | amd64, ppc64le | api | qcow2, vhd | 250 | none | none | both | yes | [custom images](https://cloud.ibm.com/docs/vpc?topic=vpc-importing-custom-images-vpc) |

*GCP FreeBSD images in separate `freebsd-org-cloud-dev` project, not default catalog.

**Key notes Tier 1:**
- Azure: VHD only (fixed-size, not dynamic, not VHDX). Gen2/UEFI requires Hyper-V Gen V2 property set.
- AWS: ARM64 NOT importable via VM Import/Export. Use official FreeBSD AMIs from SSM Parameter Store instead.
- OCI: FreeBSD must use emulated mode (not paravirtualized) for x86. ARM64 via marketplace.
- IBM Cloud: No FreeBSD stock image. ppc64le via separate Power Virtual Server product.

---

## Tier 2 — Developer-Favorite Mid-Tier

| provider_id | display_name | Hypervisor | Arch | BYOI | Formats | Max GB | ISO Mount | BSD Stock | Boot | IPv6 | Last Verified |
|---|---|---|---|---|---|---|---|---|---|---|---|
| vultr | Vultr Cloud Compute | KVM | amd64 | api | iso | 10 | api | freebsd | both | yes | [ISOs](https://docs.vultr.com/products/orchestration/isos) |
| digitalocean | DigitalOcean | KVM | amd64 | api | raw, qcow2, vhdx, vdi, vmdk | 100 | none | none** | both | yes | [custom images](https://docs.digitalocean.com/products/custom-images/details/features/) |
| linode_akamai | Akamai Cloud (Linode) | KVM | amd64, aarch64 | api | raw | 6 | none | none | bios | yes | [upload](https://techdocs.akamai.com/cloud-computing/docs/upload-an-image) |
| hetzner_cloud | Hetzner Cloud | KVM | amd64, aarch64 | api | raw*** | — | console | none | both | yes | [hcloud-upload-image](https://github.com/apricote/hcloud-upload-image) |
| hetzner_robot | Hetzner Robot (Dedicated) | bare-metal | amd64 | console | tar.gz | — | console | none | both | yes | [installimage](https://docs.hetzner.com/robot/dedicated-server/operating-systems/installing-custom-images/) |
| scaleway | Scaleway Instances | KVM | amd64, aarch64 | api | qcow2 | 1000 | none | none | uefi | yes | [snapshot import](https://www.scaleway.com/en/docs/instances/api-cli/snapshot-import-export-feature/) |
| ovhcloud_public | OVHcloud Public Cloud | KVM | amd64, aarch64 | api | raw, qcow2 | — | console | none | both | yes | [upload](https://help.ovhcloud.com/csm/en-public-cloud-compute-upload-own-image) |
| ovhcloud_dedicated | OVHcloud Dedicated (BYOI) | bare-metal | amd64, aarch64 | api | raw, qcow2 | — | console | none | both | yes | [BYOI](https://help.ovhcloud.com/csm/en-dedicated-servers-bringyourownimage) |
| contabo | Contabo VPS/VDS | KVM | amd64 | api | iso, qcow2 | — | console | none | both | yes | [custom images](https://contabo.com/en-us/custom-images/) |

**DigitalOcean dropped FreeBSD stock images July 2022. Custom image upload required.  
***Hetzner Cloud has no official image upload API; raw image via rescue-system workaround using community tool `hcloud-upload-image`.

**Key notes Tier 2:**
- Scaleway: EFI-only boot for imported images — BIOS-only images WILL NOT BOOT.
- Akamai/Linode: ext3/ext4 filesystem requirement effectively blocks UFS and ZFS native use. Max 6 GB too small for many BSD deployments.
- Hetzner Cloud: No official BYOI API. Community tool required. Snapshot-based workaround.
- Contabo: Custom Images is a paid add-on, must purchase at order time.
- Vultr: ISO only (not raw/qcow2 direct). 2-per-account ISO limit. 10 GB max.

---

## Tier 3 — Specialty / Niche

| provider_id | display_name | Hypervisor | Arch | BYOI | Formats | Max GB | ISO Mount | BSD Stock | Boot | IPv6 | Last Verified |
|---|---|---|---|---|---|---|---|---|---|---|---|
| equinix_metal | **[SUNSETS 2026-06-30]** Equinix Metal | bare-metal | amd64, aarch64 | api | iso (iPXE) | — | api | freebsd | both | yes | [DCD](https://www.datacenterdynamics.com/en/news/equinix-to-kill-off-metal-by-june-2026/) |
| hivelocity | Hivelocity Bare Metal | bare-metal | amd64 | api | iso (iPXE) | — | console | none | both | yes | [iPXE docs](https://developers.hivelocity.net/docs/custom-ipxe) |
| phoenixnap | phoenixNAP BMC | bare-metal | amd64 | api | iso | — | console | none | both | yes | [BMC](https://phoenixnap.com/bare-metal-cloud) |
| ramnode | RamNode KVM VPS | KVM | amd64 | console | iso | — | console | freebsd | both | yes | [KB](https://clientarea.ramnode.com/knowledgebase/48/) |
| buyvm | BuyVM / Frantech | KVM | amd64 | console | iso | — | console | freebsd, openbsd, netbsd | both | yes | [BSD OS](https://buyvm.net/operating-systems/bsd-family/) |
| lambda_cloud | Lambda Cloud GPU | KVM | amd64 | none | — | — | none | none | uefi | no | [docs](https://docs.lambda.ai/public-cloud/on-demand/) |
| coreweave | CoreWeave GPU | KVM | amd64 | api | raw, qcow2 | — | none | none | uefi | no | [platform](https://www.coreweave.com/platform) |
| runpod | RunPod GPU | KVM | amd64 | api | oci-container | 10 | none | none | uefi | no | [docs](https://docs.runpod.io/) |
| paperspace | Paperspace/Gradient | KVM | amd64 | console | oci-container | — | none | none | uefi | no | [docs](https://docs.digitalocean.com/products/paperspace/) |
| crusoe | Crusoe Cloud GPU | KVM | amd64 | api | raw, qcow2 | — | none | none | uefi | no | [cloud](https://www.crusoe.ai/cloud) |

**Key notes Tier 3:**
- Equinix Metal: **DO NOT build new genoa adapters**. EOL June 30, 2026. Existing deployments must migrate.
- GPU providers (Lambda, RunPod, Paperspace, Crusoe, CoreWeave): Focus on ML/AI. Lambda has NO BYOI. RunPod is container-only. CoreWeave is Kubernetes/KubeVirt with theoretically importable images.
- Hivelocity/phoenixNAP: iPXE-based custom OS. Full bare metal, good for BSD if iPXE-bootable.

---

## Tier 4 — Edge/Serverless (Out of Scope for VM Images)

| provider_id | display_name | Model | BYOI | BSD | Notes |
|---|---|---|---|---|---|
| flyio | Fly.io | Firecracker microVM | none (Docker only) | no | Docker→Firecracker internal; no raw image API |
| cloudflare_workers | Cloudflare Workers | V8 isolates | none | no | No VM concept at all |
| render | Render | Managed containers | none (Docker only) | no | Docker/Dockerfile only |
| railway | Railway | Managed containers | none (Docker only) | no | Docker/Nixpacks only |
| northflank | Northflank | Kubernetes | none (OCI container) | no | BYOC = cloud account not OS image |
| koyeb | Koyeb | Firecracker/Nomad | none (Docker only) | no | Docker→Firecracker; no BYOI |

All Tier 4 providers are **out of scope** for genoa VM image deployment. See `BLOCKED.md` for details.

---

## Tier 5 — BSD-Friendly Small Providers

| provider_id | display_name | Hypervisor | Arch | BYOI | BSD Stock | Boot | IPv6 | Last Verified |
|---|---|---|---|---|---|---|---|---|
| arp_networks | ARP Networks | KVM | amd64 | api (raw) | freebsd, openbsd | both | yes | [arpnetworks.com](https://arpnetworks.com/) |
| tornado_vps | Tornado VPS | Xen | amd64 | console | freebsd, openbsd, netbsd | both | yes | [tornadovps.com](https://tornadovps.com/) |
| buyvm | BuyVM/Frantech | KVM | amd64 | console | freebsd, openbsd, netbsd | both | yes | [buyvm.net](https://buyvm.net/operating-systems/bsd-family/) |
| orionvm | OrionVM | KVM | amd64 | api (raw) | freebsd | both | yes | [orionvm.com](https://www.orionvm.com/) |
| boxybsd | BoxyBSD | KVM | amd64 | none | freebsd, openbsd, netbsd | both | yes | [boxybsd.com](https://boxybsd.com/) |
| mythic_beasts | Mythic Beasts (Pi) | bare-metal | aarch64 | api (raw) | none* | uefi | yes | [mythic-beasts.com](https://www.mythic-beasts.com/support/api/raspberry-pi) |
| m5hosting | M5 Hosting | bare-metal | amd64 | console | freebsd | both | no | [m5hosting.com](https://www.m5hosting.com/) |
| rootbsd_netactuate | RootBSD → NetActuate | KVM | amd64 | — | — | — | — | **DEFUNCT** (see NetActuate) |

*Mythic Beasts stocks Raspberry Pi OS and Ubuntu. FreeBSD on Pi possible via custom image.

**Key notes Tier 5:**
- ARP Networks: Premier BSD specialist, since 2008. Ceph storage. Full kernel compilation allowed.
- Tornado VPS: Xen hypervisor (rare). All three major BSDs actively maintained (as of Dec 2025).
- BoxyBSD: Free, no credit card, not for production. Excellent for BSD testing across species.
- OrionVM: Australia-based. Active company as of Q1 2025. OpenZFS default on FreeBSD templates.

---

## Tier 6 — Apple Silicon Hosts

| provider_id | display_name | Hypervisor | Arch | BYOI | BSD | Notes |
|---|---|---|---|---|---|---|
| macstadium | MacStadium (Orka) | HVF (Apple) | aarch64 | api (macOS OCI) | none | macOS VMs only; Orka 3.x Kubernetes-native |
| scaleway_apple | Scaleway Mac mini M1/M4 | bare-metal | aarch64 | none | none | Bare metal macOS; no VMs possible |
| aws_ec2_mac | AWS EC2 Mac (M1/M2/M4) | HVF (Apple) | aarch64 | api (AMI/macOS) | none | EC2 Image Builder for macOS AMI; 24h min tenancy |
| hetzner_mac | Hetzner Mac mini | bare-metal | aarch64 | none | none | **DEFUNCT** — discontinued |

All Apple Silicon hosts support macOS only. BSD (including FreeBSD) not deployable. HVF (Apple Hypervisor.framework) is aarch64-only and macOS-host-only.

---

## Tier 7 — Special Targets

| provider_id | display_name | Hypervisor | Arch | BYOI | Formats | BSD | Notes |
|---|---|---|---|---|---|---|---|
| mnx_joyent | MNX/Triton (ex-Joyent) | proprietary (SmartOS) | amd64 | api | raw, vmdk | none (illumos zones) | SmartOS/illumos cloud. Spun from Joyent to MNX 2022. Still active. |
| local_kvm | Local KVM/QEMU | KVM | all | api | all | freebsd, openbsd, netbsd | All formats/archs. QEMU=GPL, invoke as external process only. |
| local_bhyve | Local bhyve | proprietary (BSD) | amd64, aarch64 | api | raw, qcow2, vmdk | freebsd, openbsd, netbsd | BSD-licensed. FreeBSD host required. Ideal genoa local target. |

---

## Format Support Quick Reference

| Format | AWS | GCP | Azure | OCI | Alicloud | DO | Akamai | Scaleway | OVH | Vultr | Contabo |
|---|---|---|---|---|---|---|---|---|---|---|---|
| raw | yes | yes | no | no | yes | yes | yes | no | yes | no | no |
| qcow2 | no | no | no | yes | yes | yes | no | yes | yes | no | yes |
| vmdk | yes | yes | no | yes | yes | yes | no | no | no | no | no |
| vhd | yes | no | yes | no | yes | no | no | no | no | no | no |
| vhdx | yes | no | no | no | no | yes | no | no | no | no | no |
| ova | yes | no | no | no | no | no | no | no | no | no | no |
| vdi | no | no | no | no | no | yes | no | no | no | no | no |
| iso | no | no | no | no | no | no | no | no | yes | yes | yes |

---

*Table generated from providers.json. For machine consumption use the JSON catalog directly.*
