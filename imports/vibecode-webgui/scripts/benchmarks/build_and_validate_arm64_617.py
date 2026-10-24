#!/usr/bin/env python3
"""Build and validate MiniVim arm64 6.17.x kernel.

This script automates the workflow described in issue #574.
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional


# Colors for output
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
BLUE = '\033[0;34m'
NC = '\033[0m'


@dataclass
class HardwareProfile:
    """Hardware profile."""

    chip: str = "Unknown"
    logical_cpu: int = 8
    physical_cpu: int = 8
    perf_cores: int = 0
    effi_cores: int = 0
    memory_gb: int = 16


@dataclass
class BuildReport:
    """Build report."""

    report_id: str = ""
    timestamp: str = ""
    arch: str = "arm64"
    kernel_version: str = "6.17.14"
    hardware: HardwareProfile = None
    clean_build_seconds: int = 0
    clean_build_minutes: float = 0.0
    incremental_build_seconds: int = 0
    incremental_build_minutes: float = 0.0
    compiler: str = ""
    jobs: int = 0
    image_path: str = ""
    image_size_bytes: int = 0
    image_size_mb: float = 0.0


def log(msg: str) -> None:
    """Print log message."""
    print(msg)


def success(msg: str) -> None:
    """Print success message."""
    print(f"{GREEN}+{NC} {msg}")


def warning(msg: str) -> None:
    """Print warning message."""
    print(f"{YELLOW}!{NC} {msg}")


def error(msg: str) -> None:
    """Print error message."""
    print(f"{RED}x{NC} {msg}")


def run_command(
    cmd: list[str],
    cwd: Optional[Path] = None,
    capture: bool = True,
    env: Optional[dict] = None,
    timeout: int = 3600
) -> tuple[int, str, str]:
    """Run a command."""
    try:
        merged_env = os.environ.copy()
        if env:
            merged_env.update(env)

        result = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=capture,
            text=True,
            env=merged_env,
            timeout=timeout
        )
        return result.returncode, result.stdout or "", result.stderr or ""
    except subprocess.TimeoutExpired:
        return -1, "", "timeout"
    except FileNotFoundError:
        return -1, "", "command not found"


def sysctl_get(key: str) -> Optional[str]:
    """Get sysctl value."""
    rc, stdout, _ = run_command(["sysctl", "-n", key])
    if rc == 0:
        return stdout.strip()
    return None


def detect_hardware() -> HardwareProfile:
    """Detect hardware profile."""
    profile = HardwareProfile()

    profile.chip = sysctl_get("machdep.cpu.brand_string") or "Unknown"
    profile.logical_cpu = int(sysctl_get("hw.logicalcpu") or "8")
    profile.physical_cpu = int(sysctl_get("hw.physicalcpu") or "8")
    profile.perf_cores = int(sysctl_get("hw.perflevel0.physicalcpu") or "0")
    profile.effi_cores = int(sysctl_get("hw.perflevel1.physicalcpu") or "0")

    memsize = sysctl_get("hw.memsize")
    if memsize:
        profile.memory_gb = int(memsize) // (1024 * 1024 * 1024)

    return profile


def check_apple_silicon() -> bool:
    """Check if running on Apple Silicon."""
    chip = sysctl_get("machdep.cpu.brand_string")
    if chip and "Apple M" in chip:
        return True
    return False


def save_cpu_profile(reports_dir: Path, timestamp: str) -> Path:
    """Save CPU profile."""
    cpu_profile = reports_dir / f"arm64-6.17-cpu-profile-{timestamp}.txt"

    lines = ["=== Hardware Profile ==="]
    lines.append(f"Timestamp: {datetime.utcnow().strftime('%Y-%m-%dT%H:%M:%SZ')}")
    lines.append("")

    # Get sysctl info
    rc, stdout, _ = run_command(["sysctl", "-a"])
    if rc == 0:
        for line in stdout.splitlines():
            if any(x in line for x in ["hw.logicalcpu", "hw.physicalcpu",
                                        "hw.cpufrequency", "hw.memsize",
                                        "hw.machine", "hw.perflevel"]):
                lines.append(line)

    lines.append("")
    lines.append("=== System Profile ===")
    rc, stdout, _ = run_command(["system_profiler", "SPHardwareDataType"])
    if rc == 0:
        lines.append(stdout)

    cpu_profile.write_text("\n".join(lines))
    return cpu_profile


def run_build(
    script_path: Path,
    log_file: Path,
    env: dict,
    arch: str = "arm64"
) -> tuple[int, int]:
    """Run kernel build.

    Returns:
        (return_code, duration_seconds)
    """
    import time
    start = time.time()

    # Run build with output to both console and log
    with open(log_file, "w") as f:
        result = subprocess.run(
            [str(script_path), arch],
            env={**os.environ, **env},
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )

        f.write(result.stdout)
        print(result.stdout)

    end = time.time()
    return result.returncode, int(end - start)


def build_and_validate() -> int:
    """Run the full build and validation process."""
    script_dir = Path(__file__).parent.resolve()
    repo_root = script_dir.parent.parent
    reports_dir = repo_root / "reports" / "benchmarks"
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    print("=== MiniVim arm64 6.17.x Build and Validation ===")
    print(f"Timestamp: {timestamp}")
    print()

    # Check Apple Silicon
    if not check_apple_silicon():
        warning("Not running on Apple Silicon")
        print("This script is optimized for M1/M2/M3/M4 processors")
        response = input("Continue anyway? (y/N) ")
        if response.lower() != 'y':
            return 1

    # Detect hardware
    hw = detect_hardware()
    print("Hardware Profile:")
    print(f"  Chip: {hw.chip}")
    print(f"  Logical CPUs: {hw.logical_cpu}")
    print(f"  Physical CPUs: {hw.physical_cpu}")
    print(f"  Performance Cores: {hw.perf_cores}")
    print(f"  Efficiency Cores: {hw.effi_cores}")
    print(f"  Memory: {hw.memory_gb}GB")
    print()

    # Create reports directory
    reports_dir.mkdir(parents=True, exist_ok=True)

    # Save CPU profile
    cpu_profile = save_cpu_profile(reports_dir, timestamp)
    log(f"Saving CPU profile to {cpu_profile}...")

    # Check for ccache
    cc = "clang"
    if shutil.which("ccache"):
        success("ccache available")
        rc, stdout, _ = run_command(["ccache", "-s"])
        if rc == 0:
            print(stdout)
        cc = "ccache clang"
    else:
        warning("ccache not found. Install for faster builds:")
        print("   brew install ccache")
    print()

    # Set up environment
    env = {
        "CC": cc,
        "KCFLAGS": "-pipe",
        "MINIVIM_JOBS": str(hw.logical_cpu)
    }

    # Check for GNU make
    if shutil.which("/usr/local/opt/make/libexec/gnubin/make"):
        env["PATH"] = f"/usr/local/opt/make/libexec/gnubin:{os.environ.get('PATH', '')}"

    build_script = script_dir / "build_minivim_kernel_617.py"
    if not build_script.exists():
        build_script = script_dir / "build-minivim-kernel-6.17.sh"

    # Phase 1: Clean Build
    print("=== Phase 1: Clean Build ===")
    clean_log = reports_dir / f"arm64-6.17-clean-build-{timestamp}.log"
    rc, clean_seconds = run_build(build_script, clean_log, env)
    clean_minutes = round(clean_seconds / 60, 1)

    print()
    print(f"Clean build completed in {clean_seconds}s ({clean_minutes} minutes)")
    print()

    # Phase 2: Incremental Build
    print("=== Phase 2: Incremental Build ===")
    incr_log = reports_dir / f"arm64-6.17-incremental-build-{timestamp}.log"
    incr_env = {**env, "SKIP_MRPROPER": "1"}
    rc, incr_seconds = run_build(build_script, incr_log, incr_env)
    incr_minutes = round(incr_seconds / 60, 1)

    print()
    print(f"Incremental build completed in {incr_seconds}s ({incr_minutes} minutes)")
    print()

    # Check output
    kernel_image = repo_root / "bench-images" / "minivim" / "Image-arm64-6.17.14"
    if not kernel_image.exists():
        error(f"Kernel image not found at {kernel_image}")
        return 1

    kernel_size = kernel_image.stat().st_size
    kernel_size_mb = round(kernel_size / (1024 * 1024), 1)

    success("Kernel built successfully")
    print(f"   Path: {kernel_image}")
    print(f"   Size: {kernel_size_mb} MB")
    print()

    # Generate build report
    build_report = reports_dir / f"arm64-6.17-build-report-{timestamp}.json"

    report_data = {
        "report_id": f"arm64-6.17-{timestamp}",
        "timestamp": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "arch": "arm64",
        "kernel_version": "6.17.14",
        "hardware": {
            "model": hw.chip,
            "cores_logical": hw.logical_cpu,
            "cores_physical": hw.physical_cpu,
            "cores_performance": hw.perf_cores,
            "cores_efficiency": hw.effi_cores,
            "memory_gb": hw.memory_gb
        },
        "build": {
            "clean_build_seconds": clean_seconds,
            "clean_build_minutes": clean_minutes,
            "incremental_build_seconds": incr_seconds,
            "incremental_build_minutes": incr_minutes,
            "compiler": cc,
            "jobs": hw.logical_cpu,
            "kcflags": "-pipe"
        },
        "output": {
            "image_path": str(kernel_image),
            "image_size_bytes": kernel_size,
            "image_size_mb": kernel_size_mb
        },
        "comparison": {
            "intel_reference": {
                "model": "Intel i7-9750H",
                "clean_build_minutes": 20,
                "speedup": round(20 / clean_minutes, 2) if clean_minutes > 0 else 0
            },
            "expected_boot_improvement": "43% (4.38s -> 2.5s)"
        }
    }

    build_report.write_text(json.dumps(report_data, indent=2))

    print("=== Build Summary ===")
    print(json.dumps(report_data, indent=2))
    print()

    # Phase 3: Boot Validation
    print("=== Phase 3: Boot Validation ===")
    print()

    if shutil.which("limactl"):
        success("Lima detected")
        print()
        print("To validate boot with Lima (vmType=vz):")
        print()
        print(f"  limactl start --name=minivim-test-617 \\")
        print(f"    --vm-type=vz \\")
        print(f"    --arch=aarch64 \\")
        print(f"    --kernel={kernel_image} \\")
        print(f"    --initrd={repo_root}/bench-images/busybox/busybox-neovim-initrd.cpio.gz")
        print()
        print("Then to measure boot time:")
        print("  time limactl shell minivim-test-617")
    else:
        warning("Lima not installed. To validate boot:")
        print("   brew install lima")

    print()
    print("=== Results ===")
    print(f"Build report: {build_report}")
    print(f"Clean build log: {clean_log}")
    print(f"Incremental build log: {incr_log}")
    print(f"CPU profile: {cpu_profile}")
    print()
    print("Next steps:")
    print("1. Review the build report and timings")
    print("2. Test boot with Lima or HyperKit")
    print("3. Commit build artifacts and logs to reports/benchmarks/")
    print("4. Update issue #574 with results")
    print()

    return 0


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Build and validate MiniVim arm64 6.17.x kernel"
    )

    args = parser.parse_args()
    return build_and_validate()


if __name__ == "__main__":
    sys.exit(main())
