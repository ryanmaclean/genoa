# Synergy Test: D validates A, B, E

**Test date:** 2026-04-30  
**Working directory:** `/Users/studio/genoa/synergy-d-validates/`  
**Hypothesis:** D's `conformance/validate.nu attestation` can serve as a common validation envelope for all three other producers.

---

## 0. Validator bug discovered

Before results: D's validator (`conformance/validate.nu`) crashes with a fatal Nushell error
before it can emit any output or exit code for **all three inputs**.

```
Error: nu::shell::needs_positive_value
  x Negative value passed when positive one is required
   ,-[conformance/validate.nu:318:30]
 317 |     if $i < ($caps | length) {
 318 |       let cap = ($caps | get $i)
       :                              ^-- use a positive value
```

**Root cause:** The loop `for i in (0..($caps | length | $in - 1))` generates range `0..(-1)`
when `capability_claims` is empty. In Nushell, `0..(-1)` iterates `[0, -1]`. The guard
`if $i < ($caps | length)` evaluates `if -1 < 0` as `true`, then `$caps | get -1` panics
because `get` refuses negative indices. The fix is `if $i >= 0 and $i < ($caps | length)`.

**The bug is in `validate_attestation` at line 316 and mirrors an identical bug in
`validate_manifest` at line 196.** Any document with an empty `capability_claims` array
(which all three producers emit) triggers the crash.

**Impact:** D's conformance tool cannot validate anything from A, B, or E as shipped.
Exit code is always 1, output is always a stack trace. The tool is non-operational.

Validation results below were obtained by replaying D's schema logic manually in Nushell
(extracting the same field-by-field checks from validate.nu, with the crashing loop removed).

---

## 1. Per-producer validation results

### 1.1 Option A — smolBSD receipt

**Sample file:** `samples/a-receipt.json`  
**Source:** `option-a-smolbsd/out/smolbsd-qemu-x86_64-v0.1.0.receipt.json`

**Result: FAIL (11 errors)**

```json
{
  "valid": false,
  "file": "samples/a-receipt.json",
  "doc_type": "attestation",
  "schema": "https://genoa.dev/v1/schemas/attestation.v1.json",
  "errors": [
    "Required field missing: _type",
    "Required field missing: subject",
    "Required field missing: predicateType",
    "Required field missing: predicate",
    "_type must be 'https://in-toto.io/Statement/v1', got ''",
    "predicateType must be 'https://genoa.dev/AgentHost/v1', got ''",
    "subject must be a non-empty array",
    "Required field missing: predicate.image_identity",
    "Required field missing: predicate.capability_claims",
    "Required field missing: predicate.slsa_level",
    "Required field missing: predicate.sbom_digest"
  ],
  "warnings": []
}
```

**Analysis:** A emits a completely different schema — a flat receipt format, not an in-toto
Statement. None of the four top-level D-required fields (`_type`, `subject`, `predicateType`,
`predicate`) exist in A's receipt. A's receipt is structured around `schema_version`, `receipt_id`,
`built_at`, `image`, `build`, `agent`, `hashes`, `claims`. Total schema mismatch.

---

### 1.2 Option B — cloud-init attestation

**Sample file:** `samples/b-attestation.json`  
**Source:** `option-b-cloudinit/dist/ai-assistant-edge-v1-qcow2/attestation.json`

**Result: FAIL (5 errors)**

```json
{
  "valid": false,
  "file": "samples/b-attestation.json",
  "doc_type": "attestation",
  "schema": "https://genoa.dev/v1/schemas/attestation.v1.json",
  "errors": [
    "predicateType must be 'https://genoa.dev/AgentHost/v1', got 'https://genoa.dev/image-build/v1'",
    "Required field missing: predicate.image_identity",
    "Required field missing: predicate.capability_claims",
    "Required field missing: predicate.slsa_level",
    "Required field missing: predicate.sbom_digest"
  ],
  "warnings": []
}
```

**Analysis:** B is structurally the closest to D. It correctly emits an in-toto v1 Statement
with `_type`, `subject`, `predicateType`, `predicate`. The envelope is right. The failures are:

1. **`predicateType` mismatch:** B uses `https://genoa.dev/image-build/v1`; D requires
   `https://genoa.dev/AgentHost/v1`. This is a namespace collision — both are "genoa.dev" URLs
   but different paths. Neither one defers to the other.
2. **Predicate shape mismatch:** D's predicate requires `image_identity`, `capability_claims`,
   `slsa_level`, `sbom_digest`. B's predicate has `buildType`, `builder`, `buildConfig`,
   `metadata`, `materials`, `trust`, `sbom`. Different keys for largely overlapping concerns.

B would pass D's envelope check if `predicateType` were changed and the predicate keys were
remapped. The in-toto wrapper is fully compatible.

---

### 1.3 Option E — LSD receipt

**Sample file:** `samples/e-receipt.json`  
**Source:** `option-e-lsd/out/lsd-receipt.json`

**Result: FAIL (10 errors)**

```json
{
  "valid": false,
  "file": "samples/e-receipt.json",
  "doc_type": "attestation",
  "schema": "https://genoa.dev/v1/schemas/attestation.v1.json",
  "errors": [
    "Required field missing: _type",
    "Required field missing: subject",
    "Required field missing: predicateType",
    "Required field missing: predicate",
    "_type must be 'https://in-toto.io/Statement/v1', got ''",
    "predicateType must be 'https://genoa.dev/AgentHost/v1', got ''",
    "Required field missing: predicate.image_identity",
    "Required field missing: predicate.capability_claims",
    "Required field missing: predicate.slsa_level",
    "Required field missing: predicate.sbom_digest"
  ],
  "warnings": []
}
```

**Analysis:** E's receipt is not an in-toto Statement at all. It tracks installer artifacts
(`bootstrap.sh`, `bsdinstall.script`) rather than a disk image. Its schema is flat and
installer-pipeline-oriented: `schema_version`, `built_at`, `manifest_sha256`, `artifacts[]`,
`tool`, `signing`, `trust_level`. No in-toto envelope. Total schema mismatch.

---

## 2. Schema field diff table

Rows = semantically equivalent fields. Cols = A, B (D-schema), D-schema, E.

| Concept | A (`receipt.v1.json`) | B (`attestation.v1.json`) | D (`attestation.v1.json`) | E (`receipt.v1.json`) |
|---|---|---|---|---|
| **Envelope type** | (none — flat) | `_type = in-toto/Statement/v1` | `_type = in-toto/Statement/v1` | (none — flat) |
| **Predicate type** | (none) | `predicateType = image-build/v1` | `predicateType = AgentHost/v1` | (none) |
| **Subject/artifact digest** | `hashes.image_sha256` (bare hex) | `subject[].digest.sha256` (bare hex) | `subject[].digest.sha256` (bare hex) | `artifacts[].sha256` (bare hex) |
| **Subject name** | `image.name` + `image.version` | `subject[].name` (target string) | `subject[].name` | `artifacts[].name` |
| **Image name** | `image.name` | (in `buildConfig`) | `predicate.image_identity.name` | (no image concept — installer artifacts) |
| **Image version** | `image.version` | (manifest hash serves as version proxy) | `predicate.image_identity.version` | (none) |
| **Architecture** | `build.arch` (build host arch, not target) | (none — not declared) | `predicate.image_identity.architecture` (enum: amd64/arm64/…) | (none) |
| **OS** | `image.format` (qcow2/raw/vmdk) | (in osbuild manifest template, not attestation) | `predicate.image_identity.os` (enum: freebsd/linux/…) | (none) |
| **Build timestamp** | `built_at` (top-level) | `predicate.metadata.buildStartedOn` / `buildFinishedOn` | `predicate.image_identity.build_timestamp` (optional) | `built_at` (top-level) |
| **Builder identity** | `build.host` + `build.genoa_version` | `predicate.builder.id` + `predicate.builder.version` | `predicate.build_environment.builder_id` (optional, URI) | `tool.name` + `tool.version` + `tool.commit` |
| **Source manifest hash** | `hashes.manifest_sha256` | `predicate.buildConfig.manifest_hash` | (not in predicate; would be in `build_environment.resolved_dependencies`) | `manifest_sha256` (top-level) |
| **SBOM reference** | (none) | `predicate.sbom.format` + `predicate.sbom.uri` | `predicate.sbom_digest` (sha256, required) | (none) |
| **SLSA level** | (none) | (none — `trust.level` uses different vocabulary) | `predicate.slsa_level` (int 0–4, required) | `trust_level` (string enum, non-SLSA vocabulary) |
| **Trust/signing declaration** | `signing.tool` + `signing.placeholder` | `predicate.trust.level` + `predicate.trust.signed_by` + `predicate.trust.policy` | `predicate.signature` (optional, keyid+sig+cert) | `trust_level` (top-level string) + `signing.method` |
| **Capabilities** | (none — `claims[]` is runtime probes, not capability decls) | (none) | `predicate.capability_claims[]` (required, may be empty) | (none) |
| **Build commands** | `build.build_commands[]` (detailed, with stub flags) | (osbuild command emitted to stdout, not in attestation) | (none — SLSA `build_environment` is optional) | (installer scripts are artifacts, not commands) |
| **Verifiable claims** | `claims[]` (probe+expect+status format) | `predicate.metadata.completeness` (boolean flags only) | (none defined) | (none) |
| **Warnings** | (none in schema; embedded in claims) | (none in schema) | (none) | `warnings[]` (top-level array) |
| **Schema version** | `schema_version: "v1"` | (implicit — `$id` URL versioned) | (implicit — `$id` URL versioned) | `schema_version: "1.0.0"` (SemVer) |
| **additionalProperties** | `false` (strict) | `false` (strict) | `false` (strict) | `false` (strict) |

**Common ground:** All four schemas use `sha256` for artifact digests and follow JSON Schema
draft 2020-12 with `additionalProperties: false`. Beyond that, structural alignment is minimal.

**Incompatible fields:**
- A's `signing.tool` enum `["signify"]` vs B's `trust.level` enum vs E's `signing.method`
  enum `["sigstore","gpg","none"]` vs D's `signature.keyid+sig+cert` — four different signing
  models, none overlapping.
- A's `build.builder_type` enum `["local","fb-vm-24","fb13-vm","fb14-vm","native-fleet-pi","zig-cc","dry-run"]`
  is opaque to D.
- E's `trust_level` enum `["unsigned","self-signed","cosign-verified","slsa-l1","slsa-l2","slsa-l3"]`
  conflates signing method and SLSA level into one field; D separates them.
- D's `image_identity.architecture` enum `["amd64","arm64","riscv64","armv7","s390x","ppc64le"]`
  and `image_identity.os` enum `["freebsd","netbsd","openbsd","linux","windows"]` — neither A
  nor E populates these in their attestation output (A has arch in `build.arch` which tracks the
  build *host*, not the target image).

---

## 3. Recommended harmonization

**Direction: move B to D-conformance; keep A and E as-is with a thin wrapper layer.**

### Why not the other direction (change D to accept A/B/E as-is)?

D's schema makes in-toto the non-negotiable envelope. That is a sound design choice — in-toto
is a real CNCF spec with ecosystem tooling. Relaxing D to accept flat receipts would make D
meaningless as a spec.

### Changes needed per producer

#### Option B → D-conformant (minimal diff)

B already emits a valid in-toto v1 Statement. Required changes:

1. **`predicateType`:** Change `"https://genoa.dev/image-build/v1"` to
   `"https://genoa.dev/AgentHost/v1"`. One constant change in `genoa.nu`.

2. **Predicate reshape:** Map B's existing fields into D's predicate keys:
   ```
   B: predicate.builder.id            → D: predicate.image_identity.id (synthesized)
   B: predicate.buildConfig.manifest_hash  → D: predicate.build_environment.resolved_dependencies[0]
   B: predicate.metadata.buildStartedOn   → D: predicate.image_identity.build_timestamp
   B: predicate.sbom.uri (stub)           → D: predicate.sbom_digest (sha256 of stub)
   ```
   B must add: `image_identity` with `id`, `name`, `version`, `architecture`, `os`.
   B must add: `capability_claims: []` (empty is valid).
   B must add: `slsa_level: 0` (honest — no SLSA guarantees in current build).

   The `trust` block can be moved to `signature` with appropriate key mapping.
   B's `predicate.buildType`, `builder`, `buildConfig`, `metadata`, `materials` would all need
   to be dropped (D uses `additionalProperties: false`). They could be preserved in
   `build_environment.resolved_dependencies`.

   **Effort: ~50 lines of genoa.nu changes.**

#### Option A → D-conformant (major refactor)

A's receipt is fundamentally a different document type — a build log with runtime probe specs,
not an image identity attestation. The receipts serve different purposes:
- A's `claims[]` = runtime verification probes for `fleet-eval`
- D's `predicate` = build-time identity attestation for supply chain

**Recommended approach:** Keep A's receipt format as-is for fleet-eval consumption.
Add a separate `nu genoa.nu attest` subcommand that wraps the receipt data into a
D-conformant in-toto Statement:

```
A receipt → genoa attest → D-conformant attestation.json (co-emitted alongside receipt)
```

The attestation would synthesize:
- `image_identity` from `image.*` + `build.arch` (with arch-to-D-enum mapping)
- `slsa_level: 0` (no SLSA infrastructure in A's build)
- `sbom_digest`: A would need to add SBOM generation (currently absent)
- `capability_claims: []`

**Effort: ~80 lines + SBOM stub. The `sbom_digest` requirement is the blocking item;
A has no SBOM concept today.**

#### Option E → D-conformant (structural mismatch)

E's receipt tracks installer artifacts (`bootstrap.sh`, `bsdinstall.script`), not a produced
disk image. There is no image digest to put in `subject[].digest.sha256` because E doesn't
produce an image — it produces scripts that *create* an image at provision time.

This is a conceptual mismatch: D's `AgentHost/v1` predicate assumes a produced image artifact.
E's model is fundamentally different — it ships an installer, not an image.

**Options:**
1. E adds a `nu lsd.nu attest` wrapper after provisioning completes (outside the current
   build phase), which attests the *provisioned* machine rather than the installer scripts.
   This is architecturally correct but requires E to be run post-boot.
2. E treats the installer scripts as the attested artifact — legitimate but requires a
   different `predicateType` than `AgentHost/v1` (e.g., `genoa.dev/Installer/v1`).
3. D adds a second predicate type for installer-phase provenance.

**Effort: Option 1 is ~60 lines; but the conceptual gap with D's model is genuine.**

---

## 4. Composability score

**Score: 3/10**

**Rationale:**

| Factor | Score | Notes |
|---|---|---|
| Envelope compatibility | 5/10 | B already uses in-toto correctly; A and E do not |
| Predicate field overlap | 2/10 | Almost no field name overlap across schemas |
| Validator operational | 0/10 | D's validator crashes on every input due to Nushell range bug |
| Common trust vocabulary | 2/10 | Four different signing/trust models, zero overlap |
| SBOM coverage | 3/10 | Only B and D reference SBOM; A and E have none |
| Architecture/OS coverage | 4/10 | Only D mandates target arch/os; A tracks build-host arch |
| Conceptual alignment | 4/10 | B=image baker (aligns), A=image builder (partial), E=installer generator (misaligned) |

D's `AgentHost/v1` predicate is opinionated about the output being a deployable image with
a known digest. That is the right model for A and B. It is the wrong model for E.

---

## 5. Honest assessment

**Should D become the unified envelope, or should A/B/E reuse in-toto verbatim and skip D's `AgentHost/v1` predicate?**

**Recommendation: D should NOT be the unified envelope as currently specified. In-toto verbatim is the better base.**

Reasons:

1. **D's validator is broken.** It cannot validate any of the three producers' outputs without
   crashing. A spec that ships a non-functional validator is not ready to be a standard.

2. **D's `predicateType = AgentHost/v1` is too narrow.** The `image-build/v1` predicate type
   used by B is actually more honest — it describes what all three producers are doing (building).
   `AgentHost/v1` implies runtime agent hosting, which is a concern of the *deployed image*, not
   the build attestation. The naming conflates build-time provenance with runtime capability.

3. **D mandates `sbom_digest` as a required field.** None of A, B, or E produce a real SBOM.
   A has no SBOM concept. B stubs it. E has no SBOM. Making this required creates immediate
   conformance debt for all producers and will be systematically faked with placeholder hashes,
   which defeats the purpose.

4. **D mandates `capability_claims[]` (array, required).** This is a useful concept but is
   currently completely absent from all producers. Requiring it guarantees empty arrays
   everywhere, which reduces it to noise.

5. **D mandates `slsa_level` (required int 0–4).** This is a good forcing function, but all
   three producers would honestly declare `slsa_level: 0`, making it another mandatory-but-
   vacuous field.

6. **The `additionalProperties: false` strictness is correct** but means B cannot add its
   `trust`, `materials`, and `buildConfig` fields that are genuinely more informative than
   D's equivalents. D's `build_environment` block is optional and weaker than B's `trust` block.

**Preferred path:**

Use `in-toto v1 Statement` as the envelope (all four specs agree on this or should).
Standardize on a `predicateType` of `https://genoa.dev/image-build/v1` (B's version is more
accurately named). Define a `genoa.dev/image-build/v1` predicate schema that merges D's
`image_identity` (good, should be required) with B's `trust` block (explicit trust vocabulary
is better than D's optional `signature`), drops `sbom_digest` to optional, and drops
`capability_claims` from the build attestation entirely (capabilities belong in the discovery
endpoint, not the build receipt).

In-toto tooling (cosign, sigstore, Rekor) already understands in-toto Statements. D's
`AgentHost/v1` predicate adds ceremony without adding verifiability.

**If D's author wants D to win:** Fix the validator bug (5-line change), make `sbom_digest`
and `capability_claims` optional, and rename `predicateType` to align with B's `image-build/v1`
naming. Then A and E each need a thin `attest` wrapper — the envelope overhead is about 80 lines
total across both.
