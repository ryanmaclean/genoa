# genoa — TODO

Status as of 2026-05-16. genoa builds minimal FreeBSD/NetBSD cloud images with embedded agents and deploys to 40+ providers.

---

## ✅ Done (v0.1.3 → v0.1.4-dev milestone)

- **Image boots** — verified in 2 environments: FreeBSD QEMU (buildworld, KVM, ~30s) and macOS QEMU (Apple Silicon TCG, 121s). EDK2 UEFI → `BOOTx64.EFI` → loader → kernel → login prompt. The `mountroot>` bug is gone (`vfs.root.mountfrom` resolves).
- **42/42 smoke tests** green on macOS, FreeBSD buildworld, and GitHub Actions CI.
- **CI green** — Smoke Tests + Validate Manifests, Nu 0.111.0 musl.
- **26 subcommands** — validate, build, run, sign, verify-image, diff, publish, deploy, deploy-from-snapshot, clone-instance, snapshots, snapshot-import/-status, instances, watch, providers, receipts, versions, notify, status, health, selftest, suggest, catalog, schema, describe.
- **genoa.nu refactored** — 1875 lines → 289-line shim + 8 `lib/` modules.
- **Validator** — 20 checks incl. JSON Schema Draft 7.
- **Build profile (uefi.nu)** — writes loader.conf, rc.conf, fstab (9b/9c/9d); pkg install (11b); arm64 tarball fetch (7b).
- **ii-agent v0.2.0** — portable `/bin/sh`, no Nu runtime dependency.
- **Providers** — Vultr + Linode (real), AWS EC2 + GCE GCP (stubs), catalog of 40+.
- **Infra** — buildworld 2GB swap, rc.d HTTP image server, Gitea act_runner registered.
- **Security** — personal SSH key scrubbed, `.gitleaks.toml`, `bin/pre-push-check.nu`.
- **Docs** — README, CHANGELOG, CLAUDE.md, audit-2026-05-16.md.

---

## 🚧 Blocked (external dependencies)

| Item | Blocker | Unblock action |
|------|---------|----------------|
| **Live Vultr deploy** | Account $0 balance; snapshot `d372185f` (v0.1.3) ready | Add Vultr credit |
| **Vultr API access** | Home IP `24.80.182.14` not on API allowlist (dynamic IP) | Add IP to Vultr API allowlist, or use stable egress (Tailscale exit node) |
| **Gitea Actions native FreeBSD CI** | act_runner can't reach LAN Gitea | Authorize Tailscale: `https://login.tailscale.com/a/f900156015407` |
| **Linode rescue-dd test** | `LINODE_TOKEN` not set | Set token, or skip Linode path |
| **genoa suggest (Ollama)** | `ollama.local` unreachable from this network | Test from fleet host with Ollama access |

---

## 🔴 High priority

- [ ] **Publish v0.1.4 Gitea release** — bundle: ii-agent /bin/sh, pkg install step, aarch64 fetch, audit fixes, lib/ refactor. Currently only v0.1.3 is released.
- [ ] **Real cloud boot test** — every boot so far is QEMU. Need ONE successful boot on a real cloud VM (Vultr snapshot, or Linode rescue-dd, or wipe fbsd-x86-vultr-01). Confirms growfs, DHCP, ii-agent heartbeat work outside emulation.
- [ ] **Finish vultr-01 boot test** — full 2GB image re-fetched (prior was 152MB partial). Re-run QEMU boot on `45.76.21.213`.
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
