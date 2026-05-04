# Agent Port Quickstart

Primary reader: LLM agent. Structure: sequential steps with exact commands and
expected output shapes. All commands run from the genoa repo root.

---

## 1. Three-call discovery

Discover what genoa can build, what fields are valid, and what the template
looks like — in three tool calls.

```
nu genoa.nu catalog
```
Returns a JSON array of provider records from `catalog/providers.v1.json`.
Each record has `id`, `byoi_format`, `architectures_supported`, and
`deployment_path`. Use `id` as the value for `[deploy].provider` in your
manifest.

```
nu genoa.nu schema
```
Returns the full manifest JSON Schema (`schema/manifest.v1.json`). Parse
`properties` to enumerate every valid field. `required` lists mandatory keys.
`additionalProperties: false` means unknown keys are rejected.

```
nu genoa.nu describe examples/agent-port-template.toml
```
Returns a structured summary of the template manifest — all sections, their
resolved values, and which fields are placeholders. Use this to understand
the shape before adapting.

---

## 2. Adapt the template

Copy the template, then change exactly these fields:

| Field | Where | What to set |
|---|---|---|
| `image.name` | `[image]` | your agent slug, e.g. `"my-agent-freebsd-amd64"` |
| `image.version` | `[image]` | SemVer matching your agent release, e.g. `"v0.3.1"` |
| `agent.name` | `[agent]` | agent identifier, e.g. `"my-agent"` |
| `agent.version` | `[agent]` | must match `image.version` |
| `agent.source.type` | `[agent.source]` | `"url"`, `"gitea_release"`, or `"local_path"` |
| `agent.source.url` | `[agent.source]` | direct HTTPS URL to your FreeBSD binary |
| `agent.source.sha256` | `[agent.source]` | 64-char hex digest (see note below) |
| `rc_service.name` | `[agent.rc_service]` | rc.d name with underscores, e.g. `"my_agent"` |
| `rc_service.command_args` | `[agent.rc_service]` | startup flags for your binary |
| `network.hostname` | `[network]` | VM hostname, e.g. `"my-agent-01"` |
| `metadata.*` | `[metadata]` | your team contact, repo, CI pipeline |

Fields not in this table can stay at their template defaults for an initial
build.

**Source type selection:**
- `"url"` — binary hosted at a public or presigned HTTPS URL; requires `url` + `sha256`
- `"gitea_release"` — binary is a release asset on `gitea.local:3000`; requires `repo`, `tag`, `asset`, `sha256`
- `"local_path"` — binary already on the build host filesystem; requires `path`; `sha256` not checked

**sha256 note:** set `agent.source.sha256` to the real SHA-256 of your
binary before production builds. All-zeros
(`0000000000000000000000000000000000000000000000000000000000000000`)
triggers a validation warning and will be flagged in the build receipt.
Compute it with:
```
sha256sum ./my-agent-freebsd-amd64          # Linux / FreeBSD
shasum -a 256 ./my-agent-freebsd-amd64      # macOS
```

---

## 3. Pre-flight validation

```
nu genoa.nu validate your-agent.toml
```

Passing output shape (JSON):
```json
{
  "action": "validated",
  "manifest_path": "your-agent.toml",
  "valid": true,
  "checks": [...],
  "errors": [],
  "warnings": []
}
```

A passing run has `"valid": true` and `"errors": []`. Warnings do not block
the build but should be resolved before production. Common warnings:
- `sha256 is all-zeros` — replace with real digest
- `image.format not accepted by provider` — check `catalog/providers.v1.json`
  `.byoi_format` for your `deploy.provider`

On validation failure, `"valid": false` and `"errors"` contains an array of
strings describing what failed. Fix all errors before proceeding.

---

## 4. Dry-run

```
nu genoa.nu build your-agent.toml --dry-run
```

Prints a 16-step plan without executing any build steps. The plan is returned
as a record with a `steps` array; each element has:
```json
{ "step": 3, "label": "create_disk_image", "action": "would-run", "description": "...", "cmd": "..." }
```

Review steps to confirm:
- Step 2 (`resolve_artifacts`) shows the correct agent URL or path
- Step 10 (`configure_loader`) lists your boot options rendered correctly
- Step 12 (`inject_agent`) names the correct agent binary and rc.d service
- Step 15 (`umount_and_compact`) is present before the receipt is emitted

If any step detail looks wrong, fix the manifest and re-validate before
running a real build.

---

## 5. Build

```
nu genoa.nu build your-agent.toml
```

Requires a FreeBSD build host. If you are running genoa on macOS or Linux,
set `target.build_host` in your manifest to an SSH-reachable FreeBSD machine:

```toml
[target]
build_host = "builder@fb-vm-24:2225"
```

genoa will SSH in, transfer the manifest, run the build remotely, and pull
the finished image and receipt back to `[image].output_dir` (default: `./out`).

On success the command exits 0 and writes two files:
```
out/your-agent-freebsd-amd64-v0.1.0.raw
out/your-agent-freebsd-amd64-v0.1.0.receipt.json
```

The receipt is a JSON provenance envelope with `sha256`, `build_host`,
`timestamp`, `manifest_hash`, and `agent.source` fields. Keep it — the
deploy step reads it automatically.

---

## 6. Deploy

```
nu genoa.nu deploy your-agent.toml
```

genoa reads the receipt from `[image].output_dir` automatically — no path
argument needed. It looks up `[deploy].provider` in `catalog/providers.v1.json`
to determine the upload strategy (`snapshot-url` for Vultr, `byoi-api` for
others) and dispatches accordingly.

Provider credentials are read from environment variables. For Vultr:
```
VULTR_API_KEY=<your-key> nu genoa.nu deploy your-agent.toml
```

On success the command returns a JSON object:
```json
{
  "action": "deployed",
  "provider": "vultr",
  "snapshot_id": "cb676a46-66fd-4dfb-b839-443f2e6c0b60",
  "instance_id": "...",
  "instance_ip": "...",
  "region": "ewr",
  "plan": "vc2-1c-1gb",
  "image_url": "https://..."
}
```

---

## 7. One-shot

```
nu genoa.nu run your-agent.toml
```

Chains validate → build → publish → deploy in a single command. Aborts on the
first failure and prints the step that failed as a JSON error object. Equivalent to:

```
nu genoa.nu validate your-agent.toml &&
nu genoa.nu build   your-agent.toml &&
nu genoa.nu publish your-agent.toml &&
nu genoa.nu deploy  your-agent.toml
```

Use `run` in CI pipelines where you want a single exit code. Use the
individual commands when debugging a specific stage.
