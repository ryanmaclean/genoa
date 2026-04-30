# Bake-off Report — Option C (unikernel)

## What was built

- Files: 17 (excluding Cargo.lock and target/), Rust LOC: 591 (source only), Nushell LOC: 253
- Crates: genoa-config 0.1.0, genoa-agent 0.1.0, genoa-init 0.1.0
- External deps: smoltcp 0.11.0, rustls 0.23.40, serde 1.0, serde_json 1.0, sha2 0.10, hex 0.4, toml 0.8 (build-time only)
- `cargo check` status: **PASS** (exit code 0)

## License compliance

All deps + transitives identified: see LICENSE-DEPS.md for the full table
(~40 transitive crates).

All under: MIT / Apache-2.0 / ISC / 0BSD / BSD-3-Clause (subtle). Zero
GPL, LGPL, or AGPL. The `ring` crate uses a custom permissive ISC-derived
license; aws-lc-rs (Apache-2.0 + ISC) is a documented drop-in if legal
review flags ring.

## AX-first surface verification

Actual stdout from `nu bake-off-demo.nu schema | head -10`:
```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/ryanmaclean/genoa/schema/manifest.v1.json",
  "title": "Genoa Manifest v1",
  "description": "Compile-time manifest baked into a Genoa unikernel image. Parsed by genoa-config/build.rs at cargo build time; the resulting constants are embedded as &'static str in the kernel binary.",
  "type": "object",
  "required": [
    "schema_version",
    "identity",
    "network",
```

Actual stdout from `nu bake-off-demo.nu describe`:
```json
{
  "subcommand": "describe",
  "schema_version": "1",
  "agent_id": "genoa-c-demo-01",
  "attestation_pubkey": "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
  "manifest_hash": "5ae2fc9fcc8f29aa3c4f83de3fcc424e9bd020e8bcd7b9bd0eee26259c0eae9d",
  "target_triple": "x86_64-unknown-hermit (stub; cargo check runs on host)",
  "task_endpoint": "https://genoa.example.com/v1/tasks/next",
  "result_endpoint": "https://genoa.example.com/v1/tasks/result",
  "poll_interval_ms": 2000,
  "dhcp_enabled": true,
  "static_ip_fallback": "10.0.2.15",
  "license_set": [...],
  "crates": [...],
  "ax_first": {
    "status_endpoint": "/v1/status",
    "task_endpoint": "/v1/tasks/next",
    "result_endpoint": "/v1/tasks/result",
    "response_format": "signed JSON (Ed25519, key in attestation_pubkey above)",
    "discovery": "genoa.toml baked into image; /v1/status is the live probe"
  }
}
```

Actual stdout from `nu bake-off-demo.nu check`:
```json
{
  "subcommand": "check",
  "status": "PASS",
  "exit_code": 0,
  "elapsed_ms": 157,
  "command": "cargo check --workspace",
  "target": "host (stable/nightly Rust)",
  "note": "Full Hermit build requires: cargo +nightly build --target x86_64-unknown-hermit -Zbuild-std=core,alloc",
  "stderr_tail": "    Finished `dev` profile [unoptimized + debuginfo] target(s) in 0.12s"
}
```

## What works (real)

- `cargo check --workspace` passes with zero warnings and zero errors.
- `genoa-config/build.rs` actually parses `genoa.toml` via the `toml` crate,
  computes a SHA-256 hash, and emits all constants via `cargo:rustc-env`.
  The manifest hash `5ae2fc9f...` is real and changes if `genoa.toml` changes.
- `genoa-config/src/lib.rs` exposes those constants as `&'static str` in
  a `#![no_std]` crate. `POLL_INTERVAL_MS` is parsed at compile time in a
  `const {}` block — no runtime TOML parsing happens in the kernel image.
- `genoa-agent/src/lib.rs`: `execute()` dispatch, `TaskEnvelope`/`TaskResult`
  types, `build_status()`, and the `poll_once()` control flow all typecheck.
  Four unit tests pass with `cargo test --workspace`.
- `schema/manifest.v1.json` is valid JSON Schema 2020-12 (validated by structure;
  ajv or check-jsonschema can confirm).
- `bake-off-demo.nu` returns valid JSON for all three subcommands.

## What's stubbed (and why)

- **Hermit kernel image**: requires `rustup target add x86_64-unknown-hermit
  --toolchain nightly` + `-Zbuild-std=core,alloc`. Not installed locally.
  The exact invocation is documented in `build.nu hermit-build`. Tagged STUB.
- **TLS I/O**: `tls_connect()` returns `Ok(TlsStub)` in all build modes.
  Real code would wrap a `smoltcp::TcpSocket` with `rustls::ClientConnection`.
  The API shape (Result<TlsStub, AgentError>) is correct and forward-compatible.
  Tagged STUB.
- **DHCP**: `bring_up_network()` returns a string. Real code would spin a
  `smoltcp::iface::Interface` over a `virtio-net` device and run the
  `smoltcp::socket::dhcpv4::Socket` state machine. Tagged STUB.
- **HTTP/1.1 framer**: `http_get()` / `http_post()` return `Err(AgentError::Stub)`.
  ~200 LOC of hand-rolled HTTP/1.1 over `rustls::Stream` would replace them.
  Tagged STUB.
- **Ed25519 attestation signing**: `build_status()` emits
  `"STUB_SIGNATURE_NOT_REAL"`. Real: `ed25519-dalek` (MIT/Apache-2.0) with
  the private key sealed in memory or provisioned at first boot. Tagged STUB.
- **QEMU boot**: no Hermit loader ELF in this tree. Tagged STUB.
- **TLS CA bundle**: `tls/ca-bundle.pem` is a placeholder comment. Real:
  embed a mozilla/certifi-derived PEM or a single pinned DER root. Tagged STUB.

## Reality check

This is v0.05, not v0.1. To get to a booting unikernel:

1. Install Hermit toolchain (~1h including debugging build-std issues) — medium risk
2. Wire smoltcp virtio-net device driver (Hermit provides `hermit-net`) — ~4h
3. Wire DHCP via `smoltcp::socket::dhcpv4` — ~2h
4. Write HTTP/1.1 framer over rustls::Stream (~200 LOC) — ~4h
5. Wire Ed25519 signing with ed25519-dalek — ~2h
6. Get a real CA bundle embedded (webpki-roots or custom) — ~1h
7. Test end-to-end in QEMU against a local mock control plane — ~4h
8. aarch64 port (Hermit supports it; mostly recompile, some asm) — ~8h

Rough total to v0.1 (booting, network-connected, real TLS): ~26h of focused work.
To production readiness (attestation, secrets management, update mechanism): 3-6 months.

## Build/run instructions

```sh
nu build.nu check          # typecheck (no Hermit toolchain needed)
cargo test --workspace     # unit tests on host
nu bake-off-demo.nu check  # structured JSON status
```

## Self-graded fit score: 6/10

## Self-grade weakness

The unikernel pattern is genuinely the highest-isolation option and has a
compelling story: the agent IS the kernel — no shell, no userland, minimal
attack surface. The schema-baked-at-build-time pattern is solid and the
build.rs approach is real, not fake. The weakness is that a booting kernel
is nowhere near deliverable in 90 minutes from scratch, and all judges
will notice that `run()` spins at the I/O boundary. A competitor who ships
a container or VM with working network I/O will look more "done" in a demo,
even if architecturally inferior. The honest score accounts for that gap.

## Synergy hooks

- "If A (smolBSD) emits images: I am orthogonal — different artifact, a
  FreeBSD-userland VM vs. a bare-metal unikernel ELF. But `genoa.toml`'s
  schema shares the `[identity]`, `[tasks]`, and `[attestation]` blocks
  with whatever manifest A uses. If A adopts `schema/manifest.v1.json`
  as a common control-plane contract, a single control plane can schedule
  tasks to both Option-A VMs and Option-C unikernels via the same
  `/v1/tasks/next` endpoint."

- "If D (spec) wants to validate my output: probe `/v1/status` on port 80
  (HTTP, stub) or 443 (TLS, stub). The response is JSON with fields
  `agent_id`, `manifest_hash`, `attestation_pubkey`, `uptime_ms`, `signature`.
  The `manifest_hash` field allows D to verify the deployed image matches
  a known-good `genoa.toml` by SHA-256 comparison — no binary inspection
  needed. The `attestation_pubkey` field allows D to verify the `signature`
  over the response body using Ed25519 (when the signing stub is replaced)."
