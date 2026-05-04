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

- `describe` parses the manifest and prints a structured summary of all sections and their resolved values.
- `build` executes the profile (uefi / kboot), emits image + receipt with attestation.
- Optional `--dry-run` shows what would happen without actually building.

## Subcommands

```nushell
genoa catalog                            # List providers from catalog/providers.v1.json
genoa schema                             # Print manifest schema (JSON Schema)
genoa describe <manifest.toml>           # Parse manifest, print structured section summary
genoa validate <manifest.toml>           # Validate manifest against schema, return check results
genoa build <manifest.toml> [--profile uefi|kboot] [--dry-run]
genoa publish <image> [--backend r2|s3|gitea]
genoa deploy <manifest.toml> --provider <id>
genoa verify <image> <receipt.json>
genoa run <manifest.toml> [--provider <id>] [--backend r2|s3|gitea] [--dry-run]
genoa status [--dir <path>]              # Scan for receipts, return aggregate build summary
```

`run` is the end-to-end pipeline: validate → build → publish → deploy, returning a combined JSON result.

## Core concepts

**Manifest** (TOML)
- Declarative image specification: OS, kernel, packages, agent payload, network config, deployment target.
- Versioned schema: v1 = current (field additions backcompat).
- Includes `target.build_host` for remote FreeBSD build hosts (see Remote build host below).

**Profile** (enum: uefi, kboot)
- Boot loader strategy selected at build time.
- Dispatches to `profiles/uefi.nu` or `profiles/kboot.nu`.
- Both execute real commands on FreeBSD via `run_step`; on non-FreeBSD hosts with `--dry-run`, they return a structured plan.

**Receipt** (JSON)
- Attestation envelope emitted alongside every image.
- Contains: build provenance, agent source + hash, hashes of image/manifest/kernel config.
- Verifiable claims array for fleet-eval integration.

**Provider** (catalog entry)
- Cloud provider descriptor: ID, display name, BYOI support, supported architectures, BSD support.
- `deployment_path` field routes dispatch logic: `rescue-dd`, `byoi-api`, `snapshot-url`.
- Read from `catalog/providers.v1.json`.

## Adapters

**vultr.nu** — makes real Vultr API calls. Requires `VULTR_API_KEY`. Supports snapshot-from-URL (upload a public image URL, Vultr imports it). Dry-run returns plan JSON without credentials or API calls.

**linode.nu** — generates a structured rescue+dd deployment plan (Path 3, officially documented by Linode): boot-to-rescue, SSH access, image verify, `curl | dd` write, reboot. No credentials required to generate the plan.

**oci.nu** — stub; returns `{"action":"stub"}` for unsupported providers.

## Remote build host

Set `target.build_host = "user@host"` (or `"user@host:port"`) in the manifest. When present, `genoa build` SCPs the manifest to the host and runs the build via SSH, returning the remote result. Useful when the local machine is not FreeBSD.

## Testing

```bash
nu test/smoke.nu
```

16 smoke tests covering catalog, schema, describe, validate, build (dry-run, uefi, kboot), deploy (Vultr dry-run, Linode), publish (dry-run), verify, run (dry-run), and missing-file error handling.

## File layout

| Path | Purpose |
|---|---|
| `genoa.nu` | Main CLI (all subcommands) |
| `publish.nu` | Standalone publish helper |
| `schema/manifest.v1.json` | JSON Schema for manifests |
| `schema/receipt.v1.json` | JSON Schema for receipts |
| `catalog/providers.v1.json` | Provider catalog (40 entries) |
| `profiles/uefi.nu` | UEFI profile — real FreeBSD commands |
| `profiles/kboot.nu` | kboot profile — real FreeBSD commands |
| `adapters/vultr.nu` | Vultr adapter — real API calls |
| `adapters/linode.nu` | Linode adapter — rescue+dd plan |
| `formats/convert.nu` | Image format conversion |
| `templates/` | uefi/, kboot/, publish/ build templates |
| `docs/agent-port-quickstart.md` | LLM-first quickstart |
| `test/smoke.nu` | 16 smoke tests |

## Design notes

**AX-first**
- Manifests are TOML (structured, schema'd, versioned).
- All output is JSON (catalog, schema, receipts, plan, hashes).
- No prose parsing required.
- Single `catalog` endpoint lists all providers; dispatch is deterministic by ID + path.
- See `docs/agent-port-quickstart.md` for the agent-optimized onboarding path.

**Attestation** — every build emits a receipt with image SHA256, manifest SHA256, agent source + SHA256. Verifiable by fleet-eval: `fleet-eval verify "image built" --probe "sha256sum $image" --expect "..."`

**License** — BSD-2-Clause (MIT-compatible). All dependencies must be MIT, BSD-2-Clause, BSD-3-Clause, or Apache-2.0.
