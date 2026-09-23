# Cross-project lessons — 2026-09

Genoa owns **artifact construction, deployment, verification, and receipts**.

## Reuse

- **smolFire** is the source of truth for one-ELF FreeBSD microVM boot behavior and measurements.
- **NetBSD MICROVM / rump** should be represented as additional build targets, not separate bespoke pipelines.
- **option-c-unikernel** is prior art: inspect and reuse its Rust/smoltcp work before starting new unikernel networking.
- **BOP** owns run/work identity; Genoa receipts should correlate with it but not duplicate it.
- **Moth** may supply a smaller embedded worker than a shell-heavy agent image.

## Manifest direction

A manifest should distinguish immutable boot artifact from writable state device and record:
- runtime/kernel identity
- filesystem type and UUID/label
- boot artifact hash
- state artifact hash
- deployment/provider identity

Do not force UEFI/qcow2 for direct-kernel/PVH targets.

## Agent assignment

Copilot is primary. Codex fallback uses `@codex` delegation rather than issue assignment.
