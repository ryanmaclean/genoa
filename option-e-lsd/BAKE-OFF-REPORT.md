# Bake-off Report — Option E (LSD)

## What was built

- Files: 15, total LOC: ~1900 (including this report)
- Languages: Nushell 972 LOC (lsd.nu + 3 provider adapters), Bash template 231 LOC (bootstrap.sh.tera), bsdinstall sh template 92 LOC
- Subcommands actually working: `catalog`, `schema`, `describe`, `build`, `verify`

## License compliance

- All deps: BSD-2-Clause (mfsBSD, fetched at runtime), MIT (Nushell runtime), PSF-2.0 (Python, optional)
- Code written: BSD-2-Clause throughout
- Confirmed NOT vendoring: iPXE (GPL-2), cloud-localds (GPL), xorriso (GPL-2), syslinux (GPL-2)
- QEMU (GPL-2) installed from distro package manager at runtime — not vendored, not linked

## AX-first surface verification

Actual stdout from:

### `nu lsd.nu catalog | jq '.providers'`

```json
[
  {
    "id": "hetzner-cloud",
    "display_name": "Hetzner Cloud",
    "rescue_method": "api-rescue-boot",
    "trampoline_strategy": "rescue-qemu-passthrough",
    "imds_base": "http://169.254.169.254/hetzner/v1/metadata",
    "supported_bases": [
      {
        "os": "freebsd",
        "version": "15.0-RELEASE",
        "arch": "aarch64",
        "plans": ["cax11", "cax21", "cax31", "cax41"],
        "filesystem": ["zfs", "ufs"],
        "status": "spec",
        "mfsbsd_url": "https://mfsbsd.vx.sk/files/iso/15/aarch64/mfsbsd-se-15.0-RELEASE-arm64-aarch64.iso",
        "notes": ["virtio-mmio bus on ARM64; UEFI required; KVM available in rescue"]
      }
      ...
    ]
  },
  { "id": "hetzner-robot", ... },
  { "id": "oci", ... },
  { "id": "digitalocean", ... }
]
```

### `nu lsd.nu schema | jq '.["$schema"]'`

```json
"https://json-schema.org/draft/2020-12/schema"
```

### `nu lsd.nu describe examples/hetzner-cax-freebsd.toml`

```json
{
  "schema_version": "1.0.0",
  "tool": "lsd",
  "tool_version": "0.1.0",
  "manifest": "examples/hetzner-cax-freebsd.toml",
  "valid": true,
  "errors": [],
  "warnings": ["trust.mfs_image_sha256 is a placeholder (all zeros) — replace with real digest before production use"],
  "plan": {
    "provider": "hetzner-cloud",
    "plan": "cax11",
    "region": "nbg1",
    "rescue_method": "api-rescue-boot",
    "trampoline_strategy": "rescue-qemu-passthrough",
    "base_os": "freebsd",
    "base_version": "15.0-RELEASE",
    "arch": "aarch64",
    "filesystem": "zfs",
    "hostname": "bsd-cax11-001",
    "ipv6": true
  },
  "installer": {
    "mfsbsd_url": "https://mfsbsd.vx.sk/files/iso/15/aarch64/mfsbsd-se-15.0-RELEASE-arm64-aarch64.iso",
    "mfsbsd_sha256_expected": "0000000000000000000000000000000000000000000000000000000000000000",
    "sha256_is_placeholder": true,
    "provenance_url": "https://mfsbsd.vx.sk/files/iso/15/aarch64/..."
  },
  "qemu": {
    "qemu_bin": "qemu-system-aarch64",
    "qemu_machine": "virt,accel=kvm",
    "qemu_cpu": "host",
    "qemu_target_disk": "/dev/sda",
    "qemu_target_disk_in_bsd": "vtbd0",
    "firmware_required": true,
    "firmware_package": "ovmf"
  },
  "imds": {
    "endpoint": "http://169.254.169.254/hetzner/v1/metadata",
    "provider_notes": ["virtio-mmio bus on ARM64; UEFI required; KVM available in rescue"]
  },
  "next_steps": [...]
}
```

### `nu lsd.nu describe examples/do-debian-mfsbsd.toml | jq '.warnings'` — IPv6 warning

```json
[
  "trust.mfs_image_sha256 is a placeholder (all zeros) — replace with real digest before production use",
  "digitalocean-custom-images-no-ipv6: DigitalOcean custom-image Droplets do not receive automatic IPv6 configuration. The DO networking agent is absent from BYOI images. Set ipv6=false in [network]. Reference: https://docs.digitalocean.com/products/custom-images/"
]
```

IPv6 warning confirmed. It is structural — always emitted for `digitalocean` provider, regardless of manifest `ipv6` field value.

## What works (real)

- All 5 subcommands (`catalog`, `schema`, `describe`, `build`, `verify`) execute and return valid JSON
- Manifest validation with structured errors: enum checks (provider, os, arch, fs), hostname RFC-1123, sha256 format, IPv6 conflict detection
- Template rendering: `build` substitutes all Tera-style variables in `bootstrap.sh.tera` and `bsdinstall.script.tera`, writes to `--out` dir
- Receipt generation: `build` emits `lsd-receipt.json` with SHA-256 hashes and size for each artifact
- Receipt verification: `verify` recomputes hashes, compares structurally, reports mismatches
- DO IPv6 warning: always emitted as a structured warning in `describe` output for any `digitalocean` manifest
- AX-first 3-call cold-start: `catalog` → `schema` → `describe` gives a cold LM everything needed to call `build`
- Placeholder sha256 detection: warns (not errors) so examples are usable without real download

## What's stubbed

- mfsBSD ISO sha256 in all example manifests is `000...000` (placeholder) — replace with real digest from mfsbsd.vx.sk before production use
- QEMU is not actually invoked — bootstrap.sh renders correctly but is not executed in this harness
- `bsdinstall script` is not run — template renders with correct bsdinstall(8) syntax but is not executed
- OCI BYOI upload is not automated — the BYOI workflow is documented in the adapter and example TOML
- No actual cloud credentials; `describe` emits `would-deploy` plan only
- `tool.commit` in receipts is `"unknown"` — git integration not wired in v0.1

## Provider matrix honesty

| Provider | Base | Arch | Status |
|---|---|---|---|
| Hetzner Robot | FreeBSD 15 | x86_64 | spec'd via depenguin-run pattern, NOT exercised in this harness |
| Hetzner Cloud CAX | FreeBSD 15 | aarch64 | spec'd, virtio-mmio quirks documented, NOT exercised |
| OCI Always Free | FreeBSD 15 | aarch64 | BYOI documented, qcow2 upload path noted, NOT exercised |
| DO custom image | FreeBSD 15 | x86_64 | trampoline spec'd, IPv6 warning baked in, NOT exercised |
| AWS / GCP | any | any | not addressed in v0.1 |

## Build/run instructions

```sh
nu lsd.nu describe examples/hetzner-cax-freebsd.toml
nu lsd.nu build examples/hetzner-cax-freebsd.toml --out ./out
nu lsd.nu verify examples/hetzner-cax-freebsd.toml ./out/lsd-receipt.json
```

## Self-graded fit score: 7/10

## Self-grade weakness

- **Provider TOS volatility**: DO custom-image limits, OCI Always Free capacity, and Hetzner rescue APIs change without notice. The catalog is a hardcoded const — a real v1.0 would fetch from a live catalog endpoint.
- **ARM64 UEFI firmware path**: OVMF/AAVMF package names and firmware file paths differ across Debian versions and Alpine releases. bootstrap.sh tries common paths but will fail on uncommon distros.
- **Tera template substitution**: The current implementation is naive `str replace --all` — does not handle missing variables gracefully or support Tera control-flow syntax (the templates use `{% if %}` blocks that are pattern-replaced, not parsed).
- **mfsBSD sha256 not pre-baked**: All examples ship with placeholder `000...000` sha256 because downloading the large ISO in a harness is impractical. A real release would bake the real digest into the catalog.
- **No actual end-to-end test**: The QEMU loop is untested in this harness. The bootstrap.sh is correct by inspection and analogy with depenguin-run, not by execution.

## Synergy hooks

- "If A (smolBSD) emits a FreeBSD image: I can consume A's image as the `mfsbsd_url` payload. A would emit a bootable ISO or qcow2; my manifest's `base.mfsbsd_url` would point to A's artifact URL, and `trust.mfs_image_sha256` would bind to A's emitted sha256. The `lsd build` pipeline would fetch A's image, verify it, and boot it in QEMU exactly as it does mfsbsd.vx.sk images."
- "If D (spec) wants to validate my receipts: my receipt schema is at `schema/receipt.v1.json`. The `trust_level` field is explicit (`unsigned` | `cosign-verified` | `slsa-l1..3`). D's verifier can POST a receipt JSON to a validator endpoint and match against the schema without any out-of-band knowledge."
- "If B (ports/packages) produces a FreeBSD package set: `bsdinstall.script.tera` can be extended to run `pkg install` post-install from B's repository URL. The template already supports post-install scripting via the bsdinstall `script` phase."
