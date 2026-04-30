// genoa-config/src/lib.rs
// Compile-time manifest constants baked into the kernel image by build.rs.
// This crate is no_std so it links cleanly into the Hermit unikernel image.
//
// All constants are sourced from cargo:rustc-env vars emitted by build.rs.
// No runtime parsing, no file I/O — everything is a &'static str or u64.
#![no_std]

/// SHA-256 hex digest of the genoa.toml that was used at build time.
/// Agents and verifiers can confirm image integrity by comparing this with
/// a separately-published manifest hash.
pub const MANIFEST_HASH: &str = env!("GENOA_MANIFEST_HASH");

/// Unique identity string for this agent instance.
pub const AGENT_ID: &str = env!("GENOA_AGENT_ID");

/// Hex-encoded Ed25519 public key used to verify attestation signatures on
/// the /v1/status response.
pub const ATTESTATION_PUBKEY_HEX: &str = env!("GENOA_ATTESTATION_PUBKEY");

/// URL of the task-polling endpoint.
pub const TASK_ENDPOINT: &str = env!("GENOA_TASK_ENDPOINT");

/// URL of the result-posting endpoint.
pub const RESULT_ENDPOINT: &str = env!("GENOA_RESULT_ENDPOINT");

/// Schema version of the genoa.toml that was parsed.
pub const SCHEMA_VERSION: &str = env!("GENOA_SCHEMA_VERSION");

/// Whether DHCP should be attempted on boot.
pub const DHCP_ENABLED: bool = {
    // env! always returns &str; we parse it ourselves because const fn
    // parsing is limited.  "true" → true, anything else → false.
    let bytes = env!("GENOA_DHCP").as_bytes();
    bytes[0] == b't'
};

/// Static fallback IP (dotted-decimal) if DHCP is disabled or times out.
pub const STATIC_IP: &str = env!("GENOA_STATIC_IP");

/// Poll interval in milliseconds between /v1/tasks/next requests.
pub const POLL_INTERVAL_MS: u64 = {
    // Const parsing of a decimal integer string.
    let s = env!("GENOA_POLL_INTERVAL_MS").as_bytes();
    let mut val: u64 = 0;
    let mut i = 0;
    while i < s.len() {
        val = val * 10 + (s[i] - b'0') as u64;
        i += 1;
    }
    val
};

/// A machine-readable description block for the AX-first `describe` surface.
/// Returns a static string slice that is valid JSON.
pub fn describe_json() -> &'static str {
    // This is intentionally a literal with substituted constants so the
    // compiler inlines it — no heap allocation needed.
    // For a real implementation we'd use a const fn formatter or a build.rs
    // that writes this out; for the demo we return the compile-time env info
    // via the individual constants above, and the describe subcommand in
    // bake-off-demo.nu assembles the JSON on the host side.
    concat!(
        r#"{"schema_version":""#, env!("GENOA_SCHEMA_VERSION"), r#"","#,
        r#""agent_id":""#,        env!("GENOA_AGENT_ID"),        r#"","#,
        r#""manifest_hash":""#,   env!("GENOA_MANIFEST_HASH"),   r#"","#,
        r#""task_endpoint":""#,   env!("GENOA_TASK_ENDPOINT"),   r#"","#,
        r#""attestation_pubkey":""#, env!("GENOA_ATTESTATION_PUBKEY"), r#""}"#,
    )
}
