#!/usr/bin/env nu
# bake-off-demo.nu — AX-first demo surface for Genoa Option-C
#
# All subcommands return JSON to stdout (machine-consumable first, human second).
#
# Subcommands:
#   nu bake-off-demo.nu check    — run cargo check; return JSON status
#   nu bake-off-demo.nu describe — return JSON description of the built artifact
#   nu bake-off-demo.nu schema   — return the manifest JSON Schema

def main [subcmd: string = "check"] {
    match $subcmd {
        "check"    => cmd-check,
        "describe" => cmd-describe,
        "schema"   => cmd-schema,
        _          => {
            {
                error: $"unknown subcommand: ($subcmd)",
                valid_subcommands: ["check", "describe", "schema"]
            } | to json
            exit 1
        }
    }
}

# ── check ──────────────────────────────────────────────────────────────────
def cmd-check [] {
    let start_ms = (date now | format date "%s%3f" | into int)

    # Run cargo check and capture both streams
    let result = (do { cargo check --workspace } | complete)

    let end_ms = (date now | format date "%s%3f" | into int)
    let elapsed_ms = ($end_ms - $start_ms)

    let status = if $result.exit_code == 0 { "PASS" } else { "FAIL" }

    {
        subcommand:  "check",
        status:      $status,
        exit_code:   $result.exit_code,
        elapsed_ms:  $elapsed_ms,
        command:     "cargo check --workspace",
        target:      "host (stable/nightly Rust)",
        note:        "Full Hermit build requires: cargo +nightly build --target x86_64-unknown-hermit -Zbuild-std=core,alloc",
        stderr_tail: ($result.stderr | lines | last 5 | str join "\n"),
    } | to json --indent 2
}

# ── describe ────────────────────────────────────────────────────────────────
def cmd-describe [] {
    # Read genoa.toml to extract fields the same way build.rs would.
    let toml_path = ([$env.PWD, "genoa.toml"] | path join)

    if not ($toml_path | path exists) {
        {
            error: "genoa.toml not found",
            expected_path: $toml_path
        } | to json
        exit 1
    }

    let manifest = (open $toml_path)

    # Compute SHA-256 hash of the raw TOML bytes using sha256sum or shasum
    let raw_bytes = (open --raw $toml_path)
    let hash_line = (echo $raw_bytes | sha256sum | str trim)
    let manifest_hash = ($hash_line | split row " " | first | str trim)

    {
        subcommand:          "describe",
        schema_version:      ($manifest.schema_version? | default "unknown"),
        agent_id:            ($manifest.identity?.agent_id? | default "unknown"),
        attestation_pubkey:  ($manifest.identity?.attestation_pubkey? | default "unknown"),
        manifest_hash:       $manifest_hash,
        target_triple:       "x86_64-unknown-hermit (stub; cargo check runs on host)",
        task_endpoint:       ($manifest.tasks?.endpoint? | default "unknown"),
        result_endpoint:     ($manifest.tasks?.result_endpoint? | default "unknown"),
        poll_interval_ms:    ($manifest.tasks?.poll_interval_ms? | default 2000),
        dhcp_enabled:        ($manifest.network?.dhcp? | default true),
        static_ip_fallback:  ($manifest.network?.static_ip? | default "10.0.2.15"),
        license_set: [
            "Apache-2.0 (project + Hermit substrate)",
            "MIT (serde, serde_json, hex, sha2)",
            "0BSD (smoltcp)",
            "Apache-2.0/MIT/ISC (rustls triple-license)",
            "MIT OR Apache-2.0 (toml, build-time only)"
        ],
        crates: [
            {name: "genoa-agent",  version: "0.1.0", license: "Apache-2.0"},
            {name: "genoa-config", version: "0.1.0", license: "Apache-2.0"},
            {name: "genoa-init",   version: "0.1.0", license: "Apache-2.0"},
            {name: "smoltcp",      version: "0.11",  license: "0BSD"},
            {name: "rustls",       version: "0.23",  license: "Apache-2.0/MIT/ISC"},
            {name: "serde",        version: "1.0",   license: "MIT OR Apache-2.0"},
            {name: "serde_json",   version: "1.0",   license: "MIT OR Apache-2.0"},
            {name: "sha2",         version: "0.10",  license: "MIT OR Apache-2.0"},
            {name: "hex",          version: "0.4",   license: "MIT OR Apache-2.0"},
            {name: "toml",         version: "0.8",   license: "MIT OR Apache-2.0"},
        ],
        ax_first: {
            status_endpoint:  "/v1/status",
            task_endpoint:    "/v1/tasks/next",
            result_endpoint:  "/v1/tasks/result",
            response_format:  "signed JSON (Ed25519, key in attestation_pubkey above)",
            discovery:        "genoa.toml baked into image; /v1/status is the live probe"
        }
    } | to json --indent 2
}

# ── schema ──────────────────────────────────────────────────────────────────
def cmd-schema [] {
    let schema_path = ([$env.PWD, "schema", "manifest.v1.json"] | path join)
    if not ($schema_path | path exists) {
        {error: "schema/manifest.v1.json not found", expected: $schema_path} | to json
        exit 1
    }
    open $schema_path | to json --indent 2
}
