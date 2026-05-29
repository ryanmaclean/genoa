# genoa Architecture

Primary reader: LLM agent. Structure: module inventory, data flow, schema
contracts. All paths are relative to the repo root.

---

## Overview

genoa is an AX-first Nushell CLI for building FreeBSD (and NetBSD) cloud images.
`genoa.nu` is a **thin shim** that sources eight `lib/` modules and three
`profiles/`, then defines a handful of top-level subcommands (`catalog`,
`schema`, `describe`, `providers`, `publish`, `run`). All non-trivial logic
lives in the modules.

Source order in `genoa.nu` is significant: `lib/cloud.nu` must be sourced first
because it defines `find_vultr`, which is called by `lib/deploy.nu` and
`lib/system.nu`.

```
source profiles/uefi.nu
source profiles/kboot.nu
source profiles/netbsd.nu
source adapters/linode.nu
source adapters/vultr.nu
source adapters/aws.nu
source adapters/gce.nu
source adapters/digitalocean.nu

# lib/ — source order matters: cloud.nu defines find_vultr used by deploy.nu and system.nu
source lib/cloud.nu
source lib/validate.nu
source lib/build.nu
source lib/deploy.nu
source lib/artifacts.nu
source lib/system.nu
source lib/signing.nu
source lib/suggest.nu
```

---

## Subcommand inventory (26 subcommands)

Defined via `def "main <name>"` across `genoa.nu` and `lib/`:

| Subcommand | Module | Purpose |
|---|---|---|
| `catalog` | `genoa.nu` | List providers from `catalog/providers.v1.json` |
| `schema` | `genoa.nu` | Return `schema/manifest.v1.json` |
| `describe` | `genoa.nu` | Summarize a manifest (basic field read — no validation) |
| `providers` | `genoa.nu` | Filtered provider list with arch, formats, regions |
| `publish` | `genoa.nu` | Upload image via `publish.nu` (R2/S3/Gitea/local) |
| `run` | `genoa.nu` | Chain: validate → build → publish → deploy |
| `validate` | `lib/validate.nu` | Run 13 manifest checks; return `valid`/`checks`/`errors`/`warnings` |
| `verify` | `lib/validate.nu` | Verify a receipt against its image (SHA-256 check) |
| `build` | `lib/build.nu` | Dispatch to profile; write schema-conformant receipt |
| `deploy` | `lib/deploy.nu` | Route to adapter by `deployment_path`; provision instance |
| `deploy-from-snapshot` | `lib/deploy.nu` | Create instance from existing snapshot ID |
| `clone-instance` | `lib/deploy.nu` | Clone a running instance via snapshot |
| `snapshots` | `lib/cloud.nu` | List Vultr snapshots |
| `snapshot-import` | `lib/cloud.nu` | Import image URL as Vultr snapshot |
| `snapshot-status` | `lib/cloud.nu` | Poll Vultr snapshot import status |
| `instances` | `lib/cloud.nu` | List Vultr instances |
| `watch` | `lib/cloud.nu` | Poll instance until running or timeout |
| `versions` | `lib/cloud.nu` | List deployed image versions from snapshot descriptions |
| `receipts` | `lib/artifacts.nu` | Inventory receipts under `artifacts/` |
| `diff` | `lib/artifacts.nu` | Diff two receipt files (field-level comparison) |
| `health` | `lib/system.nu` | Check required build tools (mdconfig, gpart, newfs, etc.) |
| `selftest` | `lib/system.nu` | Run `test/smoke.nu` and return pass/fail counts |
| `notify` | `lib/system.nu` | Send build notification (IRC/webhook) from a receipt |
| `status` | `lib/system.nu` | Summarize build artifacts in `./out` |
| `sign` | `lib/signing.nu` | Sign an image with signify or minisign |
| `verify-image` | `lib/signing.nu` | Verify an image signature |
| `suggest` | `lib/suggest.nu` | AI-powered manifest generation via Ollama |

---

## lib/ module responsibilities

### `lib/cloud.nu`
Defines `find_vultr` (locates `vultr` CLI binary — checks Homebrew path first,
then `PATH`). Provides all Vultr cloud-ops subcommands: `snapshots`,
`snapshot-import`, `snapshot-status`, `instances`, `watch`, `versions`.
**Must be sourced before `lib/deploy.nu` and `lib/system.nu`.**

### `lib/validate.nu`
Runs 13 sequential checks against a manifest TOML:
1. `file_exists` — readable
2. `schema_version` — must be `"v1"`
3. `required_fields` — `image`, `target`, `kernel`, `agent`
4. `image_name_slug` — `^[a-z0-9][a-z0-9_-]*$`
5. `image_format` — `raw`, `qcow2`, `vmdk`
6. `image_size_mb` — integer ≥ 512
7. `target_arch` — `amd64`, `aarch64`, `riscv64`
8. `target_os` — `freebsd`, `netbsd`
9. `provider_known` — `id` exists in `catalog/providers.v1.json`
10. `profile_file_exists` — `profiles/<profile>.nu` on disk
11. `agent_source_type` — `url`, `gitea_release`, or `local_path`
12. `sha256_not_placeholder` — warns on all-zeros SHA-256
13. `image_version_semver` — `^v[0-9]+\.[0-9]+\.[0-9]+$`

Also provides `main verify` — checks image and receipt existence, compares
SHA-256 digests (or notes `PLACEHOLDER_DRY_RUN`).

### `lib/build.nu`
Dispatches to the appropriate profile (`uefi_build`, `kboot_build`,
`netbsd_build`) based on `--profile` flag or manifest `profile` field.
Handles:
- Remote build dispatch via `target.build_host` (SCP manifest → SSH build →
  SCP image and receipt back)
- Derives canonical artifact filenames: `<name>-<version>.<format>` and
  `<name>-<version>.receipt.json` under `image.output_dir` (default `./out`)
- Runs signing step if `signing.tool` is `"signify"` (locates binary at
  `/usr/bin/signify`, `/usr/local/bin/signify`, or `/usr/local/bin/signify-ossl`)
- Writes the authoritative receipt (see Receipt schema below)

### `lib/deploy.nu`
Routes to adapter by `deployment_path` from `catalog/providers.v1.json`:

| `deployment_path` | Adapter |
|---|---|
| `"snapshot-url"` | `adapters/vultr.nu` |
| `"rescue-dd"` | `adapters/linode.nu` |
| `"byoi-api"` | `adapters/oci.nu` |
| `"digitalocean"` (pid match) | `adapters/digitalocean.nu` |

Image path is resolved in order: `--image` flag → `--from-receipt` flag →
manifest-derived path (`output_dir/name-version.format`) → fallback
`/tmp/genoa.raw`.

Also provides `deploy-from-snapshot` and `clone-instance` for snapshot-based
workflows.

### `lib/artifacts.nu`
- `main receipts` — globs `artifacts/**/*.receipt.json`, returns inventory sorted
  by `built_at` descending
- `main diff` — field-level comparison of two receipts (image version, build host,
  agent version, profile, SHA-256 deltas)

### `lib/system.nu`
Operational subcommands. Requires `find_vultr` from `lib/cloud.nu`.
- `main health` — probes required build tools with `which`; checks `uname -s == FreeBSD`
- `main selftest` — runs `test/smoke.nu` via subprocess
- `main notify` — reads a receipt, sends IRC/webhook notification (dry-run safe)
- `main status` — lists `.raw` and `.receipt.json` files in `./out`; optionally
  checks Vultr snapshot import status for each image

### `lib/signing.nu`
Standalone signing subcommands (supplement to the signing step in `lib/build.nu`):
- `main sign` — signs an image with `signify` or `minisign`; respects
  `signing.tool` and `signing.key_path` from the manifest (overridable via flags)
- `main verify-image` — checks the `.sig` or `.minisig` alongside the image

### `lib/suggest.nu`
AI manifest generation. Builds a prompt from `schema/manifest.v1.json` +
`examples/freebsd-vultr-aarch64.toml`, sends to an Ollama endpoint
(`http://ollama.local:11434` by default), and returns TOML. `--dry-run` returns
the prompt preview without calling Ollama. `--output <file>` saves the generated
TOML to disk.

---

## profiles/

### `profiles/uefi.nu` — FreeBSD UEFI (real builds, production)
The only profile that executes real destructive steps on FreeBSD.

Build tool chain: `mdconfig` → `gpart` → `newfs_msdos` (ESP) → `newfs` (UFS2
rootfs) → `mount` → `tar` (base.txz extraction) → `fetch` (agent binary) →
`cp` (agent + rc.d) → `umount` → `mdconfig -d`

Step numbering (relevant labels):
- `3` `create_disk_image` — `truncate -s <size> image.raw`
- `3b` `attach_mdconfig` — `mdconfig -a -t vnode -f image.raw`
- `4` `partition_gpt` — `gpart create + add` (ESP + freebsd-ufs)
- `5` `format_esp` — `newfs_msdos -F 32 /dev/md0p1`
- `6` `format_rootfs` — `newfs -O 2 /dev/md0p2`
- `7` `mount_rootfs` — `mount /dev/md0p2 /mnt/rootfs`
- `7b` `mount_esp` — `mount -t msdosfs /dev/md0p1 /mnt/esp`
- `8` `extract_base` — `tar -xpf FreeBSD-<ver>-base.txz -C /mnt/rootfs`
- `9` `extract_kernel` — `tar -xpf FreeBSD-<ver>-kernel.txz -C /mnt/rootfs`
- `8b` `install_bootloader` — `cp /mnt/rootfs/boot/loader.efi /mnt/esp/EFI/BOOT/BOOTX64.EFI`
- `10` `render_loader_conf` — renders `templates/uefi/loader.conf.tera` into `/mnt/rootfs/boot/loader.conf`
- `11` `render_rc_conf` — appends service enable lines to `/mnt/rootfs/etc/rc.conf`
- `11b` `install_packages` — `pkg -c /mnt/rootfs install -y <packages>` (if `packages` field set)
- `12` `inject_agent` — `cp ./out/<agent> /mnt/rootfs/usr/local/bin/<agent> && chmod 755`; agent is installed as a `/bin/sh` script
- `13b` `install_ssh_keys` — copies `network.ssh_keys` to `/mnt/rootfs/root/.ssh/authorized_keys`
- `14` `cloud_init_clean` — removes stale cloud-init state
- `15` `umount_and_compact` — `umount /mnt/rootfs && sync`
- `15b` `detach_mdconfig` — `mdconfig -d -u <unit>`

All destructive steps carry `action: "would-run"` in dry-run mode. Steps with
`action: "real"` run unconditionally (read/plan only — no system mutation).

### `profiles/kboot.nu` — kboot/Linux-kernel (plan-only)
Builds FreeBSD images for ext4-only providers (Linode, AWS, GCP) using
GRUB2 + Linux mini-kernel + `loader.kboot` initrd approach. The Linux mini-kernel
bridges the gap between the provider's ext4 expectation and FreeBSD UFS2 root.

**Status:** Plan-only. Known issues: step 9 runs `make menuconfig` (interactive,
blocks unattended builds); all manifest fields are ignored (top-level fallbacks only);
step commands are amd64-only and Linux-centric (uses `/dev/loop0`).

### `profiles/netbsd.nu` — NetBSD (dry-run stub)
Generates a build plan for NetBSD 10.x cloud images. Real builds require a
cross-build toolchain (`nbmake`). All steps are `action: "would-run"` only.

---

## adapters/

| File | Status | Mechanism |
|---|---|---|
| `adapters/vultr.nu` | Real | Snapshot-from-URL: POST image HTTPS URL to Vultr API → poll → create instance |
| `adapters/linode.nu` | Real | Rescue+dd: boot Linode into rescue mode → download image → `dd` to `/dev/sda` |
| `adapters/oci.nu` | Real | BYOI API: upload qcow2 to Object Storage → OCI custom image API |
| `adapters/oci-shim.nu` | Shim | OCI adapter shim (wraps oci.nu for subprocess invocation) |
| `adapters/digitalocean.nu` | Real | Import raw image from URL via doctl custom-image API |
| `adapters/aws.nu` | Stub | EC2 VM Import: S3 upload → `aws ec2 import-snapshot` → register AMI (not yet implemented) |
| `adapters/gce.nu` | Stub | GCE custom image: package as `.tar.gz` → GCS upload → `gcloud compute images create` (not yet implemented) |

---

## Schema contracts

### `schema/manifest.v1.json`
Input contract. Every manifest must pass `genoa validate` before building.
Required top-level fields: `schema_version` (const `"v1"`), `image`, `target`,
`kernel`, `agent`. `additionalProperties: false` — unknown keys are rejected.

Key sections:
- `image`: `name` (slug), `version` (SemVer), `format` (`raw`/`qcow2`/`vmdk`),
  `size_mb` (≥ 512), `output_dir`
- `target`: `os` (`freebsd`/`netbsd`), `arch` (`amd64`/`aarch64`/`riscv64`),
  `build_host` (SSH remote for cross-host builds)
- `kernel`: `version`, `base_txz_url`, `kernel_txz_url`
- `agent`: `name`, `version`, `source` (`type`/`url`/`sha256` or `gitea_release`
  fields or `local_path`)
- `agent.source` types: `"url"` (HTTPS + sha256), `"gitea_release"` (repo/tag/asset/sha256),
  `"local_path"` (path; sha256 not checked)
- `deploy`: `provider` (must match an `id` in `catalog/providers.v1.json`)
- `signing`: `tool` (`"signify"` / `"minisign"` / `"none"`), `key_file`, `public_key_file`
- `network`: `hostname`, `interface`, `mode`, `static_ip`, `gateway`
- `boot`: `console_speed`, `kern_hz`
- `packages`: list of pkg names to install into rootfs

### `schema/receipt.v1.json`
Output contract. Written by `lib/build.nu` after every build.
Required fields: `schema_version` (const `"v1"`), `receipt_id` (UUIDv4),
`built_at`, `image`, `build`, `agent`, `hashes`, `claims`.

Key sections:
- `image`: `name`, `version`, `format`, `output_path`
- `build`: `host`, `builder_type` (`"dry-run"` / `"genoa-local"` / `"genoa-crosshost"`),
  `os_version`, `arch`, `genoa_version`, `profile`, `dry_run`
- `agent`: `name`, `version`, `install_path`
- `hashes`: `image_sha256`, `manifest_sha256`, `manifest_path`
- `signing`: result of the signing step (or `{action: "unsigned", tool: "none"}`)
- `claims`: array of `{claim, executor, probe, expect, status}` records for
  fleet-eval integration (five claims per build: image SHA-256, manifest SHA-256,
  agent name, image format, target OS)

---

## Build flow

```
genoa run manifest.toml
  │
  ├─ 1. genoa validate manifest.toml   (lib/validate.nu — 13 checks)
  │       └─ abort if valid: false
  │
  ├─ 2. genoa build manifest.toml      (lib/build.nu)
  │       ├─ open manifest
  │       ├─ if target.build_host set → SCP manifest → SSH build → SCP artifacts back
  │       ├─ else → dispatch to profile (uefi_build / kboot_build / netbsd_build)
  │       │         ├─ mdconfig → gpart → newfs → mount
  │       │         ├─ tar extract base + kernel
  │       │         ├─ render loader.conf + rc.conf
  │       │         ├─ inject agent binary (/bin/sh script) + rc.d service
  │       │         └─ umount → mdconfig -d
  │       ├─ signing step (if signing.tool != "none")
  │       └─ write receipt.v1.json (schema-conformant)
  │
  ├─ 3. genoa publish <image-path>     (publish.nu — R2/S3/Gitea/local)
  │
  └─ 4. genoa deploy manifest.toml    (lib/deploy.nu)
          ├─ resolve image path
          ├─ lookup provider in catalog/providers.v1.json
          └─ dispatch to adapter by deployment_path
```

Each stage in `genoa run` is invoked as a subprocess (`^nu genoa.nu <stage>`)
so that parse errors in one stage cannot prevent others from loading.

---

## catalog/providers.v1.json

Machine-readable provider registry. Each entry has:
- `id` — slug used in manifest `deploy.provider`
- `display_name`
- `deployment_path` — adapter routing key (`"snapshot-url"`, `"rescue-dd"`, `"byoi-api"`)
- `byoi_format` — accepted image formats
- `arch_support` — supported architectures
- `freebsd_support` — boolean
- `min_image_size_mb`
- `regions` — array of region codes
- `docs` — provider documentation URL

Discover the current provider list: `nu genoa.nu providers`.

---

## Key design invariants

1. **All output is JSON.** Every subcommand returns JSON to stdout. No prose,
   no tables — even errors are JSON objects with `action: "failed"`.
2. **Dry-run is always honoured.** No destructive step executes without
   `is_freebsd && !dry_run`. On macOS/Linux all build steps return
   `action: "would-run"`.
3. **Source order matters.** `lib/cloud.nu` must be sourced before `lib/deploy.nu`
   and `lib/system.nu` because it defines `find_vultr`.
4. **Receipt schema_version is `"v1"` with the `v` prefix.** Consumers must
   reject receipts with other values.
5. **Adapter routing is by `deployment_path`.** Adding a new provider requires
   adding a `catalog/providers.v1.json` entry with the correct `deployment_path`
   and an adapter file — no changes to `genoa.nu` or `lib/deploy.nu` are needed
   for the routing table match case.
