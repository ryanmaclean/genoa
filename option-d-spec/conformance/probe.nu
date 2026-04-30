#!/usr/bin/env nu
# probe.nu — genoa L1 Conformance Probe
# SPDX-License-Identifier: BSD-2-Clause
# Copyright 2026 genoa contributors
#
# Usage:
#   probe.nu run <hostname>            # L1 conformance check against a live host
#   probe.nu run <hostname> --level L2 # Check specific conformance level
#   probe.nu help                      # Show usage
#
# Output: structured JSON on stdout. Always exits 0; conformance verdict in JSON.
#
# L1 checks:
#   1. GET /.well-known/genoa.json — must respond 200
#   2. Response parses as valid JSON
#   3. Required fields present: genoa_version, image.id, image.name, image.version,
#      agent_runtime.type, agent_runtime.endpoint, catalog_url, conformance.level
#   4. catalog_url is a valid URI
#   5. Signature: stub (real key infra required for production)
#
# L2 adds:
#   6. attestation_url present
#   7. GET attestation_url — must respond 200
#   8. Attestation has correct _type and predicateType

def main [] {
  print "genoa conformance probe v1.0.0"
  print "Usage: probe.nu run <hostname> [--level L1|L2|L3] [--port 80] [--scheme http]"
  print "       probe.nu help"
}

# Run conformance probe against a host
def "main run" [
  hostname: string,         # Hostname or IP to probe (e.g. 192.168.1.10 or myhost.local)
  --level: string = "L1",   # Conformance level to check: L1, L2, L3
  --port: int = 80,         # HTTP port (default 80; use 443 for HTTPS)
  --scheme: string = "http" # URI scheme: http or https
] {
  let start_time = (date now)
  let base_url = $"($scheme)://($hostname):($port)"
  let discovery_url = $"($base_url)/.well-known/genoa.json"

  mut result = {
    probe_version: "1.0.0",
    genoa_spec: "1.0.0",
    target: $hostname,
    level_requested: $level,
    timestamp: ($start_time | format date "%Y-%m-%dT%H:%M:%SZ"),
    overall: "fail",
    checks: [],
    errors: [],
    signature_verified: "stub",
    signature_stub_reason: "Real signature verification requires Sigstore/TUF key infrastructure. See schemas/attestation.v1.json for the signature field specification."
  }

  # --- CHECK 1: HTTP reachability ---
  let check1 = (run_check "L1.1" "discovery_endpoint_reachable" $"GET ($discovery_url)" {
    let response = (try {
      http get $discovery_url --full
    } catch { |e|
      {status: 0, body: "", error: ($e | to text)}
    })

    if ($response | get -o status | default 0) == 200 {
      {pass: true, detail: $"HTTP 200 from ($discovery_url)"}
    } else if ($response | get -o error | default "") != "" {
      {pass: false, detail: $"Connection failed: ($response | get -o error | default 'unknown error')"}
    } else {
      {pass: false, detail: $"HTTP ($response | get -o status | default 'N/A') from ($discovery_url)"}
    }
  })
  $result.checks = ($result.checks | append $check1)

  # If not reachable, skip remaining checks and return structured failure
  if not $check1.pass {
    $result.errors = ($result.errors | append "Host unreachable — remaining checks skipped. This is expected for offline probes.")
    $result.overall = "fail"
    print ($result | to json --indent 2)
    return
  }

  # Fetch the discovery document once for remaining checks
  let discovery_doc = (try {
    http get $discovery_url
  } catch { |e|
    null
  })

  # --- CHECK 2: Valid JSON ---
  let check2 = (run_check "L1.2" "discovery_valid_json" "Parse response as JSON" {
    if $discovery_doc == null {
      {pass: false, detail: "Response could not be parsed as JSON"}
    } else {
      {pass: true, detail: "Response is valid JSON"}
    }
  })
  $result.checks = ($result.checks | append $check2)

  if not $check2.pass {
    $result.overall = "fail"
    print ($result | to json --indent 2)
    return
  }

  # --- CHECK 3: Required fields ---
  let required_fields = ["genoa_version", "catalog_url"]
  let check3 = (run_check "L1.3" "required_fields_present" $"Fields: ($required_fields | str join ', ')" {
    let missing = ($required_fields | where { |f|
      ($discovery_doc | get -o $f | default null) == null
    })

    # Also check nested required fields
    let image_id = ($discovery_doc | get -o image.id | default null)
    let image_name = ($discovery_doc | get -o image.name | default null)
    let image_version = ($discovery_doc | get -o image.version | default null)
    let runtime_type = ($discovery_doc | get -o agent_runtime.type | default null)
    let runtime_endpoint = ($discovery_doc | get -o agent_runtime.endpoint | default null)
    let conformance_level = ($discovery_doc | get -o conformance.level | default null)

    let nested_missing = (
      []
      | append (if $image_id == null { ["image.id"] } else { [] })
      | append (if $image_name == null { ["image.name"] } else { [] })
      | append (if $image_version == null { ["image.version"] } else { [] })
      | append (if $runtime_type == null { ["agent_runtime.type"] } else { [] })
      | append (if $runtime_endpoint == null { ["agent_runtime.endpoint"] } else { [] })
      | append (if $conformance_level == null { ["conformance.level"] } else { [] })
    )

    let all_missing = ($missing | append $nested_missing)
    if ($all_missing | length) == 0 {
      {pass: true, detail: "All required fields present"}
    } else {
      {pass: false, detail: $"Missing fields: ($all_missing | str join ', ')"}
    }
  })
  $result.checks = ($result.checks | append $check3)

  # --- CHECK 4: genoa_version format ---
  let check4 = (run_check "L1.4" "genoa_version_semver" "genoa_version matches SemVer pattern" {
    let gv = ($discovery_doc | get -o genoa_version | default "")
    let semver_pattern = '^[0-9]+\.[0-9]+\.[0-9]+$'
    if ($gv | str length) == 0 {
      {pass: false, detail: "genoa_version is empty"}
    } else if ($gv =~ $semver_pattern) {
      {pass: true, detail: $"genoa_version = ($gv)"}
    } else {
      {pass: false, detail: $"genoa_version '($gv)' does not match SemVer pattern"}
    }
  })
  $result.checks = ($result.checks | append $check4)

  # --- CHECK 5: catalog_url is a URI ---
  let check5 = (run_check "L1.5" "catalog_url_valid_uri" "catalog_url starts with http(s)://" {
    let cu = ($discovery_doc | get -o catalog_url | default "")
    if ($cu | str starts-with "http://") or ($cu | str starts-with "https://") {
      {pass: true, detail: $"catalog_url = ($cu)"}
    } else {
      {pass: false, detail: $"catalog_url '($cu)' is not a valid URI"}
    }
  })
  $result.checks = ($result.checks | append $check5)

  # --- CHECK 6: conformance level is valid enum ---
  let check6 = (run_check "L1.6" "conformance_level_valid" "conformance.level in [L0,L1,L2,L3]" {
    let cl = ($discovery_doc | get -o conformance.level | default "")
    let valid_levels = ["L0", "L1", "L2", "L3"]
    if $cl in $valid_levels {
      {pass: true, detail: $"conformance.level = ($cl)"}
    } else {
      {pass: false, detail: $"conformance.level '($cl)' not in valid set ($valid_levels | str join ', ')"}
    }
  })
  $result.checks = ($result.checks | append $check6)

  # --- L2 checks ---
  if $level in ["L2", "L3"] {
    let check_l2_1 = (run_check "L2.1" "attestation_url_present" "attestation_url field exists" {
      let au = ($discovery_doc | get -o attestation_url | default null)
      if $au != null {
        {pass: true, detail: $"attestation_url = ($au)"}
      } else {
        {pass: false, detail: "attestation_url field missing from discovery document"}
      }
    })
    $result.checks = ($result.checks | append $check_l2_1)

    let attestation_url = ($discovery_doc | get -o attestation_url | default null)
    if $attestation_url != null {
      let check_l2_2 = (run_check "L2.2" "attestation_reachable" $"GET ($attestation_url)" {
        let att_response = (try {
          http get $attestation_url --full
        } catch { |e|
          {status: 0, error: ($e | to text)}
        })

        if ($att_response | get -o status | default 0) == 200 {
          {pass: true, detail: $"HTTP 200 from ($attestation_url)"}
        } else {
          {pass: false, detail: $"Attestation fetch failed: status ($att_response | get -o status | default 'N/A')"}
        }
      })
      $result.checks = ($result.checks | append $check_l2_2)

      let check_l2_3 = (run_check "L2.3" "attestation_predicate_type" "predicateType = https://genoa.dev/AgentHost/v1" {
        let att_doc = (try { http get $attestation_url } catch { null })
        if $att_doc == null {
          {pass: false, detail: "Could not fetch attestation document"}
        } else {
          let pt = ($att_doc | get -o predicateType | default "")
          let et = ($att_doc | get -o _type | default "")
          if $pt == "https://genoa.dev/AgentHost/v1" and $et == "https://in-toto.io/Statement/v1" {
            {pass: true, detail: "predicateType and _type are correct"}
          } else {
            {pass: false, detail: $"predicateType='($pt)' _type='($et)' — expected genoa AgentHost/v1 and in-toto Statement/v1"}
          }
        }
      })
      $result.checks = ($result.checks | append $check_l2_3)
    }
  }

  # --- L3 checks ---
  if $level == "L3" {
    let check_l3_1 = (run_check "L3.1" "slsa_level_2_or_higher" "predicate.slsa_level >= 2" {
      let att_url = ($discovery_doc | get -o attestation_url | default null)
      if $att_url == null {
        {pass: false, detail: "No attestation_url — cannot check SLSA level"}
      } else {
        let att_doc = (try { http get $att_url } catch { null })
        if $att_doc == null {
          {pass: false, detail: "Could not fetch attestation document"}
        } else {
          let slsa = ($att_doc | get -o predicate.slsa_level | default 0)
          if $slsa >= 2 {
            {pass: true, detail: $"slsa_level = ($slsa)"}
          } else {
            {pass: false, detail: $"slsa_level = ($slsa) — L3 requires >= 2"}
          }
        }
      }
    })
    $result.checks = ($result.checks | append $check_l3_1)

    let check_l3_2 = (run_check "L3.2" "sbom_digest_present" "predicate.sbom_digest is present" {
      let att_url = ($discovery_doc | get -o attestation_url | default null)
      if $att_url == null {
        {pass: false, detail: "No attestation_url — cannot check SBOM digest"}
      } else {
        let att_doc = (try { http get $att_url } catch { null })
        if $att_doc == null {
          {pass: false, detail: "Could not fetch attestation document"}
        } else {
          let sbom = ($att_doc | get -o predicate.sbom_digest | default null)
          if $sbom != null and ($sbom | str starts-with "sha256:") {
            {pass: true, detail: $"sbom_digest = ($sbom)"}
          } else {
            {pass: false, detail: "sbom_digest missing or invalid format"}
          }
        }
      }
    })
    $result.checks = ($result.checks | append $check_l3_2)
  }

  # --- Compute overall verdict ---
  let passed = ($result.checks | where pass == true | length)
  let total = ($result.checks | length)
  let failed = ($result.checks | where pass == false | length)

  $result.summary = {
    total_checks: $total,
    passed: $passed,
    failed: $failed
  }

  $result.overall = (if $failed == 0 { "pass" } else { "fail" })
  $result.level_achieved = (if $failed == 0 {
    $level
  } else {
    # Find highest passing level
    let l1_fails = ($result.checks | where {|c| ($c.id | str starts-with "L1") and not $c.pass} | length)
    if $l1_fails > 0 { "L0" } else { "L1" }
  })

  print ($result | to json --indent 2)
}

# Show help
def "main help" [] {
  print "genoa conformance probe v1.0.0"
  print ""
  print "USAGE:"
  print "  probe.nu run <hostname>                    # L1 check"
  print "  probe.nu run <hostname> --level L2         # L1+L2 check"
  print "  probe.nu run <hostname> --level L3         # Full check"
  print "  probe.nu run <hostname> --port 8080        # Custom port"
  print "  probe.nu run <hostname> --scheme https     # HTTPS"
  print ""
  print "OUTPUT:"
  print "  Structured JSON. overall='pass'|'fail'. Always exits 0."
  print ""
  print "CONFORMANCE LEVELS:"
  print "  L1: Discovery endpoint responds, valid JSON, required fields, valid schema"
  print "  L2: L1 + attestation endpoint reachable + correct predicateType"
  print "  L3: L2 + SLSA level >= 2 + SBOM digest present"
  print ""
  print "STUBS:"
  print "  signature_verified is always 'stub' — real verification requires Sigstore/TUF."
}

# Helper: run a check closure, capture pass/fail with metadata
def run_check [id: string, name: string, description: string, check_fn: closure] {
  let result = (do $check_fn)
  {
    id: $id,
    name: $name,
    description: $description,
    pass: $result.pass,
    detail: $result.detail
  }
}
