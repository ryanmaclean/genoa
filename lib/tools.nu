# lib/tools.nu — shared CLI-binary locator
# Sourced first by genoa.nu so all other lib/ modules and adapters can use it.
# SPDX-License-Identifier: BSD-2-Clause

# find_bin — locate a CLI binary: check /opt/homebrew/bin, then PATH.
# Returns the full path string, or null if not found.
export def find_bin [name: string] {
  let brew = $"/opt/homebrew/bin/($name)"
  if ($brew | path exists) { return $brew }
  (which $name | get 0?.path? | default null)
}

# find_vultr — convenience wrapper (kept for call-site compatibility)
export def find_vultr [] { find_bin "vultr" }
