// genoa-init/src/main.rs
//
// Kernel-side entry point for the Genoa unikernel.
//
// In a full Hermit build this file is compiled with:
//   cargo +nightly build --target x86_64-unknown-hermit -Zbuild-std=core,alloc
//
// The linker entry point `_start` is provided by the Hermit runtime
// (libhermit-rs). After Hermit initialises the heap, sets up the network
// device, and calls `main()`, we hand off to `genoa_agent::run()`.
//
// On the host (cargo check / cargo test) this is just a normal `fn main()`
// that demonstrates the call-graph typechecks end-to-end.

// For the real unikernel build, uncomment:
// #![no_std]
// #![no_main]
// extern crate alloc;

use genoa_agent::run;
use genoa_config::{AGENT_ID, MANIFEST_HASH, SCHEMA_VERSION, TASK_ENDPOINT};

// In the Hermit build this attribute is `#[no_mangle]` on `extern "C" fn main()`.
// For host cargo check we use `fn main()`.
fn main() {
    // Boot banner — in the unikernel this goes to the Hermit serial console.
    // In harness mode it goes to stdout so the demo script can capture it.
    println!("=== Genoa unikernel v{} ===", env!("CARGO_PKG_VERSION"));
    println!("agent_id       : {AGENT_ID}");
    println!("manifest_hash  : {MANIFEST_HASH}");
    println!("schema_version : {SCHEMA_VERSION}");
    println!("task_endpoint  : {TASK_ENDPOINT}");
    println!("--- entering agent loop (stub: will spin at I/O boundary) ---");

    // Hand off to the agent loop.  `run()` is `-> !` — it never returns.
    run()
}
