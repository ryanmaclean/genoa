# R3 Report: Image Formats and Boot Paths for Genoa-Deploy

**Agent:** R3 (Image Formats and Boot Paths)
**Date:** 2026-04-30
**Working directory:** `/Users/studio/genoa/research-r3-formats/`

---

## Executive summary

Genoa needs **5 output formats** and **4 active boot paths** (plus 1 manual
fallback) to cover 90% of cloud providers and deployment scenarios. The raw
image from Genoa-A is the canonical artifact — everything else is derived.

---

## Part 1: Output formats needed

### Minimum viable set (covers ~90% of public cloud providers)

| # | Format | Providers | Conversion from raw |
|---|--------|-----------|-------------------|
| 1 | **raw** | DigitalOcean, Hetzner (rescue target), Linode, Vultr, bare-metal | Identity — no conversion |
| 2 | **gce-tar** (`disk.raw` in `.tar.gz`) | Google Cloud | `cp + tar -czvf` |
| 3 | **vhd-fixed** | Azure (Gen1) | `qemu-img convert -O vpc -o subformat=fixed` + 1 MiB alignment |
| 4 | **vmdk-streamOptimized** | VMware vSphere, VMware Cloud | `qemu-img convert -O vmdk -o subformat=streamOptimized` |
| 5 | **qcow2** | OpenStack (Glance), Proxmox, UpCloud | `qemu-img convert -O qcow2 -c` |

### Secondary / deferred formats

| Format | Deferred reason |
|--------|----------------|
| vhdx | Azure Gen2; vhd-fixed covers Gen1. Add after Gen1 works. |
| ova | Enterprise VMware; wraps vmdk-streamOptimized with OVF XML. High effort, low cloud priority. |
| vdi | VirtualBox local only. Dev tool. No cloud provider accepts it. |
| ami | Not a format — AWS builds AMI from raw via import-snapshot + register-image |

### Key constraint: qemu-img is GPL-2.0-only

Invoke as an external subprocess only. Never link or vendor. This is the
established pattern (same as git, rsync): the GPL does not propagate across
the exec() boundary.

### Reproducibility

No derived format (qcow2, VMDK, VHD, VHDX) is bit-for-bit reproducible across
conversions — metadata fields (UUID, timestamps) are non-deterministic. Always
compute and publish the SHA256 of the `.raw` source as the canonical hash.
Hash the raw, not the derived format.

---

## Part 2: Boot paths implemented

### Active paths (implement in priority order)

| Priority | Path | Status | Providers covered |
|----------|------|--------|------------------|
| 1 | **Path 0: BYOI Direct Upload** | Implement first | AWS, GCP, Azure, DO, Linode, OCI, Scaleway |
| 2 | **Path 3: Rescue + dd** | Implement second | Hetzner Cloud, Equinix Metal, OVH, Vultr fallback |
| 3 | **Path 1: Snapshot from URL** | Implement third | Vultr, Exoscale, some DO workflows |
| 4 | **Path 4: Rescue + chroot fixup** | Implement fourth | Same as Path 3 + providers with non-standard IMDS |

### Fallback (document, do not automate)

| Path | Status |
|------|--------|
| **Path 2: Console ISO mount** | MANUAL ONLY — document as operator procedure |

### Rejected

| Path | Status |
|------|--------|
| **Path 5: kexec Linux→BSD** | RESEARCH ONLY — not v1. depenguinator-3 is unmaintained. Multiboot 2 support in Linux kexec is incomplete. |
| **QEMU-in-rescue** | REJECTED — wasteful. Not the depenguin pattern. User has explicitly excluded this. |

---

## Part 3: The 5 highest-value (path, provider) pairs to implement first

These five pairs maximize provider coverage per unit of implementation effort:

### 1. (Path 0, AWS) — FreeBSD via bsdec2-image-upload

**Why first:** AWS is the largest cloud. `bsdec2-image-upload` (BSD-2-Clause)
already handles the full FreeBSD AMI lifecycle: S3 upload → import-snapshot →
register-image → AMI copy to regions. It is proven in FreeBSD's own release
engineering. Wrap it in `genoa image push aws`.

**Format:** raw → S3 → EBS snapshot
**Effort:** 2-3 days (wrap existing tool, add polling, integrate with genoa CLI)

---

### 2. (Path 0, GCP) — FreeBSD via gcloud

**Why second:** GCP is the second-largest public cloud. The conversion
(raw → disk.raw → image.tar.gz) is trivial. `gcloud compute images create`
with `--source-uri` is a single API call. GCE UEFI support is mature.

**Format:** raw → gce-tar → GCS → `gcloud compute images create`
**Effort:** 2 days (gce-tar builder + GCS upload + gcloud wrapper)

---

### 3. (Path 3, Hetzner Cloud) — Universal rescue trampoline

**Why third:** Hetzner Cloud has no BYOI API, is widely used in the open-source
community, and has a clean rescue API (`hcloud server enable-rescue`). Implementing
Path 3 for Hetzner also validates the rescue+dd infrastructure that will be
reused for OVH, Equinix, and any future provider without a BYOI API.

**Format:** raw (published to R2/S3) → rescue curl → dd
**Effort:** 3-4 days (Hetzner API adapter, SSH executor, polling, publish step)

Note: Hetzner uses Hetzner IMDS at `http://169.254.169.254/hetzner/v1/`
(compatible with the standard path prefix but Hetzner-specific metadata schema).
After Path 3 works, Path 4 (chroot SSH key injection) is a 1-day add-on if the
BSD IMDS agent doesn't yet handle Hetzner's metadata schema.

---

### 4. (Path 0, Azure) — vhd-fixed via az CLI

**Why fourth:** Azure is the third major cloud. The tricky part is the 1 MiB
alignment requirement for VHD. Once the alignment logic is correct, the upload
itself is straightforward (`az disk create` or page blob upload). Gen1 VHD-fixed
covers the widest Azure VM surface.

**Format:** raw → qemu-img resize (align to MiB) → qemu-img convert (vpc/vhd-fixed) → az upload
**Effort:** 3 days (alignment math, VHD conversion, Azure CLI wrapper)

---

### 5. (Path 1, Vultr) — Snapshot from URL

**Why fifth:** Vultr is popular in the BSD community and its snapshot-from-URL
API is simpler than a full BYOI pipeline. It also validates the `genoa publish`
step (R2 or S3 hosting), which is a prerequisite for Path 3 as well. Implementing
Path 1 for Vultr forces the publish infrastructure into existence, benefiting all
other paths.

**Format:** raw → published to R2 → Vultr `/v2/snapshots/create-from-url`
**Effort:** 2 days (R2 publish step + Vultr API adapter + polling)

---

## Part 4: What genoa-deploy must implement

### Core shared infrastructure

1. **Format converter** — wraps `qemu-img convert` as subprocess; per-format adapters
2. **genoa publish** — uploads artifact to R2/S3/B2/Gitea, returns URL + SHA256 manifest
3. **Async poller** — generic poll-until-complete for provider import jobs
4. **SSH executor** — runs scripts in rescue environment (for Paths 3/4)
5. **Provider adapter interface** — typed interface that each provider implements

### Per-provider adapters (v1 scope)

| Provider | Path | Adapter surface |
|----------|------|----------------|
| AWS | 0 | `bsdec2-image-upload` wrapper + S3 upload + AMI copy |
| GCP | 0 | GCS upload + `gcloud compute images create` |
| Azure | 0 | VHD alignment + page blob upload + `az image create` |
| DigitalOcean | 0 | `doctl compute image create` with URL |
| Linode | 0 | `linode-cli images upload` |
| Hetzner Cloud | 3/4 | `hcloud` API: rescue enable/disable + SSH executor |
| Vultr | 1 | R2 publish + `/v2/snapshots/create-from-url` + poll |

---

## Critical non-obvious findings

1. **No path uses iPXE.** All paths use either provider BYOI APIs, provider
   rescue boot (provider-managed, no iPXE dependency), or HTTPS-based image
   transfer. The iPXE (GPL-2) constraint is fully satisfied.

2. **QEMU is never in the deployment critical path.** It is used only for format
   conversion (subprocess). No QEMU-as-emulator in any path.

3. **Hetzner is the canonical Path 3 target** — it is the most popular
   "no BYOI API" provider. Implementing Path 3 for Hetzner makes it work for
   OVH, Equinix, and others with minimal additional work.

4. **The publish step is shared infrastructure** — Paths 1, 3, and 4 all require
   `genoa publish`. Cloudflare R2 (zero egress, S3-compat) is the recommended
   default backend. Build this early.

5. **Firecracker / Fly.io is out of scope** — Firecracker does not run BSD
   kernels. A "Linux kernel + BSD userland" approach is not the Genoa design
   target. Mark these providers as explicitly unsupported.

6. **ZFS root images complicate Path 4** — mounting ZFS from rescue Linux
   requires matching OpenZFS feature flags. Genoa-A should use a conservative
   feature set, or Path 4 chroot should prefer UFS2 root for Path 3/4 targets.

7. **AMI is not a format** — it is a cloud construct built from a raw EBS
   snapshot. The upload artifact for AWS is always `.raw`; the AMI is the output
   of the registration step.

---

## Deliverables index

| File | Contents |
|------|----------|
| `format-conversion.json` | Machine-readable format matrix |
| `format-conversion.md` | Conversion quirks and gotchas |
| `path-00-byoi.md` | Path 0: BYOI Direct Upload |
| `path-01-snapshot-url.md` | Path 1: Snapshot from URL |
| `path-02-console-iso.md` | Path 2: Console ISO mount (manual) |
| `path-03-rescue-dd.md` | Path 3: Rescue + dd |
| `path-04-rescue-chroot.md` | Path 4: Rescue + chroot fixup |
| `path-05-kexec.md` | Path 5: kexec (research only, not v1) |
| `decision-tree.dot` | Graphviz decision tree source |
| `decision-tree.md` | Decision tree as worked examples table |
| `publish-step.md` | Hosting options for genoa publish |
| `R3-REPORT.md` | This file |
