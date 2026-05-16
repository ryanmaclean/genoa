# lib/suggest.nu — main suggest (AI-powered manifest generation via Ollama)
# Sourced by genoa.nu.

def "main suggest" [
  description: string              # natural language description of the desired manifest
  --model: string = "llama3.2"    # Ollama model name
  --ollama: string = "http://ollama.local:11434"  # Ollama endpoint
  --dry-run                        # return prompt without calling Ollama
  --output: string = ""            # if set, write manifest TOML to this file
] {
  # Build prompt from schema + example + user description
  let schema_json = try { open "schema/manifest.v1.json" | to json --indent 2 } catch { "{}" }
  let example_toml = try { open --raw "examples/freebsd-vultr-aarch64.toml" } catch { "# example not found" }

  let prompt_header = "You are a genoa manifest generator. genoa is an AX-first CLI for building FreeBSD/NetBSD cloud images."
  let prompt_schema_section = $"## JSON Schema\n\n($schema_json)"
  let prompt_example_section = $"## Example Manifest\n\n($example_toml)"
  let prompt_rules = "Rules:\n- Return ONLY valid TOML, no markdown fences, no explanation.\n- schema_version must be \"v1\".\n- Required fields: schema_version, image, target, kernel, agent (with source).\n- image.name: ^[a-z0-9][a-z0-9-]+[a-z0-9]$\n- image.version: ^v[0-9]+.[0-9]+.[0-9]+$\n- image.format: raw, vmdk, vhd, or qcow2\n- image.size_mb >= 512\n- target.os: freebsd or netbsd\n- target.arch: amd64, aarch64, or riscv64\n- agent.source.type: url, gitea_release, or local_path\n- profile: uefi, kboot, or netbsd"
  let prompt_task = $"## Task\n\nGenerate a valid genoa manifest TOML for: ($description)\n\n($prompt_rules)"
  let prompt = ([$prompt_header $prompt_schema_section $prompt_example_section $prompt_task] | str join "\n\n")

  if $dry_run {
    return ({
      action:         "suggest"
      dry_run:        true
      description:    $description
      prompt_preview: ($prompt | str substring 0..200)
      ollama_url:     $ollama
      model:          $model
    } | to json --indent 2)
  }

  let ollama_url = $"($ollama)/api/generate"
  let payload = {
    model:  $model
    prompt: $prompt
    stream: false
  }

  let response = try {
    ^curl -sf -X POST $ollama_url -H "Content-Type: application/json" -d ($payload | to json) | from json
  } catch { |e|
    return ({
      action:      "suggest"
      error:       $"Ollama request failed: ($e.msg)"
      ollama_url:  $ollama_url
      model:       $model
      description: $description
    } | to json --indent 2)
  }

  let manifest_toml = ($response.response? | default "" | str trim)

  if ($manifest_toml | is-empty) {
    return ({
      action:      "suggest"
      error:       "LLM returned empty response"
      model:       $model
      backend:     "ollama"
      description: $description
    } | to json --indent 2)
  }

  # Parse the TOML
  let manifest = try { $manifest_toml | from toml } catch { null }
  if $manifest == null {
    return ({
      action:      "suggest"
      error:       "LLM returned invalid TOML"
      raw:         $manifest_toml
      model:       $model
      backend:     "ollama"
      description: $description
    } | to json --indent 2)
  }

  # Write to temp file and validate
  let tmp = (^mktemp /tmp/genoa-suggest-XXXXXX.toml | str trim)
  $manifest_toml | save --force $tmp
  let validation = try {
    ^nu genoa.nu validate $tmp | from json
  } catch { |e|
    {valid: false, errors: [$"validate subprocess failed: ($e.msg)"], warnings: [], checks: []}
  }
  ^rm -f $tmp

  # Optionally write manifest to output file
  if $output != "" {
    $manifest_toml | save --force $output
  }

  {
    action:            "suggest"
    description:       $description
    manifest_toml:     $manifest_toml
    manifest:          $manifest
    valid:             ($validation.valid? | default false)
    validation_errors: ($validation.errors? | default [])
    model:             $model
    backend:           "ollama"
  } | to json --indent 2
}
