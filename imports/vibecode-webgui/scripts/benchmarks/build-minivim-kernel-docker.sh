#!/usr/bin/env bash
# Build MiniVim kernel in Alpine Docker (avoids macOS Make issues)

set -euo pipefail

ARCH="${1:-x86_64}"
KERNEL_VERSION="${2:-6.17.4}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "Building kernel ${KERNEL_VERSION} in Alpine Docker..."

docker run --rm \
  -v "${REPO_ROOT}:/work" \
  -w /work \
  alpine:latest \
  sh -c "
    apk add --no-cache build-base linux-headers flex bison bc perl elfutils-dev openssl-dev
    
    mkdir -p artifacts/minivim/work
    cd artifacts/minivim/work
    
    # Download kernel if needed
    if [ ! -d linux-${KERNEL_VERSION} ]; then
      wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KERNEL_VERSION}.tar.xz
      tar xf linux-${KERNEL_VERSION}.tar.xz
      rm linux-${KERNEL_VERSION}.tar.xz
    fi
    
    cd linux-${KERNEL_VERSION}
    make mrproper
    make ARCH=${ARCH} tinyconfig
    
    # Merge kernel configs
    scripts/kconfig/merge_config.sh -m .config \
      /work/scripts/benchmarks/kernel-configs/minivim-base.config \
      /work/scripts/benchmarks/kernel-configs/minivim-${ARCH}.config
    
    yes '' | make ARCH=${ARCH} olddefconfig
    make ARCH=${ARCH} -j\$(nproc) bzImage
    
    # Copy output
    mkdir -p /work/bench-images/minivim
    cp arch/x86/boot/bzImage /work/bench-images/minivim/vmlinuz-${KERNEL_VERSION}-musl
    
    echo '=== Build Complete ==='
    ls -lh /work/bench-images/minivim/vmlinuz-${KERNEL_VERSION}-musl
  "
