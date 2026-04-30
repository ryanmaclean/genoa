# Bake-off Report — Option A (smolBSD-for-agents)

## What was built
- Files: 8 (plus 2 generated test artifacts in out/), total LOC: 1712
- Languages: Nushell (.nu), JSON Schema (.json), TOML (.toml), Markdown (.md)
- Subcommands actually working: `schema`, `catalog`, `describe`, `build`, `build --dry-run`, `verify`

## License compliance
- All deps:
  - nushell 0.111.0 — MIT
  - FreeBSD base tools (sha256, hostname, uname, mkdir, stat) — BSD-2-Clause (on FreeBSD); not bundled
  - signify (optional) — ISC (MIT-equivalent)
  - FreeBSD build system (make, mk-vmimage.sh) — BSD-2-Clause; not bundled, invoked as stubs
- All under: BSD-2-Clause (our code), MIT (nushell), ISC/BSD-2 (system tools not bundled)
- No GPL/LGPL/AGPL/BSD-4-Clause code bundled or statically linked
- Full audit in LICENSE-DEPS.md

## AX-first surface verification

### `nu genoa.nu catalog`

```json
{
  "schema_version": "v1",
  "catalog_version": "v1",
  "generator": "genoa/0.1.0",
  "description": "All image profiles this genoa instance can produce. Feed any profile's example_manifest to `genoa describe` or `genoa build`.",
  "profiles": [
    {
      "id": "freebsd-aarch64-rpi5-iiagent",
      "name": "FreeBSD aarch64 RPi5 + ii-agent",
      "description": "Minimal FreeBSD 15.0-RELEASE aarch64 for Raspberry Pi 5 with ii-agent v0.1 wired to Ergo IRC.",
      "target": { "os": "freebsd", "os_version": "15.0-RELEASE", "arch": "aarch64", "platform": "rpi5" },
      "agent": "ii-agent",
      "image_format": "raw",
      "size_budget_mib": 512,
      "example_manifest": "examples/rpi5-iiagent.toml",
      "status": "stable",
      "tags": ["irc", "agent", "rpi5", "aarch64", "freebsd"]
    },
    {
      "id": "freebsd-amd64-qemu-base",
      "name": "FreeBSD amd64 QEMU bring-up (no agent)",
      "example_manifest": "examples/qemu-x86_64.toml",
      "status": "stable"
    },
    {
      "id": "freebsd-aarch64-qemu-iiagent",
      "name": "FreeBSD aarch64 QEMU + ii-agent (CI)",
      "status": "beta"
    }
  ],
  "how_to_build": {
    "step1": "Pick a profile from .profiles[]. Note .example_manifest.",
    "step2": "nu genoa.nu describe <example_manifest>  # verify the plan",
    "step3": "nu genoa.nu build <example_manifest> --dry-run  # see exact commands",
    "step4": "nu genoa.nu build <example_manifest>  # execute (requires FreeBSD build host)",
    "step5": "nu genoa.nu verify out/<image> out/<receipt.json>  # check attestation"
  }
}
```

### `nu genoa.nu schema | jq '.["$schema"]'`

```
"https://json-schema.org/draft/2020-12/schema"
```

### `nu genoa.nu describe examples/rpi5-iiagent.toml`

```json
{
  "schema_version": "v1",
  "plan_type": "build_plan",
  "dry_run": false,
  "genoa_version": "0.1.0",
  "manifest_path": "examples/rpi5-iiagent.toml",
  "resolved": {
    "image": {
      "name": "smolbsd-rpi5-iiagent",
      "version": "v0.1.0",
      "format": "raw",
      "output_path": "./out/smolbsd-rpi5-iiagent-v0.1.0.raw",
      "receipt_path": "./out/smolbsd-rpi5-iiagent-v0.1.0.receipt.json"
    },
    "target": {
      "os": "freebsd", "os_version": "15.0-RELEASE", "arch": "aarch64",
      "platform": "rpi5", "build_host": "builder@localhost:2225"
    },
    "kernel": { "config": "RPI", "strip_debug": true, "extra_options": ["nodevice wlan", "..."] },
    "packages": { "include": ["FreeBSD-runtime", "FreeBSD-clibs", "...14 packages"], "count": 14 },
    "agent": {
      "name": "ii-agent", "version": "v0.1.0",
      "install_path": "/usr/local/bin",
      "resolved_url": "http://gitea.local:3000/studio/ii-agent/releases/download/ii-agent/v0.1.0-freebsd-aarch64/ii-agent-freebsd-aarch64",
      "rc_service_name": "ii_agent", "rc_service_enabled": true,
      "rc_service_args": "-s ergo.local -p 6697 -n smolbsd-pi5 -j '#fleet' --tls"
    }
  },
  "build_steps": [ "...12 steps (4 real, 7 stubbed, 1 receipt)..." ],
  "size_estimates": { "total_on_disk_mib": 108, "within_budget": true, "budget_mib": 512 },
  "validation": { "manifest_valid": true, "schema_version_ok": true, "required_fields_present": true }
}
```

## What works (real)

- Manifest TOML parsing with structured error on bad TOML
- Schema version validation (rejects non-v1 manifests with JSON error)
- Required field validation (lists missing fields in JSON error)
- Arch and format validation
- Full build plan resolution: arch mapping (amd64→amd64, aarch64→arm64), kernel config, 12 build steps, agent URL resolution from gitea_release/url/local_path, package set, network config
- `build` (stub mode): creates real output directory, writes placeholder image, computes real sha256, emits valid receipt JSON
- `verify`: recomputes sha256 from disk, compares to receipt, returns PASS/FAIL as JSON with claims summary and trust field
- All subcommands exit non-zero with structured JSON errors on failure
- AX acceptance test: all 3 calls complete in under 1 second each, return parseable JSON

## What's stubbed

- `make buildworld` / `make buildkernel` / `make vm-image` — each prints its would-run command JSON with `"action":"would-run"` and `stub_reason`; real invocation requires a FreeBSD build host with /usr/src
- Agent fetch — emits resolved URL but does not curl; sha256 must be supplied in manifest and verified post-fetch
- signify signing — emits receipt with `"placeholder": true` in signing block; real signing requires a signify key file on the build host
- The "image" produced by `build` (non-dry-run) is a text placeholder for testing `verify`; replace with `cp` from the FreeBSD release output directory

## Build/run instructions

```sh
nu genoa.nu catalog                                 # discover profiles
nu genoa.nu describe examples/rpi5-iiagent.toml    # inspect build plan
nu genoa.nu build examples/qemu-x86_64.toml --dry-run  # see all commands
```

## Self-graded fit score: 8/10

## Self-grade weakness: Actual `make release` orchestration requires a live FreeBSD build host; the CLI is a plan-and-validate layer, not a full build system. A serious implementation would add SSH remoting to `fb-vm-24` so the CLI can actually drive the build remotely rather than printing stub commands.

## Synergy hooks (for combination tests)

- "If E (LSD) wants to consume my image: my output path is `./out/<name>-<version>.<format>` and the co-located receipt is `./out/<name>-<version>.receipt.json` conforming to `schema/receipt.v1.json`."
- "If D (spec) wants to validate my receipts: my receipt schema lives at `schema/receipt.v1.json` (JSON Schema draft 2020-12, `$id` is the canonical URL). Feed the receipt to a JSON Schema validator against that file."
- "If B (cloud-init) wants to inject user-data into my image: the `vm_extra_pre_umount()` hook in the release conf is the right injection point; add a `cloud-init` package to `[packages].include` and drop the datasource config at `/etc/rc.conf.d/cloudinit` in that hook."
- "If C (unikernel) needs a comparison baseline: my qcow2 artifact size target is 128 MiB (amd64 QEMU profile); emit `nu genoa.nu describe examples/qemu-x86_64.toml | jq .size_estimates` for the breakdown."
