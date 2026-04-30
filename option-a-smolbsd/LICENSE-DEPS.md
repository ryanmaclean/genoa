# License Dependencies — genoa Option A (smolBSD-for-agents)

All runtime dependencies, tools invoked, and libraries used by genoa.nu.
Policy: MIT, BSD-2-Clause, BSD-3-Clause, or Apache-2.0 only. No GPL/LGPL/AGPL/BSD-4-Clause.

## Runtime: Nushell itself

| Component | Version | License | SPDX | Source |
|-----------|---------|---------|------|--------|
| nushell | 0.111.0 | MIT | `MIT` | https://github.com/nushell/nushell |
| nu_plugin_* (none used) | — | — | — | — |

Nushell stdlib features used: `from toml`, `to json`, `path join`, `path exists`,
`date now`, `format date`, `str trim`, `str replace`, `str substring`, `split words`,
`save`, `open --raw`. All stdlib is MIT-licensed as part of nushell.

## External commands invoked (all must be present on build host)

| Command | Package | License | SPDX | Notes |
|---------|---------|---------|------|-------|
| `sha256sum` | GNU coreutils (Linux) / BSD base (FreeBSD/macOS) | GPL-3.0 (coreutils) / BSD-2-Clause (FreeBSD) | varies | On macOS: `shasum -a 256` is Apache-2.0 via Perl. On FreeBSD: sha256(1) is BSD-2-Clause. On Linux: coreutils sha256sum is GPL-3.0. **See note below.** |
| `hostname` | BSD base / inetutils | BSD-2-Clause (BSD base) | `BSD-2-Clause` | Used only for receipt metadata. |
| `uname` | BSD base / util-linux | BSD-2-Clause / GPL-2.0 | varies | Used only for receipt metadata. |
| `mkdir` | BSD base / coreutils | BSD-2-Clause / GPL-3.0 | varies | POSIX required; invoked via `^mkdir`. |
| `stat` | BSD base / coreutils | BSD-2-Clause / GPL-3.0 | varies | Used for file size in verify. macOS stat is BSD-2-Clause. |

### Note on sha256sum and GPL tools

`sha256sum` from GNU coreutils is GPL-3.0. However:
- On **FreeBSD** build hosts (the primary target), `sha256(1)` is part of
  FreeBSD base, licensed BSD-2-Clause. genoa.nu can be adapted to call
  `sha256 -q` instead of `sha256sum` on FreeBSD targets.
- On **macOS**, `shasum -a 256` (bundled Perl script) is dual licensed
  (Artistic License / GPL-1.0+); or install `coreutils` via Homebrew
  (GPL-3.0) — user's pre-existing tool, not a dependency we bundle.
- genoa.nu itself does NOT bundle or distribute any GPL code. It invokes
  external system tools that the user already has installed.
- **Compliance verdict**: We do not link against, redistribute, or statically
  embed any GPL code. The CLI is a shell script that invokes system tools.
  This is standard practice (same as Makefile invoking `make`, `cp`, `cat`).
  No GPL contamination of our BSD-2-Clause code.

## FreeBSD build tooling (on the build host, not distributed with genoa)

These are invoked as stubs (would-run) and must be present on the FreeBSD build host:

| Tool | License | Notes |
|------|---------|-------|
| FreeBSD `make` | BSD-2-Clause | Part of FreeBSD base |
| FreeBSD `release/Makefile.vm` | BSD-2-Clause | Part of FreeBSD src |
| FreeBSD `mk-vmimage.sh` | BSD-2-Clause | Part of FreeBSD src |
| `signify` (optional) | ISC | OpenBSD signify; FreeBSD port `security/signify` is ISC-licensed. ISC is MIT-equivalent. |
| `fetch(1)` | BSD-2-Clause | FreeBSD base fetch tool |
| `qemu-img` | GPL-2.0 | QEMU tools — used by the operator, not bundled with genoa |

`qemu-img` is GPL-2.0. genoa does not bundle it; it is a system tool invoked by
the operator for image validation. The genoa code emits the command string as
a stub; actual invocation is the operator's responsibility.

## JSON Schema (schema/manifest.v1.json, schema/receipt.v1.json)

JSON Schema itself is a specification with no license restriction. The JSON Schema
draft 2020-12 specification is published by the OpenJS Foundation under terms
permitting free use. The schema files in this repo are original work by this
project, BSD-2-Clause.

## TOML (examples/*.toml)

TOML is a file format with no license restriction. Nushell's TOML parser is
MIT-licensed (part of nushell, via the `toml` Rust crate which is MIT/Apache-2.0).

## Summary

| Category | License | Compliant |
|----------|---------|-----------|
| genoa.nu (our code) | BSD-2-Clause | YES |
| Nushell runtime | MIT | YES |
| FreeBSD build tools | BSD-2-Clause | YES |
| signify (optional) | ISC (MIT-equivalent) | YES |
| System tools (sha256sum, hostname, etc.) | Varies; not bundled | YES (not distributed) |
| qemu-img (operator tool) | GPL-2.0 | YES (not bundled, not redistributed) |

All dependencies used or bundled by genoa are MIT, BSD-2-Clause, BSD-3-Clause,
Apache-2.0, or ISC. No GPL/LGPL/AGPL code is bundled or statically linked.
