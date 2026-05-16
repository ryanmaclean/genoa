# genoa — Claude Code Context

## 1. What this is

**genoa** is an AX-first Nushell CLI for building and deploying minimal FreeBSD (and NetBSD) cloud images with embedded AI agents. It manages the full pipeline: manifest validation → UEFI/kboot image build → image publishing → provider deployment (Vultr, Linode, AWS EC2, GCE). All output is structured JSON with `action` fields. Schema-versioned receipts carry SHA256 claims and provenance. Every command supports `--dry-run`. The CLI is designed so an agent dropped in cold can discover, invoke, and compose commands without reading prose — `nu genoa.nu catalog` and `nu genoa.nu schema` are the entry points.

## 2. Key files

| Path | Purpose |
|---|---|
| `genoa.nu` | CLI shim — sources all profiles, adapters, and lib modules; defines all `main *` subcommands |
| `profiles/uefi.nu` | UEFI build profile (GPT + FAT16 ESP 128MB + UFS2 root); real execution on FreeBSD only |
| `profiles/kboot.nu` | kboot build profile (GRUB2 + ext4); real execution on Linux only |
| `profiles/netbsd.nu` | NetBSD stub profile — dry-run plan only |
| `adapters/vultr.nu` | Vultr deployment adapter (snapshot-url import) |
| `adapters/linode.nu` | Linode adapter (rescue-dd plan with detailed steps) |
| `adapters/aws.nu` | AWS EC2 adapter stub |
| `adapters/gce.nu` | GCE adapter stub |
| `lib/cloud.nu` | Cloud provider helpers including `find_vultr`; must be sourced before `deploy.nu` and `system.nu` |
| `lib/validate.nu` | Manifest validator (20 checks, JSON Schema Draft 7) |
| `lib/build.nu` | Build orchestration |
| `lib/deploy.nu` | Deployment orchestration |
| `lib/artifacts.nu` | Receipt creation and listing |
| `lib/system.nu` | Health checks and platform detection |
| `lib/signing.nu` | Image signing via signify/minisign |
| `lib/suggest.nu` | AX-first suggestion engine |
| `catalog/providers.v1.json` | Machine-readable provider catalog (35+ entries) |
| `schema/manifest.v1.json` | JSON Schema Draft 7 manifest schema |
| `examples/` | Example manifests per provider/arch |
| `artifacts/` | Build receipts and manifests by version (`v0.1.0/` … `v0.1.3/`) |
| `completions/genoa.nu` | Nushell tab-completions for all subcommands |
| `test/smoke.nu` | Smoke test suite (42 tests) |

## 3. How to run

All commands must be run from the **repo root** (genoa.nu sources lib/ and profiles/ with relative paths):

```sh
# Discovery
nu genoa.nu catalog
nu genoa.nu schema
nu genoa.nu providers
nu genoa.nu health

# Validate a manifest
nu genoa.nu validate examples/freebsd-vultr-aarch64.toml

# Dry-run build (safe on macOS/Linux — no disk writes)
nu genoa.nu build examples/freebsd-vultr-aarch64.toml --dry-run

# Full pipeline dry-run
nu genoa.nu run examples/freebsd-vultr-aarch64.toml --dry-run

# Full self-test (returns structured JSON)
nu genoa.nu selftest
```

Real builds (`--dry-run` omitted) require FreeBSD (`mdconfig`, `gpart`, `newfs_msdos`, `newfs`). The buildworld is a Vultr FreeBSD 15 amd64 instance (`root@108.61.206.203`).

## 4. How to test

```sh
# Smoke suite (42 tests, runs on macOS and FreeBSD)
nu test/smoke.nu

# Self-test (structured JSON, runs as subprocess)
nu genoa.nu selftest
```

CI runs smoke tests + manifest validation via GitHub Actions (Nu 0.111.0 musl binary). Gitea Actions (FreeBSD native) are pending Tailscale auth.

## 5. Architecture

`genoa.nu` is a thin **shim** that sources everything at file scope (source inside `if` loses outer scope — Nu 0.101.0 regression, still present). Load order is fixed:

1. `profiles/*.nu` — build profiles (uefi, kboot, netbsd)
2. `adapters/*.nu` — provider adapters (linode, vultr, aws, gce)
3. `lib/cloud.nu` — **must come first in lib/** (defines `find_vultr` used by deploy/system)
4. `lib/validate.nu`, `lib/build.nu`, `lib/deploy.nu`, `lib/artifacts.nu`, `lib/system.nu`, `lib/signing.nu`, `lib/suggest.nu`

Build profiles distinguish real vs. dry-run via `run_step`: on FreeBSD with `dry_run=false`, it runs the command via `sh -c`; otherwise it returns the step unchanged with `action: "would-run"`.

SSH key injection (step 13b in `profiles/uefi.nu`): keys from `manifest.network.ssh_keys` are written to a temp file then copied into the image at `/mnt/rootfs/root/.ssh/authorized_keys`. If `ssh_keys = []`, step 13b is **skipped** — no authorized_keys is installed.

## 6. Nu version

**Nu 0.111.0+ required.** Key constraint: `($int)M` inside `$"..."` is parsed as filesize literal — pre-compute integer args as strings before interpolation (see `let image_size_arg = ($image_size | into string) + "M"` in uefi.nu).

CI uses the Nu 0.111.0 musl static binary (cached in GitHub Actions by cache key `nu-0.101.0-linux-x86_64` — note: cache key name is historical, binary is 0.111.0).

## 7. AX-first

Every subcommand emits JSON with a top-level `action` field indicating what happened. No command writes prose to stdout. Structured receipts carry `claims` arrays for `fleet-eval` verification. The provider catalog and manifest schema are self-describing and machine-queryable in under three tool calls:

```sh
nu genoa.nu catalog          # discover providers
nu genoa.nu schema           # get manifest schema
nu genoa.nu describe <file>  # summarize a specific manifest
```

## 8. VCS

This project uses **jj (Jujutsu)**, not git. Never use `git commit` directly.

Standard workflow:

```sh
# Describe current working commit
jj describe -m "feat: add X"

# Move main bookmark to current commit
jj bookmark move main --to @

# Push to remote
jj git push --branch main
```

Use `jj log` to inspect history. `jj st` for status. `jj diff` for changes.

## 9. Active work

- **v0.1.3** — released 2026-05-13; the build at `artifacts/v0.1.3/` is the canonical reference image. Image boots fully under QEMU with EDK2 UEFI (sshd, ntpd, ii_agent, DHCP, growfs all start).
- **v0.1.4-dev** — in progress; 26 subcommands total, fstab step added, Nushell completions, Gitea CI.

## 10. Critical bugs fixed (history)

| Version | Bug | Fix |
|---|---|---|
| v0.1.3 | `loader.conf`/`rc.conf` not written to disk | `save --force` in steps 9b/9c of uefi.nu |
| v0.1.3 | `loader.efi` version mismatch | Step 8b replaces buildworld's loader from base.txz |
| v0.1.2 | FAT32 cluster count too low for 128MB ESP | Changed to FAT16 (`newfs_msdos -F 16`) |
| v0.1.2 | `mountroot>` hang at boot | `loader.conf` now sets `vfs.root.mountfrom="ufs:/dev/gpt/rootfs"` |
| v0.1.2 | Nu filesize interpolation | Pre-compute: `let arg = ($size | into string) + "M"` |
| v0.1.1 | Nu `source` inside `if` loses scope | Hoisted all 4 `source` calls to file scope in `genoa.nu` |

**SSH access note:** v0.1.3 was built with `ssh_keys = []`. No authorized_keys is in the image. Console (KVM) is the only login path if deployed to Vultr. Add your public key to `network.ssh_keys` in the manifest before building to get SSH access.

## 11. License

BSD-2-Clause
