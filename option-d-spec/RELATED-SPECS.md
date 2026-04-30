# RELATED-SPECS.md — What genoa References vs. What's Net New

SPDX-License-Identifier: Apache-2.0

This document is required for honest disclosure about genoa's composition.
genoa is ~70% composition of existing specs, ~30% net-new glue contract.

---

## Specs We Reference (Do Not Redefine)

### in-toto Attestation Framework v1.0
- **Source**: https://github.com/in-toto/attestation/blob/v1.0/spec/v1.0/statement.md
- **License**: Apache-2.0
- **What we use**: The `Statement` envelope verbatim: `_type`, `subject` (ResourceDescriptor), `predicateType`, `predicate` fields. We did not modify the envelope.
- **What we add**: The `predicateType: "https://genoa.dev/AgentHost/v1"` predicate definition and its required fields (`image_identity`, `capability_claims`, `slsa_level`, `sbom_digest`). This is a new in-toto predicate, not a reimplementation of the framework.
- **Honest delta**: We wrote a JSON Schema for our predicate. The framework itself is borrowed wholesale.

### SLSA v1.0 (Supply-chain Levels for Software Artifacts)
- **Source**: https://slsa.dev/spec/v1.0/
- **License**: Apache-2.0
- **What we use**: Build Level integer taxonomy (L0-L3 mapping), `buildEnvironment` field names, `builder_id` URI convention, `resolved_dependencies` ResourceDescriptor pattern.
- **What we add**: Nothing. We reference SLSA levels in our conformance levels (L1/L2/L3 does NOT equal SLSA L1/L2/L3 — our levels are genoa-specific but SLSA slsa_level is a field within our attestation predicate).
- **Honest delta**: Zero new SLSA concepts. We reference and expose existing SLSA levels.

### MCP (Model Context Protocol) 2025-11-05
- **Source**: https://modelcontextprotocol.io/specification/2025-11-05/server/tools
- **License**: MIT
- **What we use**: The `Tool` object shape: `name` (string, pattern), `description` (string), `inputSchema` (JSON Schema object). The `tools/list` and `tools/call` protocol conventions.
- **What we add**: The `provenance` object (source, trust, package_id, attestation_ref, added_at, added_by). The `annotations` map. The `deprecated`/`alternatives` fields.
- **Honest delta**: ~30 lines of net-new schema on top of MCP tool shape. The provenance field is genuinely new — MCP has no supply-chain concept.

### OCI Image Spec
- **Source**: https://github.com/opencontainers/image-spec/blob/main/image-index.md
- **License**: Apache-2.0
- **What we use**: `platform.os` enum values (freebsd, netbsd, openbsd, linux, windows), `platform.architecture` enum values (amd64, arm64, riscv64, etc.). The `sha256:` digest format convention.
- **What we add**: Nothing. We adopt OCI conventions verbatim to ensure compatibility with OCI-aware tooling.
- **Honest delta**: Zero new OCI concepts.

### SPDX 2.3 (Software Package Data Exchange)
- **Source**: https://spdx.github.io/spdx-spec/v2.3/
- **License**: Creative Commons Attribution 3.0
- **What we use**: SPDXID naming convention for capability.provenance.package_id cross-references. The SBOM external document reference concept for sbom.url.
- **What we add**: Nothing. We reference SPDX IDs — we do not define a new SBOM format.
- **Honest delta**: Zero new SPDX concepts. We make it easy to cross-reference capabilities to their SBOM entries.

### RFC 8615 (Well-Known URIs)
- **Source**: https://datatracker.ietf.org/doc/html/rfc8615
- **License**: IETF (public)
- **What we use**: The `/.well-known/` URI prefix convention for the discovery endpoint.
- **What we add**: The `genoa.json` suffix and its JSON payload schema.
- **Honest delta**: The discovery payload schema is net-new. The well-known URI mechanism is borrowed.

### RFC 2119 (Key Words for Requirement Levels)
- **Source**: https://datatracker.ietf.org/doc/html/rfc2119
- **What we use**: MUST/SHOULD/MAY terminology in the spec.

### HAL (Hypertext Application Language)
- **Source**: https://datatracker.ietf.org/doc/html/draft-kelly-json-hal
- **What we use**: The `links` object pattern in the discovery response for self-describing resource references.
- **What we add**: Nothing formal. We use the pattern loosely, not the full HAL spec.

---

## What's Genuinely Net-New in genoa

1. **The `genoa.toml` manifest format** — a TOML file that ties together image identity (OCI-style), agent runtime (MCP-style), and supply-chain claims (SLSA/in-toto-style) in a single embedded document. No prior spec does this combination.

2. **The `/.well-known/genoa.json` discovery contract** — the specific required fields and the three-call discovery guarantee. RFC 8615 gives us the mechanism; the payload schema is ours.

3. **The `predicateType: "https://genoa.dev/AgentHost/v1"` in-toto predicate** — a new in-toto predicate that combines image identity, capability claims, SLSA level, and SBOM digest. in-toto defines predicates for provenance (SLSA), SPDX, etc. — not for agent host capability claims.

4. **The `capability.provenance` extension to MCP tools** — MCP tool objects have no supply-chain awareness. The provenance.trust field and its three-tier trust model (attested/signed/unverified) is new.

5. **Conformance levels L1/L2/L3 for agent-host images** — a conformance ladder specific to agent-host OS images. SLSA has build-level conformance; OCI has no runtime conformance; MCP has no image-level conformance. This is the composition contract.

6. **The catalog JSON document** — a single machine-readable index of all spec resources enabling cold-start LM discovery. This is new; none of the referenced specs have an equivalent.

---

## Honest 70/30 Assessment

| Category | Percentage | Details |
|----------|------------|---------|
| **Composed** (referenced from existing specs) | ~68% | in-toto Statement envelope, SLSA level taxonomy, MCP tool shape, OCI platform enums, SPDX ID conventions, RFC 8615 well-known URI |
| **Net-new** (genoa-specific contribution) | ~32% | genoa.toml manifest format, discovery payload schema, AgentHost/v1 predicate definition, capability provenance extension, conformance level ladder, catalog document |

This is the right ratio for a composition spec. Specs that reinvent everything they touch are wrong. genoa's value is in the composition — picking the right existing building blocks and specifying the glue contract that ties them together into a cold-start-safe LM interface.

---

## What We Deliberately Did Not Reinvent

- **Signing/key infrastructure**: Deferred to Sigstore + Rekor. We stub signature_verified in the probe and document why.
- **SBOM format**: We reference SPDX/CycloneDX by name and digest. We do not define a new SBOM format.
- **Build provenance**: We reference SLSA buildEnvironment fields. We do not define new build provenance semantics.
- **Agent protocol**: We reference MCP. We do not define a new agent protocol.
- **OS image format**: We reference OCI. We do not define a new image format.
