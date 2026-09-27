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

# sha256_file — portable SHA-256 of a file as lowercase hex.
# Prefers native tools (streaming, fine for multi-GB state disks):
# sha256 -q (FreeBSD), sha256sum (Linux/coreutils), shasum -a 256 (macOS).
# Falls back to Nushell's builtin hasher (reads the whole file into memory).
export def sha256_file [path: string] {
  if (which sha256 | is-not-empty) and ((^uname -s | str trim) == "FreeBSD") {
    return (^sha256 -q $path | str trim)
  }
  if (which sha256sum | is-not-empty) {
    return (^sha256sum $path | split row " " | first | str trim)
  }
  if (which shasum | is-not-empty) {
    return (^shasum -a 256 $path | split row " " | first | str trim)
  }
  open --raw $path | hash sha256
}
