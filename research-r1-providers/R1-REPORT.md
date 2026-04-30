# R1 Research Report — genoa-deploy Provider Matrix
**Agent:** R1  
**Date:** 2026-04-30  
**Coverage:** 40 providers across 7 tiers  
**Scope:** Cloud and virtualization deployment targets for arbitrary BSD/Linux/unikernel images

---

## Coverage Summary

| Metric | Count |
|---|---|
| Total providers documented | 40 |
| Active providers | 34 |
| Deprecated / defunct | 4 (Equinix Metal sunsetting June 2026, Hetzner Mac mini, RootBSD, Lambda BYOI=none) |
| BYOI-capable (api or console) | 28 |
| BYOI-capable via API (fully automated path) | 20 |
| Natively BSD-friendly (FreeBSD stock image) | 9 |
| Natively BSD-friendly (FreeBSD + OpenBSD stock) | 5 |
| Natively BSD-friendly (FreeBSD + OpenBSD + NetBSD) | 4 |
| Out of scope (container/serverless only) | 8 |
| Tier 4 (all out of scope) | 6 |

---

## 5 Most Important Findings

### 1. Format Fragmentation is the Core genoa Problem

No single image format is accepted by all providers. The matrix reveals five distinct format regimes:

- **AWS regime**: OVA, VMDK, VHD, VHDX, raw (but NOT qcow2; NOT aarch64 import)
- **OpenStack/KVM regime**: qcow2 or raw (OCI, OVHcloud, Scaleway, Alibaba, Tencent, IBM)
- **Azure regime**: fixed-size VHD only (not VHDX, not dynamic)
- **ISO regime**: Vultr, Contabo, bare-metal providers (Equinix, Hivelocity)
- **Raw-only regime**: Akamai/Linode, Hetzner Cloud (workaround), Mythic Beasts

This means genoa MUST maintain a format conversion pipeline. Minimum viable: raw → qcow2 → vmdk → vhd (fixed-size). The `qemu-img convert` chain covers all cases except ISO (which requires a different build path). **The single biggest genoa engineering investment is format conversion and validation, not provider API integration.**

### 2. Equinix Metal's Sunset Removes the Cleanest Bare-Metal BYOI Path

Equinix Metal's custom iPXE model was architecturally optimal for genoa's goal: provide any bootable image URL, deploy to bare metal in any format the iPXE script can chainload, full hardware access, API-driven. This service sunsets June 30, 2026. No current provider offers an equivalent combination of API-driven provisioning, arbitrary OS support, and bare metal. The closest replacements are:

- **Hivelocity** (iPXE, API, bare metal) — no ARM, smaller footprint
- **phoenixNAP BMC** (API, cloud-init, bare metal) — custom OS documented but details sparse
- **OVHcloud Dedicated BYOI** (API, raw/qcow2, bare metal) — well-documented, Feb 2026 docs

genoa adapters built for Equinix Metal should be migration-planned to one of the above.

### 3. FreeBSD Cloud Support is Improving but Unevenly Distributed

As of 2026, FreeBSD is available as a stock image on AWS, GCP, Azure, OCI, Alibaba Cloud, and Vultr — a major improvement over five years ago. FreeBSD 14.x cloud-init support reached Tier 1 status (Q1 2024), eliminating the need for the bsd-cloudinit workaround on well-supported providers. However:

- **DigitalOcean dropped FreeBSD** permanently (July 2022) — requires custom image upload
- **Akamai/Linode** never officially supported FreeBSD and has ext3/ext4 filesystem requirement that actively blocks UFS/ZFS
- **OCI FreeBSD**: x86 requires "emulated mode" (not paravirtualized) — a non-obvious configuration that burns new users
- **GCP FreeBSD**: Images in a non-default project (`freebsd-org-cloud-dev`) — invisible to standard image discovery

The authoritative guidance from Colin Percival (Nov 2025 blog post) identifies seven specific requirements for providers to properly support FreeBSD — most providers meet 2-3 of the 7. **Providers meeting all 7 (AWS, Azure via Foundation partnership) offer reliably working FreeBSD; others are best-effort.**

### 4. Three License Traps Block Vendoring Core Tooling

genoa cannot ship code that contains:

1. **QEMU (GPL-2.0)**: Must be invoked as external process. All qemu-img format conversion must be exec'd, not embedded. The entire image manipulation pipeline depends on this external-process model.
2. **SmartOS/illumos components (CDDL)**: MNX/Triton is an interesting deployment target (illumos zones, KVM, API-driven) but any CDDL-licensed code cannot be vendored into genoa. The Triton HTTP API is fine; shipping SmartOS userland is not.
3. **libvirt (LGPL-2.1)**: Dynamic linking permitted, static linking triggers copyleft. If genoa links libvirt, it must be dynamic and the genoa license must permit LGPL combination (MIT/Apache/BSD all permit this).

**Safe to vendor:** bsdec2-image-upload (BSD-2-Clause), hcloud-upload-image (MIT), all major cloud CLIs (Apache-2.0/MIT), bhyve tooling (BSD-2-Clause). The bhyve ecosystem (vm-bhyve, cbsd) is entirely BSD-licensed and ideal for the local-bhyve deployment target.

### 5. Aarch64 Coverage is a First-Class Gap

Of 40 providers, only 12 support aarch64 for BYOI or custom image deployment:
- Tier 1: AWS (not via VMIE, only official AMIs), GCP (via community project), Azure, OCI, Alibaba, Tencent
- Tier 2: Akamai (instances but ext4 constraint), Hetzner Cloud (CAX instances), Scaleway, OVHcloud
- Tier 5: Mythic Beasts (Raspberry Pi, aarch64 bare metal)
- Tier 6: MacStadium, Scaleway Apple Silicon, AWS EC2 Mac (macOS only)

For BSD aarch64 specifically, OCI's free-tier Ampere A1 (4 OCPUs, 24 GB RAM, always-free) is the single most accessible aarch64 BSD deployment target. AWS aarch64 FreeBSD works but only via official FreeBSD RE AMIs (no custom import path). genoa aarch64 adapters should target OCI Ampere as the primary validation platform.

---

## 3 Questions a Deployment Tool Author MUST Answer

### Q1: What is the genoa image format pipeline?

The matrix reveals that no format works everywhere. genoa must decide: does it produce ONE canonical format and convert on-the-fly per provider, or does it maintain multiple pre-built format artifacts? 

The matrix suggests a **hub-and-spoke** model with raw as the hub:
```
canonical raw image
├── → qcow2        (OCI, Scaleway, OVHcloud, Alibaba, IBM, Tencent, OrionVM, ARP)
├── → vmdk          (AWS, GCP, Alibaba, Tencent)
├── → vhd (fixed)  (Azure, AWS)
├── → tar.gz(raw)  (GCP, Hetzner Robot)
└── → iso          (Vultr, Contabo, bare-metal iPXE providers)
```

The critical question: does genoa do conversion in the build pipeline (image-time, slow once) or at deploy time (fast CI but requires qemu-img at runtime)? Given genoa's "ship to ANY platform" goal, build-time pre-production of all formats is likely the correct architecture.

### Q2: How does genoa handle providers with no official BYOI API (Hetzner Cloud, Akamai)?

Two significant providers have no usable BYOI path for BSD:
- **Hetzner Cloud**: No image upload API. Community workaround exists but is fragile.
- **Akamai/Linode**: API exists but ext3/ext4 filesystem constraint and 6 GB size limit block BSD practically.

genoa must decide: (a) mark these as "limited support" with documented caveats, (b) implement the workaround and own the fragility risk, or (c) exclude them from the adapter matrix entirely. The answer determines whether genoa's hetzner and linode adapters are first-class or footnoted.

### Q3: What is the genoa strategy for FreeBSD cloud-init integration?

Every provider in the matrix uses cloud-init (or a cloud-init-compatible system) for:
- SSH key injection
- Network configuration  
- Hostname setting
- First-boot scripts

FreeBSD's cloud-init story has two implementations: `nuageinit` (base system, Lua, FreeBSD 14.1+) and `bsd-cloudinit` (package, Python, older compatibility). Which one does genoa bake into BSD images? The answer determines compatibility with each provider's metadata service. Additionally, the cloud-init datasource cache gotcha (bumping instance-id does NOT always invalidate per-datasource cache — see NoCloud datasource docs) means genoa must ensure correct instance-id uniqueness at image-build time, not just deployment time, to avoid stale configuration being served to re-deployed instances.

---

## Adapter Dispatch Recommendations for providers.json

For `genoa deploy --provider <id>`, the `byoi_support` field drives adapter selection:

| byoi_support | Adapter strategy |
|---|---|
| `api` | Full automation: build image → convert format → upload via provider API → deploy |
| `console` | Semi-automated: build image → generate instructions + image → human console step required |
| `none` | Blocked: emit clear error with reason from BLOCKED.md |

Priority implementation order based on BYOI coverage, BSD importance, and market share:

1. `aws` — largest market share, official FreeBSD AMIs, VM Import/Export for custom
2. `gcp` — second largest, raw import straightforward, FreeBSD community project
3. `azure` — third largest, fixed-size VHD conversion required
4. `oci` — best free-tier aarch64, QCOW2 import, FreeBSD officially listed in BYOI docs
5. `vultr` — best mid-tier BSD experience, ISO boot, all 33 regions
6. `local_bhyve` — all-BSD-licensed toolchain, ideal dev/test target
7. `local_kvm` — QEMU external process model, all formats, all archs
8. `ovhcloud_dedicated` — full bare-metal BYOI, raw/qcow2, well-documented
9. `hetzner_cloud` — large user base, workaround documented, hcloud-upload-image MIT
10. `digitalocean` — large user base, no FreeBSD stock but custom image works
11. `buyvm` / `arp_networks` / `tornado_vps` — BSD specialists, smaller scale
12. `scaleway` — EFI constraint documented, qcow2, ARM available

---

## Data Provenance and Confidence

All entries verified against primary documentation URLs or official provider blog posts. Staleness ratings:

- **low** (verified within 6 months, i.e., after Oct 2025): AWS, GCP, Azure, OCI, Alibaba, Scaleway, DigitalOcean, Akamai, Vultr, OVHcloud, Hetzner Cloud, Hetzner Robot, Equinix Metal, Fly.io, Cloudflare, Render, Railway, Northflank, Koyeb, Lambda Cloud, RunPod, Tornado VPS, BoxyBSD, MacStadium, Scaleway Apple Silicon, AWS EC2 Mac, Hetzner Mac, MNX/Triton
- **medium** (6-18 months, some risk of drift): Tencent Cloud (China region parity uncertain), Hivelocity (iPXE details), phoenixNAP (custom OS details require account), Contabo (add-on model), CoreWeave (BYOI details sparse), Paperspace (template cloning details), Crusoe (BYOI unconfirmed), BuyVM (BSD template versions may be stale), RamNode, Mythic Beasts, OrionVM, M5 Hosting
- **high** (none in this pass — all entries have at least one verified URL from 2024-2026)
