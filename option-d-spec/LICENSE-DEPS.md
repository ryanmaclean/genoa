# LICENSE-DEPS.md — Dependency License Inventory

All runtime dependencies of the genoa conformance tools are listed here.
genoa policy: MIT, BSD-2-Clause, BSD-3-Clause, or Apache-2.0 only. No GPL/LGPL/AGPL.

---

## Nushell (runtime for probe.nu and validate.nu)

- **License**: MIT
- **Source**: https://github.com/nushell/nushell
- **Version**: >= 0.100.0
- **Use**: Script runtime for conformance/probe.nu and conformance/validate.nu
- **Distribution**: Not bundled. Must be installed separately by the user.

## JSON Schema 2020-12

- **License**: BSD-2-Clause (JSON Schema specification itself is freely usable)
- **Source**: https://json-schema.org/draft/2020-12
- **Use**: Schema vocabulary used in all schemas/*.v1.json files
- **Distribution**: Vocabulary reference only, not bundled code.

## Optional: jsonschema-rs CLI (for production schema validation)

- **License**: MIT
- **Source**: https://github.com/Stranger6667/jsonschema-rs
- **Version**: Any (0.20+)
- **Use**: Optional external JSON Schema 2020-12 validator for stricter validation than the built-in Nushell checks
- **Install**: `cargo install jsonschema-cli` or `brew install jsonschema`
- **Distribution**: Not bundled.

## Optional: AJV (Alternative JS JSON Schema validator)

- **License**: MIT
- **Source**: https://github.com/ajv-validator/ajv
- **Version**: >= 8.x (for JSON Schema 2020-12 support)
- **Use**: Alternative validator for Node.js environments
- **Distribution**: Not bundled.

---

## Referenced Specifications (Not Code Dependencies)

These are spec references, not runtime code. Listed for completeness.

| Spec | License | URL |
|------|---------|-----|
| in-toto v1 | Apache-2.0 | https://github.com/in-toto/attestation |
| SLSA v1.0 | Apache-2.0 | https://slsa.dev |
| MCP 2025-11-05 | MIT | https://modelcontextprotocol.io |
| OCI Image Spec | Apache-2.0 | https://github.com/opencontainers/image-spec |
| SPDX 2.3 | CC-BY-3.0 | https://spdx.github.io/spdx-spec/v2.3/ |
| RFC 8615 | IETF | https://datatracker.ietf.org/doc/html/rfc8615 |

Note: SPDX 2.3 specification is licensed CC-BY-3.0 (the specification text).
The SPDX format itself is freely implementable. genoa only references SPDX IDs —
it does not bundle or redistribute the SPDX specification.

---

## Spec Documents (spec/genoa-v1.md and RELATED-SPECS.md)

Licensed Apache-2.0 to allow embedding in attestations and broader tool ecosystems.
See LICENSE file for the BSD-2-Clause license covering conformance code.
