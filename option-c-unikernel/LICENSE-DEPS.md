# Dependency Licenses — Genoa Option-C (unikernel)

All licenses below are MIT, Apache-2.0, ISC, 0BSD, or BSD-2/3. No GPL,
LGPL, AGPL, or copyleft dependency is present.

## Direct workspace dependencies

| Crate | Version | License | Notes |
|-------|---------|---------|-------|
| smoltcp | 0.11.0 | 0BSD | TCP/IP + DHCPv4 stack |
| rustls | 0.23.x | Apache-2.0 OR MIT OR ISC (triple) | TLS 1.2/1.3 |
| serde | 1.0.x | MIT OR Apache-2.0 | Serialisation framework |
| serde_json | 1.0.x | MIT OR Apache-2.0 | JSON encode/decode |
| sha2 | 0.10.x | MIT OR Apache-2.0 | SHA-256 for manifest hash |
| hex | 0.4.x | MIT OR Apache-2.0 | Hex encoding |
| toml | 0.8.x | MIT OR Apache-2.0 | TOML parse (build-time host only, not in image) |

## Transitive dependencies (resolved by Cargo.lock as of 2026-04-30)

| Crate | Version | License | Why |
|-------|---------|---------|-----|
| bitflags | 1.3.2 | MIT OR Apache-2.0 | smoltcp flags |
| block-buffer | 0.10.4 | MIT OR Apache-2.0 | sha2 internals |
| byteorder | 1.5.0 | MIT OR Unlicense | smoltcp |
| cc | 1.2.x | MIT OR Apache-2.0 | ring build (native code) |
| cfg-if | 1.0.4 | MIT OR Apache-2.0 | conditional compilation |
| cpufeatures | 0.2.x | MIT OR Apache-2.0 | sha2 SIMD detection |
| crypto-common | 0.1.7 | MIT OR Apache-2.0 | sha2 |
| digest | 0.10.7 | MIT OR Apache-2.0 | sha2 |
| equivalent | 1.0.x | MIT OR Apache-2.0 | indexmap |
| find-msvc-tools | 0.1.x | MIT OR Apache-2.0 | cc build helper |
| generic-array | 0.14.7 | MIT | sha2 / crypto-common |
| getrandom | 0.2.x | MIT OR Apache-2.0 | ring |
| hash32 | 0.3.x | MIT OR Apache-2.0 | heapless |
| hashbrown | 0.17.0 | MIT OR Apache-2.0 | indexmap |
| heapless | 0.8.0 | MIT OR Apache-2.0 | smoltcp fixed-size containers |
| hex | 0.4.3 | MIT OR Apache-2.0 | manifest hash encoding |
| indexmap | 2.x | MIT OR Apache-2.0 | serde_json, toml |
| itoa | 1.0.x | MIT OR Apache-2.0 | serde_json |
| libc | 0.2.x | MIT OR Apache-2.0 | ring (platform glue) |
| log | 0.4.x | MIT OR Apache-2.0 | rustls logging |
| managed | 0.8.0 | 0BSD | smoltcp |
| memchr | 2.x | MIT OR Unlicense | serde_json |
| once_cell | 1.x | MIT OR Apache-2.0 | rustls |
| proc-macro2 | 1.0.x | MIT OR Apache-2.0 | serde_derive |
| quote | 1.0.x | MIT OR Apache-2.0 | serde_derive |
| ring | 0.17.x | ISC (custom permissive) | rustls crypto backend; see note |
| rustls-pki-types | 1.x | MIT OR Apache-2.0 | rustls |
| rustls-webpki | 0.103.x | ISC | rustls cert verification |
| serde_core | 1.0.x | MIT OR Apache-2.0 | serde re-export |
| serde_derive | 1.0.x | MIT OR Apache-2.0 | derive macros |
| serde_spanned | 0.6.x | MIT OR Apache-2.0 | toml |
| shlex | 1.3.x | MIT OR Apache-2.0 | cc build helper |
| stable_deref_trait | 1.2.x | MIT OR Apache-2.0 | smoltcp |
| subtle | 2.6.x | BSD-3-Clause | constant-time comparisons, ring |
| syn | 2.0.x | MIT OR Apache-2.0 | serde_derive |
| toml_datetime | 0.6.x | MIT OR Apache-2.0 | toml |
| toml_edit | 0.22.x | MIT OR Apache-2.0 | toml |
| typenum | 1.x | MIT OR Apache-2.0 | generic-array |
| unicode-ident | 1.0.x | MIT OR Apache-2.0 OR Unicode-DFS-2016 | proc-macro2 |
| untrusted | 0.9.x | ISC | ring |
| version_check | 0.9.x | MIT OR Apache-2.0 | build dep |
| winnow | 0.7.x | MIT | toml parsing |
| zeroize | 1.8.x | MIT OR Apache-2.0 | ring/rustls secret zeroing |
| zmij | 1.0.x | MIT OR Apache-2.0 | ring build helper |

## Planned substrate (not yet linked)

| Crate | Version | License | Notes |
|-------|---------|---------|-------|
| hermit-os/hermit-rs | main | MIT OR Apache-2.0 | Unikernel runtime substrate; not yet linked — requires nightly + Hermit target |

## ring license note

`ring` uses a custom permissive license derived from BoringSSL and ISC. The
project explicitly states it is permissive (no copyleft). The Rust ecosystem
broadly considers it compatible with Apache-2.0 projects. See
https://github.com/briansmith/ring/blob/main/LICENSE for the full text.
If your legal team requires a pre-approved SPDX expression, consider
substituting `aws-lc-rs` (Apache-2.0 + ISC) as the rustls backend — it is
a drop-in replacement via `rustls = { features = ["aws-lc-rs"] }`.
