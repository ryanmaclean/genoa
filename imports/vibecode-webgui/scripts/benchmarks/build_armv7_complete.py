#!/usr/bin/env python3
from __future__ import annotations

# Datadog Unified Service Tagging
_dd_service = "bench-build-armv7-complete"
_dd_env = __import__("os").environ.get("DD_ENV", "development")
_dd_version = __import__("os").environ.get("DD_VERSION", "0.1.0")
try:
    from ddtrace import config as _dd_config, patch_all as _dd_patch, tracer as _dd_tracer
    _dd_config.service = _dd_service
    _dd_config.env = _dd_env
    _dd_config.version = _dd_version
    _dd_tracer.set_tags({"team": "platform", "component": "benchmarks"})
    _dd_patch()
except ImportError:
    pass


# Datadog Log Aggregation
from scripts.lib.log_aggregation import get_log_aggregation


# Initialize log aggregation
log_agg = get_log_aggregation()

"""Complete ARMv7 6.17.x kernel build and validation workflow.

Usage:
    python build_armv7_complete.py [options]

Options:
    --skip-build      Skip kernel build (use existing kernel)
    --skip-validate   Skip validation
    --kernel-version  Override kernel version (default: 6.17.14)
"""


# -- VibeCode Telemetry --
import sys
import os
try:
    sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '../')))
    from vibecode.telemetry import init_telemetry
    tracer = init_telemetry(os.path.basename(__file__))
except ImportError:
    pass
# ------------------------


# Datadog APM tracing
try:
    from ddtrace import patch_all
    patch_all()
except ImportError:
    pass  # ddtrace not installed


import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

try:
    from .benchmark_utils import (
        REPO_ROOT,
        check_command,
        detect_cpu_count,
        get_iso_timestamp,
        run_cmd,
        success,
        warn,
        error as log_error,
    )
except ImportError:
    sys.path.insert(0, str(Path(__file__).parent))
    from benchmark_utils import (
        REPO_ROOT,
        check_command,
        detect_cpu_count,
        get_iso_timestamp,
        run_cmd,
        success,
        warn,
        error as log_error,
    )


DEFAULT_KERNEL_VERSION = "6.17.14"


def check_dependencies() -> list[str]:
    """Check for required dependencies.

    Returns:
        List of missing dependencies
    """
    missing = []

    required = ["make", "bc", "curl"]
    for cmd in required:
        if not check_command(cmd):
            missing.append(cmd)

    # Check for cross-compilation toolchain
    if not check_command("arm-linux-gnueabihf-gcc"):
        warn("Cross-compilation toolchain not found")
        print("   Install with: sudo apt-get install gcc-arm-linux-gnueabihf")
        missing.append("gcc-arm-linux-gnueabihf")

    return missing


def build_kernel(kernel_version: str, jobs: int) -> tuple[int, int]:
    """Build the ARMv7 kernel.

    Returns:
        Tuple of (build_minutes, build_seconds)
    """
    env = os.environ.copy()
    env["MINIVIM_JOBS"] = str(jobs)
    env["SKIP_MRPROPER"] = os.environ.get("SKIP_MRPROPER", "0")
    env["CROSS_COMPILE"] = os.environ.get("CROSS_COMPILE", "arm-linux-gnueabihf-")

    # Use clang if available with ccache
    if check_command("clang"):
        env["CC"] = "ccache clang" if check_command("ccache") else "clang"
        env["KCFLAGS"] = "-pipe"

    print("Build configuration:")
    print(f"  Jobs: {jobs}")
    print(f"  Cross compile: {env.get('CROSS_COMPILE', 'native')}")
    print(f"  Compiler: {env.get('CC', 'gcc')}")
    print()

    start = time.time()

    # Use Python build script if available
    try:
        from .build_minivim_kernel import main as build_main
        build_main(["armv7", kernel_version])
    except ImportError:
        # Fall back to shell script
        run_cmd(
            [str(REPO_ROOT / "scripts" / "benchmarks" / "build-minivim-kernel.sh"), "armv7", kernel_version],
            env=env,
        )

    duration = int(time.time() - start)
    return duration // 60, duration % 60


def validate_kernel(kernel_version: str) -> bool:
    """Run kernel validation.

    Returns:
        True if validation passed
    """
    try:
        from .validate_armv7_kernel import main as validate_main
        return validate_main([kernel_version]) == 0
    except ImportError:
        # Fall back to shell script
        result = run_cmd(
            [str(REPO_ROOT / "scripts" / "benchmarks" / "validate-armv7-kernel.sh"), kernel_version],
            check=False,
        )
        return result.returncode == 0


def main(argv: list[str] | None = None) -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip kernel build (use existing kernel)",
    )
    parser.add_argument(
        "--skip-validate",
        action="store_true",
        help="Skip validation",
    )
    parser.add_argument(
        "--kernel-version",
        default=DEFAULT_KERNEL_VERSION,
        help=f"Kernel version (default: {DEFAULT_KERNEL_VERSION})",
    )

    args = parser.parse_args(argv)

    print("\u2554" + "\u2550" * 64 + "\u2557")
    print("\u2551       ARMv7 6.17.x Complete Build & Validation Workflow       \u2551")
    print("\u255a" + "\u2550" * 64 + "\u255d")
    print()
    print("Configuration:")
    print(f"  Kernel Version: {args.kernel_version}")
    print(f"  Skip Build: {args.skip_build}")
    print(f"  Skip Validate: {args.skip_validate}")
    print()

    start_time = time.time()

    # Phase 1: Dependency Check
    print("=" * 64)
    print("Phase 1: Checking build dependencies")
    print("=" * 64)

    missing = check_dependencies()

    if missing:
        log_error(f"Missing required dependencies: {', '.join(missing)}")
        return 1

    success("All required dependencies found")

    # Check recommended tools
    recommended = []
    if not check_command("clang"):
        recommended.append("clang")
    if not check_command("ccache"):
        recommended.append("ccache")

    if recommended:
        print(f"   Recommended tools not found: {', '.join(recommended)}")
        print(f"   Install with: sudo apt-get install {' '.join(recommended)}")

    # Phase 2: Kernel Build
    jobs = int(os.environ.get("MINIVIM_JOBS", detect_cpu_count()))
    build_minutes = 0
    build_seconds = 0

    if not args.skip_build:
        print()
        print("=" * 64)
        print("Phase 2: Building ARMv7 kernel")
        print("=" * 64)

        build_minutes, build_seconds = build_kernel(args.kernel_version, jobs)

        print()
        success(f"Kernel build completed in {build_minutes}m {build_seconds}s")
    else:
        print()
        print("=" * 64)
        print("Phase 2: Skipping kernel build (--skip-build)")
        print("=" * 64)

    # Phase 3: Validation
    if not args.skip_validate:
        print()
        print("=" * 64)
        print("Phase 3: Validating kernel build")
        print("=" * 64)

        if not validate_kernel(args.kernel_version):
            log_error("Validation failed")
            return 1
    else:
        print()
        print("=" * 64)
        print("Phase 3: Skipping validation (--skip-validate)")
        print("=" * 64)

    # Phase 4: Artifact Organization
    print()
    print("=" * 64)
    print("Phase 4: Organizing artifacts")
    print("=" * 64)

    artifacts_dir = REPO_ROOT / "artifacts" / "minivim"
    output_dir = REPO_ROOT / "bench-images" / "minivim"
    artifacts_dir.mkdir(parents=True, exist_ok=True)

    # Copy kernel image
    kernel_image = output_dir / f"zImage-armv7-{args.kernel_version}"
    if kernel_image.exists():
        import shutil
        shutil.copy(kernel_image, artifacts_dir)
        success(f"Kernel image: {artifacts_dir}/zImage-armv7-{args.kernel_version}")

    # Copy CPU info if available
    cpu_info = output_dir / "cpuinfo-armv7.txt"
    if cpu_info.exists():
        import shutil
        shutil.copy(cpu_info, artifacts_dir)
        success(f"CPU info: {artifacts_dir}/cpuinfo-armv7.txt")

    # Check validation report
    validation_report = artifacts_dir / f"armv7-validation-{args.kernel_version}.json"
    if validation_report.exists():
        success(f"Validation report: {validation_report}")

    # Generate build manifest
    manifest_path = artifacts_dir / f"build-manifest-armv7-{args.kernel_version}.txt"
    with open(manifest_path, "w") as f:
        f.write("ARMv7 MiniVim Kernel Build Manifest\n")
        f.write("=" * 40 + "\n\n")
        f.write(f"Build Date: {get_iso_timestamp()}\n")
        f.write(f"Kernel Version: {args.kernel_version}\n")
        f.write("Architecture: armv7 (32-bit ARM)\n\n")
        f.write("Build Configuration:\n")
        f.write(f"- Jobs: {jobs}\n")
        f.write(f"- Cross Compile: {os.environ.get('CROSS_COMPILE', 'native')}\n")
        f.write(f"- Compiler: {os.environ.get('CC', 'gcc')}\n")
        f.write(f"- Skip mrproper: {os.environ.get('SKIP_MRPROPER', '0')}\n\n")
        f.write(f"Build Time: {build_minutes}m {build_seconds}s\n\n")
        f.write("Artifacts:\n")
        f.write(f"- Kernel: zImage-armv7-{args.kernel_version}\n")
        f.write("- CPU Info: cpuinfo-armv7.txt\n")
        f.write(f"- Validation: armv7-validation-{args.kernel_version}.json\n\n")
        f.write("Builder System:\n")
        f.write(os.uname().sysname + " " + os.uname().release + "\n")

        if check_command("lscpu"):
            f.write("\nCPU Information:\n")
            try:
                result = subprocess.run(["lscpu"], capture_output=True, text=True)
                f.write("\n".join(result.stdout.split("\n")[:20]))
            except Exception:
                pass

    success(f"Build manifest: {manifest_path}")

    # Summary
    total_time = int(time.time() - start_time)
    total_minutes = total_time // 60
    total_seconds = total_time % 60

    print()
    print("\u2554" + "\u2550" * 64 + "\u2557")
    print("\u2551                     Workflow Complete \u2705                        \u2551")
    print("\u255a" + "\u2550" * 64 + "\u255d")
    print()
    print("Summary:")
    print(f"  Total Time: {total_minutes}m {total_seconds}s")
    print(f"  Artifacts: {artifacts_dir}/")
    print()
    print("Next Steps:")
    print(f"  1. Review artifacts in {artifacts_dir}/")
    print("  2. Test kernel boot with QEMU (if available)")
    print("  3. Run benchmarks: python3 scripts/benchmarks/boot_latency_bench.py")
    print("  4. Update documentation: docs/virtualization/minivim-kernel.md")
    print("  5. Attach artifacts to release bundle")
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())