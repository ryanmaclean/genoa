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

### Discovery & Introspection

| Command | Description |
|---------|-------------|
| `catalog` | Dump full provider catalog as JSON |
| `schema` | Dump the manifest JSON schema |
| `describe` | Summarize manifest fields (image, target, agent, network) |
| `providers` | Query provider catalog (filterable by `--id`) |
| `versions` | List published Gitea releases via API |
| `receipts` | List all receipts under `artifacts/` |

### Validation & Build

| Command | Description |
|---------|-------------|
| `validate` | Validate a manifest against schema (20 checks) |
| `build` | Build a cloud image using uefi or kboot profile; writes receipt |
| `verify` | Verify a receipt file: image exists, SHA256 matches, claims pass |
| `verify-image` | Mount image and check loader.conf/rc.conf present (FreeBSD only) |
| `diff` | Compare two build receipts field by field |
| `sign` | Sign an image with signify or minisign (`--dry-run` supported) |

### Publishing & Deployment

| Command | Description |
|---------|-------------|
| `publish` | Upload image to a storage backend (r2, s3, gitea, local) |
| `deploy` | Deploy an image via the provider adapter (Vultr, Linode, OCI) |
| `deploy-from-snapshot` | Launch a Vultr instance from an existing snapshot |
| `clone-instance` | Clone a running Vultr instance |
| `run` | Full pipeline: validate → build → publish → deploy (per-stage results) |

### Snapshot & Instance Lifecycle

| Command | Description |
|---------|-------------|
| `snapshots` | List Vultr snapshots |
| `snapshot-import` | Import image to Vultr by URL |
| `snapshot-status` | Poll status of a Vultr snapshot by ID |
| `instances` | List running Vultr instances (`--all` for all regions) |
| `watch` | Poll snapshot/instance until target status (with timeout) |

### Observability & System

| Command | Description |
|---------|-------------|
| `status` | Full system state: snapshots, instances, recent builds, platform |
| `health` | Check all 10 required build tools and platform readiness |
| `selftest` | Run smoke suite as subprocess; returns structured pass/fail JSON |
| `notify` | Post enriched build metrics to Datadog (profile/host/os tags, age_hours) |

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

### NetBSD (`profiles/netbsd.nu`)

Stub profile for NetBSD cloud image support. Returns a structured dry-run plan. Use with `examples/netbsd-vultr-amd64.toml`.

### microvm (`profiles/microvm.nu`) — direct-kernel PVH + state disks

Packages a **pre-built** PVH-bootable kernel ELF — smolfire's one-ELF SMOLFIRE microVM (kernel + embedded MFS root, no root disk) or a NetBSD 11 `netbsd-MICROVM` kernel — together with **independently hashable writable state disks** (FFS, NetBSD LFS, HAMMER2). smolfire owns the OS build; genoa owns packaging, hashes, launch plans and the receipt (issue #1).

```sh
nu genoa.nu validate examples/freebsd-smolfire-microvm-amd64.toml
nu genoa.nu build    examples/netbsd11-microvm-amd64.toml --dry-run --run-id <bop-run-id>
nu genoa.nu deploy   examples/freebsd-smolfire-microvm-amd64.toml --dry-run   # local VMM launch plan
```

- `boot.mode = "direct-kernel"`, `image.format = "elf"`; `boot.vmm` = `firecracker` and/or `qemu-microvm` (x86 only). The build emits a Firecracker `--config-file` body and a `qemu-system-* -M microvm` argv; genoa never starts the VMM.
- `rootfs.type = "embedded"` (no root disk) or `"image"` (immutable initrd/ramdisk file, hashed separately).
- `[[state_disks]]`: `name`, `fs` (`ffs|lfs|hammer2|hammer1`), `size_mb`, optional `label`, `uuid`, `device`, `mountpoint`, `journal`. Which filesystem is allowed on which target OS comes from `catalog/statefs.v1.json` (supported / experimental → warning / unsupported → error; HAMMER1 is DragonFly-only and always rejected).
- Real builds: copying + ELF-magic + pinned-sha256 check of the boot artifact works on any host. A state disk is formatted only when its tools exist on the build host (FFS: `makefs` on FreeBSD/NetBSD; LFS: `vndconfig`+`newfs_lfs` on NetBSD; HAMMER2: `newfs_hammer2`). Otherwise that disk is `requires-host`, its `sha256` is `null`, and the build returns `build-failed` — a disk that was not built never gets a hash.
- `deploy` with a cloud `--provider` is refused (no silent UEFI/qcow2 conversion); without a provider it returns the launch plan from the receipt.

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
  "correlation": { "run_id": "<--run-id or null>", "manifest_sha256": "", "artifact_sha256": "" },
  "claims": [{ "claim": "", "probe": "", "expect": "" }]
}
```

`profile = "microvm"` receipts add `boot` (mode, vmm, cmdline, kernel version, `root_disk: false`, artifact sha256, rootfs identity), `state_disks[]` (fs, label, uuid + uuid_source, device, path, sha256 per disk) and `launch` (Firecracker config / qemu argv). `correlation` joins the artifact to a run by `(run_id, content hashes)`; genoa never mints its own ordering/version counter — filesystem-native versions (HAMMER TID, LFS checkpoint) stay with the filesystem. The full contract is `schema/receipt.v1.json` (v1.1.0, additive). `nu genoa.nu verify <receipt>` re-hashes the boot artifact and every built state disk.

Verify a receipt: `nu genoa.nu verify out/smolbsd-v0.1.0.receipt.json`

## Development

```sh
# Run smoke suite (42 tests)
nu test/smoke.nu

# Run full self-test (structured JSON output)
nu genoa.nu selftest

# Check build tool dependencies
nu genoa.nu health
```

## Infrastructure

- **Buildworld**: FreeBSD 15 amd64 on Vultr (2 vCPU, 4 GB RAM, 80 GB disk) — 2GB swap, rc.d HTTP service, SSH keepalive, Gitea act_runner registered
- **Gitea**: `http://10.0.2.230:3001/string/genoa` — releases published there
- **CI**: GitHub Actions (Nu 0.111.0 musl, smoke + validate-manifests) + Gitea Actions (FreeBSD native, pending Tailscale auth)
- **Completions**: `completions/genoa.nu` — Nushell tab-completions for all subcommands

## License

BSD-2-Clause
