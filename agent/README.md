# ii-agent

Minimal cloud agent for genoa images. All I/O is JSON (AX-first).

## Subcommands

| Command | Description |
|---|---|
| `ii-agent version` | Print version, platform, arch as JSON |
| `ii-agent status` | Print health blob (version, pid, uptime, hostname, timestamp) as JSON |
| `ii-agent run-task --cmd <cmd>` | Run a shell command, return stdout/stderr/exit_code/elapsed as JSON |
| `ii-agent heartbeat --endpoint <url>` | POST status JSON to endpoint; `--dry-run` to preview payload |
| `ii-agent start --endpoint <url>` | Boot entrypoint used by rc.d — posts heartbeat and exits |

## Response envelope

All subcommands return a JSON object. The `action` field indicates outcome:

- `"ran"` / `"posted"` / `"would-post"` — success or dry-run
- `"failed"` — error; check `error` or `stderr` field

## Installation (in image)

The build copies:
- `out/ii-agent` → `/usr/local/bin/ii-agent.nu` (the Nu script)
- `rc.d/ii-agent` → `/usr/local/etc/rc.d/ii_agent`

rc.conf enables it via `ii_agent_enable="YES"`.

## Configuration (rc.conf knobs)

| Variable | Default | Description |
|---|---|---|
| `ii_agent_enable` | `NO` | Set `YES` to enable |
| `ii_agent_endpoint` | `http://localhost:7071/task` | Heartbeat POST target |

## License

Apache-2.0
