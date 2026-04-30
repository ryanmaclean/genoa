# LSD — Linux→BSD Stomper Deploy

**Option E** in the genoa bake-off.

Nushell CLI that emits a Linux→QEMU→mfsBSD trampoline installer for cloud
providers that only support Linux base images. Write a `lsd.toml`, run three
commands, get FreeBSD on your cloud box.

## Quickstart (3 commands)

```sh
nu lsd.nu catalog                                     # discover what's supported
nu lsd.nu describe examples/hetzner-cax-freebsd.toml # inspect the plan
nu lsd.nu build examples/hetzner-cax-freebsd.toml --out ./out  # emit bootstrap.sh
```

Then copy `out/bootstrap.sh` into your provider's rescue shell and run it as root.

## How it works

```
Your laptop          Provider rescue (Linux)          Cloud disk
──────────           ──────────────────────────       ──────────
lsd build  ──────►  bootstrap.sh runs as root
  lsd.toml          apt install qemu-system-*
  bootstrap.sh      curl mfsBSD.iso; sha256 verify
  bsdinstall.script qemu-system-* \
  lsd-receipt.json    -drive /dev/sda (passthrough) ──► FreeBSD installs
                      -cdrom mfsBSD.iso                  on real cloud disk
                      -cdrom seed.img (ssh keys)
                    QEMU exits → reboot → FreeBSD
```

The trampoline passes the **raw cloud disk** through as a virtio-blk device.
mfsBSD runs `bsdinstall script` non-interactively. After QEMU exits, the
server reboots directly into the installed FreeBSD.

## What's tested vs. claimed

| Provider | Base | Arch | Status |
|---|---|---|---|
| Hetzner Robot | FreeBSD 15 | x86_64 | spec'd via depenguin-run pattern, NOT exercised in this harness |
| Hetzner Cloud CAX | FreeBSD 15 | aarch64 | spec'd, virtio-mmio quirks documented, NOT exercised |
| OCI Always Free | FreeBSD 15 | aarch64 | BYOI documented, qcow2 upload path noted, NOT exercised |
| DO custom image | FreeBSD 15 | x86_64 | trampoline spec'd, IPv6 warning baked in, NOT exercised |
| AWS / GCP | any | any | not addressed in v0.1 |

**What does work in this harness:**
- `lsd catalog` — returns validated JSON catalog
- `lsd schema` — returns full JSON Schema for `lsd.toml`
- `lsd describe <manifest>` — renders structured plan, validates manifest, emits provider warnings
- `lsd build <manifest>` — renders and writes `bootstrap.sh`, `bsdinstall.script`, `lsd-receipt.json`
- `lsd verify <manifest> <receipt>` — recomputes and compares all artifact hashes
- Manifest validation (provider/arch/fs enum checks, hostname RFC-1123, sha256 format)
- DO IPv6 warning is structural — always emitted, cannot be suppressed
- Template rendering (Tera-style variable substitution, arch/fs conditionals)

**What's stubbed:**
- mfsBSD ISO download (placeholder sha256 in examples — replace with real digest)
- Actual QEMU boot (no cloud credentials; bootstrap.sh renders correctly but is not executed)
- Real `bsdinstall script` run (template renders, not executed)
- BYOI image upload to OCI/DO

## Manifest format (`lsd.toml`)

```toml
lsd_schema_version = "1.0.0"

[target]
provider = "hetzner-cloud"   # hetzner-cloud | hetzner-robot | oci | digitalocean
plan     = "cax11"
region   = "nbg1"

[base]
os         = "freebsd"       # freebsd | netbsd
version    = "15.0-RELEASE"
arch       = "aarch64"       # amd64 | aarch64
filesystem = "zfs"           # zfs | ufs

[network]
ssh_keys = ["ssh-ed25519 AAAA..."]
hostname = "my-bsd-host"

[trust]
mfs_image_sha256 = "<64-hex-chars>"  # sha256 of mfsBSD ISO
provenance_url   = "https://..."     # optional
```

Full schema: `nu lsd.nu schema` or `schema/manifest.v1.json`

## AX-first discovery

A cold LM can discover and use this tool in three calls:

```
nu lsd.nu catalog   → what providers/OS/arch tuples are supported
nu lsd.nu schema    → what fields are required in lsd.toml
nu lsd.nu describe examples/hetzner-cax-freebsd.toml  → full plan + warnings
```

Then `nu lsd.nu build <manifest> --out ./out` to produce the installer.

## Hetzner CAX (ARM64) notes

- Rescue boots Debian 12; `apt-get install qemu-system-arm ovmf` works cleanly
- CAX instances use virtio-mmio (not virtio-pci); `loader.conf` needs `virtio_mmio_load="YES"`
- KVM is available in rescue — no nested-virt penalty
- Primary disk: `/dev/sda` (verify with `lsblk` first)

## DigitalOcean warning

DO custom-image Droplets **cannot auto-configure IPv6**. The DO networking
agent that handles this is Linux-only and absent from custom images.
`lsd describe` always emits `digitalocean-custom-images-no-ipv6` for DO
manifests — this is a hard provider limit, not a bug.

## Reference

Pattern inspired by [depenguin-me/depenguin-run](https://github.com/depenguin-me/depenguin-run) (MIT).
Generalized to multiple providers; no code copied.

## License

BSD-2-Clause. See LICENSE. mfsBSD (BSD-2) fetched at runtime. QEMU (GPL-2)
installed from distro packages, not vendored. See LICENSE-DEPS.md.
