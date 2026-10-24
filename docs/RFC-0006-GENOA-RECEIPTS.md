> Split from ryanmaclean/skills#10 RFC 0006 on 2026-10-24; status Proposed.

# RFC 0006 (Genoa part) — Genoa-owned receipts: `genoa.receipt.v1`

Status: Proposed (the owner decides; see "Owner decisions")  
Date: 2026-09-24

Scope: this document holds the Genoa-owned half of RFC 0006. The canonical-repo and mirror half (registry rows, GitHub vs QNAS, D1, D2, D5-D7) lives in `ryanmaclean/datadog-agent-freebsd` as `docs/RFC-0006-CANONICAL-REPO.md`. Section text below is moved verbatim from the original RFC; references to "this PR" mean the original RFC.

## Update 2026-10-24 (status refresh; no decision is taken here)

- **Hosts.** Several build/test hosts named in legacy ledgers have been retired and others are being provisioned. No registry document names them, and host names stay out of this public registry (the RFC already keeps converted ledgers off this repo). Receipt `subject` and host fields must use the fleet hostname rules in Appendix A, not a retired host's name.

## Problem

3. **Genoa doesn't own the receipts, despite the ownership rule** ("build/deploy/provenance receipts → Genoa"). Six formats are in use today:
   - per-host `DEPLOYED.jsonl` lines with no version. 13 lines use 9 distinct key shapes, 3 lines have no `result`, and the lines carry truncated hashes (`sha256_prefix`).
   - `ddfb.native-deploy/v1`
   - `ddfb.otel-deploy/v1`
   - the QNAS build ledger, `schema_version: "1"`, with 36 records. It also embeds deployment facts (`deployed_hosts`), which mixes build and deploy.
   - `ddfb.build-record/v1`, written by the port's `bin/record.nu` to its own JSONL
   - Genoa's image-only `receipt.v1`

## Proposal

### C. Genoa owns receipts: `genoa.receipt.v1`

- **Genoa owns the schema.** It lives at `ryanmaclean/genoa:schemas/v1/receipt.schema.json` (Appendix A), with `genoa receipt append | verify | project` commands.
- **One append-only JSONL log per subject.** Git history of that log is the order (C5). Corrections are new receipts that set `operation.supersedes` (C21).
- **Port tools emit receipts.** The port's tools (`bin/record.nu` and the native/otel deploy scripts) emit `genoa.receipt.v1` and call `genoa receipt append`. They stop keeping their own ledgers.
- **Derived views only (C11).** `HISTORY.md`, Datadog notebooks and fleet snapshots are rebuilt from the log.

C20 statement:

- **Removed:** 5 of the formats above (all but Genoa's image receipt, whose shape the claims reuse) and their stores: the per-host `DEPLOYED.jsonl` files, the QNAS build ledger, the `bin/record.nu` ledger, and the two `ddfb.*-deploy/v1` formats. One format and one store replace them.
- **Invariant owned:** immutable evidence that an artifact was built, deployed, verified, rolled back or retired. The registry already gives this to Genoa.
- **Mutable state (C27):** none is added. The log is append-only.

### Schema rules (Appendix A)

| Concern | Rule | Constraint |
|---|---|---|
| Identity | `receipt_id`, plus `operation.operation_id` and `attempt`. Every retry of the same deploy shares `operation_id`. `run_id` links a BOP run; a Receipt is not a Run. | C2, C6, Glossary |
| Content | `artifact.sha256` must be the full 64 hex characters unless `trust.level = backfill`. | C2 |
| Order | Append order under git. `prev_receipt_sha256` is a hash chain for tamper evidence, not a counter. Wall-clock fields are metadata. | C5 |
| Completion | `outcome.completed = true` requires `gate.passed = true` and a stated `completed_invariant`. "Restarted" or "not failing" is not completion. | C3, C7 |
| Trust | `trust.level` is declared: `verified`, `self-attested`, `agent-report` or `backfill`. Backfill requires a `legacy` pointer (format, source, line, line sha256). | AX-first |
| Encoding | Receipt hash = sha256 of `"genoa.receipt.v1\n"` followed by the RFC 8785 (JCS) encoding of the receipt. | C24 |
| Hygiene | Hostnames and URLs must not be IP literals (enforced by pattern). `additionalProperties: false` everywhere except `metrics` and `tags`, so unknown fields such as credentials are rejected. | fleet rules |
| Claims | `evidence[].claim` reuses the claim/probe/expect/status shape that Genoa image receipts and fleet-eval already use. | reuse |

### Validation evidence (dry run, 2026-09-24)

A Nushell converter (a dry run that writes only to a local file) mapped all 49 legacy records into `genoa.receipt.v1`: 13 deploy lines and 36 build-ledger lines.

- **All 49 validate** against Appendix A (JSON Schema draft 2020-12).
- **5 bad inputs are rejected:**
  - an IP-literal host
  - `completed` without a gate
  - `verified` with a null sha256
  - an unknown extra field
  - an IP-literal URL
- **Findings:**
  - 32 of 49 records have no full artifact hash.
  - Only 14 of 49 meet the completion rule.
  - The converter found retried operations under a single `operation_id`: one config change was rolled back twice and passed on attempt 3.

The converter and the converted data stay off this public repo because they contain LAN hostnames and backup paths.

## Migration (after the owner accepts)

1. **genoa:** add `schemas/v1/receipt.schema.json` and the `genoa receipt` commands. Genoa owns this PR.
4. **Backfill:** convert the legacy logs once into `trust.level = backfill` receipts and append them to the Genoa log. Then freeze the legacy files, each with a pointer README.

## Owner decisions

| # | Decision | Recommendation |
|---|---|---|
| D3 | Where the Genoa receipt log lives | A new **private** Genoa-owned repo (e.g. `genoa-receipts`). `genoa` is public, and receipts name LAN hosts and backup paths. Rejected alternatives: redacted receipts in public `genoa` (they lose evidence) and a `receipts/` directory in the port repo (a second owner, which violates C1). |
| D4 | Whether a private repo's name may appear in this public registry | Yes, the name only (no URLs or hosts). C1 needs the row. |

## Appendix A — `genoa.receipt.v1` JSON Schema (proposed; its home is Genoa)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://github.com/ryanmaclean/genoa/schemas/v1/receipt.schema.json",
  "title": "Genoa receipt v1 (build | deploy | verify | rollback | retire)",
  "description": "One immutable fact per JSONL line: evidence that an artifact was built, deployed, verified, rolled back or retired. Owned by Genoa (registry ownership rule: build/deploy/provenance receipts -> Genoa). Order is the append order of the Genoa-owned log under git (C5); corrections are new receipts that set operation.supersedes (C21). Hash for chaining = sha256 over the bytes \"genoa.receipt.v1\\n\" followed by the RFC 8785 (JCS) encoding of the whole receipt (C24).",
  "x-schema-semver": "1.0.0",
  "type": "object",
  "required": [
    "schema",
    "receipt_id",
    "kind",
    "operation",
    "subject",
    "recorded_at",
    "producer",
    "outcome",
    "trust",
    "evidence"
  ],
  "additionalProperties": false,
  "properties": {
    "schema": {
      "const": "genoa.receipt.v1"
    },
    "receipt_id": {
      "$ref": "#/$defs/uuid",
      "description": "Identity of this receipt (UUIDv4 or UUIDv7). Never reused."
    },
    "kind": {
      "enum": [
        "build",
        "deploy",
        "verify",
        "rollback",
        "retire"
      ]
    },
    "operation": {
      "type": "object",
      "description": "Logical operation identity (C6): every attempt of the same build/deploy shares operation_id; attempt increments.",
      "required": [
        "operation_id",
        "attempt"
      ],
      "additionalProperties": false,
      "properties": {
        "operation_id": {
          "type": "string",
          "pattern": "^[a-z0-9][a-z0-9._:/+-]{2,200}$"
        },
        "attempt": {
          "type": "integer",
          "minimum": 1
        },
        "run_id": {
          "type": [
            "string",
            "null"
          ],
          "description": "BOP run identity when the work was a BOP card run (BOP owns run identity). A Receipt is not a Run."
        },
        "supersedes": {
          "oneOf": [
            {
              "$ref": "#/$defs/uuid"
            },
            {
              "type": "null"
            }
          ],
          "description": "receipt_id this receipt corrects (C21: never edit in place)."
        }
      }
    },
    "subject": {
      "type": "object",
      "required": [
        "project",
        "components"
      ],
      "additionalProperties": false,
      "properties": {
        "project": {
          "type": "string",
          "description": "Registry repo name that owns the recipe, e.g. datadog-agent-freebsd."
        },
        "components": {
          "type": "array",
          "items": {
            "type": "string"
          },
          "minItems": 1,
          "uniqueItems": true
        }
      }
    },
    "artifact": {
      "type": "object",
      "required": [
        "name",
        "version",
        "sha256"
      ],
      "additionalProperties": false,
      "properties": {
        "name": {
          "type": "string"
        },
        "version": {
          "type": "string"
        },
        "release_tag": {
          "type": [
            "string",
            "null"
          ]
        },
        "sha256": {
          "oneOf": [
            {
              "$ref": "#/$defs/sha256"
            },
            {
              "type": "null"
            }
          ],
          "description": "Content identity of the artifact bytes. null only when trust.level=backfill and the bytes are gone."
        },
        "sha256_prefix": {
          "type": "string",
          "pattern": "^[a-f0-9]{8,63}$",
          "description": "Backfill only: the truncated hash a legacy record carried."
        },
        "size_bytes": {
          "type": [
            "integer",
            "null"
          ],
          "minimum": 0
        },
        "urls": {
          "type": "array",
          "items": {
            "$ref": "#/$defs/url"
          },
          "description": "Where the bytes can be fetched. First entry = canonical release; later entries = mirrors. Hostnames only, never IP literals."
        },
        "source": {
          "type": "object",
          "additionalProperties": false,
          "required": [
            "repo",
            "commit"
          ],
          "properties": {
            "repo": {
              "type": "string",
              "description": "Canonical recipe repo, owner/name."
            },
            "commit": {
              "oneOf": [
                {
                  "$ref": "#/$defs/gitsha"
                },
                {
                  "type": "null"
                }
              ]
            },
            "patch_series": {
              "type": [
                "string",
                "null"
              ]
            },
            "branch": {
              "type": [
                "string",
                "null"
              ],
              "description": "Branch the artifact was built from when it is not a tagged release."
            }
          }
        },
        "upstream": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "repo": {
              "type": "string"
            },
            "tag": {
              "type": [
                "string",
                "null"
              ]
            },
            "commit": {
              "oneOf": [
                {
                  "$ref": "#/$defs/gitsha"
                },
                {
                  "type": "null"
                }
              ]
            }
          }
        }
      }
    },
    "build": {
      "type": "object",
      "required": [
        "host",
        "os",
        "os_version",
        "arch"
      ],
      "additionalProperties": false,
      "properties": {
        "host": {
          "oneOf": [
            {
              "$ref": "#/$defs/hostname"
            },
            {
              "type": "null"
            }
          ],
          "description": "null only for backfill when the build host is not evidenced."
        },
        "jail": {
          "type": [
            "string",
            "null"
          ]
        },
        "os": {
          "enum": [
            "freebsd",
            "netbsd",
            "openbsd",
            "dragonfly",
            "linux",
            "macos",
            null
          ]
        },
        "os_version": {
          "type": [
            "string",
            "null"
          ]
        },
        "arch": {
          "enum": [
            "amd64",
            "arm64",
            "armv7",
            "riscv64",
            "i386",
            null
          ]
        },
        "native": {
          "type": "boolean",
          "description": "true = built on the target OS+arch (the port forbids cross-compiles)."
        },
        "pipeline": {
          "type": [
            "string",
            "null"
          ],
          "description": "e.g. invoke, ports."
        },
        "toolchain": {
          "type": "object",
          "additionalProperties": {
            "type": [
              "string",
              "null"
            ]
          }
        },
        "started_at": {
          "type": [
            "string",
            "null"
          ],
          "format": "date-time"
        },
        "finished_at": {
          "type": [
            "string",
            "null"
          ],
          "format": "date-time"
        }
      }
    },
    "deploy": {
      "type": "object",
      "required": [
        "target_host",
        "change"
      ],
      "additionalProperties": false,
      "properties": {
        "target_host": {
          "$ref": "#/$defs/hostname"
        },
        "change": {
          "enum": [
            "package",
            "binary",
            "config",
            "binary+config",
            "files"
          ]
        },
        "change_summary": {
          "type": [
            "string",
            "null"
          ]
        },
        "previous": {
          "type": [
            "object",
            "null"
          ],
          "additionalProperties": false,
          "properties": {
            "release_tag": {
              "type": [
                "string",
                "null"
              ]
            },
            "commit": {
              "oneOf": [
                {
                  "$ref": "#/$defs/gitsha"
                },
                {
                  "type": "null"
                }
              ]
            },
            "sha256": {
              "oneOf": [
                {
                  "$ref": "#/$defs/sha256"
                },
                {
                  "type": "null"
                }
              ]
            }
          }
        },
        "backup_ref": {
          "type": [
            "string",
            "null"
          ],
          "description": "Path or ref of the pre-change backup on the target (rollback source)."
        },
        "method": {
          "type": [
            "string",
            "null"
          ],
          "description": "e.g. ansible playbook name, bin/deploy.nu, pkg add."
        }
      }
    },
    "gate": {
      "type": "object",
      "required": [
        "name",
        "passed",
        "criteria"
      ],
      "additionalProperties": false,
      "properties": {
        "name": {
          "type": "string"
        },
        "version": {
          "type": [
            "string",
            "null"
          ]
        },
        "passed": {
          "type": "boolean"
        },
        "criteria": {
          "type": "array",
          "items": {
            "type": "object",
            "required": [
              "name",
              "pass"
            ],
            "additionalProperties": false,
            "properties": {
              "name": {
                "type": "string"
              },
              "expected": {},
              "observed": {},
              "pass": {
                "type": [
                  "boolean",
                  "null"
                ],
                "description": "null = not checked (never guessed)."
              }
            }
          }
        }
      }
    },
    "outcome": {
      "type": "object",
      "required": [
        "result",
        "completed"
      ],
      "additionalProperties": false,
      "properties": {
        "result": {
          "enum": [
            "succeeded",
            "failed",
            "rolled-back",
            "aborted-pre-change",
            "abandoned",
            "unknown"
          ]
        },
        "phase": {
          "enum": [
            "fetch",
            "patch",
            "build",
            "package",
            "publish",
            "install",
            "restart",
            "verify",
            null
          ]
        },
        "reason": {
          "type": [
            "string",
            "null"
          ]
        },
        "completed": {
          "type": "boolean",
          "description": "C7: true only when completed_invariant was checked and holds. Not running / accepted / written is not completion."
        },
        "completed_invariant": {
          "type": [
            "string",
            "null"
          ]
        }
      }
    },
    "metrics": {
      "type": "object",
      "description": "Numeric observations taken during the operation (checks_before, cpu_pct_after_120s, ...). Observation, not canonical state (C11).",
      "additionalProperties": {
        "type": [
          "number",
          "null"
        ]
      }
    },
    "evidence": {
      "type": "array",
      "minItems": 1,
      "items": {
        "type": "object",
        "required": [
          "kind",
          "ref"
        ],
        "additionalProperties": false,
        "properties": {
          "kind": {
            "enum": [
              "claim",
              "log",
              "file",
              "url",
              "metric-query",
              "legacy-record"
            ]
          },
          "ref": {
            "type": "string"
          },
          "sha256": {
            "oneOf": [
              {
                "$ref": "#/$defs/sha256"
              },
              {
                "type": "null"
              }
            ]
          },
          "claim": {
            "type": "object",
            "description": "proveryay / fleet-eval claim shape, same as genoa image receipts.",
            "required": [
              "claim",
              "probe",
              "expect",
              "status"
            ],
            "additionalProperties": false,
            "properties": {
              "claim": {
                "type": "string"
              },
              "executor": {
                "enum": [
                  "sh",
                  "nu",
                  "pup",
                  "ssh"
                ]
              },
              "probe": {
                "type": "string"
              },
              "expect": {
                "type": "string"
              },
              "status": {
                "enum": [
                  "verified",
                  "asserted",
                  "failed"
                ]
              }
            }
          }
        }
      }
    },
    "trust": {
      "type": "object",
      "description": "Trust is a declared field, never an assumption.",
      "required": [
        "level"
      ],
      "additionalProperties": false,
      "properties": {
        "level": {
          "enum": [
            "verified",
            "self-attested",
            "agent-report",
            "backfill"
          ]
        },
        "verifier": {
          "type": [
            "string",
            "null"
          ]
        },
        "verified_at": {
          "type": [
            "string",
            "null"
          ],
          "format": "date-time"
        },
        "note": {
          "type": [
            "string",
            "null"
          ]
        }
      }
    },
    "producer": {
      "type": "object",
      "required": [
        "tool",
        "agent"
      ],
      "additionalProperties": false,
      "properties": {
        "tool": {
          "type": "string",
          "description": "e.g. genoa receipt append, bin/record.nu."
        },
        "tool_version": {
          "type": [
            "string",
            "null"
          ]
        },
        "agent": {
          "type": "string",
          "description": "Human or agent name that produced the fact."
        }
      }
    },
    "recorded_at": {
      "type": "string",
      "format": "date-time",
      "description": "Human metadata only; wall clock is not an ordering primitive (C5)."
    },
    "occurred_at": {
      "type": [
        "string",
        "null"
      ],
      "format": "date-time"
    },
    "prev_receipt_sha256": {
      "oneOf": [
        {
          "$ref": "#/$defs/sha256"
        },
        {
          "type": "null"
        }
      ],
      "description": "Hash of the previous line in the same log (tamper evidence; not an ordering counter)."
    },
    "legacy": {
      "type": "object",
      "description": "Backfill pointer to the record this receipt was converted from.",
      "required": [
        "format",
        "source",
        "line_sha256"
      ],
      "additionalProperties": false,
      "properties": {
        "format": {
          "enum": [
            "deployed-jsonl-unversioned",
            "ddfb.native-deploy/v1",
            "ddfb.otel-deploy/v1",
            "qnas-build-record-1",
            "ddfb.build-record/v1",
            "genoa-image-receipt-v1"
          ]
        },
        "source": {
          "type": "string"
        },
        "line": {
          "type": [
            "integer",
            "null"
          ],
          "minimum": 1
        },
        "line_sha256": {
          "$ref": "#/$defs/sha256"
        }
      }
    },
    "tags": {
      "type": "object",
      "additionalProperties": {
        "type": "string"
      }
    }
  },
  "allOf": [
    {
      "if": {
        "properties": {
          "kind": {
            "const": "build"
          }
        }
      },
      "then": {
        "required": [
          "build",
          "artifact"
        ]
      }
    },
    {
      "if": {
        "properties": {
          "kind": {
            "enum": [
              "deploy",
              "rollback"
            ]
          }
        }
      },
      "then": {
        "required": [
          "deploy",
          "artifact"
        ]
      }
    },
    {
      "if": {
        "properties": {
          "outcome": {
            "properties": {
              "completed": {
                "const": true
              }
            }
          }
        }
      },
      "then": {
        "required": [
          "gate"
        ],
        "properties": {
          "gate": {
            "properties": {
              "passed": {
                "const": true
              }
            }
          },
          "outcome": {
            "required": [
              "completed_invariant"
            ],
            "properties": {
              "completed_invariant": {
                "type": "string"
              }
            }
          }
        }
      }
    },
    {
      "if": {
        "properties": {
          "trust": {
            "properties": {
              "level": {
                "const": "backfill"
              }
            }
          }
        }
      },
      "then": {
        "required": [
          "legacy"
        ]
      }
    },
    {
      "if": {
        "properties": {
          "trust": {
            "properties": {
              "level": {
                "not": {
                  "const": "backfill"
                }
              }
            }
          }
        },
        "required": [
          "artifact"
        ]
      },
      "then": {
        "properties": {
          "artifact": {
            "properties": {
              "sha256": {
                "$ref": "#/$defs/sha256"
              }
            }
          }
        }
      }
    }
  ],
  "$defs": {
    "uuid": {
      "type": "string",
      "pattern": "^[0-9a-f]{8}-[0-9a-f]{4}-[47][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"
    },
    "sha256": {
      "type": "string",
      "pattern": "^[a-f0-9]{64}$"
    },
    "gitsha": {
      "type": "string",
      "pattern": "^[a-f0-9]{7,40}$",
      "description": "Git commit; full 40-hex preferred, abbreviated accepted for backfill."
    },
    "hostname": {
      "type": "string",
      "pattern": "^(?![0-9.]+$)(?!.*:)[a-z0-9][a-z0-9.-]{0,252}$",
      "description": "Hostname, never an IP literal (no hardcoded IPs)."
    },
    "url": {
      "type": "string",
      "pattern": "^https?://(?![0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+[:/]|\\[)[^\\s]+$",
      "description": "http(s) URL whose host is a name, never an IP literal."
    }
  }
}
```

## Appendix B — example receipt (synthetic placeholders)

```json
{
  "schema": "genoa.receipt.v1",
  "receipt_id": "0b7e3c1a-5d2f-4e8a-9c41-7f3a2b6d9e10",
  "kind": "deploy",
  "operation": { "operation_id": "deploy:pi-arm64-01:v7.83.3-freebsd15.1:package", "attempt": 1, "run_id": null, "supersedes": null },
  "subject": { "project": "datadog-agent-freebsd", "components": ["agent", "process-agent", "trace-agent"] },
  "artifact": {
    "name": "datadog-agent-7.83.3-freebsd15.1-arm64.tar.zst",
    "version": "7.83.3",
    "release_tag": "v7.83.3-freebsd15.1",
    "sha256": "0000000000000000000000000000000000000000000000000000000000000000",
    "size_bytes": 123456789,
    "urls": [
      "https://github.com/OWNER/datadog-agent-freebsd/releases/download/v7.83.3-freebsd15.1/datadog-agent-7.83.3-freebsd15.1-arm64.tar.zst",
      "http://gitea.local:3000/OWNER/datadog-agent-FreeBSD/releases/download/v7.83.3-freebsd15.1/datadog-agent-7.83.3-freebsd15.1-arm64.tar.zst"
    ],
    "source": { "repo": "OWNER/datadog-agent-freebsd", "commit": "1111111111111111111111111111111111111111", "branch": null, "patch_series": "patches/7.83.3" },
    "upstream": { "repo": "DataDog/datadog-agent", "tag": "7.83.3", "commit": "2222222222222222222222222222222222222222" }
  },
  "deploy": {
    "target_host": "pi-arm64-01",
    "change": "package",
    "change_summary": "upgrade 7.80.2 -> 7.83.3",
    "previous": { "release_tag": "v7.80.2-freebsd", "commit": null, "sha256": null },
    "backup_ref": "/var/backups/datadog-pre-7.83.3",
    "method": "ansible playbook 70-datadog-agent"
  },
  "gate": {
    "name": "health-gate",
    "version": "2",
    "passed": true,
    "criteria": [
      { "name": "api_key_valid", "expected": true, "observed": true, "pass": true },
      { "name": "check_names_equal_within_360s", "expected": true, "observed": true, "pass": true },
      { "name": "new_error_lines", "expected": 0, "observed": 0, "pass": true }
    ]
  },
  "outcome": { "result": "succeeded", "phase": null, "reason": null, "completed": true, "completed_invariant": "health-gate v2 passed on the new pid; check set equal to pre-change set" },
  "metrics": { "checks_before": 33, "checks_after": 33 },
  "evidence": [
    { "kind": "claim", "ref": "installed binary hash", "sha256": null,
      "claim": { "claim": "installed agent matches release sha256", "executor": "ssh", "probe": "sha256 -q /usr/local/bin/datadog-agent", "expect": "<artifact member sha256>", "status": "verified" } },
    { "kind": "metric-query", "ref": "avg:datadog.agent.running{host:pi-arm64-01}", "sha256": null }
  ],
  "trust": { "level": "verified", "verifier": "fleet-eval", "verified_at": "2026-09-24T12:40:00Z", "note": null },
  "producer": { "tool": "genoa receipt append", "tool_version": "0.2.0", "agent": "rollout agent" },
  "recorded_at": "2026-09-24T12:41:00Z",
  "occurred_at": "2026-09-24T12:31:33Z",
  "prev_receipt_sha256": null,
  "tags": {}
}
```
