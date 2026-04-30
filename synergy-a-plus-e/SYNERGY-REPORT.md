# A+E Synergy Report
**Option A** (genoa / smolBSD) × **Option E** (lsd / Linux→BSD Stomper Deploy)
Analyst: bridge.nu v0.1.0 — 2026-04-30

---

## Summary verdict

**PARTIAL — score 6/10.**

A and E are complementary tools that happen to share one use-case seam. They do not conflict badly, but they were designed with different deployment models in mind. Making them compose into a single-manifest, one-command flow requires a well-defined 20-40 line patch to E and one new bridging field in A. The conceptual fit is real; the implementation gap is small but non-zero.

---

## What each tool does

| | Option A (genoa) | Option E (lsd) |
|---|---|---|
| Role | Build a minimal FreeBSD raw image with an agent baked in | Emit a Linux-rescue bootstrap that installs BSD on a Linux-only cloud host |
| Output | `<name>.raw` + `<name>.receipt.json` | `bootstrap.sh` + `bsdinstall.script` |
| Install model | Image is produced offline on a FreeBSD build host | Image is produced online during cloud rescue via mfsBSD + bsdinstall(8) |
| Agent | Baked into the image at build time | Not in scope — stock FreeBSD only |
| Format | Raw disk image (or qcow2/vmdk) | Shell script + bsdinstall script |

---

## The seam: where A's output plugs into E's installer

E's bsdinstall.script contains:

```sh
export DISTRIBUTIONS="base.txz kernel.txz"
export BSDINSTALL_DISTSITE="https://download.freebsd.org/releases/{{ bsd_arch }}/{{ bsd_arch }}/{{ bsd_version }}"
```

This is the substitution point. When using a stock E install, bsdinstall fetches FreeBSD distribution tarballs from `download.freebsd.org` and installs them. To use A's image instead, E's `bootstrap.sh` must:

1. **Skip** the mfsBSD ISO fetch.
2. **Fetch** A's raw image (from a URL or scp'd to the rescue host).
3. **Verify** its sha256 against `receipt.hashes.image_sha256`.
4. **Write** it directly to the target disk: `dd if=genoa.img of=/dev/sda bs=8M conv=fdatasync`
5. **Reboot** — the image already has the agent, rc.conf, and hostname baked in.

QEMU is still useful in this path: writing to `/dev/sda` from within a Linux OS running on that same disk is unsafe. The rescue host's OS is in RAM (mfsBSD-style), but the Linux rescue disk IS the target — so QEMU passthrough (`-drive file=/dev/sda,if=virtio`) makes the write safe even in Linux rescue.

The `bsdinstall.script` is entirely dropped in custom_image mode. A's image already contains the configured rc.conf and agent.

**SSH key injection** is the one unresolved step: A's `[network]` section has no `ssh_keys` array (it has `interface`, `mode`, `hostname`). After dd, E cannot inject keys into the installed system without a second QEMU boot or an mdconfig(8) image mount. The cleanest fix is to add `network.ssh_keys` to A's manifest schema so genoa bakes the keys into `/root/.ssh/authorized_keys` at image build time.

---

## Schema conflicts (full table)

| Key | A meaning | E meaning | Severity | Resolution |
|---|---|---|---|---|
| `[target]` | Build target: OS, arch, platform, build_host | Cloud provider, plan, region | **HIGH** | Rename E's `[target]` to `[deploy]` in the unified manifest. Bridge splits before routing to each CLI. |
| `schema_version` | `"v1"` (string const, genoa-specific) | Not used — E uses `lsd_schema_version = "1.0.0"` | LOW | Different key names. No collision. |
| `[network]` | NIC interface + DHCP mode + hostname (baked into image) | ssh_keys array + hostname (written to disk by bsdinstall) | MEDIUM | `hostname` is shared (bridge copies to both). `ssh_keys` is E-only; `interface` is A-only. Needs `network.ssh_keys` added to A's schema for baked-in key support. |
| `[trust]` (E) vs `[signing]` (A) | A: signify key paths for image signing | E: mfsBSD ISO sha256 + provenance URL | LOW | Different key names, different semantics. In custom_image mode, `trust.mfs_image_sha256` is replaced by `deploy.base.custom_image_sha256` from A's receipt. |
| `format` (A) | qcow2 / raw / vmdk | Not present in E — E installs via bsdinstall, no image format concept | MEDIUM | For A+E, format must be `raw`. qcow2 cannot be dd'd to a block device without conversion. Bridge validates this and rejects non-raw in custom_image mode. |
| `arch` encoding | A: `aarch64` (LLVM convention) | E: `aarch64` (same) | NONE | No conflict. |
| `os_version` pattern | A: `15.0-RELEASE` (allows patch: `15.0.1-RELEASE`) | E: `15.0-RELEASE` (same pattern) | NONE | No conflict. |
| `platform` (A) | rpi5 / qemu / rpi4 / generic | Not present in E | LOW | Bridge maps A `platform=qemu` → E's `qemu_machine=virt,accel=kvm`. No conflict, just a translation. |

---

## New fields required

### In E (lsd) — required for custom_image mode

```toml
# In [base]:
mode                = "custom_image"   # enum: mfsbsd | custom_image
custom_image_url    = "https://..."    # URL or file:// path to genoa raw image
custom_image_sha256 = "abcd..."        # from A's receipt.hashes.image_sha256
```

`lsd.nu` changes needed:
- `validate_manifest`: accept `base.mode` field; validate `custom_image_url` + `custom_image_sha256` when mode=custom_image
- `render_bootstrap`: when mode=custom_image, emit `fetch_and_verify_image()` + `write_image_to_disk()` instead of `fetch_and_verify_iso()` + `boot_mfsbsd()`
- `render_bsdinstall`: when mode=custom_image, return empty string (script not needed)
- Schema: add three fields to `base` object

Estimated diff: ~40 lines in lsd.nu, ~20 lines in schema/manifest.v1.json.

### In A (genoa) — optional but recommended

```toml
# In [network]:
ssh_keys = ["ssh-ed25519 AAAA..."]   # inject into /root/.ssh/authorized_keys at build time
```

```toml
# In [image]:
export_url = "https://cdn.example.com/smolbsd-v0.1.0.raw"   # so bridge.nu can auto-populate deploy.base.custom_image_url
```

Without `network.ssh_keys` in A, the E bootstrap must either (a) inject keys via a second QEMU pass or (b) rely on provider IMDS at first boot. Neither is as clean as baking the keys at build time. The `export_url` field is convenience-only — bridge.nu can also accept a file:// path.

---

## Smallest change for one-command flow

**Net total: ~60 lines of code, zero breaking schema changes.**

### Step 1: Patch lsd.nu (~40 lines)

Add custom_image install mode to `render_bootstrap` and `render_bsdinstall`. The existing QEMU passthrough infrastructure in `bootstrap.sh` already handles the mechanism — the only change is what gets written to the disk (raw image dd vs bsdinstall from mfsBSD).

### Step 2: Add `network.ssh_keys` to genoa manifest.v1.json (~15 lines)

One new optional field in the `network` object. genoa bakes the keys into the image during step 10 (`install_agent_into_image`) via the same mdconfig mount hook.

### Step 3: bridge.nu already works

`bridge.nu plan unified.toml` runs without error today (tested). After the lsd patch, it would emit a fully actionable plan: A's build steps + the artifact handoff point with the exact sha256 from the receipt + E's custom_image bootstrap steps.

### Resulting UX for an LM

```
# Discover
nu bridge.nu version
nu bridge.nu schema

# Plan (no side effects)
nu bridge.nu plan hetzner-cax11-iiagent.toml

# Execute (requires FreeBSD build host + Hetzner account)
nu genoa.nu build hetzner-cax11-iiagent.toml
# → out/image/smolbsd-hetzner-iiagent-v0.1.0.raw + receipt.json

# Deploy
nu bridge.nu inject-receipt unified.toml out/image/smolbsd-hetzner-iiagent-v0.1.0.receipt.json
nu lsd.nu build /tmp/bridge-plan/lsd-manifest.toml --out ./lsd-out
# scp lsd-out/bootstrap.sh root@rescue-host:/tmp/
# ssh root@rescue-host 'bash /tmp/bootstrap.sh'
```

Three tools, one manifest, one command per phase. An LM cold-starts with `bridge.nu schema` and has everything it needs.

---

## Does it cleanly compose?

**Partial.** The tools are philosophically aligned (both BSD-first, both AX-first JSON output, both BSD-2-Clause, both Nushell), but they were independently designed for different layers of the stack:

- A is a **build tool** — it produces an artifact.
- E is an **installer tool** — it puts an artifact on a disk in the cloud.

The gap is that E hardcodes its artifact source as "mfsBSD ISO + bsdinstall stock install." It has no concept of a pre-built image. Adding that concept is a small but real code change.

The **receipt schema** from A is well-suited as the handoff envelope: it already carries `hashes.image_sha256`, `image.output_path`, `image.format`, and `build.arch`. Bridge.nu reads the receipt and injects those values into the lsd manifest. This part works today.

The **schema conflict** on `[target]` is the only name collision worth caring about. It is resolved by the `[deploy]` renaming in the unified manifest, with no changes to either tool's existing schema.

---

## Score: 6/10

| Dimension | Score | Notes |
|---|---|---|
| Philosophical alignment | 9/10 | Both BSD-first, AX-first, JSON output, BSD-2-Clause, Nushell |
| Schema compatibility | 6/10 | One hard name collision (`[target]`), one semantic mismatch (`[network]`) |
| Data handoff | 8/10 | A's receipt has everything E needs. Bridge reads it cleanly. |
| Code changes needed | 6/10 | E needs ~40 lines; A needs ~15 lines. Not trivial but not a refactor. |
| Operational fit | 5/10 | A runs on a FreeBSD build host; E runs on a Linux rescue environment. Different machines, different times. The pipeline is sequential, not parallel. |
| LM discoverability | 7/10 | With bridge.nu, three calls get you the full plan. Without it, an LM must infer the connection from two independent CLIs. |

**Overall: 6/10 — natural fit, non-trivial glue.** If this were a 10, E would already have a `base.mode = "custom_image"` field. It doesn't. The tools were designed for adjacent but not identical problems. The synergy is real and worth pursuing, but it requires a conscious decision to patch E, not just a config change.

---

## Files in this directory

| File | Purpose |
|---|---|
| `bridge.nu` | Bridge CLI: `plan`, `schema`, `version` subcommands. Runs without error today. |
| `unified.toml` | Example combined manifest: genoa image profile + lsd deploy target in one file. |
| `SYNERGY-REPORT.md` | This document. |
