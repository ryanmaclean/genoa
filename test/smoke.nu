#!/usr/bin/env nu
# test/smoke.nu — genoa smoke test suite
# Run from repo root: nu test/smoke.nu
# Exit 0 = all pass. Exit 1 = any failures.
#
# Each test sources genoa.nu and calls `main <subcommand>` directly via
# `nu -c "source genoa.nu; main ..."`, so output is structured Nushell
# data piped through `| to json` and then parsed back with `from json`.
# This avoids any dependency on the shell's PATH or on JSON being the
# default display format.

const GENOA = "genoa.nu"  # relative to repo root; run from repo root

# ---------------------------------------------------------------------------
# run_test — wraps a closure; returns a {test, pass, detail} record
# ---------------------------------------------------------------------------
def run_test [name: string, body: closure] {
  let result = try {
    let val = do $body
    {test: $name, pass: true, detail: ($val | into string)}
  } catch { |e|
    {test: $name, pass: false, detail: $e.msg}
  }
  $result
}

# ---------------------------------------------------------------------------
# genoa — helper: run a genoa subcommand and return parsed JSON output
# Usage: genoa "describe 'examples/foo.toml'"
# ---------------------------------------------------------------------------
def genoa [cmd: string] {
  let script = $"source ($GENOA); ($cmd) | to json"
  ^nu -c $script | from json
}

# ---------------------------------------------------------------------------
# Test cases
# ---------------------------------------------------------------------------

let tests = [

  # catalog — schema_version field equals "1.0.0"
  (run_test "catalog" {
    let val = (genoa "main catalog" | get schema_version)
    if $val != "1.0.0" {
      error make {msg: $"expected 1.0.0 got ($val)"}
    }
    $val
  })

  # schema — title field is non-empty
  (run_test "schema" {
    let val = (genoa "main schema" | get title)
    if ($val | is-empty) {
      error make {msg: "expected non-empty title, got empty string"}
    }
    $val
  })

  # describe_vultr — provider field equals "vultr"
  (run_test "describe_vultr" {
    let val = (genoa "main describe 'examples/freebsd-vultr-aarch64.toml'" | get provider)
    if $val != "vultr" {
      error make {msg: $"expected vultr got ($val)"}
    }
    $val
  })

  # describe_linode — provider field equals "linode_akamai"
  (run_test "describe_linode" {
    let val = (genoa "main describe 'examples/freebsd-linode-amd64.toml'" | get provider)
    if $val != "linode_akamai" {
      error make {msg: $"expected linode_akamai got ($val)"}
    }
    $val
  })

  # validate_vultr — valid == true
  (run_test "validate_vultr" {
    let rec = (genoa "main validate 'examples/freebsd-vultr-aarch64.toml'")
    let val = ($rec | get valid)
    if $val != true {
      error make {msg: $"expected valid=true got ($val); errors: ($rec | get errors | to json)"}
    }
    $val
  })

  # validate_template — valid == true
  (run_test "validate_template" {
    let rec = (genoa "main validate 'examples/agent-port-template.toml'")
    let val = ($rec | get valid)
    if $val != true {
      error make {msg: $"expected valid=true got ($val); errors: ($rec | get errors | to json)"}
    }
    $val
  })

  # validate_errors — 0 errors on all valid manifests
  (run_test "validate_errors" {
    let errs_vultr  = (genoa "main validate 'examples/freebsd-vultr-aarch64.toml'" | get errors | length)
    let errs_linode = (genoa "main validate 'examples/freebsd-linode-amd64.toml'"  | get errors | length)
    let errs_tmpl   = (genoa "main validate 'examples/agent-port-template.toml'"   | get errors | length)
    let total = ($errs_vultr + $errs_linode + $errs_tmpl)
    if $total != 0 {
      error make {msg: $"expected 0 total errors across valid manifests, got ($total)"}
    }
    $"vultr=($errs_vultr) linode=($errs_linode) template=($errs_tmpl)"
  })

  # validate_warnings — sha256 all-zeros placeholder produces a warning (not an error)
  (run_test "validate_warnings" {
    let rec = (genoa "main validate 'examples/freebsd-vultr-aarch64.toml'")
    let warn_count = ($rec | get warnings | length)
    let err_count  = ($rec | get errors   | length)
    if $warn_count == 0 {
      error make {msg: "expected at least 1 warning for all-zeros sha256 placeholder, got 0"}
    }
    if $err_count != 0 {
      error make {msg: $"sha256 placeholder should produce a warning not an error, but errors=($err_count)"}
    }
    $"warnings=($warn_count) errors=($err_count)"
  })

  # build_dry_uefi — profile field equals "uefi"
  (run_test "build_dry_uefi" {
    let rec = (genoa "main build 'examples/freebsd-vultr-aarch64.toml' --dry-run")
    let val = ($rec | get profile)
    if $val != "uefi" {
      error make {msg: $"expected profile=uefi got ($val)"}
    }
    $val
  })

  # build_dry_kboot — profile field equals "kboot" when --profile kboot passed
  (run_test "build_dry_kboot" {
    let rec = (genoa "main build 'examples/freebsd-linode-amd64.toml' --profile kboot --dry-run")
    let val = ($rec | get profile)
    if $val != "kboot" {
      error make {msg: $"expected profile=kboot got ($val)"}
    }
    $val
  })

  # build_steps_uefi — uefi dry-run has exactly 16 steps
  (run_test "build_steps_uefi" {
    let rec = (genoa "main build 'examples/freebsd-vultr-aarch64.toml' --dry-run")
    let count = ($rec | get steps | length)
    if $count != 16 {
      error make {msg: $"expected 16 uefi steps got ($count)"}
    }
    $count
  })

  # build_steps_kboot — kboot dry-run has exactly 20 steps
  (run_test "build_steps_kboot" {
    let rec = (genoa "main build 'examples/freebsd-linode-amd64.toml' --profile kboot --dry-run")
    let count = ($rec | get steps | length)
    if $count != 20 {
      error make {msg: $"expected 20 kboot steps got ($count)"}
    }
    $count
  })

  # receipt_written — after build --dry-run, receipt file exists on disk
  (run_test "receipt_written" {
    let rec = (genoa "main build 'examples/freebsd-vultr-aarch64.toml' --dry-run")
    let receipt_path = ($rec | get receipt_path)
    if not ($receipt_path | path exists) {
      error make {msg: $"expected receipt file at ($receipt_path) but it does not exist"}
    }
    $receipt_path
  })

  # receipt_schema — receipt has required keys: receipt_id, image_path, manifest_sha256, built_at
  (run_test "receipt_schema" {
    let rec = (genoa "main build 'examples/freebsd-vultr-aarch64.toml' --dry-run")
    let receipt_path = ($rec | get receipt_path)
    let receipt = (open $receipt_path)
    let required = ["receipt_id" "image_path" "manifest_sha256" "built_at"]
    let missing = ($required | where { |k| $k not-in $receipt })
    if ($missing | length) > 0 {
      error make {msg: $"receipt missing fields: ($missing | str join ', ')"}
    }
    $"all required fields present in ($receipt_path)"
  })

  # deploy_dry_run — returns a record (not an exception)
  (run_test "deploy_dry_run" {
    let rec = (genoa "main deploy 'examples/freebsd-vultr-aarch64.toml' --provider vultr --dry-run")
    let keys = ($rec | columns)
    if ($keys | length) == 0 {
      error make {msg: "expected non-empty record from deploy --dry-run, got empty"}
    }
    $"keys: ($keys | str join ', ')"
  })

  # run_dry_pipeline — output has a "pipeline" key
  (run_test "run_dry_pipeline" {
    let rec = (genoa "main run 'examples/freebsd-vultr-aarch64.toml' --dry-run")
    if "pipeline" not-in $rec {
      error make {msg: $"expected 'pipeline' key in result, got keys: ($rec | columns | str join ', ')"}
    }
    ($rec | get pipeline)
  })

  # status_no_receipts_in_clean_dir — receipts_found == 0 in an empty temp dir
  (run_test "status_no_receipts_in_clean_dir" {
    let tmp = (^mktemp -d | str trim)
    # Copy genoa.nu into temp dir so source works without relative-path issues
    ^cp genoa.nu $tmp
    let script = $"cd ($tmp); source genoa.nu; main status | to json"
    let rec = (^nu -c $script | from json)
    ^rm -rf $tmp
    let found = ($rec | get receipts_found)
    if $found != 0 {
      error make {msg: $"expected receipts_found=0 in clean dir, got ($found)"}
    }
    $"receipts_found=($found)"
  })

]

# ---------------------------------------------------------------------------
# Summary output
# ---------------------------------------------------------------------------

print ""
print "=== genoa smoke tests ==="
print ""

$tests | table | print

print ""

let passed = ($tests | where pass == true  | length)
let failed = ($tests | where pass == false | length)
let total  = ($tests | length)

print $"Results: ($passed)/($total) passed, ($failed) failed"
print ""

if $failed > 0 {
  print "FAILED tests:"
  $tests | where pass == false | each { |t|
    print $"  - ($t.test): ($t.detail)"
  }
  print ""
  exit 1
}

print "All tests passed."
