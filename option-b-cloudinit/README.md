# genoa — cloud-init image baker (Option B)

Nushell CLI that takes a TOML manifest and produces an osbuild manifest + cloud-init seed for Linux cloud images with an AI-assistant stack pre-baked.

**License:** BSD-2-Clause  
**Requires:** Nushell ≥ 0.111, osbuild ≥ 110 (for actual builds)

## 3-command quickstart

```sh
nu genoa.nu catalog                                        # discover supported (base, arch, target) tuples
nu genoa.nu describe examples/ai-assistant-edge.toml      # validate manifest + produce build plan with hashes
nu genoa.nu build   examples/ai-assistant-edge.toml --target pi --dry-run
```

## Commands

| Command | What it does |
|---------|-------------|
| `catalog` | JSON list of all supported (base, arch, target) tuples — AX discovery endpoint |
| `schema [--attestation]` | Print the JSON Schema for manifests or attestations |
| `describe <manifest.toml>` | Validate manifest, resolve hashes, emit structured build plan |
| `build <manifest.toml> [--target qcow2\|aws\|gcp\|do\|pi\|raw] [--dry-run]` | Render templates, produce osbuild manifest, build seed ISO, emit attestation |
| `verify <image-or-dir> <attestation.json>` | Recompute hashes and check against attestation |

## Manifest format

```toml
[genoa]
schema_version = "v1"
manifest_id    = "my-ai-node"
created_at     = "2026-04-30T00:00:00Z"

[image]
base     = "alpine-3.20"   # or debian-bookworm, ubuntu-noble, fedora-40
arch     = "aarch64"       # or x86_64, armv7l
hostname = "ai-edge-01"

[stack.datadog_agent]
enabled            = true
api_key_secret_ref = "DD_API_KEY"   # env var — never inline secrets

[stack.ollama]
enabled = true
models  = ["llama3.2:3b", "nomic-embed-text"]

[targets.pi]
enabled      = true
disk_size_gb = 32
pi_model     = "pi5"

[secrets]
backend = "env"   # reads DD_API_KEY etc. from environment at build time
```

Full example: [`examples/ai-assistant-edge.toml`](examples/ai-assistant-edge.toml)

## Supported targets

| Base | Arch | Targets |
|------|------|---------|
| alpine-3.20 | aarch64 | pi, qcow2, raw |
| alpine-3.20 | x86_64 | qcow2, aws, gcp, raw |
| debian-bookworm | x86_64 | qcow2, aws, gcp, do, raw |

## AI stack components

- **datadog-agent** — v7, auto-installs via official script, secret ref for API key
- **ollama** — latest, model pull list, systemd unit, GPU auto-detect
- **ii-agent** — Anthropic autonomous agent runtime, systemd unit
- **ac-client** — Anthropic Claude CLI

## NoCloud seed ISO cache note

`instance-id` in the seed ISO `meta-data` is set to `genoa-<sha256(manifest)[0:12]>`.
Every distinct manifest produces a distinct instance-id, which forces cloud-init
to re-run on re-deploy. If you need to force re-run on an already-provisioned host,
also clear `/var/lib/cloud/instance` and `/var/lib/cloud/instances/<old-id>/`.

## Rejected tools

Packer (BUSL-1.1), mkosi (LGPL-2.1), debian live-build (GPL-3), kiwi-ng (GPL-3),
cloud-localds (GPL-3). See [LICENSE-DEPS.md](LICENSE-DEPS.md).
