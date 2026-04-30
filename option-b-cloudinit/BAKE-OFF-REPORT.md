# Bake-off Report — Option B (cloud-init baker)

## What was built

- Files: 11, total LOC: 2552 (+ README 55, BAKE-OFF-REPORT ~100)
- Languages: Nushell (genoa.nu 820 LOC, seed-iso/build.nu 186 LOC), Tera templates (user-data 195 LOC, 2× osbuild templates 587 LOC), JSON Schema (manifest.v1 332 LOC, attestation.v1 208 LOC), TOML (example 147 LOC)
- Subcommands actually working: `catalog`, `schema`, `describe`, `build --dry-run`, `verify`

## License compliance

**Approved deps:**

| Tool | License |
|------|---------|
| Nushell ≥ 0.111 | MIT |
| osbuild / osbuild-composer | Apache-2.0 |
| bootc | Apache-2.0 / MIT |
| cosign | Apache-2.0 |
| syft | Apache-2.0 |
| Tera template syntax | MIT |
| JSON Schema draft 2020-12 | royalty-free spec |
| qemu-img | GPL-2.0+ (external invocation only — never linked) |
| xorriso | GPL-3.0 (external invocation only — never linked; phase-2 replaces with Zig/MIT) |

**Rejected (and why):**

| Tool | License | Reason |
|------|---------|--------|
| HashiCorp Packer | BUSL-1.1 | Non-free for commercial use |
| mkosi | LGPL-2.1 | Copyleft — not approved |
| debian live-build | GPL-3.0 | Copyleft — not approved |
| SUSE kiwi-ng | GPL-3.0 | Copyleft — not approved |
| cloud-localds (cloud-utils) | GPL-3.0 | Copyleft; genoa builds NoCloud ISOs natively instead |

## AX-first surface verification

Actual stdout from the 3-call test (run on Nushell 0.111.0, macOS Darwin 25.3.0):

### Call 1: `nu genoa.nu catalog`

```json
{
  "schema": "https://genoa.dev/catalog/v1",
  "genoa_version": "0.1.0",
  "description": "Supported (base, arch, target) tuples for genoa image builds",
  "entries": [
    { "base": "alpine-3.20", "arch": "aarch64", "targets": ["pi","qcow2","raw"], "status": "supported", "template": "templates/osbuild/alpine-aarch64.json.tera" },
    { "base": "alpine-3.20", "arch": "x86_64",  "targets": ["qcow2","aws","gcp","raw"], "status": "supported", "template": "templates/osbuild/alpine-aarch64.json.tera" },
    { "base": "debian-bookworm", "arch": "x86_64", "targets": ["qcow2","aws","gcp","do","raw"], "status": "supported", "template": "templates/osbuild/debian-amd64.json.tera" },
    { "base": "debian-bookworm", "arch": "aarch64", "targets": ["pi","qcow2","raw"], "status": "planned", "template": null },
    { "base": "ubuntu-noble",    "arch": "x86_64",  "targets": ["qcow2","aws","gcp","do"], "status": "planned", "template": null },
    { "base": "ubuntu-noble",    "arch": "aarch64",  "targets": ["pi","qcow2"], "status": "planned", "template": null },
    { "base": "fedora-40",       "arch": "x86_64",  "targets": ["qcow2","aws"], "status": "planned", "template": null }
  ],
  "stack_components": ["datadog_agent","ollama","ii_agent","ac_client"],
  "cloud_init_datasources": ["NoCloud","Ec2","GCE","DigitalOcean"],
  "rejected_tools": [
    { "name": "HashiCorp Packer", "reason": "BUSL-1.1 — non-free for commercial use" },
    { "name": "mkosi",            "reason": "LGPL-2.1 — copyleft" },
    { "name": "debian live-build","reason": "GPL-3 — copyleft" },
    { "name": "SUSE kiwi-ng",     "reason": "GPL-3 — copyleft" },
    { "name": "cloud-localds",    "reason": "GPL-3 — copyleft; genoa builds NoCloud ISOs natively" }
  ]
}
```

### Call 2: `nu genoa.nu schema`

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://genoa.dev/schema/manifest/v1",
  "title": "Genoa Cloud Image Manifest v1",
  "description": "Schema for genoa cloud-init image baker manifests. Secrets are always referenced by name, never inlined.",
  "type": "object",
  "required": ["genoa", "image", "stack"],
  "additionalProperties": false,
  ... (full schema in schema/manifest.v1.json)
}
```

### Call 3: `nu genoa.nu describe examples/ai-assistant-edge.toml`

```json
{
  "schema": "https://genoa.dev/describe/v1",
  "genoa_version": "0.1.0",
  "manifest_id": "ai-assistant-edge-v1",
  "manifest_hash": "sha256:6d2538ff753887251d18d568b66e284e7d22ff9f5ba2bf0f7e40dbd2afcc314a",
  "manifest_path": "/Users/studio/genoa/option-b-cloudinit/examples/ai-assistant-edge.toml",
  "valid": true,
  "plan": {
    "base": "alpine-3.20",
    "arch": "aarch64",
    "hostname": "ai-edge-01",
    "configured_targets": ["pi", "qcow2", "aws"],
    "stack": { "datadog_agent": true, "ollama": true, "ii_agent": true, "ac_client": true },
    "secrets_backend": "env",
    "secret_refs": [
      { "ref": "DD_API_KEY",        "component": "datadog_agent" },
      { "ref": "ANTHROPIC_API_KEY", "component": "ii_agent" },
      { "ref": "DEPLOY_SSH_KEYS",   "component": "users.deploy" }
    ]
  },
  "hashes": {
    "manifest":           "sha256:6d2538ff753887251d18d568b66e284e7d22ff9f5ba2bf0f7e40dbd2afcc314a",
    "user_data_template": "sha256:2cac4349728f067e2de9821068d7e2164fbc6f5e7ed27ae782d730c574e0879c",
    "osbuild_template":   "sha256:f58781be6f1bac3ed9d1f8643df0ef1a91182c2340f387d9d60a760ddd74d74f"
  },
  "osbuild_template": { "key": "alpine-3.20-aarch64", "relative": "templates/osbuild/alpine-aarch64.json.tera" },
  "build_commands": [
    "nu genoa.nu build ai-assistant-edge-v1 --target pi --dry-run",
    "nu genoa.nu build ai-assistant-edge-v1 --target qcow2 --dry-run",
    "nu genoa.nu build ai-assistant-edge-v1 --target aws --dry-run"
  ],
  "next_step": "nu genoa.nu build <manifest.toml> --target <target> [--dry-run]"
}
```

A cold LM now knows every supported tuple, the full type system, and the exact next command in 3 calls.

## What works (real)

- Manifest parsing and structural validation (required keys, enum values, secret-inline detection)
- JSON Schema for manifests (`schema/manifest.v1.json`) and attestations (`schema/attestation.v1.json`) — both follow draft 2020-12
- `catalog` — JSON discovery endpoint listing all (base, arch, target) tuples with template paths
- `describe` — validates manifest, resolves all template hashes, emits structured plan with `next_step`
- `build --dry-run` — renders `user-data.tera` from TOML manifest context (hostname, locale, timezone, users with SSH keys, ollama model list, DD tags all substituted correctly); renders osbuild manifest template; prints would-run osbuild and cloud upload commands with correct paths; emits JSON result with hashes
- `verify` — recomputes sha256 hashes of osbuild manifest + user-data from build dir and compares against attestation; checks trust field is declared
- `schema --attestation` — prints in-toto v1 attestation schema
- in-toto v1 attestation structure with `predicateType: "https://genoa.dev/image-build/v1"`, trust field (explicit, not assumed), stub SBOM
- `instance-id` in cloud-init seed is `genoa-<sha256(manifest)[0:12]>` — guarantees cache invalidation on manifest change; documented with upstream ref

## What's stubbed

- **Actual osbuild execution** — emits rendered osbuild manifest JSON + `would-run: sudo osbuild ...` line. Needs root + container runtime. Phase-2: wire into osbuild-composer API.
- **Real seed ISO (FAT12 + ISO9660)** — `seed-iso/build.nu` writes loose `meta-data` / `user-data` files and calls `xorriso` if present (external GPL invocation). Phase-2: compile `seed-iso/iso-writer-stub.zig` with Zig (MIT) to produce a native ISO9660 writer with no GPL dependency.
- **Real SBOM** — stub SPDX-JSON with `"placeholder": true`. Phase-2: `syft <image> -o spdx-json` (Apache-2.0).
- **Cloud uploads** — `aws ec2 import-snapshot`, `gcloud compute images import`, `doctl compute image create` are emitted as would-run strings. Phase-2: execute after credentials validated.
- **Secrets backends beyond `env`** — `aws-secrets-manager`, `hashicorp-vault`, `gcp-secret-manager`, `file` are schema-declared but resolve to env fallback. Phase-2: implement each.
- **Tera full rendering** — pure-Nushell renderer handles `{{ var }}`, `{{ var | default(...) }}`, `{% for %}` loops, `{% if %}` conditionals (via strip). Phase-2: invoke `tera-cli` (MIT) binary for full Tera compliance.

## Build/run instructions

```sh
nu genoa.nu catalog
nu genoa.nu describe examples/ai-assistant-edge.toml
nu genoa.nu build examples/ai-assistant-edge.toml --target pi --dry-run
```

## Self-graded fit score: 7/10

## Self-grade weakness

The Nushell template renderer is a best-effort substitution loop, not a full Tera parser — complex conditionals with nested variable access (`{% if user.ssh_keys_secret_ref is defined %}`) are stripped rather than evaluated. The seed ISO is loose files + optional xorriso (GPL external), not a native byte-level ISO9660 writer. Both are honest phase-2 items with a clear implementation path (tera-cli MIT, Zig MIT ISO writer). The core value proposition — manifest → structured plan → rendered templates → attestation — works end-to-end on real Nushell 0.111.

## Synergy hooks

- "If A (smolBSD) emits images: I could swap my osbuild base-image stage for a `bootc` stage that references smolBSD's OCI output as the FROM layer, and reuse my cloud-init seed verbatim for first-boot provisioning — the datasource label `cidata` and the user-data format are distro-agnostic."
- "If D (spec) wants to validate my attestations: my attestation conforms to `https://genoa.dev/image-build/v1` with explicit `trust.level`, `trust.signed_by`, and a `completeness` block — point me at the validator endpoint and I'll POST the JSON directly from `genoa build`."
- "If C (Ansible) wants to consume my images: `describe` output includes `manifest_hash` and `secret_refs` as structured JSON — Ansible can read that as a vars file and pass the secret refs as vault lookups to the cloud-init environment."
