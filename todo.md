# genoa — TODO

Status as of 2026-06-04. genoa builds minimal FreeBSD/NetBSD cloud images with embedded agents and deploys to 40+ providers.

---

## ✅ Done (v0.1.3 → v0.1.4-dev milestone)

- **Image boots** — verified in 2 environments: FreeBSD QEMU (buildworld, KVM, ~30s) and macOS QEMU (Apple Silicon TCG, 121s). EDK2 UEFI → `BOOTx64.EFI` → loader → kernel → login prompt. The `mountroot>` bug is gone (`vfs.root.mountfrom` resolves).
- **53/53 smoke tests** green on macOS, FreeBSD buildworld, and GitHub Actions CI.
- **CI green** — Smoke Tests + Validate Manifests, Nu 0.111.0 musl.
- **Security hardened** (2026-06-04, two ultracode review workflows) — closed a HIGH-severity command-injection class: manifest fields (`image.name`, `output_dir`, `network.hostname`, `agent.name`, `target.os_version`) flowed unsanitized into `^sh -c` in `profiles/uefi.nu`, and `build` never called `validate` so checks were bypassable. Fix: fail-closed `manifest_safety_check` at the top of `lib/build.nu` (runs before any command string is built) + shell-metachar + field-format validation in `lib/validate.nu`. Verified end-to-end: crafted injection manifests now return `action:failed` and execute nothing. Also: verify-image dry-run shape harmonized, notify temp-file cleanup guard, ~19 correctness/silent-failure/AX-first fixes. Deferred by design: BUG-13 (cosmetic step reorder), SF-7 (Vultr API error taxonomy — needs design).
- **29 subcommands** — validate, build, run, sign, verify-image, diff, publish, deploy, deploy-from-snapshot, clone-instance, snapshots, snapshot-import/-status, instances, watch, providers, receipts, versions, notify, status, health, selftest, suggest, catalog, schema, describe.
- **genoa.nu refactored** — 1875 lines → ~290-line shim + 9 `lib/` modules (incl. lib/tools.nu `find_bin`).
- **Validator** — 20 checks incl. JSON Schema Draft 7.
- **Build profile (uefi.nu)** — writes loader.conf, rc.conf, fstab (9b/9c/9d); pkg install (11b); cross-arch tarball fetch (7b) for aarch64 AND riscv64.
- **3-arch UEFI** — amd64 (`BOOTx64.EFI`), aarch64 (`BOOTaa64.EFI`), riscv64 (`BOOTRISCV64.EFI`). FreeBSD mirror paths corrected: `amd64/amd64`, `arm64/aarch64`, `riscv/riscv64` (fixed a latent aarch64 path bug too).
- **ii-agent v0.2.0** — portable `/bin/sh`, no Nu runtime dependency.
- **Providers** — Vultr, Linode, DigitalOcean, AWS EC2, GCE GCP all **real adapters** + OCI; catalog of 40+.
- **`run` pipeline** — validate → build → sign → publish → deploy (sign skipped when signing.tool=none).
- **Infra** — buildworld 2GB swap, rc.d HTTP image server, Gitea act_runner registered.
- **Security** — personal SSH key scrubbed, `.gitleaks.toml`, `bin/pre-push-check.nu`.
- **Docs** — README, CHANGELOG, CLAUDE.md, audit-2026-05-16.md, architecture.md, agent-port-quickstart.

---

## 🆕 RISC-V (new box arrived 2026-06-04)

- ✅ **Build support done** — `examples/freebsd-qemu-riscv64.toml`, BOOTRISCV64.EFI, `riscv/riscv64` mirror, cross-arch fetch, 3 riscv smoke tests (validate + EFI binary + fetch path). Validated by dry-run + adversarial verify.
- ⚠️ **CRITICAL caveat — genoa's UEFI profile assumes pure-UEFI boot, which RISC-V real hardware does NOT do yet.** FreeBSD riscv64 boots via **U-Boot + OpenSBI** (machine→supervisor mode handoff), not standalone loader.efi. The genoa image is valid for **QEMU virt only** right now:
  `qemu-system-riscv64 -machine virt -bios .../opensbi/.../fw_jump.elf -kernel .../u-boot-qemu-riscv64/u-boot.bin -drive file=image.raw,...`
- [ ] **Identify the box** — what board? (StarFive VisionFive2/JH7110, Milk-V Mars/Pioneer, SiFive HiFive FU540/FU740, other). This determines feasibility:
  - VisionFive2: needs upstream U-Boot (ports U-Boot does NOT work) + DTB at `/dtb/jh7110-starfive-visionfive-2-v1.3b.dtb` on ESP + OpenSBI v1.7+ + SPI-flash boot mode.
  - SiFive FU540/FU740: upstream U-Boot for the SoC + OpenSBI platform fw + DTB + SD ZSBL in magic GUID partition.
- [ ] **riscv-sbc profile** (future) — a board-aware profile that lays down U-Boot/OpenSBI/DTB. Out of scope for the QEMU image; needs the board in hand.
- [ ] **Add box to SSH config** — not currently in `~/.ssh/config` or `/etc/hosts`. Once reachable, run a real QEMU-or-hardware boot test.

---

## 🏗️ Build host — MOVED to fbryz3070 (2026-06-04)

- ✅ **New builder: `fbryz3070` (10.0.2.44)** — FreeBSD 15.0-RELEASE-p6 native, Ryzen 9 5950X (32 threads), **128 GiB RAM**, 226 GB free, all build tools + qemu present. Builds are fast and reliable; CAN mount md GPT partitions (verify-image works natively).
- ⚰️ **Retired the 1 GB Vultr buildworld** (`108.61.206.203`) for builds — it CPU/RAM-starved and dropped SSH every build cycle. Keep it only as image HTTP host / Vultr deploy-staging if needed.
- ⚠️ `jj` not installed on fbryz3070 — it pulls via `git` from GitHub; jj stays the local canonical workflow.

---

## 🚧 Blocked (external dependencies)

| Item | Blocker | Unblock action |
|------|---------|----------------|
| **Live cloud deploy** | Vultr account $0 balance (postpaid may work); snapshots `d372185f` (v0.1.3) ready | Confirm Vultr postpaid allows instance create, or add credit |
| **Gitea Actions native FreeBSD CI** | act_runner can't reach LAN Gitea (was on old buildworld) | Re-register runner on fbryz3070 (stable Gitea route) — easy now |
| **Linode rescue-dd test** | `LINODE_TOKEN` not set | Set token, or skip Linode path |
| **genoa suggest (Ollama)** | only cloud-proxy models reachable locally | Test from fleet host with local Ollama models |

Note: fleet network is intermittent (Gitea route flaps from the Mac; stable from fbryz3070). Vultr API IP-block cleared.

---

## 🔴 High priority

- ✅ **v0.1.4 Gitea release PUBLISHED** (2026-06-04, release id 94685) — built on fbryz3070, 3 assets (289 MB image + receipt + manifest). verify-image 5/5 on the built image.
- [ ] **Real cloud boot test** — every boot so far is QEMU. Need ONE successful boot on a real cloud VM (Vultr snapshot deploy, Linode rescue-dd, or wipe fbsd-x86-vultr-01). Confirms growfs, DHCP, ii-agent heartbeat outside emulation. (Vultr API works again — try deploy-from-snapshot `d372185f`.)
- [ ] **Re-register Gitea act_runner on fbryz3070** — native FreeBSD CI with a stable Gitea route (the old buildworld couldn't reach Gitea without Tailscale).
- [ ] **rc.d filename polish** — agent rc.d script installs as `ii-agent` (hyphen, from agent.name) while rcvar is `ii_agent` (underscore). Auto-starts at boot fine, but `service ii_agent ...` fails manually. Install rc.d as the rc_service.name.
- [ ] **Diagnose buildworld SSH instability** — sshd drops every few minutes. Swap added but drops continue. Check `/var/log/auth.log`, cron, Vultr console. Candidate: OOM on 1GB RAM during builds.
- [ ] **Actually build aarch64** — step 7b added but never executed. Fix example manifest (`agent.source.url` points at nonexistent `gitea.local:3000/ii/ii-agent`; sha256 is placeholder). Build + QEMU boot with `qemu-system-aarch64`.

---

## 🟡 Medium priority

- [ ] **Wire `sign` into `run` pipeline** — `sign` subcommand exists but `genoa run` never calls it. No signed images produced. Add optional sign stage when `signing.tool != none`.
- [ ] **Verify `schema/receipt.v1.json` exists** — smoke tests reference it; confirm it's present and matches emitted receipts.
- [ ] **kboot profile is a planning doc** — uses Linux-only tools (sgdisk, loop0, mkfs.ext4). Never builds anything real. Either: (a) set up a Linux build host, or (b) document it as plan-only and gate `genoa build --profile kboot` to dry-run.
- [ ] **Refresh translations** — `docs/fr/` and `docs/ja/` predate the heavy English doc updates. Re-translate README/CHANGELOG or mark as stale.
- [ ] **Consolidate binary-finder helpers** — `find_vultr` (lib/cloud.nu), `find_tool` (publish.nu), `check-vultr-cli` (adapters/vultr.nu) all do the same thing. Unify into `lib/tools.nu` per audit finding #4.
- [ ] **Provider adapter roadmap** — 36 of 40 catalog providers return "not-implemented". Prioritize next adapters (DigitalOcean? Hetzner? real AWS/GCE beyond stubs).

---

## 🟢 Future / backlog

- [ ] **Production ii-agent (Zig)** — current is `/bin/sh` MVP. The `rigfleet-ii-agent-ops` skill targets a Zig agent across 5 cross-compile targets with real task execution, auth, and Claude API integration.
- [ ] **Agent-side telemetry** — deployed images should phone home metrics (DogStatsD), not just build-time `notify`.
- [ ] **Integration test in CI** — once Gitea runner is live, run a real `mdconfig`/`gpart` build + `verify-image` on every push (not just dry-run).
- [ ] **growfs first-boot validation** — confirm root partition expands to fill disk on a real cloud volume larger than the 2GB image.
- [ ] **NetBSD profile** — currently a 13-step planning stub. Needs nbmake cross-build toolchain to be real.
- [ ] **Image signing chain of custody** — receipts have sha256 claims but no cryptographic signature. Add signify/minisign signing + verification in deploy.
- [ ] **`genoa suggest` model eval** — once Ollama-reachable, compare manifest quality across models (llama3.2, qwen, etc.).

---

## Notes

- **VCS**: jj (not git). Workflow: `jj describe -m "..."` → `jj bookmark move main --to @` → `jj git push --branch main`.
- **Gitea**: `string/genoa` at `http://10.0.2.230:3001` (login `i9-gitea`). Releases published there.
- **Buildworld**: `root@108.61.206.203` (FreeBSD 15, Vultr LAX, 1GB RAM). HTTP image server on :8080 via rc.d.
- **Secondary host**: `root@45.76.21.213` (fbsd-x86-vultr-01) — QEMU 10.2.2 installed, second test target.
- **Nu version**: 0.111.0+ required. CI uses x86_64 musl binary.
