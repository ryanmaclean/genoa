// genoa-agent/src/lib.rs
//
// Agent loop for the Genoa unikernel.
//
// In the full Hermit build this is #![no_std] + extern crate alloc.
// For cargo check on the host we gate std-dependent items behind cfg(feature="std")
// so the entire module graph typechecks with the stable/nightly host toolchain.
//
// Networking model (when running as a unikernel):
//   1. DHCP via smoltcp DHCPv4 socket (or static fallback from manifest)
//   2. TLS via rustls (no_std mode, alloc enabled)
//   3. HTTP/1.1 hand-rolled over rustls::Stream — no http crate dependency
//   4. Poll /v1/tasks/next, deserialise TaskEnvelope, execute, POST result
//
// In this demo harness `run()` performs the loop structure but the actual
// socket I/O is gated behind cfg(not(feature="std")) — i.e. it only fires
// when linked into the real Hermit image with a working network device.

#![cfg_attr(not(feature = "std"), no_std)]

#[cfg(not(feature = "std"))]
extern crate alloc;

#[cfg(not(feature = "std"))]
use alloc::{format, string::String, vec::Vec};

#[cfg(feature = "std")]
use std::{format, string::String, vec::Vec};

use genoa_config::{
    AGENT_ID, ATTESTATION_PUBKEY_HEX, DHCP_ENABLED, MANIFEST_HASH,
    POLL_INTERVAL_MS, RESULT_ENDPOINT, STATIC_IP, TASK_ENDPOINT,
};

// ---------------------------------------------------------------------------
// Public data types (AX-first: serialisable, schema-documented)
// ---------------------------------------------------------------------------

/// A task received from the control plane's /v1/tasks/next endpoint.
#[derive(Debug)]
#[cfg_attr(feature = "std", derive(serde::Deserialize))]
#[cfg_attr(not(feature = "std"), derive(serde::Deserialize))]
pub struct TaskEnvelope {
    /// Opaque task identifier.
    pub id: String,
    /// Task type tag — determines which executor is invoked.
    pub kind: String,
    /// Arbitrary JSON payload for the task.
    pub payload: serde_json::Value,
    /// ISO-8601 expiry — agent MUST NOT execute after this time.
    pub expires_at: String,
}

/// Result of executing a TaskEnvelope; posted back to RESULT_ENDPOINT.
#[derive(Debug, serde::Serialize)]
pub struct TaskResult {
    pub task_id: String,
    pub agent_id: &'static str,
    pub manifest_hash: &'static str,
    pub status: TaskStatus,
    pub output: serde_json::Value,
}

#[derive(Debug, serde::Serialize)]
pub enum TaskStatus {
    #[serde(rename = "ok")]
    Ok,
    #[serde(rename = "error")]
    Error,
    #[serde(rename = "unsupported")]
    Unsupported,
}

/// The /v1/status response — signed JSON (stub: signature field is present
/// but populated with a placeholder until real Ed25519 signing is wired in).
#[derive(Debug, serde::Serialize)]
pub struct AgentStatus {
    pub agent_id: &'static str,
    pub manifest_hash: &'static str,
    pub attestation_pubkey: &'static str,
    pub task_endpoint: &'static str,
    pub uptime_ms: u64,
    /// Ed25519 signature over the canonical JSON of the other fields (stub).
    pub signature: String,
}

// ---------------------------------------------------------------------------
// Network configuration (resolved at boot from manifest constants)
// ---------------------------------------------------------------------------

pub struct NetConfig {
    pub dhcp: bool,
    pub static_ip: &'static str,
    pub task_endpoint: &'static str,
    pub result_endpoint: &'static str,
    pub poll_interval_ms: u64,
}

impl NetConfig {
    /// Build from the compile-time manifest constants.
    pub const fn from_manifest() -> Self {
        Self {
            dhcp: DHCP_ENABLED,
            static_ip: STATIC_IP,
            task_endpoint: TASK_ENDPOINT,
            result_endpoint: RESULT_ENDPOINT,
            poll_interval_ms: POLL_INTERVAL_MS,
        }
    }
}

// ---------------------------------------------------------------------------
// Executor dispatch
// ---------------------------------------------------------------------------

/// Route a task to the appropriate executor.
/// Returns a (status, output) pair.
fn execute(task: &TaskEnvelope) -> (TaskStatus, serde_json::Value) {
    match task.kind.as_str() {
        "echo" => {
            // Simplest possible executor: echo back the payload.
            (TaskStatus::Ok, task.payload.clone())
        }
        "ping" => {
            // Returns a pong with the agent identity.
            let pong = serde_json::json!({
                "pong": true,
                "agent_id": AGENT_ID,
                "manifest_hash": MANIFEST_HASH,
            });
            (TaskStatus::Ok, pong)
        }
        "shutdown" => {
            // In the real unikernel this would call the Hermit exit syscall.
            // Here we just report success.
            (TaskStatus::Ok, serde_json::json!({"shutdown": "scheduled"}))
        }
        _ => (
            TaskStatus::Unsupported,
            serde_json::json!({"error": format!("unknown task kind: {}", task.kind)}),
        ),
    }
}

// ---------------------------------------------------------------------------
// Stubbed I/O primitives
// ---------------------------------------------------------------------------
// In the real Hermit build these are replaced by smoltcp socket calls wrapped
// in the Hermit async runtime. On the host (cargo check / cargo test with
// feature = std) they are no-ops that return plausible data.

/// Stub: perform DHCP or apply static config; returns assigned IP string.
#[allow(dead_code)]
fn bring_up_network(cfg: &NetConfig) -> String {
    if cfg.dhcp {
        // Real: spin up smoltcp EthernetInterface + DHCPv4 socket.
        // smoltcp::socket::dhcpv4::Socket is the entry point.
        // Stub: pretend DHCP succeeded.
        format!("dhcp:{}", cfg.static_ip)
    } else {
        format!("static:{}", cfg.static_ip)
    }
}

/// Stub: open a TLS connection to `host:443`, return a connection handle.
/// Real: parse the host from the endpoint URL, resolve via smoltcp DNS or
/// hard-coded gateway, open a TCP socket, wrap with rustls::ClientConnection.
#[allow(dead_code)]
fn tls_connect(_host: &str) -> Result<TlsStub, AgentError> {
    // In the real build:
    //   let config = rustls::ClientConfig::builder()
    //       .with_root_certificates(load_embedded_ca_bundle())
    //       .with_no_client_auth();
    //   let conn = rustls::ClientConnection::new(Arc::new(config), host.try_into()?)?;
    //   let tcp = smoltcp_tcp_connect(host, 443)?;
    //   Ok(rustls::Stream::new(&mut conn, &mut tcp))
    Ok(TlsStub)
}

/// Stub: HTTP/1.1 GET over the TLS connection.
#[allow(dead_code)]
fn http_get(_conn: &TlsStub, _path: &str) -> Result<Vec<u8>, AgentError> {
    // Real: write "GET {path} HTTP/1.1\r\nHost: {host}\r\n\r\n" into the
    // rustls::Stream, read response, strip headers, return body bytes.
    Err(AgentError::Stub("http_get is a stub in harness mode"))
}

/// Stub: HTTP/1.1 POST JSON over the TLS connection.
#[allow(dead_code)]
fn http_post(_conn: &TlsStub, _path: &str, _body: &[u8]) -> Result<(), AgentError> {
    Err(AgentError::Stub("http_post is a stub in harness mode"))
}

// ---------------------------------------------------------------------------
// Error type
// ---------------------------------------------------------------------------

#[derive(Debug)]
pub enum AgentError {
    /// Network or TLS failure.
    Network(&'static str),
    /// JSON parse failure.
    Json(&'static str),
    /// Stub: this code path is not executed in the harness.
    Stub(&'static str),
}

// ---------------------------------------------------------------------------
// Stub types (stand-ins for real smoltcp/rustls handles)
// ---------------------------------------------------------------------------

/// Placeholder for a live rustls::Stream<ClientConnection, smoltcp::TcpSocket>.
pub struct TlsStub;

// ---------------------------------------------------------------------------
// Main agent loop
// ---------------------------------------------------------------------------

/// Entry point called by genoa-init after the kernel environment is ready.
///
/// Flow:
///   loop {
///     1. bring_up_network()          — DHCP or static
///     2. tls_connect(host)           — TLS handshake
///     3. http_get("/v1/tasks/next")  — poll for work
///     4. execute(task)               — dispatch
///     5. http_post("/v1/tasks/result", result_json)
///     6. sleep(poll_interval_ms)
///   }
///
/// In harness mode (feature = "std") the loop runs one iteration and returns
/// AgentError::Stub at the I/O boundary so that `cargo check` and `cargo test`
/// can exercise the type structure without a live network.
pub fn run() -> ! {
    let cfg = NetConfig::from_manifest();

    // Step 1: Network bring-up (stub in harness).
    let _ip = bring_up_network(&cfg);

    // Main polling loop.
    loop {
        let result = poll_once(&cfg);
        match result {
            Ok(()) => {}
            Err(AgentError::Stub(_)) => {
                // Harness mode: the I/O stub fired. In a real unikernel this
                // branch is unreachable. We spin here so `run() -> !` is
                // satisfied without calling std::process::exit.
                spin_forever();
            }
            Err(AgentError::Network(msg)) => {
                // Log and retry; in a real unikernel we'd also back off.
                let _ = msg; // no_std: no eprintln available without Hermit's logger
            }
            Err(AgentError::Json(_)) => {
                // Malformed task — skip and continue polling.
            }
        }
    }
}

/// One poll iteration: GET task → execute → POST result.
fn poll_once(cfg: &NetConfig) -> Result<(), AgentError> {
    let conn = tls_connect(cfg.task_endpoint)?;
    let body = http_get(&conn, "/v1/tasks/next")?;

    let task: TaskEnvelope = serde_json::from_slice(&body)
        .map_err(|_| AgentError::Json("failed to deserialise TaskEnvelope"))?;

    let (status, output) = execute(&task);

    let result = TaskResult {
        task_id: task.id,
        agent_id: AGENT_ID,
        manifest_hash: MANIFEST_HASH,
        status,
        output,
    };

    let result_bytes = serde_json::to_vec(&result)
        .map_err(|_| AgentError::Json("failed to serialise TaskResult"))?;

    let result_conn = tls_connect(cfg.result_endpoint)?;
    http_post(&result_conn, "/v1/tasks/result", &result_bytes)?;

    Ok(())
}

/// Busy-spin forever. Used in harness mode to satisfy `-> !`.
/// In the real Hermit build this is replaced by `hermit::sys::shutdown(0)`.
fn spin_forever() -> ! {
    loop {
        // In a real unikernel: core::hint::spin_loop()
        #[cfg(feature = "std")]
        std::thread::yield_now();
        #[cfg(not(feature = "std"))]
        core::hint::spin_loop();
    }
}

// ---------------------------------------------------------------------------
// Status surface (/v1/status handler — called by the HTTP server stub)
// ---------------------------------------------------------------------------

/// Build the /v1/status payload.
/// In the real unikernel a minimal HTTP server (hand-rolled, <200 LOC)
/// calls this and serves the result over TLS.
pub fn build_status(uptime_ms: u64) -> AgentStatus {
    AgentStatus {
        agent_id: AGENT_ID,
        manifest_hash: MANIFEST_HASH,
        attestation_pubkey: ATTESTATION_PUBKEY_HEX,
        task_endpoint: TASK_ENDPOINT,
        uptime_ms,
        // STUB: real implementation signs the canonical JSON with the
        // agent's Ed25519 private key (loaded from a sealed secret or
        // provisioned by the control plane at first boot).
        signature: String::from("STUB_SIGNATURE_NOT_REAL"),
    }
}

// ---------------------------------------------------------------------------
// Tests (run on host with `cargo test`)
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn manifest_constants_are_non_empty() {
        assert!(!AGENT_ID.is_empty());
        assert!(!MANIFEST_HASH.is_empty());
        assert!(!TASK_ENDPOINT.is_empty());
        assert_eq!(MANIFEST_HASH.len(), 64, "SHA-256 hex should be 64 chars");
    }

    #[test]
    fn execute_echo() {
        let task = TaskEnvelope {
            id: "test-1".into(),
            kind: "echo".into(),
            payload: serde_json::json!({"hello": "world"}),
            expires_at: "2099-01-01T00:00:00Z".into(),
        };
        let (status, output) = execute(&task);
        assert!(matches!(status, TaskStatus::Ok));
        assert_eq!(output["hello"], "world");
    }

    #[test]
    fn execute_ping() {
        let task = TaskEnvelope {
            id: "test-2".into(),
            kind: "ping".into(),
            payload: serde_json::Value::Null,
            expires_at: "2099-01-01T00:00:00Z".into(),
        };
        let (status, output) = execute(&task);
        assert!(matches!(status, TaskStatus::Ok));
        assert_eq!(output["pong"], true);
        assert_eq!(output["agent_id"], AGENT_ID);
    }

    #[test]
    fn execute_unknown_returns_unsupported() {
        let task = TaskEnvelope {
            id: "test-3".into(),
            kind: "fly_to_moon".into(),
            payload: serde_json::Value::Null,
            expires_at: "2099-01-01T00:00:00Z".into(),
        };
        let (status, _) = execute(&task);
        assert!(matches!(status, TaskStatus::Unsupported));
    }

    #[test]
    fn net_config_from_manifest() {
        let cfg = NetConfig::from_manifest();
        assert_eq!(cfg.dhcp, DHCP_ENABLED);
        assert_eq!(cfg.task_endpoint, TASK_ENDPOINT);
        assert!(cfg.poll_interval_ms > 0);
    }

    #[test]
    fn build_status_round_trips_json() {
        let status = build_status(12345);
        let json = serde_json::to_string(&status).expect("serialise status");
        assert!(json.contains(AGENT_ID));
        assert!(json.contains(MANIFEST_HASH));
        assert!(json.contains("uptime_ms"));
    }
}
