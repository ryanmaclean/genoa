# Genoa Recommended Dependencies

For each role genoa needs, one recommended tool with rationale. All tools here are
on the approved license list (MIT / BSD-2 / BSD-3 / Apache-2.0).

---

## Role: Raw disk image creation (FreeBSD/NetBSD path)

**Recommended: `makefs` + `mkimg` (FreeBSD base, BSD-2-Clause)**

Both are already in FreeBSD base. `makefs` builds the filesystem image without root
privileges; `mkimg` wraps it in a partitioned disk image with the correct GPT/MBR
layout. Invoke as external subprocesses. Do not reimplement — the FreeBSD release
engineering team has hardened these for exactly this use case.

Reference: `smolBSD` (NetBSDfr) uses the same substrate on the NetBSD side.

---

## Role: AWS AMI upload and registration (FreeBSD images)

**Recommended: `bsdec2-image-upload` (BSD-2-Clause, Colin Percival)**

Purpose-built for FreeBSD AMI registration. Handles S3 multipart upload, snapshot
creation, and AMI registration in one tool. Written in C — minimal runtime
dependency. Last commit 2026-01; actively used by the FreeBSD project itself.

For non-FreeBSD images on AWS, fall back to `aws ec2 import-image` (Apache-2.0).

---

## Role: GCP image upload

**Recommended: `gcloud compute images import` (Apache-2.0 / Google Cloud SDK)**

Standard mechanism for GCP custom image import. Invoke as external subprocess.
`daisy` (Apache-2.0) can orchestrate multi-step GCP workflows if genoa needs
workflow-level control (e.g., conversion + import + test in one pipeline).

---

## Role: OCI (Oracle Cloud) image upload

**Recommended: `oci-cli` with Apache-2.0 path (UPL-1.0 OR Apache-2.0)**

Dual-licensed; select Apache-2.0 explicitly. See `license-questions.md` for
the UPL-1.0 analysis — Apache-2.0 path is safe. Invoke as external subprocess.

---

## Role: DigitalOcean image upload

**Recommended: `doctl` (Apache-2.0)**

Official DO CLI. Active. Custom image upload via `doctl compute image create`.

---

## Role: Linode image upload

**Recommended: `linode-cli` (BSD-3-Clause)**

Official Linode/Akamai CLI. Active. BSD-3 is on the approved list.

---

## Role: Hetzner image upload

**Recommended: `hcloud-cli` (MIT)**

Official Hetzner CLI. Note: Hetzner does not support arbitrary OS image upload the
same way AWS/GCP do — use server snapshots or Hetzner's server rebuild API.
genoa's Hetzner adapter should document this constraint explicitly.

---

## Role: Vultr image upload

**Recommended: `vultr-cli` (Apache-2.0)**

Official Vultr CLI. Active. Custom ISO/image upload supported.

---

## Role: Scaleway image upload

**Recommended: `scaleway-cli` / `scw` (Apache-2.0)**

Official Scaleway CLI. Active.

---

## Role: IaC / infrastructure orchestration (post-image registration)

**Recommended: `Pulumi` (Apache-2.0)**

Apache-2.0, actively maintained. genoa should not vendor Pulumi but can generate
Pulumi programs as optional output artifacts (e.g., a Pulumi stack that deploys
the registered image). OpenTofu (MPL-2.0) is NOT on the hard-approved list without
an explicit user decision.

---

## Role: First-boot configuration (Linux targets)

**Recommended: `cloud-init` with Apache-2.0 file selection**

cloud-init is the de facto standard. Dual-licensed GPL-3/Apache-2.0. genoa must
only touch Apache-2.0-licensed files if vendoring. For BSD targets, bsdinstall
scripts + rc.conf patterns are preferred (no cloud-init required on FreeBSD/NetBSD
if using the FreeBSD cloud-init port built against Apache-2.0 paths).

See `license-questions.md` for the detailed assessment.

**Important cloud-init gotcha:** The NoCloud datasource caches per-datasource.
Bumping `instance-id` does NOT always invalidate the cache on subsequent boots.
genoa must set a unique `instance-id` at image build time AND document that
operators must not reuse seed ISOs across instance lifecycles.
Reference: https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html

---

## Role: First-boot configuration (CoreOS / Flatcar Linux targets)

**Recommended: `ignition` (Apache-2.0)**

Apache-2.0, actively maintained. For CoreOS/Flatcar targets, genoa should generate
ignition configs rather than cloud-init userdata.

---

## Role: SBOM generation

**Recommended: `syft` (Apache-2.0, Anchore)**

Best-in-class SBOM generator; outputs SPDX and CycloneDX. Apache-2.0, very active.
Invoke post-build: `syft packages file:<image.raw> -o spdx-json`.
Validate output with `spdx-tools` (also Apache-2.0).

---

## Role: Artifact signing and attestation

**Recommended: `cosign` (Apache-2.0, Sigstore)**

Sign genoa-produced image manifests and SBOM documents. Apache-2.0, actively
maintained by the Linux Foundation's Sigstore project. Pairs with `in-toto`
for supply chain provenance (also Apache-2.0).

---

## Role: Log shipping from genoa-baked images

**Recommended: `Fluent Bit` (Apache-2.0)**

Apache-2.0, active, small binary footprint. Preferred over Vector (MPL-2.0, pending
license decision) and Fluentd (Apache-2.0 but heavier). Fluent Bit has BSD package
support via pkgsrc / FreeBSD ports.

---

## Role: Local testing / CI smoke-test

**Recommended: `virt-install` / `qemu-system` (LGPL / GPL — invoke only)**

Do not vendor. Invoke as external subprocess for local image smoke tests.
libvirt's `virt-install` is LGPL; `qemu` is GPL. Both may be invoked as system
commands without triggering license obligations on genoa's own code.
