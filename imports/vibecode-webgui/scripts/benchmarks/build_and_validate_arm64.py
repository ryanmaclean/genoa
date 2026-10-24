#!/usr/bin/env python3
from __future__ import annotations

# Datadog Unified Service Tagging
_dd_service = "bench-build-and-validate-arm64"
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

"""Build and validate MiniVim arm64 6.17.x kernel.

This script automates the workflow described in issue #574.
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
import json
import os
import subprocess
import sys
import time
from pathlib import Path

try:
    from .benchmark_utils import (
        REPO_ROOT,
        check_command,
        get_hardware_info,
        get_iso_timestamp,
        get_timestamp,
        log,
        success,
        warn,
        error as log_error,
    )
except ImportError:
    sys.path.insert(0, str(Path(__file__).parent))
    from benchmark_utils import (
        REPO_ROOT,
        check_command,
        get_hardware_info,
        get_iso_timestamp,
        get_timestamp,
        log,
        success,
        warn,
        error as log_error,
    )


DEFAULT_KERNEL_VERSION = "6.17.14"


def run_build(
    arch: str,
    kernel_version: str,
    jobs: int,
    skip_mrproper: bool,
    cc: str,
) -> tuple[int, str]:
    """Run kernel build.

    Returns:
        Tuple of (duration_seconds, log_path)
    """
    env = os.environ.copy()
    env["MINIVIM_JOBS"] = str(jobs)
    env["CC"] = cc
    env["KCFLAGS"] = "-pipe"
    if skip_mrproper:
        env["SKIP_MRPROPER"] = "1"

    # Add GNU make to PATH if available
    gnumake_path = "/usr/local/opt/make/libexec/gnubin"
    if Path(gnumake_path).exists():
        env["PATH"] = f"{gnumake_path}:{env.get('PATH', '')}"

    log_path = REPO_ROOT / "reports" / "benchmarks" / f"arm64-{kernel_version}-build-{get_timestamp()}.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)

    start = time.time()

    with open(log_path, "w") as log_file:
        subprocess.run(
            [str(REPO_ROOT / "scripts" / "benchmarks" / "build-minivim-kernel-6.17.sh"), arch],
            env=env,
            stdout=log_file,
            stderr=subprocess.STDOUT,
        )

    duration = int(time.time() - start)
    return duration, str(log_path)


def main(argv: list[str] | None = None) -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--kernel-version",
        default=os.environ.get("KERNEL_VERSION", DEFAULT_KERNEL_VERSION),
        help=f"Kernel version (default: {DEFAULT_KERNEL_VERSION})",
    )
    parser.add_argument(
        "--skip-lima-test",
        action="store_true",
        help="Skip Lima boot test",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=REPO_ROOT / "reports" / "benchmarks",
        help="Output directory for reports",
    )

    args = parser.parse_args(argv)

    timestamp = get_timestamp()

    print("=== MiniVim arm64 6.17.x Build and Validation ===")
    print(f"Timestamp: {timestamp}")
    print()

    # Get hardware info
    hw = get_hardware_info()

    if not hw.is_apple_silicon:
        warn(f"Warning: Not running on Apple Silicon ({hw.chip})")
        response = input("Continue anyway? (y/N) ").strip().lower()
        if response != "y":
            return 1

    print("Hardware Profile:")
    print(f"  Chip: {hw.chip}")
    print(f"  Logical CPUs: {hw.logical_cpus}")
    print(f"  Physical CPUs: {hw.physical_cpus}")
    print(f"  Performance Cores: {hw.performance_cores}")
    print(f"  Efficiency Cores: {hw.efficiency_cores}")
    print(f"  Memory: {hw.memory_gb}GB")
    print()

    # Save CPU profile
    args.output_dir.mkdir(parents=True, exist_ok=True)
    cpu_profile_path = args.output_dir / f"arm64-{args.kernel_version}-cpu-profile-{timestamp}.txt"

    with open(cpu_profile_path, "w") as f:
        f.write("=== Hardware Profile ===\n")
        f.write(f"Timestamp: {get_iso_timestamp()}\n\n")
        if check_command("sysctl"):
            try:
                result = subprocess.run(["sysctl", "-a"], capture_output=True, text=True)
                for line in result.stdout.split("\n"):
                    if any(x in line for x in ["hw.logicalcpu", "hw.physicalcpu", "hw.cpufrequency", "hw.memsize", "hw.machine", "hw.perflevel"]):
                        f.write(line + "\n")
            except Exception:
                pass
        f.write("\n=== System Profile ===\n")
        try:
            result = subprocess.run(["system_profiler", "SPHardwareDataType"], capture_output=True, text=True)
            f.write(result.stdout)
        except Exception:
            pass

    log(f"Saving CPU profile to {cpu_profile_path}...")

    # Check for ccache
    if check_command("ccache"):
        success("ccache available")
        try:
            subprocess.run(["ccache", "-s"], capture_output=True)
        except Exception:
            pass
        print()
        cc = "ccache clang"
    else:
        warn("ccache not found. Install for faster builds:")
        print("   brew install ccache")
        print()
        cc = "clang"

    # Phase 1: Clean Build
    print("=== Phase 1: Clean Build ===")
    print()

    clean_duration, clean_log = run_build(
        arch="arm64",
        kernel_version=args.kernel_version,
        jobs=hw.logical_cpus,
        skip_mrproper=False,
        cc=cc,
    )
    clean_minutes = clean_duration / 60

    print()
    print(f"Clean build completed in {clean_duration}s ({clean_minutes:.1f} minutes)")
    print()

    # Phase 2: Incremental Build
    print("=== Phase 2: Incremental Build ===")
    print()

    incr_duration, incr_log = run_build(
        arch="arm64",
        kernel_version=args.kernel_version,
        jobs=hw.logical_cpus,
        skip_mrproper=True,
        cc=cc,
    )
    incr_minutes = incr_duration / 60

    print()
    print(f"Incremental build completed in {incr_duration}s ({incr_minutes:.1f} minutes)")
    print()

    # Check output
    kernel_image = REPO_ROOT / "bench-images" / "minivim" / f"Image-arm64-{args.kernel_version}"
    if not kernel_image.exists():
        log_error(f"Kernel image not found at {kernel_image}")
        return 1

    kernel_size = kernel_image.stat().st_size
    kernel_size_mb = kernel_size / (1024 * 1024)

    success("Kernel built successfully")
    print(f"   Path: {kernel_image}")
    print(f"   Size: {kernel_size_mb:.1f} MB")
    print()

    # Generate build report
    build_report = {
        "report_id": f"arm64-{args.kernel_version}-{timestamp}",
        "timestamp": get_iso_timestamp(),
        "arch": "arm64",
        "kernel_version": args.kernel_version,
        "hardware": hw.to_dict(),
        "build": {
            "clean_build_seconds": clean_duration,
            "clean_build_minutes": clean_minutes,
            "incremental_build_seconds": incr_duration,
            "incremental_build_minutes": incr_minutes,
            "compiler": cc,
            "jobs": hw.logical_cpus,
            "kcflags": "-pipe",
        },
        "output": {
            "image_path": str(kernel_image),
            "image_size_bytes": kernel_size,
            "image_size_mb": kernel_size_mb,
        },
        "comparison": {
            "intel_reference": {
                "model": "Intel i7-9750H",
                "clean_build_minutes": 20,
                "speedup": 20 / clean_minutes if clean_minutes > 0 else 0,
            },
            "expected_boot_improvement": "43% (4.38s -> 2.5s)",
        },
    }

    report_path = args.output_dir / f"arm64-{args.kernel_version}-build-report-{timestamp}.json"
    with open(report_path, "w") as f:
        json.dump(build_report, f, indent=2)

    print("=== Build Summary ===")
    print(json.dumps(build_report, indent=2))
    print()

    # Phase 3: Boot Validation
    print("=== Phase 3: Boot Validation ===")
    print()

    if check_command("limactl") and not args.skip_lima_test:
        success("Lima detected")
        print()
        print("To validate boot with Lima (vmType=vz):")
        print()
        print(f"  limactl start --name=minivim-test-{args.kernel_version.replace('.', '')} \\")
        print("    --vm-type=vz \\")
        print("    --arch=aarch64 \\")
        print(f"    --kernel={kernel_image} \\")
        print(f"    --initrd={REPO_ROOT}/bench-images/busybox/busybox-neovim-initrd.cpio.gz")
        print()
        print("Then to measure boot time:")
        print(f"  time limactl shell minivim-test-{args.kernel_version.replace('.', '')}")
        print()
    else:
        warn("Lima not installed or test skipped. To validate boot:")
        print("   brew install lima")
        print()

    print()
    print("=== Results ===")
    print(f"Build report: {report_path}")
    print(f"Clean build log: {clean_log}")
    print(f"CPU profile: {cpu_profile_path}")
    print()
    print("Next steps:")
    print("1. Review the build report and timings")
    print("2. Test boot with Lima or HyperKit")
    print("3. Commit build artifacts and logs to reports/benchmarks/")
    print("4. Update issue #574 with results")
    print()

    return 0


if __name__ == "__main__":
    sys.exit(main())