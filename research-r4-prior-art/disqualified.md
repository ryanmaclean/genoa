# Genoa Disqualified Tools

These tools are explicitly excluded from genoa's dependency graph. The license column
gives the disqualifying identifier. "Invoke-only" means we may call the binary as an
external process (no vendoring, no import, no linking) — the license obligation does
not attach to genoa's own code in that case.

---

## BUSL-1.1 — Business Source License (HashiCorp)

| Tool | URL | Notes |
|------|-----|-------|
| HashiCorp Packer | https://github.com/hashicorp/packer | Industry standard image builder. BUSL-1.1 since 2023. Converts to MPL-2.0 after 4 years, but that is too far out and MPL itself is borderline. genoa is the BSD-native replacement for this niche. |
| HashiCorp Vagrant | https://github.com/hashicorp/vagrant | BUSL-1.1 since 2023. Vagrant box format is a useful output target but the toolchain cannot be vendored. |

Rationale: BUSL-1.1 restricts production use without a commercial license and is
explicitly not OSI-approved. Hard disqualified.

---

## LGPL-2.0 / LGPL-2.1 / LGPL-3.0 — GNU Lesser General Public License

| Tool | URL | Notes |
|------|-----|-------|
| mkosi | https://github.com/systemd/mkosi | LGPL-2.1-or-later. Excellent Linux image builder (systemd ecosystem). Can be invoked as an external subprocess for Linux base targets but cannot be vendored or statically linked. |
| virt-install (libvirt) | https://github.com/virt-manager/virt-manager | LGPL-2.0+. Invoke-only for local testing. |
| NixOS / nix binary | https://nixos.org | nix itself is LGPL-2.1. nixpkgs (MIT) is safe. Never vendor or link the nix binary. |

Rationale: LGPL requires that users be able to relink against a modified version of
the library. For statically-linked Rust/Zig binaries this is incompatible with
genoa's distribution model. External invocation is permitted.

---

## GPL-2.0 / GPL-3.0 — GNU General Public License

| Tool | URL | Notes |
|------|-----|-------|
| Yocto / OpenEmbedded toolchain | https://www.yoctoproject.org | Most tools (bitbake, meta-layers) are GPL-2.0. Project framework is MIT but the toolchain you'd actually run is GPL. Linux-only anyway. |
| QEMU | https://www.qemu.org | GPL-2.0. Invoke-only for local VM testing. Never vendor. FreeBSD ports tree ships it but genoa does not embed it. |
| cloud-init (GPL-3 files) | https://github.com/cloud-init/cloud-init | Dual-licensed GPL-3/Apache-2.0. Per-file. Some files are GPL-3 only. Vendoring any GPL-3 file is disqualified. See license-questions.md for the Apache-2.0 path. |

---

## MPL-2.0 — Mozilla Public License (borderline, not hard-approved)

| Tool | URL | Notes |
|------|-----|-------|
| OpenTofu | https://github.com/opentofu/opentofu | MPL-2.0. OSI-approved but copyleft at the file level. NOT on genoa's hard-allowed list (MIT/BSD-2/BSD-3/Apache-2.0). Requires explicit user approval before use. See license-questions.md. |
| Vector | https://github.com/vectordotdev/vector | MPL-2.0. Same analysis as OpenTofu. Excellent log pipeline tool but cannot be vendored without user approval. Fluent Bit (Apache-2.0) is the approved substitute. |

---

## Rejected-by-design (license is fine, architecture is wrong)

| Tool | URL | Notes |
|------|-----|-------|
| depenguin-me | https://github.com/depenguin-me/depenguin-run | MIT license — not a license problem. Rejected because it uses the trampoline pattern (boots mfsBSD inside Linux rescue env via QEMU to install FreeBSD). genoa builds native images directly; trampolines are out of scope by design. |

---

## Summary

| Category | Count | Action |
|----------|-------|--------|
| BUSL-1.1 (hard disqualified) | 2 | Do not use at all |
| LGPL (no vendoring) | 3 | Invoke-only permitted |
| GPL (no vendoring) | 3 | Invoke-only for dev tools; cloud-init Apache-2.0 path needs review |
| MPL-2.0 (borderline) | 2 | Needs explicit user approval; approved substitutes exist |
| Rejected-by-design | 1 | License is fine; architecture is wrong |
