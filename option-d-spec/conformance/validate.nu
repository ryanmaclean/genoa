#!/usr/bin/env nu
# validate.nu — genoa Schema Validator
# SPDX-License-Identifier: BSD-2-Clause
# Copyright 2026 genoa contributors
#
# Usage:
#   validate.nu manifest <file>     # Validate a genoa.toml or genoa-manifest.json
#   validate.nu attestation <file>  # Validate an in-toto attestation JSON
#   validate.nu discovery <file>    # Validate a /.well-known/genoa.json response
#   validate.nu capability <file>   # Validate a capability declaration JSON
#
# Output: structured JSON {"valid": bool, "errors": [...], "warnings": [...]}
# Exit code: always 0. Validity is in the JSON output.
#
# Validation approach: structural checks implemented in Nushell against the
# schema rules defined in schemas/*.v1.json. This is a faithful implementation
# of the schemas without requiring an external JSON Schema validator binary.
# For production use with a full JSON Schema 2020-12 validator, pipe through:
#   jsonschema --instance <file> --schema schemas/manifest.v1.json
# (jsonschema-rs CLI, MIT license: https://github.com/Stranger6667/jsonschema-rs)

def main [] {
  print "genoa schema validator v1.0.0"
  print "Usage:"
  print "  validate.nu manifest <file>     # Validate genoa.toml or manifest JSON"
  print "  validate.nu attestation <file>  # Validate attestation JSON"
  print "  validate.nu discovery <file>    # Validate discovery response JSON"
  print "  validate.nu capability <file>   # Validate capability declaration JSON"
}

# Validate a genoa manifest file (TOML or JSON)
def "main manifest" [
  file: string   # Path to genoa.toml or genoa-manifest.json
] {
  let result = (validate_file $file "manifest")
  print ($result | to json --indent 2)
  if not $result.valid { exit 1 }
}

# Validate a genoa attestation JSON file
def "main attestation" [
  file: string   # Path to attestation JSON
] {
  let result = (validate_file $file "attestation")
  print ($result | to json --indent 2)
  if not $result.valid { exit 1 }
}

# Validate a genoa discovery response JSON file
def "main discovery" [
  file: string   # Path to discovery JSON
] {
  let result = (validate_file $file "discovery")
  print ($result | to json --indent 2)
  if not $result.valid { exit 1 }
}

# Validate a capability declaration JSON file
def "main capability" [
  file: string   # Path to capability JSON
] {
  let result = (validate_file $file "capability")
  print ($result | to json --indent 2)
  if not $result.valid { exit 1 }
}

# Core dispatcher: load file and route to correct validator
def validate_file [file: string, doc_type: string] {
  # Check file exists
  if not ($file | path exists) {
    return {
      valid: false,
      file: $file,
      doc_type: $doc_type,
      schema: (schema_url $doc_type),
      errors: [$"File not found: ($file)"],
      warnings: []
    }
  }

  # Load document (TOML or JSON based on extension)
  let ext = ($file | path parse | get extension | str downcase)
  let doc = (if $ext == "toml" {
    try {
      open $file
    } catch { |e|
      return {
        valid: false,
        file: $file,
        doc_type: $doc_type,
        schema: (schema_url $doc_type),
        errors: [$"Failed to parse TOML: ($e | to text)"],
        warnings: []
      }
    }
  } else {
    try {
      open --raw $file | from json
    } catch { |e|
      return {
        valid: false,
        file: $file,
        doc_type: $doc_type,
        schema: (schema_url $doc_type),
        errors: [$"Failed to parse JSON: ($e | to text)"],
        warnings: []
      }
    }
  })

  # Route to specific validator
  let validation = (match $doc_type {
    "manifest"    => (validate_manifest $doc),
    "attestation" => (validate_attestation $doc),
    "discovery"   => (validate_discovery $doc),
    "capability"  => (validate_capability $doc),
    _             => {errors: [$"Unknown doc_type: ($doc_type)"], warnings: []}
  })

  {
    valid: (($validation.errors | length) == 0),
    file: $file,
    doc_type: $doc_type,
    schema: (schema_url $doc_type),
    errors: $validation.errors,
    warnings: $validation.warnings
  }
}

# Return schema URL for a doc type
def schema_url [doc_type: string] {
  match $doc_type {
    "manifest"    => "https://genoa.dev/v1/schemas/manifest.v1.json",
    "attestation" => "https://genoa.dev/v1/schemas/attestation.v1.json",
    "discovery"   => "https://genoa.dev/v1/schemas/discovery.v1.json",
    "capability"  => "https://genoa.dev/v1/schemas/capability.v1.json",
    _             => "https://genoa.dev/v1/schemas/unknown"
  }
}

# ─── MANIFEST VALIDATOR ────────────────────────────────────────────────────────
def validate_manifest [doc: record] {
  mut errors = []
  mut warnings = []

  # Required top-level keys
  for key in ["genoa", "image", "agent_runtime"] {
    if ($doc | get -o $key | default null) == null {
      $errors = ($errors | append $"Required field missing: ($key)")
    }
  }

  # genoa section
  let genoa = ($doc | get -o genoa | default {})
  let spec_version = ($genoa | get -o spec_version | default null)
  if $spec_version == null {
    $errors = ($errors | append "Required field missing: genoa.spec_version")
  } else if not ($spec_version =~ '^[0-9]+\.[0-9]+\.[0-9]+$') {
    $errors = ($errors | append $"genoa.spec_version '($spec_version)' does not match SemVer pattern [0-9]+.[0-9]+.[0-9]+")
  }

  # image section
  let image = ($doc | get -o image | default {})
  for key in ["id", "name", "version", "architecture", "os"] {
    if ($image | get -o $key | default null) == null {
      $errors = ($errors | append $"Required field missing: image.($key)")
    }
  }

  let arch = ($image | get -o architecture | default null)
  if $arch != null and $arch not-in ["amd64", "arm64", "riscv64", "armv7", "s390x", "ppc64le"] {
    $errors = ($errors | append $"image.architecture '($arch)' not in allowed values: amd64, arm64, riscv64, armv7, s390x, ppc64le")
  }

  let os = ($image | get -o os | default null)
  if $os != null and $os not-in ["freebsd", "netbsd", "openbsd", "linux", "windows"] {
    $errors = ($errors | append $"image.os '($os)' not in allowed values: freebsd, netbsd, openbsd, linux, windows")
  }

  let version = ($image | get -o version | default null)
  if $version != null and not ($version =~ '^[0-9]+\.[0-9]+\.[0-9]+') {
    $errors = ($errors | append $"image.version '($version)' does not match SemVer pattern")
  }

  # agent_runtime section
  let runtime = ($doc | get -o agent_runtime | default {})
  let rt_type = ($runtime | get -o type | default null)
  if $rt_type == null {
    $errors = ($errors | append "Required field missing: agent_runtime.type")
  } else if $rt_type not-in ["mcp-server", "openai-compatible", "anthropic-compatible", "custom"] {
    $errors = ($errors | append $"agent_runtime.type '($rt_type)' not in allowed values")
  }

  # capabilities (optional but must conform if present)
  let caps = ($doc | get -o capabilities | default [])
  for i in (0..($caps | length | $in - 1)) {
    if $i < ($caps | length) {
      let cap = ($caps | get $i)
      let cap_result = (validate_capability $cap)
      for err in $cap_result.errors {
        $errors = ($errors | append $"capabilities[$i]: ($err)")
      }
    }
  }

  # attestation_policy (optional)
  let attest = ($doc | get -o attestation_policy | default {})
  let slsa = ($attest | get -o slsa_level | default null)
  if $slsa != null {
    if not (($slsa | describe) in ["int", "float"]) {
      $errors = ($errors | append "attestation_policy.slsa_level must be an integer")
    } else if ($slsa < 0 or $slsa > 4) {
      $errors = ($errors | append $"attestation_policy.slsa_level ($slsa) must be 0-4")
    }
  }

  # sbom (optional)
  let sbom = ($doc | get -o sbom | default {})
  if ($sbom | columns | length) > 0 {
    let sbom_format = ($sbom | get -o format | default null)
    if $sbom_format == null {
      $errors = ($errors | append "sbom.format is required when sbom is present")
    } else if $sbom_format not-in ["spdx-2.3", "cyclonedx-1.5", "cyclonedx-1.6"] {
      $errors = ($errors | append $"sbom.format '($sbom_format)' not in allowed values")
    }

    let sbom_digest = ($sbom | get -o digest | default null)
    if $sbom_digest == null {
      $errors = ($errors | append "sbom.digest is required when sbom is present")
    } else if not ($sbom_digest =~ '^sha256:[a-f0-9]{64}$') {
      $errors = ($errors | append $"sbom.digest '($sbom_digest)' must match pattern sha256:[64 hex chars]")
    }
  }

  {errors: $errors, warnings: $warnings}
}

# ─── ATTESTATION VALIDATOR ─────────────────────────────────────────────────────
def validate_attestation [doc: record] {
  mut errors = []
  mut warnings = []

  # Required top-level fields
  for key in ["_type", "subject", "predicateType", "predicate"] {
    if ($doc | get -o $key | default null) == null {
      $errors = ($errors | append $"Required field missing: ($key)")
    }
  }

  # _type must be in-toto v1
  let dtype = ($doc | get -o _type | default "")
  if $dtype != "https://in-toto.io/Statement/v1" {
    $errors = ($errors | append $"_type must be 'https://in-toto.io/Statement/v1', got '($dtype)'")
  }

  # predicateType must be genoa AgentHost/v1
  let pt = ($doc | get -o predicateType | default "")
  if $pt != "https://genoa.dev/AgentHost/v1" {
    $errors = ($errors | append $"predicateType must be 'https://genoa.dev/AgentHost/v1', got '($pt)'")
  }

  # subject must be array with at least 1 item
  let subject = ($doc | get -o subject | default [])
  if ($subject | length) == 0 {
    $errors = ($errors | append "subject must be a non-empty array")
  } else {
    for i in (0..($subject | length | $in - 1)) {
      if $i < ($subject | length) {
        let s = ($subject | get $i)
        if ($s | get -o name | default null) == null {
          $errors = ($errors | append $"subject[($i)].name is required")
        }
        let digest = ($s | get -o digest | default {})
        if ($digest | get -o sha256 | default null) == null {
          $errors = ($errors | append $"subject[($i)].digest.sha256 is required")
        } else {
          let sha = ($digest | get sha256)
          if not ($sha =~ '^[a-f0-9]{64}$') {
            $errors = ($errors | append $"subject[($i)].digest.sha256 must be 64 hex chars, got '($sha)'")
          }
        }
      }
    }
  }

  # predicate required fields
  let predicate = ($doc | get -o predicate | default {})
  for key in ["image_identity", "capability_claims", "slsa_level", "sbom_digest"] {
    if ($predicate | get -o $key | default null) == null {
      $errors = ($errors | append $"Required field missing: predicate.($key)")
    }
  }

  # predicate.image_identity required fields
  let img = ($predicate | get -o image_identity | default {})
  for key in ["id", "name", "version", "architecture", "os"] {
    if ($img | get -o $key | default null) == null {
      $errors = ($errors | append $"Required field missing: predicate.image_identity.($key)")
    }
  }

  # predicate.slsa_level
  let slsa = ($predicate | get -o slsa_level | default null)
  if $slsa != null and (($slsa | describe) not-in ["int", "float"] or $slsa < 0 or $slsa > 4) {
    $errors = ($errors | append "predicate.slsa_level must be integer 0-4")
  }

  # predicate.sbom_digest
  let sbom_d = ($predicate | get -o sbom_digest | default null)
  if $sbom_d != null and not ($sbom_d =~ '^sha256:[a-f0-9]{64}$') {
    $errors = ($errors | append $"predicate.sbom_digest '($sbom_d)' must match sha256:[64 hex chars]")
  }

  # predicate.capability_claims (optional validate each)
  let caps = ($predicate | get -o capability_claims | default [])
  for i in (0..($caps | length | $in - 1)) {
    if $i < ($caps | length) {
      let cap = ($caps | get $i)
      let cap_result = (validate_capability $cap)
      for err in $cap_result.errors {
        $errors = ($errors | append $"predicate.capability_claims[($i)]: ($err)")
      }
    }
  }

  {errors: $errors, warnings: $warnings}
}

# ─── DISCOVERY VALIDATOR ───────────────────────────────────────────────────────
def validate_discovery [doc: record] {
  mut errors = []
  mut warnings = []

  for key in ["genoa_version", "image", "agent_runtime", "catalog_url", "conformance"] {
    if ($doc | get -o $key | default null) == null {
      $errors = ($errors | append $"Required field missing: ($key)")
    }
  }

  let gv = ($doc | get -o genoa_version | default "")
  if not ($gv =~ '^[0-9]+\.[0-9]+\.[0-9]+$') {
    $errors = ($errors | append $"genoa_version '($gv)' does not match SemVer")
  }

  let image = ($doc | get -o image | default {})
  for key in ["id", "name", "version"] {
    if ($image | get -o $key | default null) == null {
      $errors = ($errors | append $"Required field missing: image.($key)")
    }
  }

  let runtime = ($doc | get -o agent_runtime | default {})
  if ($runtime | get -o type | default null) == null {
    $errors = ($errors | append "Required field missing: agent_runtime.type")
  }
  if ($runtime | get -o endpoint | default null) == null {
    $errors = ($errors | append "Required field missing: agent_runtime.endpoint")
  }

  let cu = ($doc | get -o catalog_url | default "")
  if not (($cu | str starts-with "http://") or ($cu | str starts-with "https://")) {
    $errors = ($errors | append $"catalog_url '($cu)' must be a valid URI")
  }

  let cl = ($doc | get -o conformance.level | default "")
  if $cl not-in ["L0", "L1", "L2", "L3"] {
    $errors = ($errors | append $"conformance.level '($cl)' not in [L0, L1, L2, L3]")
  }

  {errors: $errors, warnings: $warnings}
}

# ─── CAPABILITY VALIDATOR ──────────────────────────────────────────────────────
def validate_capability [doc: record] {
  mut errors = []
  mut warnings = []

  for key in ["name", "description", "inputSchema", "provenance"] {
    if ($doc | get -o $key | default null) == null {
      $errors = ($errors | append $"Required field missing: ($key)")
    }
  }

  let name = ($doc | get -o name | default "")
  if not ($name =~ '^[a-zA-Z0-9_-]+$') {
    $errors = ($errors | append $"name '($name)' must match pattern [a-zA-Z0-9_-]+")
  }
  if ($name | str length) > 64 {
    $errors = ($errors | append "name exceeds 64 character maximum")
  }

  let desc = ($doc | get -o description | default "")
  if ($desc | str length) > 1024 {
    $errors = ($errors | append "description exceeds 1024 character maximum")
  }

  let schema = ($doc | get -o inputSchema | default {})
  if ($schema | get -o type | default null) == null {
    $errors = ($errors | append "inputSchema.type is required")
  } else if ($schema | get -o type) != "object" {
    $errors = ($errors | append "inputSchema.type must be 'object'")
  }

  let prov = ($doc | get -o provenance | default {})
  for key in ["source", "trust"] {
    if ($prov | get -o $key | default null) == null {
      $errors = ($errors | append $"Required field missing: provenance.($key)")
    }
  }

  let source = ($prov | get -o source | default "")
  if $source not-in ["built-in", "installed", "plugin"] {
    $errors = ($errors | append $"provenance.source '($source)' not in [built-in, installed, plugin]")
  }

  let trust = ($prov | get -o trust | default "")
  if $trust not-in ["attested", "signed", "unverified"] {
    $errors = ($errors | append $"provenance.trust '($trust)' not in [attested, signed, unverified]")
  }

  if $trust == "unverified" {
    $warnings = ($warnings | append "provenance.trust is 'unverified' — agents MUST surface this to users before invocation")
  }

  {errors: $errors, warnings: $warnings}
}
