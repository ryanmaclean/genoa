# HENSHU — Editorial Review
<!-- henshu (編集): editorial review with fresh eyes -->
<!-- Reviewer: Claude Sonnet 4.6, 2026-05-04 -->

---

## Blockers

**B1 — `linode.nu` is unreachable from any real manifest**

`lib/deploy.nu` dispatch (`main deploy`) routes to `adapters/linode.nu` only when a provider's `deployment_path` equals `"rescue-dd"`. No entry in `catalog/providers.v1.json` has `deployment_path: "rescue-dd"`. The `linode_akamai` entry (line 179 of the catalog) has `deployment_path: "byoi-api"`, which routes to `adapters/oci.nu`. A user who sets `provider = "linode_akamai"` in their manifest gets the OCI adapter, not the Linode rescue+dd adapter. The Linode adapter is dead code unless a provider entry is fixed to carry `"rescue-dd"`.

**B2 — `freebsd-vultr-aarch64.toml` fails its own validation**

`image.format = "iso"` in `examples/freebsd-vultr-aarch64.toml` (line 7). The manifest JSON Schema (`schema/manifest.v1.json` line 35) allows only `["qcow2", "raw", "vmdk"]`. The code-side validator (`genoa.nu` line 234) extends that to `["raw", "qcow2", "vmdk", "iso"]` — so the runtime validate passes, but the file advertised as the canonical Vultr example is invalid against the authoritative schema. The smoke test `validate_vultr` therefore tests something the schema does not sanction.

**B3 — `kboot_build` ignores the manifest entirely**

`profiles/kboot.nu` lines 46–49 read `$manifest.hostname?`, `$manifest.image_size_gb?`, `$manifest.image_path?`, and `$manifest.task_endpoint?` — all top-level fields that do not exist in a real manifest (where they live under `network.hostname`, `image.size_mb`, `image.output_path`, and nowhere at all for `task_endpoint`). Every field falls back to its default. Any kboot build silently ignores all manifest content and produces an identical output regardless of the input file.

**B4 — kboot step 9 is interactive; cannot run unattended**

`profiles/kboot.nu` line 169 includes `make menuconfig` in the kernel build command. `menuconfig` opens a terminal UI and blocks forever unless a TTY is present. A non-dry-run kboot build on FreeBSD would stall permanently at this step.

**B5 — ~~Receipt written by `genoa.nu build` fails its own schema~~ RESOLVED**

This blocker is resolved in the lib/ refactor. `lib/build.nu` now writes a
schema-conformant receipt with `schema_version: "v1"` and the required top-level
objects `image`, `build`, `agent`, `hashes`, `signing`, and `claims`. The receipt
also populates `claims` with verifiable probe/expect pairs for fleet-eval integration.
The old monolithic `genoa.nu` receipt writer has been replaced.

**B6 — ~~`run` does not chain `validate → build → deploy`~~ PARTIALLY RESOLVED**

`main run` in `genoa.nu` now chains `validate → build → publish → deploy` as
four stages, each run via subprocess. The validate stage runs first and aborts
the pipeline on failure. `docs/agent-port-quickstart.md` has been updated to
reflect the correct four-stage chain. The `README.md` description (out of scope
for this doc pass) still requires a separate update.

---

## Inconsistencies

**I1 — Vultr adapter uses snapshot-from-URL; catalog says `byoi_format: ["iso"]`**

`catalog/providers.v1.json` (line 145) lists Vultr's `byoi_format` as `["iso"]`. `adapters/vultr.nu` calls `vultr-cli snapshot create-url --url <url>` — a completely different mechanism (snapshot import from HTTPS URL, not ISO upload). These describe different Vultr features. An agent reading the catalog to decide format will choose ISO; the adapter then demands an HTTPS URL and rejects anything else. The template example (`freebsd-vultr-aarch64.toml`) sets `format = "iso"`, reinforcing the wrong expectation.

**I2 — Two `schema_version` fields in `manifest.v1.json`**

`schema/manifest.v1.json` line 6 has `"schema_version": "2"` as a meta-field on the JSON Schema document itself, while line 12 defines the manifest property `schema_version` as `const: "v1"`. The file simultaneously claims to be version 2 and describes version 1 manifests. An agent parsing the schema to understand versioning gets contradictory data.

**I3 — Receipt `schema_version` value: `"1"` vs `"v1"`**

`schema/receipt.v1.json` line 14 requires `schema_version` to be exactly `"v1"` (with the `v` prefix). `genoa.nu` line 109 writes `schema_version: "1"` (no prefix). `profiles/uefi.nu` line 155 also writes `schema_version: "1"`. The validate check in `genoa.nu` line 204 accepts `"v1"` for manifests. The receipt output format violates its own schema on every build.

**I4 — `main describe` documented as performing schema validation; it does not**

`README.md` line 27: "`describe` parses the manifest, validates against schema, prints a plan JSON with build steps." `genoa.nu` `main describe` opens the file, reads a handful of fields with `| default`, and returns a flat record. No validation occurs. No build steps are returned. The output is a five-field summary, not a plan.

**I5 — ~~`agent-port-quickstart.md` dry-run output shape is fiction~~ RESOLVED**

`docs/agent-port-quickstart.md` has been updated. The correct step shape is
`{ "step": N, "label": "...", "action": "would-run", "description": "...", "cmd": "..." }`
matching `profiles/uefi.nu`. The step labels in the doc now match the actual
labels used in the profile (`resolve_artifacts`, `render_loader_conf`, `inject_agent`,
`umount_and_compact`).

**I6 — ~~`agent-port-quickstart.md` validate output shape is wrong~~ RESOLVED**

`docs/agent-port-quickstart.md` has been updated. The correct output shape
(`lib/validate.nu`) is `{"action", "manifest_path", "valid", "checks", "errors", "warnings"}`.
`action` is `"validate"` (not `"validated"`). `errors` is an array of plain strings.
`checks` is documented as an array of per-check records.

**I7 — ~~`agent-port-quickstart.md` deploy output shape is wrong~~ RESOLVED**

`docs/agent-port-quickstart.md` has been updated with the correct Vultr adapter
output shape: `{"action", "provider", "snapshot_id", "instance_id", "instance_ip",
"region", "plan", "image_url"}`. The stale `image_id`, `status`, and `receipt` keys
have been removed.

**I8 — ~~`agent-port-quickstart.md` says `deploy` reads receipt automatically~~ RESOLVED**

`docs/agent-port-quickstart.md` has been updated. The correct resolution order
(`lib/deploy.nu`) is: `--image` flag → `--from-receipt` flag → manifest-derived
path (`output_dir/name-version.format`) → fallback `/tmp/genoa.raw`. The claim
that `output_dir` is scanned automatically has been removed.

**I9 — ~~`run` is documented without `publish`~~ PARTIALLY RESOLVED**

`docs/agent-port-quickstart.md` has been updated to document the correct
four-stage chain: `validate → build → publish → deploy`. `README.md` still
requires a separate update (out of scope for this doc pass).

**I10 — `linode_akamai` catalog entry: `deployment_path: "byoi-api"` and notes contradict each other**

The notes say "Only ext3/ext4 accepted - rules out UFS and ZFS natively." But `deployment_path: "byoi-api"` routes to `adapters/oci.nu`, which sends qcow2 via Object Storage — a different provider's mechanism entirely. The Linode-specific rescue+dd path that actually bypasses the ext4 requirement is implemented in `adapters/linode.nu` but is unreachable because no provider carries `deployment_path: "rescue-dd"`.

**I11 — SSH keys written to temp but never copied into image**

`profiles/uefi.nu` lines 182–186: when `network.ssh_keys` is present, the keys are written to `/tmp/genoa-authorized-keys-<name>`. The step record (lines 438–451) declares `target_path: "/mnt/rootfs/root/.ssh/authorized_keys"` but no `cmd` field copies the temp file to that path. There is no `run_step` call that performs the actual copy. SSH keys in the manifest are silently dropped on FreeBSD real builds.

**I12 — `ssh_keys` field used in `uefi.nu` is absent from `schema/manifest.v1.json`**

`profiles/uefi.nu` reads `$manifest | get network? | get ssh_keys?` (line 183). `schema/manifest.v1.json` lines 232–260 define the `network` object with `interface`, `mode`, `static_ip`, `gateway`, and `hostname`. `ssh_keys` is not there. With `additionalProperties: false` enforced, a manifest carrying `network.ssh_keys` would fail JSON Schema validation.

---

## Dead weight

**D1 — Legacy bare `def` block in `genoa.nu`**

`genoa.nu` ends with bare `def build`, `def deploy`, `def catalog`, `def schema`,
`def describe`, and `def verify` that duplicate or stub the `main *` commands.
The comment says "keep for source-import compatibility" but no other file sources
`genoa.nu` and calls the bare forms. The actual implementations have moved to
`lib/build.nu`, `lib/deploy.nu`, etc. The bare stubs shadow the lib/ implementations
if this file is ever sourced, and `def build` is a stub that returns a static
record rather than delegating to `lib/build.nu`.

**D2 — ~~`emit_receipt` in `profiles/uefi.nu` is computed but discarded~~ RESOLVED**

This is resolved in the lib/ refactor. `lib/build.nu` `main build` now writes the
authoritative schema-conformant receipt. The `emit_receipt` step in `profiles/uefi.nu`
is no longer the primary receipt writer — `lib/build.nu` performs all receipt
construction after the profile returns its build plan.

**D3 — `formats/convert.nu` exports `convert_to_vhd`, `convert_to_vmdk`, `convert_to_gcstar` — none are called**

`adapters/oci.nu` calls `convert_to_qcow2`. No code calls `convert_to_vhd`, `convert_to_vmdk`, or `convert_to_gcstar`. These three functions are exported but have no callers in the repository.

**D4 — `image.output_dir` schema field is never read**

Defined in `schema/manifest.v1.json` lines 43–47, present in `examples/agent-port-template.toml` line 40 (`output_dir = "./out"`). No file in the repository reads `m.image?.output_dir?`. The README and quickstart both reference this field's behavior, but neither the build nor the deploy code honors it.

---

## Promise gaps

**P1 — ~~Signing is entirely unimplemented~~ RESOLVED**

`lib/build.nu` now reads the `signing` section from the manifest. When
`signing.tool = "signify"`, it locates the `signify` or `signify-ossl` binary,
runs `signify -S -s <key_file> -m <image>`, and records the result in the
receipt's `signing` field. `lib/signing.nu` provides standalone `main sign`
and `main verify-image` subcommands for direct invocation. Images built with
`signing.tool = "none"` (the default) remain unsigned.

**P2 — ~~`claims` array in receipts is never populated~~ RESOLVED**

`lib/build.nu` now writes a `claims` array in every receipt. Each entry has
`claim`, `executor`, `probe`, `expect`, and `status` fields for fleet-eval
integration. Five claims are emitted per build: image SHA-256, manifest SHA-256,
agent name, image format, and target OS.

**P3 — ~~`build` object in receipts is never populated~~ RESOLVED**

`lib/build.nu` now writes a `build` object with `host` (from `uname -n`),
`builder_type` (`"dry-run"`, `"genoa-local"`, or `"genoa-crosshost"`),
`os_version`, `arch`, `genoa_version`, `profile`, and `dry_run` fields.

**P4 — ~~Remote build does not pull artifact back~~ RESOLVED**

`lib/build.nu` now SCPs both the image and receipt back from the remote host
after the SSH build completes. The remote image path is extracted from the
remote build JSON result (`image.output_path`); the receipt path is inferred
from the image path by substituting the extension with `.receipt.json`. Both
files are fetched to the local `image.output_dir` via `scp -P <port>`.

**P5 — kboot profile is amd64-only despite FreeBSD kboot supporting aarch64**

`profiles/kboot.nu` line 335 hardcodes `arch: "amd64"` in the plan record. The kboot source reference in the same file (line 378) notes "GCE ARM64 FreeBSD images" use kboot. The step commands reference `/arch/x86_64/boot/bzImage` (line 185) and `/dev/loop0` (Linux loop device, not available on FreeBSD). The profile is Linux-builder-centric, amd64-only, and does not integrate with the `target.arch` field from the manifest.

**P6 — `publish.nu` is not integrated into the main receipt**

When `main run` calls `main publish`, the resulting URL is never written back into the receipt. The receipt has no field for the published URL. An agent trying to retrieve the deployed image URL from the receipt cannot do so.

---

## Polish

**PO1 — `genoa.nu` opens the manifest file twice in `main build`**

Line 15: `let m = open $manifest_file`. Line 87: `let manifest_content = open $manifest_file`. The second open is used only to compute `manifest_sha256` for the receipt. Both variables hold the same data. The comment "Derive image_path from manifest or use default" on line 84 refers to `$m`, not `$manifest_content`.

**PO2 — `kboot_build` step 16 has a hardcoded stale FreeBSD version**

`profiles/kboot.nu` line 267: `"tar -xf /path/to/FreeBSD-13.2-RELEASE-amd64-base.txz"`. The manifest specifies an OS version; this step ignores it and names a specific old release with a literal `/path/to/` placeholder. Even as dry-run documentation this is misleading.

**PO3 — `kboot_build` returns a JSON string; `uefi_build` returns a record**

`profiles/kboot.nu` ends with `$plan | to json`. `profiles/uefi.nu` returns a
record directly. `lib/build.nu` handles this asymmetry with a `try { from json }`
wrapper. This is a smell: two implementations of the same interface with different
return types, requiring a special-case workaround in the caller.

**PO4 — `all-zeros` SHA256 check is too narrow**

`lib/validate.nu`: checks if sha256 is all `"0"` characters. `examples/freebsd-linode-amd64.toml` uses `sha256 = "111...1"` — 64 ones — which is equally fake but passes the check without warning. The validation gives false confidence.

**PO5 — `main describe` help text in `README.md` is inflated**

Line 27: "`describe` parses the manifest, validates against schema, prints a plan JSON with build steps." It does none of those last two things. The actual output is a seven-field summary record. This is the first command a user runs and it sets false expectations.

**PO6 — `status` command exists but is missing from `README.md` subcommand table**

`lib/system.nu` `main status` exists and is listed in the genoa.nu help output.
`README.md` subcommand tables omit it. (README update is out of scope for this doc pass.)

**PO7 — `genoa.nu` example in help text uses `jq` with wrong key path**

`genoa.nu` help text: `nu genoa.nu catalog | jq '.[\"providers\"][0]'`. The catalog
output is a record (not an array), so the correct jq path is `.providers[0]`. The
example would fail as written.

**PO8 — `formats/convert.nu` `convert_to_gcstar` uses `tar` as a Nushell built-in**

Lines 171–173 call `cp`, `tar -czvf`, and `rm` without the `^` external-command sigil. In Nushell, `cp` is a built-in with different syntax; `tar` is not a built-in at all and will error. Only the `dry_run` path is safe. The live path of `convert_to_gcstar` will fail on any Nushell invocation.

**PO9 — `manifest.v1.json` has `"schema_version": "2"` as an undocumented meta-field**

Line 6 of the JSON Schema document has `"schema_version": "2"` at the top level. JSON Schema does not define this key. It appears to be the author's version of the schema file itself, but it is not `$schema`-standard and collides with the `schema_version` property the schema is validating. An agent parsing the schema will encounter an unexpected top-level field.

---

## What's actually working

*Updated to reflect the lib/ refactor.*

- **`genoa catalog`** — returns structured JSON from `catalog/providers.v1.json`. Parseable, machine-friendly, 40+ entries. Works.
- **`genoa schema`** — returns `schema/manifest.v1.json`. Works.
- **`genoa providers`** — returns filtered provider list with arch support, formats, regions. New in lib/ refactor.
- **`genoa validate`** (`lib/validate.nu`) — runs 13 checks; returns `action`, `manifest_path`, `valid`, `checks`, `errors`, `warnings`. Works on a non-FreeBSD host.
- **`genoa describe`** — returns a basic summary record. Useful as a quick sanity check on field presence despite the inflated description.
- **`genoa build --dry-run` (uefi)** — produces a correct multi-step plan with `action: "would-run"` on all destructive steps. Works on macOS/Linux for planning purposes.
- **`genoa build` (uefi, FreeBSD)** — now writes a schema-conformant receipt with `schema_version: "v1"`, `image`, `build`, `agent`, `hashes`, `signing`, `claims`. Remote build via `target.build_host` SCPs artifacts back.
- **`genoa sign` / `genoa verify-image`** (`lib/signing.nu`) — standalone signing commands using signify/minisign. New in lib/ refactor.
- **`genoa deploy --provider vultr --dry-run`** — returns a structured plan JSON. Works.
- **`genoa deploy --provider linode_akamai --dry-run`** — routes to OCI adapter (see B1 — still a blocker). Accidentally returns a valid plan; wrong adapter.
- **`genoa verify`** (`lib/validate.nu`) — checks image and receipt existence, parses SHA256s, handles dry-run receipts correctly. Works.
- **`genoa health` / `genoa selftest` / `genoa notify` / `genoa status`** (`lib/system.nu`) — operational subcommands. New in lib/ refactor.
- **`genoa snapshots` / `genoa snapshot-import` / `genoa snapshot-status` / `genoa instances` / `genoa watch` / `genoa versions`** (`lib/cloud.nu`) — cloud ops subcommands. New in lib/ refactor.
- **`genoa receipts` / `genoa diff`** (`lib/artifacts.nu`) — receipt inventory and diffing. New in lib/ refactor.
- **`genoa suggest`** (`lib/suggest.nu`) — AI-powered manifest generation via Ollama. New in lib/ refactor.
- **`genoa run`** — now chains validate → build → publish → deploy as four subprocess stages. Aborts with `stopped_at` on first failure.
- **`publish.nu`** — `publish_image` and `publish_catalog` are well-structured. R2, S3, Gitea, and local backends have correct tool-detection logic. Dry-run works. Live paths depend on external tools and credentials.
- **Smoke tests** — the tests in `test/smoke.nu` exercise real code paths. They would catch regressions in catalog, schema, describe, validate, and build dry-run. However, `validate_template` and `validate_vultr` pass against a validator that accepts `"iso"` even though the schema does not.
- **Template TOML** — `examples/agent-port-template.toml` is thorough and accurate as documentation, despite a few schema mismatches. It is the best-written file in the repository for a human reader.
