# Genoa Option-C — Agent-as-Kernel (unikernel)

A single-purpose unikernel that boots straight into an agent loop:
DHCP -> TLS handshake -> poll `/v1/tasks/next` -> execute -> POST result.
No userland. No shell. No attack surface that isn't the agent.

Substrate: [Hermit](https://github.com/hermit-os/hermit-rs) (MIT OR Apache-2.0).

## Quickstart

```sh
# 1. Type-check the entire workspace (no Hermit toolchain needed)
nu build.nu check

# 2. Run host-side unit tests (echo, ping, unsupported task, status JSON)
cargo test --workspace

# 3. See the AX-first machine-readable surface
nu bake-off-demo.nu describe
nu bake-off-demo.nu check
nu bake-off-demo.nu schema | head -10
```

## What's stubbed and why

This is v0.05, not v0.1. The full unikernel path is a 6-12 month project.
Here is an exact account of what is real and what is stubbed.

### What works for real

- `cargo check --workspace` passes cleanly (zero warnings, zero errors).
- `genoa-config/build.rs` reads `genoa.toml` at build time, computes a
  SHA-256 manifest hash, and emits it as a compile-time constant (`MANIFEST_HASH`,
  `TASK_ENDPOINT`, `AGENT_ID`, etc.) baked into the binary. If you change
  `genoa.toml` and re-run `cargo check`, you get a different hash.
- `genoa-agent/src/lib.rs` is real no_std-compatible Rust: the `execute()`
  dispatcher, `TaskEnvelope`/`TaskResult` types, `build_status()`, and the
  `poll_once()` control flow all typecheck and are covered by `cargo test`.
- `schema/manifest.v1.json` is a valid JSON Schema 2020-12 document.
- `bake-off-demo.nu` returns structured JSON for all three subcommands.

### What's stubbed (and the exact reason)

| Stub | Why | How to fix |
|------|-----|------------|
| Hermit kernel image production | Requires `x86_64-unknown-hermit` target + nightly `-Zbuild-std` | `nu build.nu hermit-setup` prints the exact commands |
| TLS I/O | `tls_connect()` returns `TlsStub` in harness mode | Wire rustls `ClientConnection` to a smoltcp `TcpSocket` |
| DHCP | `bring_up_network()` returns a string; no `smoltcp::EthernetInterface` | Instantiate the smoltcp device driver for virtio-net |
| HTTP/1.1 | `http_get()` / `http_post()` return `Err(AgentError::Stub(...))` | Write ~200 LOC HTTP/1.1 framer over `rustls::Stream` |
| Ed25519 signing | `build_status()` returns `"STUB_SIGNATURE_NOT_REAL"` | Integrate `ed25519-dalek` (MIT/Apache-2.0) with a sealed key |
| QEMU run | No Hermit loader ELF in this tree | Follow `nu build.nu hermit-build` output |

## Workspace layout

```
Cargo.toml              workspace root
genoa.toml              compile-time manifest (schema: schema/manifest.v1.json)
genoa-config/
  build.rs              reads genoa.toml, emits rustc-env constants
  src/lib.rs            exposes constants as &'static str + no_std
genoa-agent/
  src/lib.rs            agent loop, task dispatch, TLS/HTTP stubs
genoa-init/
  src/main.rs           _start / main entry point
schema/
  manifest.v1.json      JSON Schema 2020-12 for genoa.toml
tls/
  ca-bundle.pem         STUB — replace with real CA PEM before deploying
build.nu                Hermit toolchain docs + cargo check/test wrapper
bake-off-demo.nu        AX-first JSON surface (check / describe / schema)
LICENSE                 Apache-2.0
LICENSE-DEPS.md         Every transitive dep + its license
```

## To boot in QEMU (when toolchain is ready)

```sh
nu build.nu hermit-setup   # print toolchain install commands
nu build.nu hermit-build   # print kernel build + qemu-system-x86_64 invocation
```

Expected serial output on boot:
```
=== Genoa unikernel v0.1.0 ===
agent_id       : genoa-c-demo-01
manifest_hash  : <sha256-of-genoa.toml>
task_endpoint  : https://genoa.example.com/v1/tasks/next
--- entering agent loop ---
```
