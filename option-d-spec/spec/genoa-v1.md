# genoa Agent-Host OS Specification v1.0.0

**SPDX-License-Identifier**: Apache-2.0  
**Status**: Draft  
**Authors**: genoa contributors  
**Date**: 2026-04-30  
**Repository**: https://github.com/ryanmaclean/genoa  
**Catalog**: https://genoa.dev/v1/catalog.json  

---

## 1. Scope

genoa defines a **meta-OS contract** for operating system images that host AI agents. It does not prescribe how an image is built, which OS is used, or which agent framework runs on it. Instead, it specifies:

1. A machine-readable manifest (`genoa.toml`) embedded in the image that declares identity, runtime, capabilities, and supply-chain provenance.
2. A well-known HTTP discovery endpoint (`/.well-known/genoa.json`) served at boot that allows any LM or orchestration system to discover the host's capabilities without prior knowledge.
3. An attestation envelope (in-toto v1 Statement) that carries supply-chain claims about the image.
4. A capability declaration schema that extends MCP tool semantics with provenance fields.
5. Conformance levels (L1/L2/L3) with a machine-runnable probe.

**The primary consumer is an LM or agent runtime, not a human operator.** Every interface is graded by whether an agent dropped in cold can discover it, trust it, invoke it, and compose it with other interfaces in under three tool calls.

### Non-Goals (see Section 9)

genoa does not define: image build pipelines, network topology, inter-agent communication protocols, or agent task scheduling.

---

## 2. Terminology

The key words MUST, MUST NOT, REQUIRED, SHALL, SHOULD, RECOMMENDED, MAY, and OPTIONAL in this document are to be interpreted as described in RFC 2119.

| Term | Definition |
|------|-----------|
| **agent-host image** | An OS image (VM, container, or bare-metal) that runs an agent runtime and serves the genoa discovery endpoint. |
| **genoa.toml** | The TOML manifest file embedded in the image at `/etc/genoa/genoa.toml`. |
| **discovery endpoint** | `GET /.well-known/genoa.json` — the JSON document served at boot that exposes image identity and runtime location. |
| **capability** | A single declared tool/function the agent runtime exposes, conforming to `schemas/capability.v1.json`. |
| **attestation** | An in-toto v1 Statement with `predicateType: "https://genoa.dev/AgentHost/v1"` that makes supply-chain claims about the image. |
| **conformance probe** | `conformance/probe.nu` — the machine-runnable script that verifies a live host's conformance level. |
| **catalog** | `catalog/v1.json` — the single document listing all schemas, examples, and conformance tools. Served at `https://genoa.dev/v1/catalog.json`. |

---

## 3. Manifest (`genoa.toml`)

### 3.1 Location

The manifest MUST be embedded at `/etc/genoa/genoa.toml` in the image filesystem. The image boot process MUST parse this file and serve its contents (as JSON) at `/.well-known/genoa.json`.

### 3.2 Schema

Full schema: `schemas/manifest.v1.json` (JSON Schema 2020-12). Canonical URL: `https://genoa.dev/v1/schemas/manifest.v1.json`.

### 3.3 Required Sections

**`[genoa]`** — Spec version metadata.

```toml
[genoa]
spec_version = "1.0.0"
schema_url   = "https://genoa.dev/v1/schemas/manifest.v1.json"
```

`spec_version` MUST be a SemVer string. Consumers MUST reject manifests where the major version differs from their supported major version.

**`[image]`** — Immutable image identity. Fields mirror OCI Image Index platform fields (see https://github.com/opencontainers/image-spec). Required: `id`, `name`, `version`, `architecture`, `os`.

- `id`: RECOMMENDED to be an OCI sha256 digest (`sha256:<64 hex>`). MAY be a UUID v7.
- `version`: MUST follow SemVer.
- `architecture`: MUST be one of: `amd64`, `arm64`, `riscv64`, `armv7`, `s390x`, `ppc64le`.
- `os`: MUST be one of: `freebsd`, `netbsd`, `openbsd`, `linux`, `windows`.

**`[agent_runtime]`** — Agent execution environment. Required: `type`. `type` MUST be one of: `mcp-server`, `openai-compatible`, `anthropic-compatible`, `custom`.

For `mcp-server` type, `protocol_versions` SHOULD list supported MCP specification dates (e.g. `["2025-11-05"]`). See MCP specification: https://modelcontextprotocol.io/specification

### 3.4 Optional Sections

**`[[capabilities]]`** — Zero or more capability declarations. Each entry MUST conform to `schemas/capability.v1.json`. See Section 6.

**`[attestation_policy]`** — Supply-chain policy declaration. `slsa_level` references SLSA Build Levels (https://slsa.dev/spec/v1.0/levels).

**`[sbom]`** — SBOM reference. `format` MUST be one of: `spdx-2.3`, `cyclonedx-1.5`, `cyclonedx-1.6`. Follows SPDX 2.3 external document reference convention (https://spdx.github.io/spdx-spec/v2.3/).

---

## 4. Discovery Endpoint

### 4.1 Protocol

The image boot process MUST start an HTTP server that responds to:

```
GET /.well-known/genoa.json HTTP/1.1
```

with status 200 and `Content-Type: application/json`. The server SHOULD start within 60 seconds of boot. The endpoint MUST NOT require authentication — it is a public discovery surface.

This follows RFC 8615 (Well-Known URIs). The `.well-known/genoa.json` suffix is registered in the genoa namespace.

### 4.2 Schema

Full schema: `schemas/discovery.v1.json`. Canonical URL: `https://genoa.dev/v1/schemas/discovery.v1.json`.

### 4.3 Required Fields

| Field | Type | Description |
|-------|------|-------------|
| `genoa_version` | SemVer string | genoa spec version implemented |
| `image.id` | string | Image identity digest or UUID |
| `image.name` | string | Image name |
| `image.version` | string | Image version |
| `agent_runtime.type` | enum | Runtime type |
| `agent_runtime.endpoint` | URI | Agent API base URL |
| `catalog_url` | URI | URL to genoa catalog (MUST point to `https://genoa.dev/v1/catalog.json` or a self-hosted mirror) |
| `conformance.level` | enum | Self-reported conformance level: L0, L1, L2, L3 |

### 4.4 Three-Call Discovery Contract

A cold LM MUST be able to discover, understand, and validate a host in at most 3 tool calls:

1. `GET /.well-known/genoa.json` — discover host identity, runtime endpoint, and catalog URL.
2. `GET <catalog_url>` — discover all schema, example, and conformance tool URLs.
3. `GET <schemas.manifest.v1.url>` OR `nu validate.nu manifest <file>` — fetch schema or run validation.

Implementations that require more than 3 calls for initial discovery are non-conformant.

---

## 5. Attestation Envelope

### 5.1 Format

genoa attestations are in-toto v1 Statements. See: https://github.com/in-toto/attestation/blob/v1.0/spec/v1.0/statement.md

```json
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [...],
  "predicateType": "https://genoa.dev/AgentHost/v1",
  "predicate": { ... }
}
```

`predicateType` MUST be exactly `"https://genoa.dev/AgentHost/v1"`. Any other value identifies a non-genoa attestation.

### 5.2 Subject

`subject` MUST contain at least one entry with `digest.sha256` equal to the image's `image.id` sha256 digest. The `name` SHOULD be `<image.name>:<image.version>`.

### 5.3 Predicate Fields

Full schema: `schemas/attestation.v1.json`.

| Field | Required | Description |
|-------|----------|-------------|
| `image_identity` | YES | Frozen snapshot of `[image]` manifest section |
| `capability_claims` | YES | Capability declarations frozen at build time |
| `slsa_level` | YES | SLSA Build Level integer 0-4 |
| `sbom_digest` | YES | sha256 digest of the SBOM document |
| `build_environment` | NO | SLSA v1.0 buildEnvironment summary |
| `signature` | NO | Signing key ID, base64 sig, transparency log entry |

### 5.4 Signing

Signing is RECOMMENDED but not required for L1/L2. For L3, the image MUST be signed. The reference signing mechanism is Sigstore (https://sigstore.dev). The transparency log SHOULD be Rekor (https://rekor.sigstore.dev).

Conformance probes emit `signature_verified: "stub"` when key infrastructure is not present. This is expected behavior for offline or development environments.

### 5.5 SLSA Alignment

`slsa_level` values map directly to SLSA Build Levels:

- 0: No claims
- 1: Provenance exists (not necessarily verified)
- 2: Hosted build platform, verified provenance
- 3: Hardened build platform
- 4: (Reserved — SLSA v1.0 defines L1-L3; L4 reserved for future)

---

## 6. Capability Declarations

### 6.1 Schema

Full schema: `schemas/capability.v1.json`. Canonical URL: `https://genoa.dev/v1/schemas/capability.v1.json`.

### 6.2 MCP Compatibility

The `name`, `description`, and `inputSchema` fields are **MCP tool/list compatible** (https://modelcontextprotocol.io/specification/2025-11-05/server/tools). For agent-host images with `agent_runtime.type: mcp-server`, a declared capability SHOULD be invocable via the MCP `tools/call` method.

### 6.3 Provenance Extension

genoa extends MCP tool shape with a REQUIRED `provenance` object:

| Field | Required | Description |
|-------|----------|-------------|
| `source` | YES | `"built-in"`, `"installed"`, or `"plugin"` |
| `trust` | YES | `"attested"`, `"signed"`, or `"unverified"` |
| `package_id` | NO | SPDX ID cross-reference to SBOM |
| `attestation_ref` | NO | Reference to capability_claims entry in attestation |
| `added_at` | NO | Timestamp of capability addition |
| `added_by` | NO | Actor identity (URI) |

**Trust Levels:**
- `attested`: Covered by image attestation. Agents MAY invoke without additional user confirmation.
- `signed`: Has package signature but not in attestation envelope. Agents SHOULD surface to users.
- `unverified`: No cryptographic claim. Agents MUST surface to end users before invocation.

---

## 7. Conformance Levels

### 7.1 Level Definitions

| Level | Name | Requirements |
|-------|------|-------------|
| **L0** | Declared | `genoa.toml` present, `genoa.spec_version` valid. No runtime requirement. |
| **L1** | Discoverable | L0 + `/.well-known/genoa.json` serves 200 OK with required fields + `catalog_url` is reachable + SemVer version valid. |
| **L2** | Attested | L1 + `attestation_url` present + attestation HTTP 200 + `_type` and `predicateType` correct. |
| **L3** | Supply-Chain Verified | L2 + `slsa_level >= 2` + `sbom_digest` present in attestation + image is Sigstore-signed. |

### 7.2 Conformance Probe

`conformance/probe.nu run <hostname> [--level L1|L2|L3]` performs the conformance check and emits structured JSON:

```json
{
  "overall": "pass",
  "level_achieved": "L1",
  "checks": [
    {"id": "L1.1", "name": "discovery_endpoint_reachable", "pass": true, "detail": "HTTP 200"}
  ],
  "signature_verified": "stub"
}
```

The probe always exits 0. Verdict is carried in the JSON. Structured failure output (for unreachable hosts) is valid probe output.

### 7.3 Self-Report vs Verified Conformance

`conformance.level` in the discovery response is **self-reported**. It does not grant conformance status. Only a successful external probe run produces a verified conformance verdict.

---

## 8. Related Specifications

See `RELATED-SPECS.md` for the full inventory. Short summary:

- **in-toto v1** (Apache-2.0): We use Statement format verbatim. Our contribution is the `predicateType: "https://genoa.dev/AgentHost/v1"` predicate definition.
- **SLSA v1.0** (Apache-2.0): We reference Build Levels and buildEnvironment fields. We do not re-implement SLSA — we reference it.
- **MCP 2025-11-05** (MIT): We extend tool shape with `provenance`. Core `name`/`description`/`inputSchema` fields are MCP-native.
- **OCI Image Spec** (Apache-2.0): We adopt `platform.os` and `platform.architecture` enums verbatim.
- **SPDX 2.3** (Creative Commons): We reference SPDX IDs for package cross-referencing. We do not define SBOM format — we reference it.
- **RFC 8615** (IETF): Well-Known URI convention for `/.well-known/genoa.json`.

genoa's net-new contribution is the composition: a single discovery contract that ties these existing specs together into a cold-start-safe interface for LM agents.

---

## 9. Out of Scope

The following are explicitly out of scope for genoa v1:

- **Image build pipelines**: genoa specifies what the manifest contains, not how the image is built. Build tooling (Makefile, Ansible, cloud-init, packer) is the image author's concern.
- **Network topology**: Port numbers, firewall rules, macvlan vs bridge — not specified. genoa assumes the agent endpoint is reachable via the network address used to probe it.
- **Agent task scheduling**: What agents run on the host, how tasks are dispatched, or how results are collected.
- **Inter-agent communication**: Agent-to-agent protocols are not specified. Use MCP, HTTP, or whatever the agents support.
- **Agent authentication to external services**: `agent_runtime.auth` covers how consumers authenticate to the agent runtime, not how the agent authenticates to external APIs.
- **Image distribution**: Registries, update mechanisms, and distribution are out of scope. genoa is a boot-time contract.
- **Persistent state**: genoa makes no claims about filesystem persistence, ephemeral vs persistent images, or data sovereignty.
- **Hardware attestation**: TPM, secure boot, and remote attestation are SLSA's domain. genoa references SLSA levels but does not implement hardware root-of-trust.

---

## 10. Versioning

This specification follows SemVer. The current version is `1.0.0`.

- **Major version changes**: Breaking changes to required fields or the discovery endpoint contract.
- **Minor version changes**: Additive fields, new optional sections, new conformance levels.
- **Patch version changes**: Clarifications, typo fixes, example updates.

Consumers MUST check `genoa.spec_version` major version before parsing. A consumer that supports `1.x.x` MUST reject manifests with `genoa.spec_version` major version 2 or higher.

---

## 11. Security Considerations

- The discovery endpoint (`/.well-known/genoa.json`) MUST NOT contain secrets, tokens, or credentials.
- `conformance.level` is self-reported and MUST NOT be trusted without external probe verification.
- Capabilities with `provenance.trust: "unverified"` MUST be surfaced to end users before invocation. Automated invocation of unverified capabilities is a security risk.
- Signature verification stubs in the conformance probe are documented and expected in development environments. Production deployments MUST NOT deploy without real signature verification.
- The `agent_runtime.auth.type: "none"` setting is appropriate only for isolated network environments. Internet-accessible agent hosts MUST use authentication.
