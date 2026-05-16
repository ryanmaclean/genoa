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
  # main commands now output JSON strings directly; parse via from json
  let script = $"source ($GENOA); ($cmd)"
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

  # build_steps_uefi — uefi dry-run has exactly 23 steps (+9b write_loader_conf, +9c write_rc_conf, +9d write_fstab, +11b install_packages)
  (run_test "build_steps_uefi" {
    let rec = (genoa "main build 'examples/freebsd-vultr-aarch64.toml' --dry-run")
    let count = ($rec | get steps | length)
    if $count != 23 {
      error make {msg: $"expected 23 uefi steps got ($count)"}
    }
    $count
  })

  # build_steps_kboot — kboot dry-run has exactly 23 steps (+18a write_loader_kboot_conf, +18b write_rc_conf)
  (run_test "build_steps_kboot" {
    let rec = (genoa "main build 'examples/freebsd-linode-amd64.toml' --profile kboot --dry-run")
    let count = ($rec | get steps | length)
    if $count != 23 {
      error make {msg: $"expected 23 kboot steps got ($count)"}
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

  # receipt_schema — receipt conforms to schema/receipt.v1.json:
  # schema_version="v1", and required top-level objects: image, build, agent, hashes, claims
  (run_test "receipt_schema" {
    let rec = (genoa "main build 'examples/freebsd-vultr-aarch64.toml' --dry-run")
    let receipt_path = ($rec | get receipt_path)
    let receipt = (open $receipt_path)
    # Check schema_version
    if ($receipt.schema_version? | default "") != "v1" {
      error make {msg: $"receipt schema_version expected v1, got: ($receipt.schema_version? | default 'missing')"}
    }
    # Check required top-level fields per schema/receipt.v1.json
    let required = ["receipt_id" "built_at" "image" "build" "agent" "hashes" "claims"]
    let missing = ($required | where { |k| $k not-in $receipt })
    if ($missing | length) > 0 {
      error make {msg: $"receipt missing fields: ($missing | str join ', ')"}
    }
    # Check nested required fields
    let img_required = ["name" "version" "format" "output_path"]
    let img_missing = ($img_required | where { |k| $k not-in $receipt.image })
    if ($img_missing | length) > 0 {
      error make {msg: $"receipt.image missing fields: ($img_missing | str join ', ')"}
    }
    let hashes_required = ["image_sha256" "manifest_sha256"]
    let hashes_missing = ($hashes_required | where { |k| $k not-in $receipt.hashes })
    if ($hashes_missing | length) > 0 {
      error make {msg: $"receipt.hashes missing fields: ($hashes_missing | str join ', ')"}
    }
    # Check claims is a non-empty list
    let claims_count = ($receipt.claims | length)
    if $claims_count == 0 {
      error make {msg: "receipt.claims must be a non-empty list; got 0 elements"}
    }
    $"v1 receipt schema valid: ($receipt_path), claims=($claims_count)"
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

  # run_dry_pipeline — full pipeline run returns action="run", ok=true, stages record
  (run_test "run_dry_pipeline" {
    let rec = (^nu genoa.nu run examples/freebsd-vultr-aarch64.toml --dry-run | from json)
    if ($rec.action? | default "") != "run" {
      error make {msg: $"expected action=run, got: ($rec.action? | default 'missing'); keys: ($rec | columns | str join ', ')"}
    }
    if ($rec.ok? | default false) != true {
      error make {msg: $"expected ok=true, got ok=($rec.ok? | default false); stopped_at=($rec.stopped_at? | default 'null')"}
    }
    if ($rec.stages?.validate?.valid? | default false) != true {
      error make {msg: $"expected stages.validate.valid=true, got: ($rec.stages?.validate?.valid? | default 'missing')"}
    }
    if not (($rec.stages?.build? | default null) != null) {
      error make {msg: "expected stages.build to be a record, got null/missing"}
    }
    $"action=($rec.action) ok=($rec.ok) stopped_at=($rec.stopped_at | default 'null')"
  })

  # status_check — status returns action=status with platform and build_ready fields
  (run_test "status_check" {
    let rec = (^nu genoa.nu status | from json)
    let action = ($rec | get action)
    if $action != "status" {
      error make {msg: $"expected action=status got ($action)"}
    }
    let platform = ($rec | get platform? | default "")
    let build_ready = ($rec | get build_ready? | default false)
    $"action=($action) platform=($platform) build_ready=($build_ready)"
  })

  # notify_dry_run — dry-run returns action="would-notify", metrics >= 3, tags list with >= 2 elements
  (run_test "notify_dry_run" {
    let rec = (^nu genoa.nu notify out/smolbsd-vultr-aarch64-v0.1.0.receipt.json --dry-run | from json)
    let action = ($rec | get action)
    if $action != "would-notify" {
      error make {msg: $"expected action=would-notify got ($action)"}
    }
    let metrics = ($rec | get metrics)
    if $metrics < 3 {
      error make {msg: $"expected metrics >= 3 got ($metrics)"}
    }
    let tags = ($rec | get tags)
    if ($tags | length) < 2 {
      error make {msg: $"expected tags list with >= 2 elements, got ($tags | length)"}
    }
    $"action=($action) metrics=($metrics) tags=($tags | length)"
  })

  # publish_gitea_dry_run — dry-run returns action="would-run", backend="gitea", output is valid JSON
  (run_test "publish_gitea_dry_run" {
    let rec = (^nu genoa.nu publish out/smolbsd-vultr-aarch64-v0.1.0.raw --backend gitea --dry-run | from json)
    let action = ($rec | get action)
    if $action != "would-run" {
      error make {msg: $"expected action=would-run got ($action)"}
    }
    let backend = ($rec | get backend)
    if $backend != "gitea" {
      error make {msg: $"expected backend=gitea got ($backend)"}
    }
    $"action=($action) backend=($backend)"
  })

  # signing_dry_run — receipt includes signing field with action="unsigned" when no signing section in manifest
  (run_test "signing_dry_run" {
    let rec = (genoa "main build 'examples/agent-port-template.toml' --dry-run")
    let receipt_path = ($rec | get receipt_path)
    let receipt = (open $receipt_path)
    if "signing" not-in $receipt {
      error make {msg: "receipt is missing 'signing' field"}
    }
    let action = ($receipt.signing?.action? | default "missing")
    if $action != "unsigned" {
      error make {msg: $"expected signing.action=unsigned, got ($action)"}
    }
    let tool = ($receipt.signing?.tool? | default "missing")
    if $tool != "none" {
      error make {msg: $"expected signing.tool=none, got ($tool)"}
    }
    $"signing.action=($action) signing.tool=($tool)"
  })

  # validate_aws_manifest — valid == true and provider_in_catalog check passes
  (run_test "validate_aws_manifest" {
    let rec = (genoa "main validate 'examples/freebsd-aws-ec2-amd64.toml'")
    let val = ($rec | get valid)
    if $val != true {
      error make {msg: $"expected valid=true got ($val); errors: ($rec | get errors | to json)"}
    }
    let catalog_check = ($rec | get checks | where check == "provider_in_catalog" | first)
    if $catalog_check.pass != true {
      error make {msg: $"expected provider_in_catalog check to pass, detail: ($catalog_check.detail)"}
    }
    $"valid=($val) provider_in_catalog=($catalog_check.pass)"
  })

  # validate_ssh_key_check — bad ssh key in network.ssh_keys causes valid=false
  (run_test "validate_ssh_key_check" {
    let tmp = (^mktemp -t genoa-test-XXXXXX | str trim) + ".toml"
    "schema_version = \"v1\"

[image]
name = \"test-image\"
version = \"v0.1.0\"
format = \"raw\"
size_mb = 1024

[target]
os = \"freebsd\"
os_version = \"15.0-RELEASE\"
arch = \"amd64\"
platform = \"generic\"

[kernel]
config = \"GENERIC\"

[agent]
name = \"test-agent\"
version = \"v0.1.0\"

[agent.source]
type = \"local_path\"
path = \"/usr/local/bin/test-agent\"

[network]
interface = \"vtnet0\"
mode = \"dhcp\"
hostname = \"test-host\"
ssh_keys = [\"not-a-valid-key bad-format\"]

profile = \"uefi\"

[deploy]
provider = \"vultr\"
" | save --force $tmp
    let rec = (^nu -c $"source genoa.nu; main validate '($tmp)'" | from json)
    ^rm -f $tmp
    if $rec.valid != false {
      error make {msg: $"expected valid=false for bad ssh key, got valid=($rec.valid); errors=($rec.errors | to json)"}
    }
    let has_ssh_error = ($rec.errors | any { |e| $e | str contains "ssh_keys_format" })
    if not $has_ssh_error {
      error make {msg: $"expected ssh_keys_format error, got errors: ($rec.errors | to json)"}
    }
    $"valid=($rec.valid) ssh_keys_format error confirmed"
  })

  # verify_image_platform — on non-FreeBSD skips (skipped=true); on FreeBSD actually runs checks
  (run_test "verify_image_platform" {
    let rec = (^nu genoa.nu verify-image out/smolbsd-vultr-amd64-v0.1.3.raw | from json)
    let plat = ($rec.platform? | default "")
    let action = ($rec.action? | default "")
    if $action != "verify-image" {
      error make {msg: $"expected action=verify-image, got ($action)"}
    }
    # On FreeBSD: should run and return ok/checks; on others: should skip
    if $plat == "FreeBSD" {
      let checks = ($rec.checks? | default [] | length)
      $"platform=FreeBSD checks=($checks) ok=($rec.ok)"
    } else {
      let skipped = ($rec.skipped? | default false)
      $"skipped=($skipped) ok=($rec.ok) platform=($plat)"
    }
  })

  # linode_rescue_plan_dry — deploy --dry-run for linode returns action="would-run" and provider="linode_akamai"
  (run_test "linode_rescue_plan_dry" {
    let rec = (genoa "main deploy 'examples/freebsd-linode-amd64.toml' --provider linode_akamai --dry-run")
    let action = ($rec | get action)
    if $action != "would-run" {
      error make {msg: $"expected action=would-run got ($action)"}
    }
    let provider = ($rec | get provider)
    if $provider != "linode_akamai" {
      error make {msg: $"expected provider=linode_akamai got ($provider)"}
    }
    $"action=($action) provider=($provider)"
  })

  # health — returns valid JSON with ok field and checks list containing all required tools
  (run_test "health" {
    let rec = (genoa "main health")
    if "ok" not-in $rec {
      error make {msg: $"expected 'ok' field in health output, got keys: ($rec | columns | str join ', ')"}
    }
    if "checks" not-in $rec {
      error make {msg: $"expected 'checks' field in health output, got keys: ($rec | columns | str join ', ')"}
    }
    let checks = ($rec | get checks)
    if ($checks | length) == 0 {
      error make {msg: "expected non-empty checks list in health output"}
    }
    let tool_names = ($checks | get tool)
    let required = ["nu" "mdconfig" "gpart" "newfs_msdos" "newfs" "mount" "umount" "tar" "fetch" "truncate"]
    let missing = ($required | where { |t| $t not-in $tool_names })
    if ($missing | length) > 0 {
      error make {msg: $"health checks missing tools: ($missing | str join ', ')"}
    }
    $"ok=($rec.ok) checks=($checks | length) platform=($rec.platform)"
  })

  # schema_json_valid — schema/manifest.v1.json is valid JSON with a $schema field
  (run_test "schema_json_valid" {
    let schema = open schema/manifest.v1.json
    let has_dollar_schema = ("$schema" in $schema)
    if not $has_dollar_schema {
      error make {msg: "schema missing $schema field"}
    }
    let props = ($schema | get properties? | default {})
    let prop_count = ($props | columns | length)
    $"$schema present, ($prop_count) top-level properties"
  })

  # sign_dry_run — dry-run returns action="would-run", tool="signify", cmd and signature_path present
  (run_test "sign_dry_run" {
    let rec = (^nu genoa.nu sign "out/some.raw" --tool signify --key "/tmp/test.sec" --dry-run | from json)
    let action = ($rec | get action)
    if $action != "would-run" {
      error make {msg: $"expected would-run, got ($action)"}
    }
    let tool = ($rec | get tool)
    if $tool != "signify" {
      error make {msg: $"expected tool=signify, got ($tool)"}
    }
    if "cmd" not-in $rec {
      error make {msg: "expected cmd field in dry-run output"}
    }
    if "signature_path" not-in $rec {
      error make {msg: "expected signature_path field in dry-run output"}
    }
    $"action=($action) tool=($tool)"
  })

  # diff_receipts — compare v0.1.2 linode and v0.1.3 vultr receipts
  (run_test "diff_receipts" {
    let rec = (^nu genoa.nu diff artifacts/v0.1.2/smolbsd-linode-amd64-v0.1.2.receipt.json artifacts/v0.1.3/smolbsd-vultr-amd64-v0.1.3.receipt.json | from json)
    if ($rec.action? | default "") != "diff" {
      error make {msg: $"expected action=diff, got: ($rec.action? | default 'missing')"}
    }
    let change_count = ($rec.changes | length)
    if $change_count == 0 {
      error make {msg: "expected at least one change between receipts, got 0"}
    }
    let has_version_change = ($rec.changes | any { |c| $c.field == "image.version" })
    if not $has_version_change {
      error make {msg: "expected image.version to differ between receipts"}
    }
    let has_name_change = ($rec.changes | any { |c| $c.field == "image.name" })
    if not $has_name_change {
      error make {msg: "expected image.name to differ between receipts"}
    }
    $"action=diff changes=($change_count)"
  })

  # snapshots_vultr — action=="snapshots" or "failed" (when vultr auth not configured)
  (run_test "snapshots_vultr" {
    let rec = (^nu genoa.nu snapshots | from json)
    let action = ($rec | get action)
    if $action != "snapshots" and $action != "failed" {
      error make {msg: $"expected action=snapshots or failed, got ($action)"}
    }
    let count = ($rec | get count? | default 0)
    $"action=($action) count=($count)"
  })

  # snapshot_import_dry — dry-run returns action="would-run", provider="vultr", url and cmd fields present
  (run_test "snapshot_import_dry" {
    let rec = (^nu genoa.nu snapshot-import "http://example.com/image.raw" --dry-run | from json)
    let action = ($rec | get action)
    if $action != "would-run" {
      error make {msg: $"expected action=would-run got ($action)"}
    }
    let provider = ($rec | get provider)
    if $provider != "vultr" {
      error make {msg: $"expected provider=vultr got ($provider)"}
    }
    if "url" not-in $rec {
      error make {msg: "expected url field in dry-run result"}
    }
    if "cmd" not-in $rec {
      error make {msg: "expected cmd field in dry-run result"}
    }
    $"action=($action) provider=($provider)"
  })

  # providers_list — action == "providers" and count > 0
  (run_test "providers_list" {
    let rec = (^nu genoa.nu providers | from json)
    if ($rec.action? | default "") != "providers" {
      error make {msg: $"expected action=providers, got: ($rec.action? | default 'missing')"}
    }
    let count = ($rec.count? | default 0)
    if $count == 0 {
      error make {msg: "expected count > 0, got 0"}
    }
    $"action=providers count=($count)"
  })

  # providers_filter — --id vultr returns count==1 and providers.0.id=="vultr"
  (run_test "providers_filter" {
    let rec = (^nu genoa.nu providers --id vultr | from json)
    let count = ($rec.count? | default 0)
    if $count != 1 {
      error make {msg: $"expected count=1, got ($count)"}
    }
    let pid = ($rec.providers? | default [] | get 0?.id? | default "")
    if $pid != "vultr" {
      error make {msg: $"expected providers.0.id=vultr, got ($pid)"}
    }
    $"count=($count) id=($pid)"
  })

  # receipts_list — action == "receipts" and count > 0
  (run_test "receipts_list" {
    let rec = (^nu genoa.nu receipts | from json)
    if ($rec.action? | default "") != "receipts" {
      error make {msg: $"expected action=receipts, got: ($rec.action? | default 'missing')"}
    }
    let count = ($rec.count? | default 0)
    if $count == 0 {
      error make {msg: "expected count > 0, got 0"}
    }
    $"action=receipts count=($count)"
  })

  # instances_vultr — action=="instances" or "failed" (when vultr auth not configured)
  (run_test "instances_vultr" {
    let rec = (^nu genoa.nu instances --all | from json)
    let action = ($rec | get action)
    if $action != "instances" and $action != "failed" {
      error make {msg: $"expected action=instances or failed, got ($action)"}
    }
    let count = ($rec | get count? | default 0)
    $"action=($action) count=($count)"
  })

  # deploy_from_snapshot_dry — dry-run returns action="would-run" and snapshot_id matches
  (run_test "deploy_from_snapshot_dry" {
    let rec = (^nu genoa.nu deploy-from-snapshot "d372185f-d65d-4e10-9995-20f865b1c177" --dry-run | from json)
    let action = ($rec | get action)
    if $action != "would-run" {
      error make {msg: $"expected action=would-run got ($action)"}
    }
    let sid = ($rec | get snapshot_id)
    if $sid != "d372185f-d65d-4e10-9995-20f865b1c177" {
      error make {msg: $"expected snapshot_id to match, got ($sid)"}
    }
    $"action=($action) snapshot_id=($sid)"
  })

  # status_check — action=="status" and platform is non-empty
  (run_test "status_check" {
    let rec = (^nu genoa.nu status | from json)
    let action = ($rec | get action)
    if $action != "status" {
      error make {msg: $"expected action=status got ($action)"}
    }
    let plat = ($rec | get platform)
    if ($plat | is-empty) {
      error make {msg: "expected non-empty platform field"}
    }
    $"action=($action) platform=($plat)"
  })

  # netbsd_build_dry — netbsd profile returns profile="netbsd" and at least 1 step
  (run_test "netbsd_build_dry" {
    let rec = (^nu genoa.nu build examples/netbsd-vultr-amd64.toml --profile netbsd --dry-run | from json)
    let profile = ($rec | get profile)
    if $profile != "netbsd" {
      error make {msg: $"expected profile=netbsd got ($profile)"}
    }
    let step_count = ($rec | get steps | length)
    if $step_count == 0 {
      error make {msg: "expected steps to be non-empty, got 0"}
    }
    $"profile=($profile) steps=($step_count)"
  })

  # watch_snapshot_dry — timeout or failed path (completes in ~1s; accepts failed when vultr auth absent)
  (run_test "watch_snapshot_dry" {
    let rec = (^nu genoa.nu watch "fake-id-0000" --until "complete" --timeout 1 --interval 1 | from json)
    let action = ($rec | get action)
    if $action != "watch" and $action != "failed" {
      error make {msg: $"expected action=watch or failed got ($action)"}
    }
    if $action == "watch" {
      let timed_out = ($rec | get timed_out? | default false)
      let resource_id = ($rec | get resource_id? | default "")
      $"action=($action) timed_out=($timed_out) resource_id=($resource_id)"
    } else {
      $"action=($action) reason=($rec | get reason? | default 'vultr auth not configured')"
    }
  })

  # versions_gitea — action=="versions" or "failed" (Gitea may not be reachable from all environments)
  (run_test "versions_gitea" {
    let rec = (^nu genoa.nu versions | from json)
    let action = ($rec | get action)
    # Accept both success and failure (Gitea may not be reachable from all environments)
    if $action != "versions" and $action != "failed" {
      error make {msg: $"expected action=versions or failed, got ($action)"}
    }
    $"action=($action) count=($rec | get count? | default 0)"
  })

  # vultr_balance_check — deploy --dry-run still returns action="would-run" (balance check skipped in dry-run)
  (run_test "vultr_balance_check" {
    let rec = (^nu genoa.nu deploy examples/freebsd-vultr-aarch64.toml --dry-run | from json)
    let action = ($rec | get action)
    if $action != "would-run" {
      error make {msg: $"expected action=would-run (dry-run skips balance check), got ($action)"}
    }
    $"action=($action)"
  })

  # clone_instance_dry — clone-instance --dry-run; accepts "failed" when vultr auth not configured
  (run_test "clone_instance_dry" {
    let rec = (^nu genoa.nu clone-instance "f2656038-47fa-4de7-968e-5c1b24ce8f39" --dry-run | from json)
    let action = ($rec | get action)
    if $action != "would-run" and $action != "failed" {
      error make {msg: $"expected action=would-run or failed, got ($action)"}
    }
    let source_id = ($rec | get source_id? | default "no-auth")
    $"action=($action) source_id=($source_id)"
  })

  # suggest_dry_run — --dry-run returns action="suggest", dry_run=true, prompt_preview and ollama_url present
  (run_test "suggest_dry_run" {
    let rec = (^nu genoa.nu suggest "minimal freebsd for vultr" --dry-run | from json)
    let action = ($rec | get action)
    if $action != "suggest" {
      error make {msg: $"expected action=suggest, got ($action)"}
    }
    let dry_run = ($rec | get dry_run? | default false)
    if $dry_run != true {
      error make {msg: $"expected dry_run=true, got ($dry_run)"}
    }
    if "prompt_preview" not-in $rec {
      error make {msg: "expected prompt_preview field in dry-run output"}
    }
    if "ollama_url" not-in $rec {
      error make {msg: "expected ollama_url field in dry-run output"}
    }
    $"action=($action) dry_run=($dry_run)"
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
