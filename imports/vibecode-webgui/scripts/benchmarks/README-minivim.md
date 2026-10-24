# MiniVim Kernel Build System

This directory contains the build system for creating minimal Linux kernels optimized for fast boot benchmarks in virtualized environments.

## Overview

The MiniVim kernel build system creates highly optimized, minimal Linux kernels for three architectures:
- **x86_64**: Intel/AMD processors (for HVF/KVM)
- **arm64**: Apple Silicon and ARM64 servers (for Virtualization.framework)
- **armv7**: Raspberry Pi and ARMv7 devices

## Quick Start

```bash
# Build x86_64 kernel (pinned to 6.17.14)
./scripts/benchmarks/build-minivim-kernel-6.17.sh x86_64

# Build ARM64 kernel
./scripts/benchmarks/build-minivim-kernel-6.17.sh arm64

# Build ARMv7 kernel
./scripts/benchmarks/build-minivim-kernel-6.17.sh armv7
```

> Need a different kernel revision? Pass it as the second argument or call
> `build-minivim-kernel.sh` directly. The wrapper defaults to Linux 6.17.14 but
> keeps override support for pre-release testing.

## Files

### Build Script
- `build-minivim-kernel.sh` - Main build script that downloads, configures, and compiles the kernel

### Configuration Fragments
Located in `kernel-configs/`:
- `minivim-base.config` - Base configuration shared across all architectures
  - Virtio drivers for virtualization
  - Minimal filesystem support (ext4, tmpfs, devtmpfs)
  - Serial console
  - Disables USB, sound, wireless, DRM, and other unnecessary subsystems
  
- `minivim-x86_64.config` - Intel/AMD specific optimizations
  - AVX/AVX2 support
  - Intel microcode
  - x2APIC
  - EFI stub support
  - KVM guest optimizations
  
- `minivim-arm64.config` - ARM64 specific optimizations
  - Apple SoC support
  - ARM64 PAN/BTI/PTR_AUTH
  - SVE (Scalable Vector Extension)
  - ARM64 errata workarounds
  - ARM GICv3 support
  
- `minivim-armv7.config` - ARMv7 specific optimizations
  - Raspberry Pi BCM2835 support
  - NEON/VFP support
  - Thumb-2 kernel
  - MMC/SD support for Pi

## Build Process

The build script performs the following steps:

1. **Download**: Fetches the specified kernel version from kernel.org
2. **Extract**: Unpacks the kernel source to `artifacts/minivim/work/`
3. **Configure**:
   - Starts with `tinyconfig` (minimal base)
   - Merges `minivim-base.config` (common features)
   - Merges architecture-specific config
4. **Build**: Compiles using clang/LLVM if available, otherwise gcc
5. **Output**: Copies the kernel image to `bench-images/minivim/`
6. **Document**: Captures CPU info for build documentation

## Output Files

After building, you'll find in `bench-images/minivim/`:
- `bzImage-x86_64-<version>` - x86_64 compressed kernel
- `Image-arm64-<version>` - ARM64 uncompressed kernel
- `zImage-armv7-<version>` - ARMv7 compressed kernel
- `cpuinfo-<arch>.txt` - CPU information from build host

## Environment Variables

- `SKIP_MRPROPER` - Set to `1` to skip `make mrproper` for incremental builds (default: `0`)
- `MINIVIM_JOBS` - Number of parallel build jobs (default: `nproc`)
- `CROSS_COMPILE` - Cross-compiler prefix (e.g., `aarch64-linux-gnu-`)

## 6.17.14 Build & Logging Workflow

```bash
mkdir -p reports/benchmarks/minivim-6.17.14

# Clean build (downloads sources on first run)
SKIP_MRPROPER=0 \
MINIVIM_JOBS=${MINIVIM_JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || nproc)} \
./scripts/benchmarks/build-minivim-kernel-6.17.sh x86_64 \
  2>&1 | tee reports/benchmarks/minivim-6.17.14/build-clean.log

# Incremental rebuild after tweaking configs
SKIP_MRPROPER=1 \
MINIVIM_JOBS=${MINIVIM_JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || nproc)} \
./scripts/benchmarks/build-minivim-kernel-6.17.sh x86_64 \
  2>&1 | tee -a reports/benchmarks/minivim-6.17.14/build-incremental.log

# Capture boot-latency metrics for the new image
python3 scripts/benchmarks/boot_latency_bench.py \
  --kernel bench-images/minivim/bzImage-x86_64-6.17.14 \
  --report reports/benchmarks/minivim-6.17.14/boot-latency.json

# Optional: push metrics to Datadog
python3 scripts/benchmarks/firecracker_bench.py \
  --kernel bench-images/minivim/bzImage-x86_64-6.17.14 \
  --report reports/benchmarks/minivim-6.17.14/firecracker.json \
  --dogstatsd localhost:8125
```

Artifacts land in `bench-images/minivim/` (`bzImage-x86_64-6.17.14`, etc.) while
the structured logs above keep a reproducible record of build performance.

## CI/CD Integration

The GitHub Actions workflow `.github/workflows/minivim-build.yml` automatically builds all three architectures on:
- Push to `minivim-refresh` branch
- Manual workflow dispatch

The workflow:
1. Installs cross-compilation toolchains
2. Builds kernels for all architectures in parallel
3. Collects artifacts (kernel images, CPU info, BusyBox initrd)
4. Uploads per-architecture artifacts

## Performance Goals

- **Boot time**: < 3 seconds from kernel start to vi prompt
- **Kernel size**: Minimal (typically 5-10 MB compressed)
- **Features**: Only what's needed for virtualized environments
- **Compatibility**: Works with QEMU, HVF, KVM, Virtualization.framework

## BusyBox Integration

The x86_64 build uses a BusyBox initramfs from `bench-images/busybox/busybox-initramfs.cpio.gz`. This provides a minimal userspace with:
- Basic shell (sh)
- Essential utilities (ls, cat, echo, mount, etc.)
- vi editor for benchmarking

See `bench-images/busybox/README.md` for details on creating custom initramfs images.

## Troubleshooting

### Build fails with "No such file or directory"
- Ensure you're running from the repository root
- Check that `scripts/benchmarks/kernel-configs/` exists with config files

### Cross-compilation fails
- Install required cross-compiler packages:
  ```bash
  # Ubuntu/Debian
  sudo apt-get install gcc-aarch64-linux-gnu gcc-arm-linux-gnueabihf
  
  # macOS (via Homebrew)
  brew install aarch64-elf-gcc arm-none-eabi-gcc
  ```

### Kernel doesn't boot
- Check that virtio drivers are enabled in the config
- Verify the initramfs is properly formatted
- Ensure the hypervisor supports the kernel features

## Advanced Usage

### Incremental Builds
```bash
# Skip mrproper for faster rebuilds
SKIP_MRPROPER=1 ./scripts/benchmarks/build-minivim-kernel-6.17.sh x86_64
```

### Custom Job Count
```bash
# Limit to 4 cores
MINIVIM_JOBS=4 ./scripts/benchmarks/build-minivim-kernel-6.17.sh x86_64
```

### Cross-Compilation
```bash
# Build ARM64 on x86_64 host
CROSS_COMPILE=aarch64-linux-gnu- ./scripts/benchmarks/build-minivim-kernel-6.17.sh arm64
```

### Using ccache
```bash
# Speed up rebuilds with ccache
export CC="ccache clang"
export KCFLAGS="-pipe"
./scripts/benchmarks/build-minivim-kernel-6.17.sh x86_64
```

## References

- [Linux Kernel Documentation](https://www.kernel.org/doc/)
- [Virtio Specification](https://docs.oasis-open.org/virtio/virtio/v1.1/virtio-v1.1.html)
- [BusyBox Documentation](https://busybox.net/about.html)
- [QEMU Documentation](https://www.qemu.org/docs/master/)

## Related Files

- `.github/workflows/minivim-build.yml` - CI workflow
- `bench-images/minivim/README.md` - Output directory documentation
- `bench-images/busybox/README.md` - BusyBox initramfs documentation
- `docs/virtualization/minivim-kernel.md` - Detailed kernel build notes
