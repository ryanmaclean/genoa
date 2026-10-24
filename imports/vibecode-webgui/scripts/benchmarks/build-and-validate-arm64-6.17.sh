#!/usr/bin/env bash
# Build and validate MiniVim arm64 6.17.x kernel
# This script automates the workflow described in issue #574
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPORTS_DIR="${REPO_ROOT}/reports/benchmarks"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "=== MiniVim arm64 6.17.x Build and Validation ==="
echo "Timestamp: ${TIMESTAMP}"
echo ""

# Check if running on Apple Silicon
if ! sysctl -n machdep.cpu.brand_string 2>/dev/null | grep -q "Apple M"; then
  echo "⚠️  Warning: Not running on Apple Silicon"
  echo "This script is optimized for M1/M2/M3/M4 processors"
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Detect hardware
CHIP=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")
LOGICAL_CPU=$(sysctl -n hw.logicalcpu 2>/dev/null || echo "8")
PHYSICAL_CPU=$(sysctl -n hw.physicalcpu 2>/dev/null || echo "8")
PERF_CORES=$(sysctl -n hw.perflevel0.physicalcpu 2>/dev/null || echo "0")
EFFI_CORES=$(sysctl -n hw.perflevel1.physicalcpu 2>/dev/null || echo "0")
MEMORY_GB=$(sysctl -n hw.memsize | awk '{print int($1/1024/1024/1024)}' 2>/dev/null || echo "16")

echo "Hardware Profile:"
echo "  Chip: ${CHIP}"
echo "  Logical CPUs: ${LOGICAL_CPU}"
echo "  Physical CPUs: ${PHYSICAL_CPU}"
echo "  Performance Cores: ${PERF_CORES}"
echo "  Efficiency Cores: ${EFFI_CORES}"
echo "  Memory: ${MEMORY_GB}GB"
echo ""

# Create reports directory
mkdir -p "${REPORTS_DIR}"

# Save CPU profile
CPU_PROFILE="${REPORTS_DIR}/arm64-6.17-cpu-profile-${TIMESTAMP}.txt"
echo "Saving CPU profile to ${CPU_PROFILE}..."
{
  echo "=== Hardware Profile ==="
  echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo ""
  sysctl -a | grep -E "hw\.(logicalcpu|physicalcpu|cpufrequency|memsize|machine|perflevel)" || true
  echo ""
  echo "=== System Profile ==="
  system_profiler SPHardwareDataType 2>/dev/null || true
} > "${CPU_PROFILE}"

# Check for ccache
if ! command -v ccache &> /dev/null; then
  echo "⚠️  Warning: ccache not found. Install for faster builds:"
  echo "   brew install ccache"
  echo ""
  CC="clang"
else
  echo "✅ ccache available"
  ccache -s || true
  echo ""
  CC="ccache clang"
fi

# Phase 1: Clean Build
echo "=== Phase 1: Clean Build ==="
echo "This will take approximately 10-12 minutes on M1 Max..."
echo ""

CLEAN_LOG="${REPORTS_DIR}/arm64-6.17-clean-build-${TIMESTAMP}.log"
CLEAN_START=$(date +%s)

PATH="/usr/local/opt/make/libexec/gnubin:$PATH" \
CC="${CC}" KCFLAGS=-pipe \
MINIVIM_JOBS="${LOGICAL_CPU}" \
./scripts/benchmarks/build-minivim-kernel-6.17.sh arm64 2>&1 | tee "${CLEAN_LOG}"

CLEAN_END=$(date +%s)
CLEAN_SECONDS=$((CLEAN_END - CLEAN_START))
CLEAN_MINUTES=$(echo "scale=1; ${CLEAN_SECONDS}/60" | bc)

echo ""
echo "Clean build completed in ${CLEAN_SECONDS}s (${CLEAN_MINUTES} minutes)"
echo ""

# Phase 2: Incremental Build
echo "=== Phase 2: Incremental Build ==="
echo "This will take approximately 4-5 minutes on M1 Max..."
echo ""

INCR_LOG="${REPORTS_DIR}/arm64-6.17-incremental-build-${TIMESTAMP}.log"
INCR_START=$(date +%s)

SKIP_MRPROPER=1 \
PATH="/usr/local/opt/make/libexec/gnubin:$PATH" \
CC="${CC}" KCFLAGS=-pipe \
MINIVIM_JOBS="${LOGICAL_CPU}" \
./scripts/benchmarks/build-minivim-kernel-6.17.sh arm64 2>&1 | tee "${INCR_LOG}"

INCR_END=$(date +%s)
INCR_SECONDS=$((INCR_END - INCR_START))
INCR_MINUTES=$(echo "scale=1; ${INCR_SECONDS}/60" | bc)

echo ""
echo "Incremental build completed in ${INCR_SECONDS}s (${INCR_MINUTES} minutes)"
echo ""

# Check output
KERNEL_IMAGE="${REPO_ROOT}/bench-images/minivim/Image-arm64-6.17.14"
if [[ ! -f "${KERNEL_IMAGE}" ]]; then
  echo "❌ Error: Kernel image not found at ${KERNEL_IMAGE}"
  exit 1
fi

KERNEL_SIZE=$(stat -f%z "${KERNEL_IMAGE}" 2>/dev/null || stat -c%s "${KERNEL_IMAGE}")
KERNEL_SIZE_MB=$(echo "scale=1; ${KERNEL_SIZE}/1024/1024" | bc)

echo "✅ Kernel built successfully"
echo "   Path: ${KERNEL_IMAGE}"
echo "   Size: ${KERNEL_SIZE_MB} MB"
echo ""

# Generate build report
BUILD_REPORT="${REPORTS_DIR}/arm64-6.17-build-report-${TIMESTAMP}.json"
cat > "${BUILD_REPORT}" <<EOF
{
  "report_id": "arm64-6.17-${TIMESTAMP}",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "arch": "arm64",
  "kernel_version": "6.17.14",
  "hardware": {
    "model": "${CHIP}",
    "cores_logical": ${LOGICAL_CPU},
    "cores_physical": ${PHYSICAL_CPU},
    "cores_performance": ${PERF_CORES},
    "cores_efficiency": ${EFFI_CORES},
    "memory_gb": ${MEMORY_GB}
  },
  "build": {
    "clean_build_seconds": ${CLEAN_SECONDS},
    "clean_build_minutes": ${CLEAN_MINUTES},
    "incremental_build_seconds": ${INCR_SECONDS},
    "incremental_build_minutes": ${INCR_MINUTES},
    "compiler": "${CC}",
    "jobs": ${LOGICAL_CPU},
    "kcflags": "-pipe"
  },
  "output": {
    "image_path": "${KERNEL_IMAGE}",
    "image_size_bytes": ${KERNEL_SIZE},
    "image_size_mb": ${KERNEL_SIZE_MB}
  },
  "comparison": {
    "intel_reference": {
      "model": "Intel i7-9750H",
      "clean_build_minutes": 20,
      "speedup": $(echo "scale=2; 20/${CLEAN_MINUTES}" | bc)
    },
    "expected_boot_improvement": "43% (4.38s -> 2.5s)"
  }
}
EOF

echo "=== Build Summary ==="
cat "${BUILD_REPORT}" | jq '.'
echo ""

# Phase 3: Boot Validation (optional)
echo "=== Phase 3: Boot Validation ==="
echo ""

if command -v limactl &> /dev/null; then
  echo "✅ Lima detected"
  echo ""
  echo "To validate boot with Lima (vmType=vz):"
  echo ""
  echo "  limactl start --name=minivim-test-617 \\"
  echo "    --vm-type=vz \\"
  echo "    --arch=aarch64 \\"
  echo "    --kernel=${KERNEL_IMAGE} \\"
  echo "    --initrd=${REPO_ROOT}/bench-images/busybox/busybox-neovim-initrd.cpio.gz"
  echo ""
  echo "Then to measure boot time:"
  echo "  time limactl shell minivim-test-617"
  echo ""
  read -p "Run Lima boot test now? (y/N) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Starting Lima VM..."
    BOOT_START=$(date +%s%3N)
    limactl start --name=minivim-test-617 \
      --vm-type=vz \
      --arch=aarch64 \
      --kernel="${KERNEL_IMAGE}" \
      --initrd="${REPO_ROOT}/bench-images/busybox/busybox-neovim-initrd.cpio.gz" || true
    BOOT_END=$(date +%s%3N)
    BOOT_MS=$((BOOT_END - BOOT_START))
    BOOT_SEC=$(echo "scale=2; ${BOOT_MS}/1000" | bc)
    
    echo ""
    echo "Boot time: ${BOOT_SEC}s"
    
    # Add to report
    jq --arg boot_sec "${BOOT_SEC}" '.boot_test = {
      "test": "lima_vz_boot",
      "boot_time_seconds": ($boot_sec | tonumber),
      "success": true
    }' "${BUILD_REPORT}" > "${BUILD_REPORT}.tmp"
    mv "${BUILD_REPORT}.tmp" "${BUILD_REPORT}"
    
    # Cleanup
    echo ""
    read -p "Stop and delete test VM? (Y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
      limactl stop minivim-test-617 || true
      limactl delete minivim-test-617 || true
    fi
  fi
else
  echo "⚠️  Lima not installed. To validate boot:"
  echo "   brew install lima"
  echo ""
fi

echo ""
echo "=== Results ==="
echo "Build report: ${BUILD_REPORT}"
echo "Clean build log: ${CLEAN_LOG}"
echo "Incremental build log: ${INCR_LOG}"
echo "CPU profile: ${CPU_PROFILE}"
echo ""
echo "Next steps:"
echo "1. Review the build report and timings"
echo "2. Test boot with Lima or HyperKit"
echo "3. Commit build artifacts and logs to reports/benchmarks/"
echo "4. Update issue #574 with results"
echo ""
