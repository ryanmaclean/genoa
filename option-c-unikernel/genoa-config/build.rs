// genoa-config/build.rs
// Runs on the HOST at cargo build / cargo check time.
// Reads ../genoa.toml, computes a SHA-256 manifest hash, and emits
// constants via cargo:rustc-env so the kernel image bakes them in at
// compile time (no runtime file I/O needed on the unikernel).

use sha2::{Digest, Sha256};
use std::path::PathBuf;

fn main() {
    // Tell Cargo to re-run this script if genoa.toml changes.
    println!("cargo:rerun-if-changed=../genoa.toml");

    let manifest_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("..").join("genoa.toml");

    let raw = std::fs::read_to_string(&manifest_path)
        .unwrap_or_else(|e| panic!("build.rs: cannot read {:?}: {}", manifest_path, e));

    // Parse TOML to extract key fields.
    let doc: toml::Table = raw.parse()
        .unwrap_or_else(|e| panic!("build.rs: cannot parse genoa.toml: {}", e));

    let agent_id = doc
        .get("identity")
        .and_then(|v| v.get("agent_id"))
        .and_then(|v| v.as_str())
        .unwrap_or("unknown");

    let attestation_pubkey = doc
        .get("identity")
        .and_then(|v| v.get("attestation_pubkey"))
        .and_then(|v| v.as_str())
        .unwrap_or("");

    let task_endpoint = doc
        .get("tasks")
        .and_then(|v| v.get("endpoint"))
        .and_then(|v| v.as_str())
        .unwrap_or("https://genoa.example.com/v1/tasks/next");

    let result_endpoint = doc
        .get("tasks")
        .and_then(|v| v.get("result_endpoint"))
        .and_then(|v| v.as_str())
        .unwrap_or("https://genoa.example.com/v1/tasks/result");

    let poll_interval_ms: u64 = doc
        .get("tasks")
        .and_then(|v| v.get("poll_interval_ms"))
        .and_then(|v| v.as_integer())
        .unwrap_or(2000) as u64;

    let dhcp: bool = doc
        .get("network")
        .and_then(|v| v.get("dhcp"))
        .and_then(|v| v.as_bool())
        .unwrap_or(true);

    let static_ip = doc
        .get("network")
        .and_then(|v| v.get("static_ip"))
        .and_then(|v| v.as_str())
        .unwrap_or("10.0.2.15");

    let schema_version = doc
        .get("schema_version")
        .and_then(|v| v.as_str())
        .unwrap_or("1");

    // SHA-256 of the raw TOML bytes — baked into the binary.
    let mut hasher = Sha256::new();
    hasher.update(raw.as_bytes());
    let hash_bytes = hasher.finalize();
    let manifest_hash = hex::encode(hash_bytes);

    // Emit as compile-time env vars consumed by genoa-config/src/lib.rs
    println!("cargo:rustc-env=GENOA_MANIFEST_HASH={manifest_hash}");
    println!("cargo:rustc-env=GENOA_AGENT_ID={agent_id}");
    println!("cargo:rustc-env=GENOA_ATTESTATION_PUBKEY={attestation_pubkey}");
    println!("cargo:rustc-env=GENOA_TASK_ENDPOINT={task_endpoint}");
    println!("cargo:rustc-env=GENOA_RESULT_ENDPOINT={result_endpoint}");
    println!("cargo:rustc-env=GENOA_POLL_INTERVAL_MS={poll_interval_ms}");
    println!("cargo:rustc-env=GENOA_DHCP={dhcp}");
    println!("cargo:rustc-env=GENOA_STATIC_IP={static_ip}");
    println!("cargo:rustc-env=GENOA_SCHEMA_VERSION={schema_version}");

    eprintln!("build.rs: manifest hash = {manifest_hash}");
    eprintln!("build.rs: agent_id      = {agent_id}");
    eprintln!("build.rs: task_endpoint = {task_endpoint}");
}
