#!/usr/bin/env bash
# Complete ARMv7 6.17.x kernel build and validation workflow
# Usage: ./build-armv7-6.17-complete.sh [options]
# Options:
#   --skip-build     Skip kernel build (use existing kernel)
#   --skip-validate  Skip validation
#   --kernel-version VERSION  Override kernel version (default: 6.17.14)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Default configuration
KERNEL_VERSION="6.17.14"
SKIP_BUILD=0
SKIP_VALIDATE=0

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --skip-validate)
            SKIP_VALIDATE=1
            shift
            ;;
        --kernel-version)
            KERNEL_VERSION="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--skip-build] [--skip-validate] [--kernel-version VERSION]"
            exit 1
            ;;
    esac
done

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║       ARMv7 6.17.x Complete Build & Validation Workflow       ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Configuration:"
echo "  Kernel Version: ${KERNEL_VERSION}"
echo "  Skip Build: ${SKIP_BUILD}"
echo "  Skip Validate: ${SKIP_VALIDATE}"
echo ""

START_TIME=$(date +%s)

# Phase 1: Dependency Check
echo "═══════════════════════════════════════════════════════════════"
echo "Phase 1: Checking build dependencies"
echo "═══════════════════════════════════════════════════════════════"

MISSING_DEPS=()

# Check for required tools
if ! command -v make &> /dev/null; then
    MISSING_DEPS+=("make")
fi

if ! command -v bc &> /dev/null; then
    MISSING_DEPS+=("bc")
fi

if ! command -v curl &> /dev/null; then
    MISSING_DEPS+=("curl")
fi

# Check for cross-compilation toolchain
if ! command -v arm-linux-gnueabihf-gcc &> /dev/null; then
    echo "⚠️  Cross-compilation toolchain not found"
    echo "   Install with: sudo apt-get install gcc-arm-linux-gnueabihf"
    MISSING_DEPS+=("gcc-arm-linux-gnueabihf")
fi

# Check for optional but recommended tools
RECOMMENDED=()
if ! command -v clang &> /dev/null; then
    RECOMMENDED+=("clang")
fi

if ! command -v ccache &> /dev/null; then
    RECOMMENDED+=("ccache")
fi

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "❌ Missing required dependencies: ${MISSING_DEPS[*]}"
    exit 1
fi

echo "✓ All required dependencies found"

if [ ${#RECOMMENDED[@]} -gt 0 ]; then
    echo "ℹ️  Recommended tools not found: ${RECOMMENDED[*]}"
    echo "   Install with: sudo apt-get install ${RECOMMENDED[*]}"
fi

# Phase 2: Kernel Build
if [ ${SKIP_BUILD} -eq 0 ]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Phase 2: Building ARMv7 kernel"
    echo "═══════════════════════════════════════════════════════════════"
    
    BUILD_START=$(date +%s)
    
    # Set optimal build configuration
    export MINIVIM_JOBS=${MINIVIM_JOBS:-$(nproc 2>/dev/null || echo 4)}
    export SKIP_MRPROPER=${SKIP_MRPROPER:-0}
    export CROSS_COMPILE=${CROSS_COMPILE:-arm-linux-gnueabihf-}
    
    # Use clang if available with ccache
    if command -v clang &> /dev/null; then
        export CC="ccache clang"
        export KCFLAGS="-pipe"
    fi
    
    echo "Build configuration:"
    echo "  Jobs: ${MINIVIM_JOBS}"
    echo "  Cross compile: ${CROSS_COMPILE}"
    echo "  Compiler: ${CC:-gcc}"
    echo ""
    
    # Execute kernel build
    "${SCRIPT_DIR}/build-minivim-kernel.sh" armv7 "${KERNEL_VERSION}"
    
    BUILD_END=$(date +%s)
    BUILD_TIME=$((BUILD_END - BUILD_START))
    BUILD_MINUTES=$((BUILD_TIME / 60))
    BUILD_SECONDS=$((BUILD_TIME % 60))
    
    echo ""
    echo "✓ Kernel build completed in ${BUILD_MINUTES}m ${BUILD_SECONDS}s"
else
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Phase 2: Skipping kernel build (--skip-build)"
    echo "═══════════════════════════════════════════════════════════════"
fi

# Phase 3: Validation
if [ ${SKIP_VALIDATE} -eq 0 ]; then
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Phase 3: Validating kernel build"
    echo "═══════════════════════════════════════════════════════════════"
    
    "${SCRIPT_DIR}/validate-armv7-kernel.sh" "${KERNEL_VERSION}"
else
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "Phase 3: Skipping validation (--skip-validate)"
    echo "═══════════════════════════════════════════════════════════════"
fi

# Phase 4: Artifact Organization
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Phase 4: Organizing artifacts"
echo "═══════════════════════════════════════════════════════════════"

ARTIFACTS_DIR="${REPO_ROOT}/artifacts/minivim"
OUTPUT_DIR="${REPO_ROOT}/bench-images/minivim"
mkdir -p "${ARTIFACTS_DIR}"

# Copy kernel image
KERNEL_IMAGE="${OUTPUT_DIR}/zImage-armv7-${KERNEL_VERSION}"
if [ -f "${KERNEL_IMAGE}" ]; then
    cp "${KERNEL_IMAGE}" "${ARTIFACTS_DIR}/"
    echo "✓ Kernel image: ${ARTIFACTS_DIR}/zImage-armv7-${KERNEL_VERSION}"
fi

# Copy CPU info if available
if [ -f "${OUTPUT_DIR}/cpuinfo-armv7.txt" ]; then
    cp "${OUTPUT_DIR}/cpuinfo-armv7.txt" "${ARTIFACTS_DIR}/"
    echo "✓ CPU info: ${ARTIFACTS_DIR}/cpuinfo-armv7.txt"
fi

# Copy validation report if available
if [ -f "${ARTIFACTS_DIR}/armv7-validation-${KERNEL_VERSION}.json" ]; then
    echo "✓ Validation report: ${ARTIFACTS_DIR}/armv7-validation-${KERNEL_VERSION}.json"
fi

# Generate build manifest
MANIFEST="${ARTIFACTS_DIR}/build-manifest-armv7-${KERNEL_VERSION}.txt"
cat > "${MANIFEST}" << EOF
ARMv7 MiniVim Kernel Build Manifest
====================================

Build Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Kernel Version: ${KERNEL_VERSION}
Architecture: armv7 (32-bit ARM)

Build Configuration:
- Jobs: ${MINIVIM_JOBS:-N/A}
- Cross Compile: ${CROSS_COMPILE:-native}
- Compiler: ${CC:-gcc}
- Skip mrproper: ${SKIP_MRPROPER:-0}

Build Time: ${BUILD_MINUTES:-N/A}m ${BUILD_SECONDS:-N/A}s

Artifacts:
- Kernel: zImage-armv7-${KERNEL_VERSION}
- CPU Info: cpuinfo-armv7.txt
- Validation: armv7-validation-${KERNEL_VERSION}.json

Builder System:
$(uname -a)

EOF

if command -v lscpu &> /dev/null; then
    echo "CPU Information:" >> "${MANIFEST}"
    lscpu | head -20 >> "${MANIFEST}"
fi

echo "✓ Build manifest: ${MANIFEST}"

# Summary
END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
TOTAL_MINUTES=$((TOTAL_TIME / 60))
TOTAL_SECONDS=$((TOTAL_TIME % 60))

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                     Workflow Complete ✅                        ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo "Summary:"
echo "  Total Time: ${TOTAL_MINUTES}m ${TOTAL_SECONDS}s"
echo "  Artifacts: ${ARTIFACTS_DIR}/"
echo ""
echo "Next Steps:"
echo "  1. Review artifacts in ${ARTIFACTS_DIR}/"
echo "  2. Test kernel boot with QEMU (if available)"
echo "  3. Run benchmarks: python3 scripts/benchmarks/boot_latency_bench.py"
echo "  4. Update documentation: docs/virtualization/minivim-kernel.md"
echo "  5. Attach artifacts to release bundle"
echo ""
