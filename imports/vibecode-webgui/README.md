# imports/vibecode-webgui

Moved from ryanmaclean/vibecode-webgui@129302a73be9719d213561116319d13ed679fd71 on 2026-10-24
(workstream WS6 of the vibecode-webgui repo split; history not carried over, see the source repo).

- Licence: MIT, Copyright (c) 2026 VibeCode Contributors. The full notice is in
  [`LICENSES/vibecode-webgui-MIT.txt`](../../LICENSES/vibecode-webgui-MIT.txt). It applies to every file under
  this directory. The rest of genoa stays BSD-2-Clause.
- Status: imported as-is. Nothing here is wired into `genoa.nu`, the manifests or genoa CI yet. Treat it as
  source material for genoa profiles and builders, not as a supported genoa interface.
- Layout: the original vibecode paths are mirrored on purpose. The builders compute `REPO_ROOT` as two
  levels up from their own directory, so run them from this directory (for example
  `./scripts/benchmarks/build-minimal-initramfs.sh arm64`). Outputs land in `bench-images/`,
  `artifacts/`, `output-*` and `manifest-*.json` here, all gitignored.

## Contents

| Path | What | Notes |
|---|---|---|
| `infrastructure/packer/` | Packer HCL templates (Ubuntu, Alpine arm64, FreeBSD arm64, OmniOS arm64 and LX zone, OpenIndiana, macOS vfkit), cloud-init seed, OmniOS/LX scripts | `vibecode-openindiana.pkr.hcl` now takes `ssh_password` as a sensitive variable with no default; the literal from the source was not copied. The other templates keep the well-known installer defaults of the source. |
| `infrastructure/packer/provisioner/vfkit/` | Go packer provisioner for vfkit | Its `go.mod` depends on `github.com/hashicorp/packer-plugin-sdk` (MPL-2.0) and other hashicorp modules. Nothing is vendored here. Building it is an owner licence decision (MPL is not on the default allowlist). |
| `scripts/benchmarks/build-*`, `build_*`, `trim*`, `validate*`, `kernel-configs/`, `README-minivim.md` | MiniVim/EFI-stub kernel, initramfs (minimal, busybox-musl, neovim, neovim+avante) and rootfs builders and validators | The split with smolfire is recorded in vibecode-1024 `ws5-ws6-split.txt` (benches and launchers went to ryanmaclean/smolfire). |
| `scripts/benchmarks/benchmark_utils.py`, `_dogstatsd.py`, `scripts/lib/{__init__,log_aggregation}.py` | Byte-identical support copies | Imported without a guard by several builders. The canonical copies stay in smolfire (benchmark libs) and vibecode (`scripts/lib`). |
| `scripts/release-testing/` | Bash harness that downloads vibecode GitHub releases and tests them in Tart/VM guests, with its own tests | `config.env` keeps the public Tart default guest login of the source. |
| `tests/unit/scripts/benchmarks/test_build_scripts.py` | Python import tests for the builders | Not run by genoa CI. |

Python files are moved unchanged; new genoa code stays Nushell or POSIX sh.
