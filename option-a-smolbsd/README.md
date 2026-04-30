# genoa — Option A: smolBSD-for-agents

A Nushell CLI that takes a TOML manifest and produces (or plans) a minimal
BSD VM image with an agent baked in. AX-first: an LM dropped in cold can
discover, plan, and build in under 3 tool calls.

## Quickstart (3 commands)

```sh
nu genoa.nu catalog                              # see what profiles exist
nu genoa.nu describe examples/rpi5-iiagent.toml # inspect a build plan
nu genoa.nu build examples/rpi5-iiagent.toml --dry-run  # see exact commands
```

## AX-first design

Every subcommand emits structured JSON. No prose-only paths. An LM cold-starts:

1. `nu genoa.nu catalog` → JSON list of profiles with `example_manifest` fields.
2. `nu genoa.nu schema` → full JSON Schema for manifests; validate before building.
3. `nu genoa.nu describe <manifest>` → resolved build plan (arch, kernel config, package set, agent URL, output path, size estimates).

From those 3 calls the LM knows exactly what to feed `build`.

## Subcommands

| Command | Description |
|---------|-------------|
| `nu genoa.nu schema` | Print JSON Schema for `genoa.toml` manifests |
| `nu genoa.nu catalog` | Print catalog JSON of all producible profiles |
| `nu genoa.nu describe <manifest.toml>` | Parse and plan; no side effects |
| `nu genoa.nu build <manifest.toml> [--dry-run]` | Execute or plan the build |
| `nu genoa.nu verify <image> <receipt.json>` | Recompute sha256 and check attestation |

## Manifest format

Manifests are TOML files conforming to `schema/manifest.v1.json`.
See `examples/rpi5-iiagent.toml` (FreeBSD aarch64 + ii-agent on RPi5)
and `examples/qemu-x86_64.toml` (QEMU amd64 bring-up, no agent).

```toml
schema_version = "v1"

[image]
name = "smolbsd-rpi5-iiagent"
version = "v0.1.0"
format = "raw"
size_mb = 4096

[target]
os = "freebsd"
os_version = "15.0-RELEASE"
arch = "aarch64"
platform = "rpi5"

[kernel]
config = "RPI"
strip_debug = true

[agent]
name = "ii-agent"
version = "v0.1.0"

[agent.source]
type = "gitea_release"
repo = "studio/ii-agent"
tag  = "ii-agent/v0.1.0-freebsd-aarch64"
asset = "ii-agent-freebsd-aarch64"
sha256 = "..." # required for production
```

## Schema URLs

- Manifest schema: `schema/manifest.v1.json`
- Receipt schema: `schema/receipt.v1.json`

Both are JSON Schema draft 2020-12, versioned at `v1`.

## What's real vs stubbed

**Real (executes):** manifest parsing and validation, build plan resolution,
`describe` output, `--dry-run` JSON, output directory creation, placeholder image
creation, SHA-256 verification, receipt emission.

**Stubbed:** `make buildworld`, `make buildkernel`, `make vm-image`, agent fetch,
signify signing. Each stub prints `STUB: <reason>` with the would-run command in JSON.

## Build requirements (for real builds)

- FreeBSD 15.0-RELEASE build host (or `fb-vm-24` via `freebsd-build-vm` skill)
- `/usr/src` with FreeBSD source tree at the target release
- `nushell` 0.106.0+ on the orchestrating host

## Attestation / receipt

Every build emits a co-located `<image>.receipt.json` conforming to
`schema/receipt.v1.json`. Fields: image SHA-256, manifest SHA-256, build host,
builder type, agent provenance, verifiable claims, optional signify signature.

Verify any image:
```sh
nu genoa.nu verify out/smolbsd-qemu-x86_64-v0.1.0.qcow2 \
                   out/smolbsd-qemu-x86_64-v0.1.0.receipt.json
```

## License

BSD-2-Clause. See `LICENSE` and `LICENSE-DEPS.md` for dependency licenses.
