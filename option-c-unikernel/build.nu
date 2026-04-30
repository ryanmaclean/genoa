#!/usr/bin/env nu
# build.nu — Genoa Option-C unikernel build wrapper
#
# Subcommands:
#   nu build.nu check          — cargo check (stable/nightly, no Hermit toolchain needed)
#   nu build.nu test           — cargo test (host tests for agent logic)
#   nu build.nu hermit-setup   — print the exact commands to install the Hermit toolchain
#   nu build.nu hermit-build   — print (and optionally run) the Hermit kernel image build
#   nu build.nu help           — print this help

def main [subcmd: string = "help"] {
    match $subcmd {
        "check"        => do-check,
        "test"         => do-test,
        "hermit-setup" => hermit-setup,
        "hermit-build" => hermit-build,
        "help"         => print-help,
        _              => {
            print $"Unknown subcommand: ($subcmd)"
            print-help
            exit 1
        }
    }
}

def print-help [] {
    print "
Genoa Option-C — unikernel agent-as-kernel build wrapper

Usage: nu build.nu <subcommand>

Subcommands:
  check          Run `cargo check` — only requires stable/nightly host Rust
  test           Run `cargo test`  — exercises agent logic on the host
  hermit-setup   Print commands to install the Hermit unikernel toolchain
  hermit-build   Print (and run if --run flag added) the Hermit kernel build
  help           This message

Quickstart (no Hermit toolchain required):
  nu build.nu check
  nu build.nu test
"
}

def do-check [] {
    print "=== cargo check (host target, stable Rust) ==="
    let result = (do { cargo check --workspace --message-format=json } | complete)
    if $result.exit_code == 0 {
        print "cargo check: PASS"
    } else {
        print "cargo check: FAIL"
        print $result.stderr
        exit $result.exit_code
    }
}

def do-test [] {
    print "=== cargo test (host target) ==="
    let result = (do { cargo test --workspace } | complete)
    if $result.exit_code == 0 {
        print "cargo test: PASS"
    } else {
        print "cargo test: FAIL"
        print $result.stderr
        exit $result.exit_code
    }
}

def hermit-setup [] {
    print "
=== Hermit Toolchain Setup ===

The following commands install the Hermit unikernel toolchain and QEMU target.
Run them on a machine with rustup and qemu-system-x86_64 available.

--- Step 1: Install nightly Rust with the Hermit target ---
  rustup toolchain install nightly
  rustup target add x86_64-unknown-hermit --toolchain nightly
  rustup component add rust-src --toolchain nightly

--- Step 2: Install the Hermit loader (boots your .elf in QEMU) ---
  cargo +nightly install --locked uhyve          # optional: macOS hypervisor
  # or use the pre-built QEMU loader:
  # https://github.com/hermit-os/loader/releases

--- Step 3: Install QEMU (if not already present) ---
  # macOS:  brew install qemu
  # Ubuntu: apt install qemu-system-x86

--- Step 4: Build the kernel image ---
  nu build.nu hermit-build

Documentation: https://github.com/hermit-os/hermit-rs
License: Hermit is MIT OR Apache-2.0
"
}

def hermit-build [] {
    print "
=== Hermit Kernel Image Build ===

The following command builds the Genoa unikernel kernel image.
It requires the Hermit toolchain (see: nu build.nu hermit-setup).

--- Build command ---
  cargo +nightly build \\
    --target x86_64-unknown-hermit \\
    --release \\
    -Zbuild-std=core,alloc \\
    -p genoa-init

  # Output: target/x86_64-unknown-hermit/release/genoa-init (ELF)

--- Run in QEMU (with Hermit loader) ---
  qemu-system-x86_64 \\
    -kernel <path-to-hermit-loader.elf> \\
    -initrd target/x86_64-unknown-hermit/release/genoa-init \\
    -cpu qemu64 \\
    -m 256M \\
    -netdev user,id=net0,hostfwd=tcp::8080-:80 \\
    -device virtio-net-pci,netdev=net0 \\
    -nographic

  # The loader hands off to the genoa-init ELF, which calls genoa_agent::run().
  # Serial output appears on stdout.  DHCP is handled by smoltcp over virtio-net.

--- Expected output (first 5 lines) ---
  [Hermit] Booting genoa-init ...
  === Genoa unikernel v0.1.0 ===
  agent_id       : genoa-c-demo-01
  manifest_hash  : <sha256-of-genoa.toml>
  task_endpoint  : https://genoa.example.com/v1/tasks/next
"
}
