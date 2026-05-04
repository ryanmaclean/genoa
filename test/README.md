# genoa smoke tests

Run from the **repo root** (not from inside `test/`):

```
nu test/smoke.nu
```

Exit code 0 means all tests passed; exit code 1 means at least one failed.
Each test calls `nu genoa.nu <subcommand>` against the real CLI and real example manifests — no mocks.
