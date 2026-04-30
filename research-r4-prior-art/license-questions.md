# Genoa License Questions — Needs User Decision

Each item below has a borderline or ambiguous license assessment. None of these
tools are included in genoa's dependency graph until the user makes an explicit
decision. This file is the audit trail for that decision process.

---

## LQ-1: cloud-init — GPL-3.0 OR Apache-2.0 dual-license (per-file)

**Tool:** cloud-init
**URL:** https://github.com/cloud-init/cloud-init
**License found:** Dual per-file: some files GPL-3.0, some Apache-2.0
**Verified:** Yes — LICENSE file in repo states "GPL-3.0 or Apache-2.0 at your option"
for the project overall, but individual source files carry their own SPDX headers.

**The risk:** "At your option" dual-licensing means the *project* allows Apache-2.0
use, but files contributed before the dual-license header was added may still carry
only GPL-3 headers. If genoa vendors a GPL-3-only file, genoa becomes GPL-3.

**What genoa actually needs:** genoa does not vendor cloud-init source. It:
1. Ships a cloud-init config (YAML) baked into the image — no license attachment.
2. Invokes cloud-init as an installed package in the guest — no license attachment.
3. May need to patch or extend cloud-init datasources.

**Recommendation:** If genoa only invokes cloud-init as a runtime package (never
imports its Python modules into genoa's own code), there is no license obligation.
Document this boundary in genoa's architecture.

**Decision needed:** Confirm that genoa will never vendor or import cloud-init Python
source. If a custom datasource plugin is needed, write it as a standalone Apache-2.0
file with no cloud-init source import.

**Additional gotcha (from fleet_ledger):** The NoCloud datasource caches
per-datasource; bumping `instance-id` does NOT always invalidate the cache on
subsequent boots. genoa must set a unique `instance-id` per image build AND document
that operators must not reuse seed ISOs across instance lifecycles.
Reference: https://cloudinit.readthedocs.io/en/latest/reference/datasources/nocloud.html

**Status:** PENDING USER DECISION — likely safe as invoke-only; needs arch confirmation.

---

## LQ-2: OpenTofu — MPL-2.0

**Tool:** OpenTofu (open-source Terraform fork)
**URL:** https://github.com/opentofu/opentofu
**License found:** MPL-2.0 (Mozilla Public License 2.0) — verified against repo LICENSE.
**Verified:** Yes.

**The issue:** MPL-2.0 is OSI-approved and permissive for most uses, but it is
file-level copyleft. Any MPL-2.0 file that genoa modifies must be redistributed
under MPL-2.0. It is NOT on genoa's hard-allowed list (MIT/BSD-2/BSD-3/Apache-2.0).

**What genoa actually needs:** Optionally, genoa could generate Terraform/OpenTofu
HCL as an output artifact (a `.tf` file describing the registered image). Generating
HCL text does not require importing OpenTofu libraries; the output file is genoa's
own Apache-2.0 code.

**Recommendation A (safe):** Only generate HCL text files as output. No OpenTofu
import or vendoring. No license issue.

**Recommendation B (if CLI invocation needed):** Invoke `tofu` as an external
subprocess. No vendoring. MPL-2.0 obligation does not attach to genoa.

**Alternative:** Pulumi (Apache-2.0) can accomplish the same IaC orchestration
without the MPL question.

**Decision needed:** Does genoa need to vendor or import OpenTofu Go libraries?
If yes, user must explicitly approve MPL-2.0. If no (text generation + external
invocation only), no approval needed.

**Status:** PENDING USER DECISION — likely safe as text output / external invoke.

---

## LQ-3: Vector — MPL-2.0

**Tool:** Vector (log/metrics pipeline by Datadog)
**URL:** https://github.com/vectordotdev/vector
**License found:** MPL-2.0 — verified against repo LICENSE.
**Verified:** Yes.

**The issue:** Same as LQ-2. MPL-2.0 is file-level copyleft, not on hard-allowed list.

**What genoa actually needs:** If genoa bakes a log shipper into images, it needs a
binary — not a library import. External invocation of the `vector` binary has no
license attachment to genoa.

**Approved substitute:** Fluent Bit (Apache-2.0) is the recommended replacement.
Same functionality, smaller binary, Apache-2.0, active development. No license question.

**Recommendation:** Use Fluent Bit unless Vector has a specific capability Fluent Bit
lacks. Do not make this decision until a concrete feature gap is identified.

**Decision needed:** Is there a specific Vector feature not available in Fluent Bit
that genoa requires? If not, close this question in favor of Fluent Bit (Apache-2.0).

**Status:** PENDING USER DECISION — Fluent Bit (Apache-2.0) preferred substitute exists.

---

## LQ-4: oci-cli — UPL-1.0 OR Apache-2.0 dual-license

**Tool:** Oracle Cloud Infrastructure CLI
**URL:** https://github.com/oracle/oci-cli
**License found:** UPL-1.0 OR Apache-2.0 dual-license — verified from GitHub page.
**Verified:** Yes — repo page states: "dual licensed under the Universal Permissive
License 1.0 and the Apache License 2.0."

**UPL-1.0 assessment:** The Universal Permissive License 1.0 is OSI-approved. It is
explicitly designed to be permissive (more so than Apache-2.0 in some respects).
The OSI summary: "a very short, permissive open source license [...] similar to the
MIT License." It includes a patent grant.

**The issue:** UPL-1.0 is not explicitly on genoa's hard-allowed list (MIT/BSD-2/
BSD-3/Apache-2.0). However, it is OSI-approved permissive with a patent grant.

**Recommendation:** Since the tool is dual-licensed, genoa can elect the Apache-2.0
path and document that choice. This requires no additional approval. When referencing
oci-cli in genoa's dependency manifest, note: "oci-cli used under Apache-2.0 (UPL-1.0
OR Apache-2.0 dual-license; Apache-2.0 elected)."

**Decision needed:** Confirm that electing the Apache-2.0 path from a dual-license
satisfies genoa's policy without needing UPL-1.0 explicitly approved.

**Status:** PENDING USER DECISION — likely auto-resolved by electing Apache-2.0 path;
needs confirmation.

---

## LQ-5: SLSA — Community Specification License 1.0 (specification portions)

**Tool:** SLSA framework (specification, not a library)
**URL:** https://github.com/slsa-framework/slsa
**License found:** Dual — Apache-2.0 (older portions) and Community Specification
License 1.0 (newer specification text).
**Verified:** Yes — repo README describes the dual-license model.

**The issue:** Community Specification License 1.0 applies to the specification
*text*, not to implementations. Implementing SLSA (writing code that achieves SLSA
levels) does not require licensing that code under CSL-1.0.

**Assessment:** Not a license risk for genoa. SLSA is a normative target
specification. genoa complies with SLSA by implementing the required provenance
and build isolation properties — no code or text from the SLSA repo is vendored.

**Status:** NO ACTION NEEDED — implementing a spec is not a license obligation.

---

## Decision log (fill in as decisions are made)

| ID | Tool | Decision | Date | Decided by |
|----|------|----------|------|-----------|
| LQ-1 | cloud-init | PENDING | — | — |
| LQ-2 | OpenTofu | PENDING | — | — |
| LQ-3 | Vector | PENDING | — | — |
| LQ-4 | oci-cli | PENDING | — | — |
| LQ-5 | SLSA | NO ACTION NEEDED | 2026-04-30 | R4 agent |
