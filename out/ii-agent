#!/usr/bin/env nu
# ii-agent — minimal cloud agent for genoa images
# Runs as a service via /usr/local/etc/rc.d/ii_agent
# All I/O: JSON. AX-first.
# SPDX-License-Identifier: Apache-2.0

const VERSION = "v0.2.0"
const DEFAULT_PORT = 7070
const DEFAULT_ENDPOINT = "http://localhost:7071/task"

def main [] {
  print $"ii-agent ($VERSION) — use: ii-agent [start|status|run-task|version|heartbeat]"
}

def "main version" [] {
  {
    version: $VERSION
    platform: (try { ^uname -s | str trim } catch { "unknown" })
    arch: (try { ^uname -m | str trim } catch { "unknown" })
  } | to json
}

def "main status" [] {
  {
    version: $VERSION
    pid: (try { ^sh -c "echo $$" | str trim | into int } catch { 0 })
    uptime: (try { ^uptime | str trim } catch { "unknown" })
    hostname: (try { ^hostname | str trim } catch { "unknown" })
    platform: (try { ^uname -s | str trim } catch { "unknown" })
    timestamp: (date now | format date "%Y-%m-%dT%H:%M:%SZ")
  } | to json --indent 2
}

def "main run-task" [
  --cmd: string = "uname -a"   # shell command to execute
  --timeout: int = 30           # seconds (reserved for future use)
] {
  let start = (date now | into int)
  let result = try {
    let out = ^sh -c $cmd | complete
    let elapsed = (((date now | into int) - $start) / 1_000_000_000)
    {
      action: "ran"
      cmd: $cmd
      exit_code: $out.exit_code
      stdout: $out.stdout
      stderr: $out.stderr
      elapsed_seconds: $elapsed
    }
  } catch { |e|
    {action: "failed" cmd: $cmd error: $e.msg}
  }
  $result | to json --indent 2
}

def "main heartbeat" [
  --endpoint: string = $DEFAULT_ENDPOINT
  --dry-run
] {
  let status_json = main status | from json
  let payload = ($status_json | merge {agent_version: $VERSION event: "heartbeat"})
  if $dry_run {
    return ({action: "would-post" endpoint: $endpoint payload: $payload} | to json --indent 2)
  }
  let resp = try {
    let body = ($payload | to json)
    ^curl -sf -X POST $endpoint -H "Content-Type: application/json" -d $body
    {action: "posted" endpoint: $endpoint status: "ok"}
  } catch { |e|
    {action: "failed" endpoint: $endpoint error: $e.msg}
  }
  $resp | to json --indent 2
}

# Boot entrypoint — called by rc.d on system start.
# Posts heartbeat then exits (no persistent daemon needed for MVP).
def "main start" [
  --endpoint: string = $DEFAULT_ENDPOINT
] {
  main heartbeat --endpoint $endpoint
}
