# genoa — unified CLI for smolBSD image build and deployment

genoa is an AX-first (agent-first) orchestration tool for building FreeBSD and NetBSD cloud images with embedded agents, then dispatching them to cloud providers via structured manifests and verified receipts.

## Quickstart

### 1. List available providers
```bash
nu genoa.nu catalog
```

Lists all 40+ supported cloud providers from `catalog/providers.v1.json`, with deployment mechanisms, architecture support, and BSD-native capabilities.

### 2. Inspect the schema
```bash
nu genoa.nu schema
```

Prints `schema/manifest.v1.json` — the JSON Schema for manifest TOML files. Agents use this to discover and validate manifest structure without prior knowledge.

### 3. Build an image
```bash
nu genoa.nu describe examples/freebsd-vultr-aarch64.toml
nu genoa.nu build examples/freebsd-vultr-aarch64.toml --profile uefi
```

- `describe` parses the manifest, validates against schema, prints a plan JSON with build steps.
- `build` executes the profile (uefi / kboot), emits image + receipt with attestation.
- Optional `--dry-run` shows what would happen without actually building.

## Core concepts

**Manifest** (TOML)
- Declarative image specification: OS, kernel, packages, agent payload, network config, deployment target.
- Versioned schema: v1 = current (field additions backcompat).
- Includes deployment metadata: provider ID and optional path override.

**Profile** (enum: uefi, kboot)
- Boot loader strategy selected at build time.
- Dispatches to `profiles/uefi.nu` or `profiles/kboot.nu` (not yet implemented).
- Stubs emit JSON reason if missing.

**Receipt** (JSON)
- Attestation envelope emitted alongside every image.
- Contains: build provenance, agent source + hash, hashes of image/manifest/kernel config.
- Verifiable claims array for fleet-eval integration.

**Provider** (catalog entry)
- Cloud provider descriptor: ID, display name, BYOI support, supported architectures, BSD support.
- `deployment_path` field routes dispatch logic: `rescue-dd`, `byoi-api`, `snapshot-url`.
- Read from `catalog/providers.v1.json`.

## File layout

```
genoa/
├── genoa.nu                          # Main CLI (Nushell)
├── schema/
│   ├── manifest.v1.json              # Manifest schema (JSON Schema)
│   └── receipt.v1.json               # Receipt schema
├── catalog/
│   └── providers.v1.json             # Provider catalog (40 entries)
├── examples/
│   ├── freebsd-vultr-aarch64.toml    # ISO for Vultr
│   └── freebsd-linode-amd64.toml     # Raw for Linode rescue-dd
├── profiles/
│   ├── uefi.nu                       # (stub: not yet implemented)
│   └── kboot.nu                      # (stub: not yet implemented)
├── adapters/
│   ├── vultr.nu                      # (stub: not yet implemented)
│   ├── linode.nu                     # (stub: not yet implemented)
│   └── oci.nu                        # (stub: not yet implemented)
├── LICENSE                           # BSD-2-Clause
└── README.md                         # This file
```

## Subcommands

```nushell
genoa catalog                            # List providers from catalog/providers.v1.json
genoa schema                             # Print manifest schema (JSON Schema)
genoa describe <manifest.toml>           # Parse + validate, print plan JSON
genoa build <manifest.toml> [--profile uefi|kboot] [--dry-run]
genoa publish <image> [--backend r2|s3|gitea]
genoa deploy <manifest.toml> --provider <id>
genoa verify <image> <receipt.json>
```

### build dispatch logic
- Read manifest profile (default: uefi).
- Source `profiles/{profile}.nu`.
- Call `{profile}_build $manifest`.
- Emit receipt JSON to `{image.output_dir}/{image.name}-{image.version}.receipt.json`.

### deploy dispatch logic
- Read manifest deploy.provider and deploy.path_override.
- Look up provider in catalog by ID.
- Extract deployment_path (or use override).
- Match deployment_path:
  - `rescue-dd` → source `adapters/linode.nu` → call `linode_deploy $manifest $image`
  - `snapshot-url` → source `adapters/vultr.nu` → call `vultr_deploy $manifest $image`
  - `byoi-api` → source `adapters/oci.nu` → call `oci_deploy $manifest $image`
  - (others) → error with unsupported deployment_path

## Design notes

**AX-first**
- Manifests are TOML (structured, schema'd, versioned).
- All output is JSON (catalog, schema, receipts, plan, hashes).
- No prose parsing required.
- Single `catalog` endpoint lists all providers; dispatch is deterministic by ID + path.

**Stubs**
- Unimplemented profiles and adapters return `{"action":"stub","reason":"..."}` JSON.
- Allows CLI to be invoked in test/audit mode before all backends are built.

**Attestation**
- Every build emits a receipt with image SHA256, manifest SHA256, agent source + SHA256.
- Verifiable by fleet-eval: `fleet-eval verify "image built" --probe "sha256sum $image" --expect "..."`

**License**
- BSD-2-Clause (MIT-compatible).
- All dependencies must be MIT, BSD-2-Clause, BSD-3-Clause, or Apache-2.0.

## See also

- `/Users/studio/genoa/option-a-smolbsd/` — reference implementation of smolBSD build infrastructure.
- `/Users/studio/genoa/research-r1-providers/providers.json` — source research for provider catalog.
- `~/.claude/skills/fleet-eval/` — verification harness for attestation receipts.
