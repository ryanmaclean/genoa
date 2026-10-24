#!/usr/bin/env bash
set -euo pipefail

# Build a minimal kernel + initramfs tuned for vi launch benchmarks.
# Usage: ./scripts/benchmarks/build-minivim-kernel.sh [x86_64|arm64|armv7] [kernel_version]

ARCH_TARGET=${1:-x86_64}
KERNEL_VERSION=${2:-6.12.10}

SUPPORTED_ARCHES=(x86_64 arm64 armv7)
if [[ ! " ${SUPPORTED_ARCHES[*]} " =~ " ${ARCH_TARGET} " ]]; then
  echo "error: unsupported arch '${ARCH_TARGET}'. choose from: ${SUPPORTED_ARCHES[*]}" >&2
  exit 1
fi

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
BUILD_ROOT="${REPO_ROOT}/bench-images/minivim"
SRC_DIR="${BUILD_ROOT}/linux-${KERNEL_VERSION}"
CONFIG_DIR="${REPO_ROOT}/scripts/benchmarks/kernel-configs"

SKIP_MRPROPER=${SKIP_MRPROPER:-0}

if command -v gmake >/dev/null 2>&1; then
  MAKE_BIN=$(command -v gmake)
else
  MAKE_BIN=$(command -v make)
fi

JOBS=${MINIVIM_JOBS:-}
if [[ -z "${JOBS}" ]]; then
  if command -v nproc >/dev/null 2>&1; then
    JOBS=$(nproc)
  elif command -v sysctl >/dev/null 2>&1; then
    JOBS=$(sysctl -n hw.logicalcpu)
  else
    JOBS=4
  fi
fi

mkdir -p "${BUILD_ROOT}"

KERNEL_TARBALL="linux-${KERNEL_VERSION}.tar.xz"
KERNEL_URL="https://cdn.kernel.org/pub/linux/kernel/v6.x/${KERNEL_TARBALL}"
if [[ ! -f "${BUILD_ROOT}/${KERNEL_TARBALL}" ]]; then
  curl -L "${KERNEL_URL}" -o "${BUILD_ROOT}/${KERNEL_TARBALL}"
fi

if [[ ! -d "${SRC_DIR}" ]]; then
  tar -C "${BUILD_ROOT}" --no-same-owner -xf "${BUILD_ROOT}/${KERNEL_TARBALL}"
fi

pushd "${SRC_DIR}" >/dev/null

# Detect host CPU features for informational logging.
CPU_INFO_FILE="${BUILD_ROOT}/cpuinfo-${ARCH_TARGET}.txt"
if command -v lscpu >/dev/null 2>&1; then
  lscpu >"${CPU_INFO_FILE}" || true
elif [[ "${ARCH_TARGET}" == "x86_64" ]] && command -v sysctl >/dev/null 2>&1; then
  sysctl -a | grep machdep.cpu >"${CPU_INFO_FILE}" || true
fi

defconfig_target="${ARCH_TARGET}"
case "${ARCH_TARGET}" in
  x86_64)
    DEFCONFIG="x86_64_defconfig"
    ;;
  arm64)
    DEFCONFIG="defconfig"
    ;;
  armv7)
    DEFCONFIG="multi_v7_defconfig"
    ;;
esac

if [[ "${SKIP_MRPROPER}" != "1" ]]; then
  "${MAKE_BIN}" ARCH="${ARCH_TARGET}" mrproper
fi

"${MAKE_BIN}" ARCH="${ARCH_TARGET}" "${DEFCONFIG}"

# Merge common + arch-specific fragments.
MERGE_FILES=(
  "${CONFIG_DIR}/minivim-base.config"
  "${CONFIG_DIR}/minivim-${ARCH_TARGET}.config"
)
./scripts/kconfig/merge_config.sh -m .config "${MERGE_FILES[@]}"
INITRAMFS_SRC="${REPO_ROOT}/bench-images/apple-vf/rootfs"
if [[ -d "${INITRAMFS_SRC}" ]]; then
  ./scripts/config --set-str INITRAMFS_SOURCE "${INITRAMFS_SRC}"
fi
"${MAKE_BIN}" ARCH="${ARCH_TARGET}" olddefconfig

# Drop objtool / ORC requirements for lightweight build.
if [[ "${ARCH_TARGET}" == "x86_64" ]]; then
  ./scripts/config --disable UNWINDER_ORC --disable STACK_VALIDATION
  "${MAKE_BIN}" ARCH="${ARCH_TARGET}" olddefconfig
fi

# Build the kernel image.
case "${ARCH_TARGET}" in
  x86_64)
    MAKEFLAGS=(ARCH=x86_64 -j"${JOBS}" bzImage)
    ;;
  arm64)
    MAKEFLAGS=(ARCH=arm64 -j"${JOBS}" Image)
    ;;
  armv7)
    MAKEFLAGS=(ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j"${JOBS}" zImage)
    ;;
esac

"${MAKE_BIN}" "${MAKEFLAGS[@]}"

# Copy artifacts to bench-images/minivim
case "${ARCH_TARGET}" in
  x86_64)
    cp arch/x86/boot/bzImage "${BUILD_ROOT}/bzImage-${ARCH_TARGET}-${KERNEL_VERSION}"
    ;;
  arm64)
    cp arch/arm64/boot/Image "${BUILD_ROOT}/Image-${ARCH_TARGET}-${KERNEL_VERSION}"
    ;;
  armv7)
    cp arch/arm/boot/zImage "${BUILD_ROOT}/zImage-${ARCH_TARGET}-${KERNEL_VERSION}"
    ;;
esac

popd >/dev/null

echo "Kernel build complete. Artifacts saved in ${BUILD_ROOT}."
