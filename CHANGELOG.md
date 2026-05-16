# Changelog

All notable changes to genoa are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

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
