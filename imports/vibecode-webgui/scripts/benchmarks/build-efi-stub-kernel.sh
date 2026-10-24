#!/usr/bin/env bash
# Build EFI-stub kernel for Apple Virtualization Framework fast boot
# The EFI-stub kernel boots directly from EFI without GRUB
set -euo pipefail

ARCH_TARGET=${1:-arm64}
KERNEL_VERSION=${2:-6.12.10}

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BUILD_ROOT="${REPO_ROOT}/bench-images/apple-vf-fastboot"
SRC_DIR="${BUILD_ROOT}/linux-${KERNEL_VERSION}"
CONFIG_DIR="${REPO_ROOT}/scripts/benchmarks/kernel-configs"
OUTPUT_DIR="${BUILD_ROOT}"

echo "=== Building EFI-stub Kernel for Apple VF ==="
echo "Architecture: $ARCH_TARGET"
echo "Kernel version: $KERNEL_VERSION"
echo ""

if [[ "$ARCH_TARGET" != "arm64" ]]; then
  echo "Error: Apple VF on Apple Silicon requires arm64 architecture"
  exit 1
fi

# Detect make command
if command -v gmake >/dev/null 2>&1; then
  MAKE_BIN=$(command -v gmake)
else
  MAKE_BIN=$(command -v make)
fi

# Determine parallel jobs
JOBS=${KERNEL_JOBS:-}
if [[ -z "$JOBS" ]]; then
  if command -v nproc >/dev/null 2>&1; then
    JOBS=$(nproc)
  elif command -v sysctl >/dev/null 2>&1; then
    JOBS=$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)
  else
    JOBS=4
  fi
fi

mkdir -p "$BUILD_ROOT"

# Download kernel source
KERNEL_TARBALL="linux-${KERNEL_VERSION}.tar.xz"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/${KERNEL_TARBALL}"

if [[ ! -f "${BUILD_ROOT}/${KERNEL_TARBALL}" ]]; then
  echo "Downloading kernel source..."
  curl -L "$KERNEL_URL" -o "${BUILD_ROOT}/${KERNEL_TARBALL}"
fi

if [[ ! -d "$SRC_DIR" ]]; then
  echo "Extracting kernel source..."
  tar -C "$BUILD_ROOT" --no-same-owner -xf "${BUILD_ROOT}/${KERNEL_TARBALL}"
fi

pushd "$SRC_DIR" >/dev/null

# Clean previous build
if [[ "${SKIP_MRPROPER:-0}" != "1" ]]; then
  "$MAKE_BIN" ARCH=arm64 mrproper
fi

# Start with arm64 defconfig
echo "Configuring kernel..."
"$MAKE_BIN" ARCH=arm64 defconfig

# Merge base minivim config
if [[ -f "${CONFIG_DIR}/minivim-base.config" ]]; then
  ./scripts/kconfig/merge_config.sh -m .config "${CONFIG_DIR}/minivim-base.config"
fi

# Merge arm64 config
if [[ -f "${CONFIG_DIR}/minivim-arm64.config" ]]; then
  ./scripts/kconfig/merge_config.sh -m .config "${CONFIG_DIR}/minivim-arm64.config"
fi

# Merge EFI-stub config
if [[ -f "${CONFIG_DIR}/efi-stub-arm64.config" ]]; then
  ./scripts/kconfig/merge_config.sh -m .config "${CONFIG_DIR}/efi-stub-arm64.config"
fi

# Ensure EFI-stub is enabled
./scripts/config --enable EFI
./scripts/config --enable EFI_STUB
./scripts/config --enable EFI_GENERIC_STUB

# Additional size optimizations
./scripts/config --enable CC_OPTIMIZE_FOR_SIZE
./scripts/config --disable DEBUG_KERNEL
./scripts/config --disable DEBUG_INFO
./scripts/config --disable MODULES

# Fast boot optimizations
./scripts/config --enable PRINTK
./scripts/config --set-str DEFAULT_INIT "/init"

# Finalize config
"$MAKE_BIN" ARCH=arm64 olddefconfig

echo ""
echo "Building kernel (this may take several minutes)..."
"$MAKE_BIN" ARCH=arm64 -j"$JOBS" Image

# Copy output
cp arch/arm64/boot/Image "${OUTPUT_DIR}/vmlinux-efi-stub"

# Calculate kernel size
KERNEL_SIZE=$(du -h "${OUTPUT_DIR}/vmlinux-efi-stub" | cut -f1)

popd >/dev/null

echo ""
echo "=== Build Complete ==="
echo "Kernel: ${OUTPUT_DIR}/vmlinux-efi-stub"
echo "Size: $KERNEL_SIZE"
echo ""
echo "To test fast boot:"
echo "  APPLEVF_KERNEL=${OUTPUT_DIR}/vmlinux-efi-stub \\"
echo "  ./scripts/benchmarks/applevf_fastboot_bench.sh bench 5"
