# genoa

Nushell CLI for building and deploying minimal FreeBSD cloud images with embedded AI agents.

## Design principles

- **AX-first**: all input/output is JSON — agents can discover, invoke, and compose without docs
- **Schema-versioned**: manifests at `schema_version = "v1"`, catalog at `catalog/providers.v1.json`
- **Structured receipts**: every build produces a receipt with SHA256 claims and provenance
- **Dry-run everywhere**: every command supports `--dry-run` for safe planning before execution

## Quick start

```sh
# Validate a manifest
nu genoa.nu validate examples/freebsd-vultr-aarch64.toml

# Dry-run build
nu genoa.nu build examples/freebsd-vultr-aarch64.toml --dry-run

# Full pipeline (dry)
nu genoa.nu run examples/freebsd-vultr-aarch64.toml --dry-run

# Check system readiness
nu genoa.nu health
```

## Commands

| Command | Description |
|---------|-------------|
| `catalog` | Dump full provider catalog as JSON |
| `schema` | Dump the manifest JSON schema |
| `describe` | Summarize manifest fields (image, target, agent, network) |
| `validate` | Validate a manifest against schema (17 checks) |
| `build` | Build a cloud image using uefi or kboot profile; writes receipt |
| `deploy` | Deploy an image via the provider adapter (Vultr, Linode, OCI) |
| `publish` | Upload image to a storage backend (r2, s3, gitea, local) |
| `run` | Full pipeline: validate → build → publish → deploy |
| `verify` | Verify a receipt file: image exists, SHA256 matches, claims pass |
| `verify-image` | Inspect a raw disk image for partition layout correctness |
| `status` | Scan output dir for receipts; report real vs dry-run builds |
| `health` | Check all 10 required build tools and platform (FreeBSD expected) |
| `selftest` | Run smoke suite as subprocess; returns structured pass/fail JSON |
| `sign` | Sign an image with signify or minisign |
| `diff` | Compare two receipt files; report changed fields |
| `snapshots` | List Vultr snapshots via CLI |
| `snapshot-import` | Import image to Vultr by URL |
| `snapshot-status` | Poll status of a Vultr snapshot by ID |
| `providers` | Query provider catalog (filterable by `--id`) |
| `receipts` | List all receipts under `artifacts/` |
| `notify` | Post build metrics to Datadog via `pup` |

## Manifest format

```toml
schema_version = "v1"

[image]
name        = "smolbsd-vultr-aarch64"  # artifact basename
version     = "v0.1.0"                 # semver, vN.N.N required
format      = "raw"                    # raw | vmdk | vhd
size_mb     = 4096                     # minimum 512
description = "Minimal FreeBSD for Vultr aarch64 via ISO boot"

[target]
os         = "freebsd"
os_version = "15.0-RELEASE"
arch       = "aarch64"                 # amd64 | aarch64
platform   = "generic"

[kernel]
config      = "GENERIC"
strip_debug = true

[packages]
include = [
  "FreeBSD-runtime",
  "FreeBSD-clibs",
  "FreeBSD-rc",
  "FreeBSD-utilities",
  "FreeBSD-pkg-bootstrap",
]

[agent]
name    = "ii-agent"
version = "v0.1.0"

[agent.source]
type   = "url"
url    = "https://gitea.local:3000/ii/ii-agent/releases/download/v0.1.0-freebsd-aarch64/ii-agent"
sha256 = "0000..."   # placeholder triggers validator warning

[agent.rc_service]
enabled = true
name    = "ii_agent"

[network]
interface = "vtnet0"   # must match provider conventions
mode      = "dhcp"
hostname  = "smolbsd-vultr"

profile = "uefi"       # uefi | kboot

[deploy]
provider = "vultr"     # must match an id in catalog/providers.v1.json

[metadata]
builder_notes  = "Raw disk image for Vultr snapshot-url import"
target_region  = "global"
```

## Supported providers

Providers with genoa adapters (`deployment_path` → adapter file):

| Provider | Method | Formats | Arch |
|----------|--------|---------|------|
| Vultr | `snapshot-url` | raw | amd64, aarch64 |
| Akamai Cloud (Linode) | `rescue-dd` | raw | amd64, aarch64 |
| Amazon EC2 | `ami-import` | raw, vmdk, vhd | amd64, aarch64 |
| Google Compute Engine | `custom-image` | raw | amd64, aarch64 |

The full catalog (35+ entries) is machine-readable at `catalog/providers.v1.json`.
Query it with: `nu genoa.nu providers` or `nu genoa.nu catalog | jq '.providers[] | .id'`.

## Build profiles

### UEFI (`profiles/uefi.nu`)

For providers that accept raw disk images via URL import. Uses GPT + FAT16 ESP (128 MB) + UFS2 root. Writes `loader.conf` and `rc.conf` into the image filesystem. Real builds require FreeBSD (`mdconfig`, `gpart`, `newfs_msdos`, `newfs`).

### kboot (`profiles/kboot.nu`)

For providers that require ext4 boot partitions (Linode, GCE). Uses GRUB2 + Linux mini-kernel + `loader.kboot`. Execution is gated on Linux — tools (`sgdisk`, loop devices, `bash`) are Linux-only. Currently generates dry-run plans only on non-Linux hosts.

## Receipt schema

Every build produces `<output_dir>/<name>-<version>.receipt.json`:

```json
{
  "schema_version": "v1",
  "receipt_id": "<uuid>",
  "built_at": "<rfc3339>",
  "manifest_path": "examples/freebsd-vultr-aarch64.toml",
  "image":  { "name": "", "version": "", "format": "", "output_path": "" },
  "build":  { "host": "", "profile": "", "os_version": "", "arch": "", "genoa_version": "", "dry_run": false },
  "agent":  { "name": "", "version": "", "install_path": "" },
  "hashes": { "image_sha256": "", "manifest_sha256": "" },
  "claims": [{ "claim": "", "probe": "", "expect": "" }]
}
```

Verify a receipt: `nu genoa.nu verify out/smolbsd-v0.1.0.receipt.json`

## Development

```sh
# Run smoke suite (32 tests)
nu test/smoke.nu

# Run full self-test (structured JSON output)
nu genoa.nu selftest

# Check build tool dependencies
nu genoa.nu health
```

## Infrastructure

- **Buildworld**: FreeBSD 15 amd64 on Vultr (2 vCPU, 4 GB RAM, 80 GB disk)
- **Gitea**: `string/genoa` repo on fleet Gitea — releases published there
- **CI**: GitHub Actions (smoke + validate-manifests) + Gitea Actions (FreeBSD native, pending Tailscale auth)

## License

BSD-2-Clause
