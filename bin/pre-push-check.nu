#!/usr/bin/env nu
# bin/pre-push-check.nu — pre-push safety checks for genoa
# Run before: jj git push
# SPDX-License-Identifier: BSD-2-Clause
#
# Checks for:
#   - Real (non-placeholder) sha256 values in examples/*.toml
#   - Real (non-example) SSH public keys in examples/*.toml
#
# Placeholder sha256 values (all-zeros, all-ones, all-F) are safe and expected
# while an agent binary URL is not yet finalised.
#
# Exit 0 = OK. Exit 1 = warnings found (push blocked).

def is_placeholder_sha256 [sha: string] {
  if ($sha | str length) < 64 { return true }
  # All-zeros, all-ones, all-F, or empty
  let chars = ($sha | split chars | uniq)
  ($chars | length) <= 1
}

def is_example_ssh_key [key: string] {
  # Our known placeholder key contains EXAMPLEKEY
  ($key | str contains "EXAMPLEKEY") or ($key | str contains "REPLACEWITHYOUROWN")
}

def main [] {
  let manifests = (ls /Users/studio/genoa/examples/*.toml | get name)
  mut warnings: list<string> = []

  for f in $manifests {
    let m = (open $f)

    # Check sha256 in [agent.source]
    let sha = ($m | get agent?.source?.sha256? | default "")
    if not (is_placeholder_sha256 $sha) {
      $warnings = ($warnings | append $"REAL SHA256 in ($f) — verify this is intentional before pushing")
    }

    # Check ssh_keys in [network]
    let keys = ($m | get network?.ssh_keys? | default [])
    for k in $keys {
      if not (is_example_ssh_key $k) {
        $warnings = ($warnings | append $"REAL SSH KEY in ($f): ($k | str substring 0..40)... — replace with placeholder before pushing to a public repo")
      }
    }
  }

  if ($warnings | length) == 0 {
    print "pre-push-check: OK — no credential issues found in examples/"
    exit 0
  } else {
    for w in $warnings {
      print $"WARNING: ($w)"
    }
    print ""
    print $"pre-push-check: ($warnings | length) issue(s) found — resolve before pushing to a public repo"
    exit 1
  }
}
