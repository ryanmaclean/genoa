# AGENTS.md

## Role

Image/artifact build, deployment, verification, and receipts.

## Owns

- manifests
- image build/deploy
- artifact hashes
- receipts/provenance

## Do not duplicate

- agent scheduler
- runtime state machine
- filesystem history engine

## Sibling repos to consult first

- ryanmaclean/smolfire
- ryanmaclean/bop
- ryanmaclean/moth

## Cross-project context

Read `docs/CROSS-PROJECT-LESSONS-2026-09.md` before making architectural changes.

## Agent delegation

- Primary GitHub coding agent: Copilot when assignable/available.
- Fallback: delegate the issue or PR to Codex with `@codex`.
- Do not treat Copilot/Codex state as canonical project state; keep canonical work in repo issues/BOP/filesystem state.


## Binding cross-project constraints

Before proposing architecture or cross-project primitives, read:

- `ryanmaclean/skills/docs/CONSTRAINTS.md`
- `ryanmaclean/skills/docs/RESEARCH-INDEX.md`
- this repo's `.project.toml`

Do not repeat research already indexed unless new evidence or requirements materially change the conclusion.

New architecture proposals must identify:
- the invariant uniquely owned by the new layer
- why a lower existing layer cannot own it
- what duplicated state or layer the proposal removes

Key constraints include:
- visibility is not durability
- identity, order, content hash, and presentation remain distinct
- ordering has one source
- retries reuse logical operation identity
- queues/rings are transport, not semantics
- derived views are disposable
- push invariants down; pull policy up
- formalize durable primitives before RTL/FPGA
- RISC-V is optional control plane, not the v0 datapath
- ASIC requires measured FPGA justification
