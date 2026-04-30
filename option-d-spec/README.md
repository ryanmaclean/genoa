# genoa — Agent-Host OS Specification (Option D: meta-OS spec)

**AX-first**: a cold LM discovers everything in 3 calls. No prose-parsing required.

## Quickstart — 3 commands

```sh
# 1. Discover what this spec defines
cat catalog/v1.json | jq '.schemas | keys'

# 2. Validate an image manifest
nu conformance/validate.nu manifest examples/manifest.toml

# 3. Probe a live host for L1 conformance
nu conformance/probe.nu run <hostname>
```

## What's here

| Path | What it is |
|------|-----------|
| `catalog/v1.json` | Single entry point — lists all schemas, examples, tools |
| `schemas/manifest.v1.json` | JSON Schema for `genoa.toml` (image identity, runtime, capabilities, SBOM) |
| `schemas/discovery.v1.json` | JSON Schema for `/.well-known/genoa.json` discovery response |
| `schemas/attestation.v1.json` | JSON Schema for in-toto v1 Statement + genoa AgentHost/v1 predicate |
| `schemas/capability.v1.json` | JSON Schema for capability declaration (extends MCP tool shape + provenance) |
| `examples/manifest.toml` | Valid example manifest |
| `examples/discovery.json` | Valid example discovery response |
| `examples/attestation.json` | Valid example attestation |
| `conformance/probe.nu` | Nushell L1/L2/L3 conformance probe (structured JSON output) |
| `conformance/validate.nu` | Nushell schema validator (manifest, attestation, discovery, capability) |
| `spec/genoa-v1.md` | Full specification text |
| `RELATED-SPECS.md` | Honest inventory of what we compose vs. what's net-new |

## 3-Call Discovery Contract

A cold LM can discover and validate any agent-host in at most 3 calls:

```
# Call 1: discover the host
GET http://<host>/.well-known/genoa.json
  → {genoa_version, image, agent_runtime, catalog_url, conformance}

# Call 2: discover the spec catalog
GET https://genoa.dev/v1/catalog.json    (or: cat catalog/v1.json)
  → {schemas: {manifest.v1, discovery.v1, ...}, conformance: {probe, validate}}

# Call 3: validate any manifest
nu validate.nu manifest <image-manifest.toml>
  → {"valid": true, "errors": [], "warnings": []}
```

## For spec authors (image builders)

1. Create `/etc/genoa/genoa.toml` using the manifest schema.
2. At boot, serve it as JSON at `GET /.well-known/genoa.json`.
3. Run `nu conformance/probe.nu run localhost --port <port>` to verify L1.

## For conformance testers

```sh
# L1 check (discovery endpoint)
nu conformance/probe.nu run myhost.local

# L2 check (L1 + attestation)
nu conformance/probe.nu run myhost.local --level L2

# L3 check (L2 + SLSA-2 + SBOM)
nu conformance/probe.nu run myhost.local --level L3

# Validate a manifest file
nu conformance/validate.nu manifest /path/to/genoa.toml

# Validate an attestation
nu conformance/validate.nu attestation /path/to/attestation.json
```

## Requirements

- **Nushell** >= 0.100.0 (tested on 0.111.0)
- No other runtime dependencies for the conformance tools.
- Optional: `jsonschema-rs` CLI (MIT) for strict JSON Schema 2020-12 validation.

## License

- Conformance tools (`conformance/`): BSD-2-Clause
- Spec documents (`spec/`, `RELATED-SPECS.md`): Apache-2.0
- JSON Schemas (`schemas/`): BSD-2-Clause (implementations may embed freely)

See `LICENSE` and `LICENSE-DEPS.md` for details.
