# License Compliance — LSD v0.1.0

## Runtime dependencies (fetched at runtime, not vendored)

| Component | License | Source | Notes |
|---|---|---|---|
| mfsBSD | BSD-2-Clause | https://mfsbsd.vx.sk/ | Fetched at runtime by bootstrap.sh; SHA-256 verified before use |
| FreeBSD distribution sets | BSD-2-Clause (various) | https://download.freebsd.org/ | Fetched by bsdinstall(8) inside mfsBSD |
| QEMU | GPL-2.0-or-later | https://www.qemu.org/ | Installed from distro package manager in rescue environment; NOT vendored |

## Code we write (this repo)

| File | License |
|---|---|
| lsd.nu | BSD-2-Clause |
| provider-adapters/*.nu | BSD-2-Clause |
| templates/bootstrap.sh.tera | BSD-2-Clause |
| templates/bsdinstall.script.tera | BSD-2-Clause |
| schema/*.json | BSD-2-Clause |
| examples/*.toml | BSD-2-Clause |

## Tools used (not vendored, not shipped)

| Tool | License | Why |
|---|---|---|
| Nushell 0.111.0 | MIT | CLI runtime |
| Python 3.x | PSF-2.0 | jq-equivalent in README examples (optional) |
| jq | MIT | Optional JSON formatting in quickstart |

## Explicitly NOT used

- **iPXE**: GPL-2.0. Not vendored, not chainloaded. We rely on the provider's rescue Linux.
- **cloud-localds**: GPL. Not used.
- **xorriso**: GPL-2.0-or-later. Not used.
- **syslinux/PXELINUX**: GPL-2.0-or-later. Not used.
- **grub**: GPL-3.0. Not used.
- **depenguin-run**: MIT (https://github.com/depenguin-me/depenguin-run). Pattern reference only; no code copied.

## License compatibility

All code written in this repo is BSD-2-Clause.
Runtime-fetched components (mfsBSD, FreeBSD) are also BSD-2-Clause.
QEMU is installed from the distro's package manager in the rescue environment
and is not linked with, vendored in, or distributed by this project.
GPL contamination risk: none.
