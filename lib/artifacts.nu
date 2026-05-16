# lib/artifacts.nu — main receipts, main diff
# Sourced by genoa.nu.

def "main receipts" [] {
  let receipt_files = try { glob "artifacts/**/*.receipt.json" } catch { [] }
  let receipts = ($receipt_files | each { |f|
    let r = try { open $f } catch { {} }
    {
      path:       $f
      version:    ($r.image?.version?     | default "")
      image_name: ($r.image?.name?        | default "")
      profile:    ($r.build?.profile?     | default "")
      built_at:   ($r.built_at?           | default "")
      host:       ($r.build?.host?        | default "")
      provider:   ($r.published?.backend? | default (
        $r.claims? | default [] | where { |c| ($c.claim? | default "") =~ "provider" } | get 0?.claim? | default ""
      ))
    }
  } | sort-by built_at --reverse)
  {action: "receipts" count: ($receipts | length) receipts: $receipts} | to json --indent 2
}

def "main diff" [
  receipt_a: string   # path to first receipt (older)
  receipt_b: string   # path to second receipt (newer)
] {
  if not ($receipt_a | path exists) {
    error make {msg: $"receipt not found: ($receipt_a)"}
  }
  if not ($receipt_b | path exists) {
    error make {msg: $"receipt not found: ($receipt_b)"}
  }

  let a = open $receipt_a
  let b = open $receipt_b

  # Flatten the fields we care about
  let fields = [
    ["image.version"        {|r| $r.image?.version? | default ""}]
    ["image.name"           {|r| $r.image?.name? | default ""}]
    ["image.format"         {|r| $r.image?.format? | default ""}]
    ["build.host"           {|r| $r.build?.host? | default ""}]
    ["build.profile"        {|r| $r.build?.profile? | default ""}]
    ["build.os_version"     {|r| $r.build?.os_version? | default ""}]
    ["build.arch"           {|r| $r.build?.arch? | default ""}]
    ["build.genoa_version"  {|r| $r.build?.genoa_version? | default ""}]
    ["agent.name"           {|r| $r.agent?.name? | default ""}]
    ["agent.version"        {|r| $r.agent?.version? | default ""}]
    ["hashes.image_sha256"  {|r| $r.hashes?.image_sha256? | default "" | str substring 0..15}]
    ["built_at"             {|r| $r.built_at? | default ""}]
  ]

  let changes = ($fields | each { |f|
    let name = $f.0
    let getter = $f.1
    let val_a = (do $getter $a)
    let val_b = (do $getter $b)
    if $val_a != $val_b {
      {field: $name from: $val_a to: $val_b}
    } else {
      null
    }
  } | compact)

  let unchanged = ($fields | each { |f|
    let name = $f.0
    let getter = $f.1
    let val_a = (do $getter $a)
    let val_b = (do $getter $b)
    if $val_a == $val_b { $name } else { null }
  } | compact)

  {
    action:    "diff"
    receipt_a: $receipt_a
    receipt_b: $receipt_b
    changes:   $changes
    unchanged: $unchanged
    summary:   $"($changes | length) fields changed, ($unchanged | length) unchanged"
  } | to json --indent 2
}
