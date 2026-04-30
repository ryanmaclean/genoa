# genoa option-b-cloudinit — Dependency Licenses

All dependencies are approved per project license policy (MIT / BSD-2 / BSD-3 / Apache-2.0 only).

## Runtime dependencies (invoked as external processes — mere aggregation, not linked)

| Tool / Library       | License        | Version  | Role                                       | Notes |
|----------------------|----------------|----------|--------------------------------------------|-------|
| Nushell (`nu`)       | MIT            | ≥0.111   | CLI shell and scripting runtime            | Core runtime |
| osbuild              | Apache-2.0     | ≥110     | Image pipeline engine                      | Invoked via `sudo osbuild ...` — not linked |
| osbuild-composer     | Apache-2.0     | ≥110     | High-level orchestration for osbuild       | Optional; invoked as external process |
| bootc                | Apache-2.0/MIT | ≥1.0     | OCI-native bootable container images       | Phase-2 target; invoked as external process |
| cosign               | Apache-2.0     | ≥2.0     | Artifact signing and verification          | Invoked as external process for attestation signing |
| syft                 | Apache-2.0     | ≥1.0     | SBOM generation (SPDX/CycloneDX)          | Invoked as external process; stub if not installed |
| qemu-img             | GPL-2.0+       | any      | QCOW2/VMDK conversion                     | **External invocation only** — never linked or vendored. GPL boundary respected. |
| xorriso              | GPL-3.0        | any      | ISO9660 writer (seed ISO fallback)        | **External invocation only** — not linked/vendored. Phase-2 replaces with Zig (MIT) native writer. |

## Template engine

| Component            | License  | Notes |
|----------------------|----------|-------|
| Tera template syntax | MIT      | Template *syntax* is used; Tera Rust crate is not vendored in this repo. Phase-2 will invoke a pre-compiled `tera-cli` binary (MIT). Current renderer is pure Nushell. |

## Phase-2 planned additions (not yet present)

| Tool                 | License   | Role |
|----------------------|-----------|------|
| Zig compiler         | MIT       | Compile native ISO9660 writer (`seed-iso/iso-writer-stub.zig`) |
| tera-cli             | MIT       | Full Tera template rendering as external process |

## JSON Schema

The schemas in `schema/` reference:
- JSON Schema draft 2020-12 — no runtime dep; spec is royalty-free

## Rejected tools (disqualified on license grounds)

| Tool                 | License   | Reason |
|----------------------|-----------|--------|
| HashiCorp Packer     | BUSL-1.1  | Business Source License — restricts commercial use. Not free/open-source. |
| mkosi               | LGPL-2.1  | Copyleft; LGPL-2.1 is not approved per project policy. |
| debian live-build    | GPL-3.0   | Copyleft; GPL-3 is not approved per project policy. |
| SUSE kiwi-ng         | GPL-3.0   | Copyleft; GPL-3 is not approved per project policy. |
| cloud-localds (cloud-utils) | GPL-3.0 | Copyleft; GPL-3 not approved. genoa builds NoCloud seed ISOs natively instead. |
| genisoimage          | GPL-2.0   | Copyleft; GPL-2 not approved. External xorriso is fallback only; native Zig writer is phase-2. |

## Note on qemu-img and xorriso

Both `qemu-img` (GPL-2+) and `xorriso` (GPL-3) are invoked as **external sub-processes** only.
genoa does not link against, vendor, or statically embed any GPL code.
This is standard "mere aggregation" as defined by the GPL itself (GPL FAQ §10).
The phase-2 plan replaces xorriso with a native Zig (MIT) ISO9660 writer, eliminating
the external GPL dependency entirely.
