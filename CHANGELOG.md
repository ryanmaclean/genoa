# Changelog

All notable changes to genoa are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [v0.1.4-dev] — Unreleased

### Added (this session, 2026-05-16)

**CLI surface expansion (26 subcommands total):**
- `sign` — image signing via signify/minisign with `--dry-run`
- `verify-image` — mounts image and checks loader.conf/rc.conf present (FreeBSD only)
- `diff` — compare two build receipts field by field
- `deploy-from-snapshot` — launch Vultr instance from an existing snapshot
- `clone-instance` — clone a running Vultr instance
- `snapshots` / `snapshot-import` / `snapshot-status` — Vultr snapshot lifecycle
- `instances` — list running Vultr instances (with `--all`)
- `watch` — poll snapshot/instance until target status (with timeout)
- `providers` — rich catalog query with `--id` filter
- `receipts` — list all build receipts in artifacts/
- `versions` — list published Gitea releases via API
- `health` — check all 10 required tools + platform readiness
- `selftest` — run smoke suite, return structured JSON
- `notify` — enriched Datadog metrics (profile/host/os tags, age_hours, step_count)
- `status` — full system state (snapshots, instances, recent builds, platform)
- `run` — full validate→build→publish→deploy pipeline with per-stage results

**Profiles & Providers:**
- NetBSD profile stub (`profiles/netbsd.nu`) + example manifest
- AWS EC2 provider entry + adapter stub + example manifest
- GCE GCP provider entry + adapter stub + example manifest
- Linode adapter: full rescue-dd plan with detailed per-step instructions

**Validator strengthened (20 checks):**
- `image_size_minimum` (≥512 MB)
- `agent_sha256_not_placeholder` (warning for all-zeros/ones)
- `network_interface_valid` (provider-aware: vtnet*/eth*/ena*/gve*)
- `ssh_keys_format` (prefix validation)
- `image_version_semver` (vN.N.N)
- `jsonschema_draft7` (validates against schema/manifest.v1.json)

**Schema upgraded** to JSON Schema Draft 7 (`schema/manifest.v1.json`)

**Build profile (uefi.nu):**
- Step 9d: write /etc/fstab (silences boot warnings)
- All configs confirmed written to disk (loader.conf, rc.conf, fstab)

**Infrastructure:**
- Buildworld hardened: 2GB swap, rc.d HTTP service, SSH keepalive, Gitea act_runner registered
- Nushell completions: `completions/genoa.nu`
- `.gitea/workflows/`: FreeBSD native CI (pending Tailscale auth)
- GitHub Actions upgraded to Nu 0.111.0 musl

**Verified:** v0.1.3 image boots fully under QEMU with EDK2 UEFI — sshd, ntpd, ii_agent, DHCP, growfs all start. `mountroot>` bug definitively gone.

**Test suite:** 42/42 passing (macOS + FreeBSD buildworld + GitHub Actions)

## [v0.1.3] — 2026-05-13

### Fixed
- **Critical boot fix**: `loader.conf` and `rc.conf` are now written to the image filesystem via `save --force` (steps 9b/9c in uefi.nu). Previously these files were only rendered into plan metadata — images booted with empty configs, meaning no sshd, no DHCP, and no agent startup.
- `loader.efi` from base.txz now replaces the buildworld's loader (step 8b) to resolve version mismatch between buildworld (15.0-RELEASE-p5) and kernel tarball (15.0-RELEASE).
- kboot profile: `run_step` now gates execution on Linux (not FreeBSD) — kboot uses sgdisk/loop0/bash which are Linux-only tools.
- kboot: `loader.kboot.conf` and `rc.conf` are now written to disk (same fix class as uefi).

### Added
- `genoa health` — checks all 10 required build tools and reports platform readiness.
- `genoa selftest` — runs the smoke suite as a subprocess and returns structured JSON.
- `network_interface_valid` validator check — ensures interface matches provider conventions.
- `ssh_keys_format` validator check — validates each SSH key starts with a known prefix.
- `image_size_minimum` validator check — requires `size_mb >= 512`.
- `agent_sha256_not_placeholder` validator warning — flags all-zero/all-one sha256 values.
- `image_version_semver` validator check — validates `vN.N.N` format.
- AWS EC2 provider entry in catalog + `adapters/aws.nu` stub + example manifest.
- GCE GCP provider entry in catalog + `adapters/gce.nu` stub + example manifest.
- Nu binary caching in GitHub Actions CI (cache key: `nu-0.101.0-linux-x86_64`).
- GitHub step summaries for smoke and validate-manifests workflows.
- Schema JSON validation step in CI.

## [v0.1.2] — 2026-05-08

### Fixed
- FAT16 ESP (not FAT32) — 128MB ESP with md(4) 4K physical sectors has too few clusters for FAT32 (need 65525+). Changed `newfs_msdos` to `-F 16`.
- ESP size reduced from 512MB to 128MB to leave sufficient rootfs space for base.txz (~600MB).
- `loader.conf` now sets `vfs.root.mountfrom="ufs:/dev/gpt/rootfs"` — without this the loader guesses the wrong root and hangs at `mountroot>`.
- Nu 0.111.0 filesize interpolation bug: `($size)M` inside `$"..."` was parsed as filesize literal, producing `"1.0G"`. Fixed by pre-computing: `let arg = ($size | into string) + "M"`.
- `mdconfig -a -t vnode -f` wraps the raw file as md(4) before gpart/newfs/mount (gpart rejects plain files with "Invalid argument").

### Added
- Step 3b: `mdconfig` attach; step 15b: `mdconfig -d -u` detach.
- `mkdir -p /mnt/rootfs/usr/local/bin` before agent copy (base.txz doesn't create /usr/local).
- Gitea publish integration via `tea` CLI.

## [v0.1.1] — 2026-05-07

### Fixed
- Nu 0.101.0 CI scoping bug: `source` inside `if` branch loses outer-scope variables. Fixed by hoisting all 4 `source` calls to file scope in `genoa.nu`.
- Validate-manifests CI workflow: replaced `nu -c 'from json'` pipe with `python3` JSON parsing.
- OCI closure leak: moved `source formats/convert.nu` to `oci-shim.nu` subprocess.

### Added
- `genoa notify` subcommand — submits build metrics to Datadog via `pup` CLI.
- `genoa status` subcommand — reports build state.
- Receipt schema v1 with nested `image`, `build`, `agent`, `hashes`, `claims` objects.
- Datadog dashboard for genoa builds (monitor 280292621).

## [v0.1.0] — 2026-05-08

### Added
- Initial release.
- `genoa validate` — manifest validation with schema checks.
- `genoa build` — UEFI and kboot profile build pipeline.
- `genoa describe` — manifest introspection.
- `genoa catalog` — provider catalog discovery.
- `genoa schema` — schema introspection.
- `genoa publish` — image publishing to R2/S3/Gitea/local backends.
- `genoa deploy` — Vultr and Linode deployment adapters (Vultr snapshot-url, Linode rescue-dd).
- `genoa run` — full validate→build→publish→deploy pipeline.
- UEFI build profile (`profiles/uefi.nu`) targeting FreeBSD 15 with GPT + FAT ESP + UFS2 root.
- kboot build profile (`profiles/kboot.nu`) for ext4-only providers (GCE, Linode).
- Provider catalog (`catalog/providers.v1.json`) with Vultr and Linode entries.
- Smoke test suite (`test/smoke.nu`) with 23 tests.
- GitHub Actions CI: smoke tests + manifest validation.
- AX-first design: all output is JSON, schema v1, structured receipts with SHA256 claims.
