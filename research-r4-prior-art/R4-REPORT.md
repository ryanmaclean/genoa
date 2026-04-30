# R4 Prior Art Report — genoa-deploy

**Agent:** R4
**Date:** 2026-04-30
**Scope:** Categories A–F (image builders, deploy tools, first-boot, BSD cloud,
attestation, agent stack)
**Working dir:** `/Users/studio/genoa/research-r4-prior-art/`

---

## Executive Summary

Genoa should use **12 tools as direct subprocess invocations** and **6 tools as
approved vendorable dependencies** (libraries or embedded binaries). It should NOT
rebuild 8 things that already exist well. There are 4 open license questions, one
of which (SLSA) is already resolved. The ecosystem is healthy — all critical
tools are actively maintained as of 2026.

---

## What Genoa MUST NOT Rebuild

These are solved problems with good, permissively-licensed implementations:

| What | Why not rebuild | Use instead |
|------|----------------|-------------|
| FreeBSD disk image creation | `makefs` + `mkimg` are in FreeBSD base, battle-tested, no-root | Invoke `makefs`/`mkimg` as subprocesses |
| FreeBSD AMI upload | `bsdec2-image-upload` does this exactly, by Colin Percival | Use as AWS adapter |
| SBOM generation | `syft` is best-in-class, outputs SPDX + CycloneDX | Invoke `syft` post-build |
| Artifact signing | `cosign` + `in-toto` are the SLSA-aligned standard | Invoke `cosign`, embed in-toto provenance |
| Cloud provider CLIs | All major providers have Apache/MIT/BSD CLIs | Invoke as subprocesses per provider |
| Log shipping | `fluent-bit` (Apache-2.0) is small, portable, BSD-friendly | Bake into images |

---

## Direct Subprocess Invocations (invoke, do not vendor)

These tools are invoked at runtime by genoa's orchestration layer. License
obligations do not attach to genoa's own code.

| Tool | License | Provider/Role | Last Active |
|------|---------|--------------|-------------|
| `makefs` | BSD-2-Clause | FreeBSD base — filesystem image | 2026 |
| `mkimg` | BSD-2-Clause | FreeBSD base — disk partitioning | 2026 |
| `bsdec2-image-upload` | BSD-2-Clause | AWS FreeBSD AMI | 2026-01 |
| `aws ec2 import-image` | Apache-2.0 | AWS generic fallback | 2026 |
| `gcloud compute images import` | Apache-2.0 | GCP | 2026 |
| `doctl` | Apache-2.0 | DigitalOcean | 2026 |
| `vultr-cli` | Apache-2.0 | Vultr | 2026 |
| `linode-cli` | BSD-3-Clause | Linode/Akamai | 2026 |
| `hcloud-cli` | MIT | Hetzner | 2026 |
| `scaleway-cli` | Apache-2.0 | Scaleway | 2026 |
| `syft` | Apache-2.0 | SBOM generation | 2026 |
| `cosign` | Apache-2.0 | Image/SBOM signing | 2026 |

**Invoke-only (LGPL/GPL — dev and test use):**
- `qemu-system-*` (GPL-2.0) — local VM testing
- `virt-install` (LGPL-2.0+) — local CI smoke tests
- `mkosi` (LGPL-2.1) — Linux base image testing

---

## Approved Vendorable Dependencies

These can be imported as libraries or embedded in genoa's binary/image. All are
on the hard-approved license list.

| Tool | License | Role |
|------|---------|------|
| `in-toto` | Apache-2.0 | Supply chain provenance attestation |
| `spdx-tools` | Apache-2.0 | SPDX validation |
| `ignition` | Apache-2.0 | First-boot config for CoreOS/Flatcar targets |
| `fluent-bit` | Apache-2.0 | Log shipping baked into genoa images |
| `caddy` | Apache-2.0 | Reverse proxy/TLS for service-capable images |
| `ollama` | MIT | LLM serving for agent-capable images |

---

## What We Are Deliberately Not Using (and Why)

| Tool | License | Reason |
|------|---------|--------|
| Packer | BUSL-1.1 | Hard disqualified; genoa is the BSD-native replacement |
| Vagrant | BUSL-1.1 | Hard disqualified |
| mkosi | LGPL-2.1 | No vendoring; invoke-only for Linux targets |
| NixOS/nix | LGPL-2.1 | No vendoring; nixpkgs (MIT) fine without nix binary |
| Yocto toolchain | GPL-2.0 | Linux-only, no BSD support, GPL toolchain |
| OpenTofu | MPL-2.0 | Not on approved list; Pulumi (Apache-2.0) covers the need |
| Vector | MPL-2.0 | Not on approved list; Fluent Bit (Apache-2.0) covers the need |
| depenguin-me | MIT (fine) | Trampoline pattern rejected by genoa design |
| image-builder (k8s-sigs) | Apache-2.0 | Packer dependency makes it unusable |
| diskimage-builder | Apache-2.0 | Linux-only; plugin model is a reference, not a dep |

---

## Open License Questions (4, need user decision)

See `license-questions.md` for full analysis.

| ID | Tool | Issue | Likely resolution |
|----|------|-------|-----------------|
| LQ-1 | cloud-init | GPL-3/Apache-2.0 per-file dual | Safe if invoke-only (no Python import); needs arch confirmation |
| LQ-2 | OpenTofu | MPL-2.0, not on approved list | Safe if text-output only or external invoke; Pulumi is the alternative |
| LQ-3 | Vector | MPL-2.0, not on approved list | Use Fluent Bit (Apache-2.0) instead; close unless specific feature gap found |
| LQ-4 | oci-cli | UPL-1.0 OR Apache-2.0 dual | Elect Apache-2.0 path; likely no approval needed |

**LQ-5 (SLSA CSL-1.0) is already resolved:** implementing a spec is not a license
obligation. No action needed.

---

## BSD Cloud Image Ecosystem Assessment

The BSD-on-cloud ecosystem is thin but not absent:

- **bsd-cloud-image.org** — community effort; low-resource, worth aligning with
  rather than duplicating. genoa outputs should be compatible with their image format
  conventions.
- **FreeBSD release/Makefile.vm** — the authoritative reference for FreeBSD cloud
  image builds. Read before implementing any Option A step.
- **smolBSD (NetBSDfr)** — user's local reference, BSD-2-Clause, actively maintained
  (2026-04-27). NetBSD path uses the same makefs/mkimg substrate.
- **bsdec2-image-upload** (Percival) — the only purpose-built FreeBSD-to-AMI tool.
  Small C program, BSD-2, should be genoa's AWS adapter.
- **depenguin-me** — MIT but trampoline pattern, explicitly rejected.
- **HardenedBSD** — FreeBSD fork with hardened defaults; reference for security
  image profiles, not a direct dependency.

---

## Architecture Implications for genoa

1. **Option A substrate** is `makefs` + `mkimg` + FreeBSD release tooling. All
   BSD-2-Clause, already in base. Do not reinvent these.

2. **Provider adapters** should be thin wrappers around the provider CLIs listed
   above. Each adapter: validate image format → call provider CLI → parse result →
   emit attestation JSON. No need to speak provider APIs directly.

3. **Attestation pipeline** should be: `syft` (SBOM) → `cosign` sign SBOM →
   `in-toto` provenance envelope → publish to transparency log. All Apache-2.0.

4. **First-boot config** for FreeBSD: `rc.conf` + `loader.conf` + bsdinstall
   scripts. No cloud-init dependency for pure BSD images. cloud-init is for Linux
   targets only — and even then, invoke as a guest package, never vendor.

5. **The cloud-init NoCloud datasource caching gotcha** (from fleet_ledger) must be
   documented in genoa's image build spec: unique `instance-id` per build, warn
   operators not to reuse seed ISOs. See LQ-1 for full context.

6. **genoa should NOT build a Packer plugin.** Packer is BUSL-1.1 and the ecosystem
   is fragmenting post-HashiCorp relicense. genoa is the replacement, not a plugin.

---

## Dormancy Check

No tools in the catalog are dormant (>18 months no activity). The most recent commit
for `bsdec2-image-upload` is 2026-01, which is within the 18-month window. All
other tools had commits in 2026.

---

## Files in This Research Package

| File | Purpose |
|------|---------|
| `inventory.json` | Full machine-readable catalog (47 entries, all categories A–F) |
| `recommended-deps.md` | Single recommended tool per genoa role with rationale |
| `disqualified.md` | Explicit exclusions with license reasons |
| `license-questions.md` | 5 borderline items needing user decisions (1 resolved) |
| `R4-REPORT.md` | This synthesis document |
