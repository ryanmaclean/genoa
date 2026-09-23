# Security Policy

## Supported work

Security fixes are prioritized for the default branch and current released/actively developed paths. Experimental and reference-only paths may receive best-effort fixes.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting / Security Advisory flow for this repository when available.

Do **not** open a public issue containing:
- credentials or tokens
- exploitable proof-of-concept details that would put users at immediate risk
- private infrastructure identifiers
- unredacted customer/user data

If private reporting is unavailable, open a minimal public issue stating that you have a security concern and request a private contact channel; omit exploit details until a private channel exists.

## Scope

Useful reports include:
- arbitrary code execution or sandbox/isolation escape
- path traversal or unsafe filesystem access
- credential or secret exposure
- command injection
- unsafe agent/tool execution
- authentication/authorization bypass
- provenance/attestation bypass
- dependency or build-chain vulnerabilities with a demonstrated impact

## Agent-generated changes

Security-sensitive changes produced by coding agents require the same review and tests as human-authored changes. Agent output, conversation history, and model claims are not security evidence by themselves.
