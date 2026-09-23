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
