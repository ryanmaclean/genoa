#!/usr/bin/env python3
"""Complete ARMv7 6.17.x kernel build and validation workflow.

Usage: ./build_armv7_617_complete.py [options]
Options:
  --skip-build     Skip kernel build (use existing kernel)
  --skip-validate  Skip validation
  --kernel-version VERSION  Override kernel version (default: 6.17.14)
"""

import argparse
import os
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Optional


# Colors for output
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
NC = '\033[0m'


@dataclass
class WorkflowConfig:
    """Workflow configuration."""

    kernel_version: str = "6.17.14"
    skip_build: bool = False
    skip_validate: bool = False
    jobs: int = 4
    cross_compile: str = "arm-linux-gnueabihf-"
    cc: str = ""


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
    capture: bool = True
) -> tuple[int, str, str]:
    """Run a command."""
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            capture_output=capture,
            text=True
        )
        return result.returncode, result.stdout or "", result.stderr or ""
    except FileNotFoundError:
        return -1, "", "command not found"


def check_dependencies() -> list[str]:
    """Check build dependencies.

    Returns:
        List of missing dependencies.
    """
    print("=" * 60)
    print("Phase 1: Checking build dependencies")
    print("=" * 60)

    missing = []

    # Required tools
    for tool in ["make", "bc", "curl"]:
        if not shutil.which(tool):
            missing.append(tool)

    # Cross-compilation toolchain
    if not shutil.which("arm-linux-gnueabihf-gcc"):
        warning("Cross-compilation toolchain not found")
        print("   Install with: sudo apt-get install gcc-arm-linux-gnueabihf")
        missing.append("gcc-arm-linux-gnueabihf")

    # Recommended tools
    recommended = []
    for tool in ["clang", "ccache"]:
        if not shutil.which(tool):
            recommended.append(tool)

    if missing:
        error(f"Missing required dependencies: {' '.join(missing)}")
    else:
        success("All required dependencies found")

    if recommended:
        warning(f"Recommended tools not found: {' '.join(recommended)}")
        print(f"   Install with: sudo apt-get install {' '.join(recommended)}")

    return missing


def run_kernel_build(
    script_dir: Path,
    config: WorkflowConfig
) -> tuple[int, int, int]:
    """Run kernel build.

    Returns:
        (return_code, duration_minutes, duration_seconds)
    """
    print()
    print("=" * 60)
    print("Phase 2: Building ARMv7 kernel")
    print("=" * 60)

    print("Build configuration:")
    print(f"  Jobs: {config.jobs}")
    print(f"  Cross compile: {config.cross_compile}")
    print(f"  Compiler: {config.cc or 'gcc'}")
    print()

    env = os.environ.copy()
    env["MINIVIM_JOBS"] = str(config.jobs)
    env["CROSS_COMPILE"] = config.cross_compile
    if config.cc:
        env["CC"] = config.cc
        env["KCFLAGS"] = "-pipe"

    build_script = script_dir / "build_minivim_kernel.py"
    if not build_script.exists():
        build_script = script_dir / "build-minivim-kernel.sh"

    start = time.time()

    result = subprocess.run(
        [str(build_script), "armv7", config.kernel_version],
        env=env
    )

    end = time.time()
    duration = int(end - start)
    minutes = duration // 60
    seconds = duration % 60

    print()
    if result.returncode == 0:
        success(f"Kernel build completed in {minutes}m {seconds}s")
    else:
        error("Kernel build failed")

    return result.returncode, minutes, seconds


def run_validation(
    script_dir: Path,
    kernel_version: str
) -> int:
    """Run kernel validation."""
    print()
    print("=" * 60)
    print("Phase 3: Validating kernel build")
    print("=" * 60)

    validate_script = script_dir / "validate_armv7_kernel.py"
    if not validate_script.exists():
        validate_script = script_dir / "validate-armv7-kernel.sh"

    result = subprocess.run([str(validate_script), kernel_version])
    return result.returncode


def organize_artifacts(
    repo_root: Path,
    config: WorkflowConfig,
    build_minutes: int,
    build_seconds: int
) -> None:
    """Organize build artifacts."""
    print()
    print("=" * 60)
    print("Phase 4: Organizing artifacts")
    print("=" * 60)

    artifacts_dir = repo_root / "artifacts" / "minivim"
    output_dir = repo_root / "bench-images" / "minivim"
    artifacts_dir.mkdir(parents=True, exist_ok=True)

    # Copy kernel image
    kernel_image = output_dir / f"zImage-armv7-{config.kernel_version}"
    if kernel_image.exists():
        shutil.copy(kernel_image, artifacts_dir)
        success(f"Kernel image: {artifacts_dir}/zImage-armv7-{config.kernel_version}")

    # Copy CPU info
    cpu_info = output_dir / "cpuinfo-armv7.txt"
    if cpu_info.exists():
        shutil.copy(cpu_info, artifacts_dir)
        success(f"CPU info: {artifacts_dir}/cpuinfo-armv7.txt")

    # Check validation report
    validation_report = artifacts_dir / f"armv7-validation-{config.kernel_version}.json"
    if validation_report.exists():
        success(f"Validation report: {validation_report}")

    # Generate build manifest
    manifest = artifacts_dir / f"build-manifest-armv7-{config.kernel_version}.txt"
    manifest_content = f"""ARMv7 MiniVim Kernel Build Manifest
====================================

Build Date: {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S UTC')}
Kernel Version: {config.kernel_version}
Architecture: armv7 (32-bit ARM)

Build Configuration:
- Jobs: {config.jobs}
- Cross Compile: {config.cross_compile}
- Compiler: {config.cc or 'gcc'}
- Skip mrproper: {os.environ.get('SKIP_MRPROPER', '0')}

Build Time: {build_minutes}m {build_seconds}s

Artifacts:
- Kernel: zImage-armv7-{config.kernel_version}
- CPU Info: cpuinfo-armv7.txt
- Validation: armv7-validation-{config.kernel_version}.json

Builder System:
{os.uname().sysname} {os.uname().release}
"""

    # Add CPU info if available
    if shutil.which("lscpu"):
        rc, stdout, _ = run_command(["lscpu"])
        if rc == 0:
            manifest_content += "\nCPU Information:\n"
            manifest_content += "\n".join(stdout.splitlines()[:20])

    manifest.write_text(manifest_content)
    success(f"Build manifest: {manifest}")


def run_workflow(config: WorkflowConfig) -> int:
    """Run the complete workflow."""
    script_dir = Path(__file__).parent.resolve()
    repo_root = script_dir.parent.parent

    start_time = time.time()

    print("+" + "=" * 62 + "+")
    print("|       ARMv7 6.17.x Complete Build & Validation Workflow       |")
    print("+" + "=" * 62 + "+")
    print()
    print("Configuration:")
    print(f"  Kernel Version: {config.kernel_version}")
    print(f"  Skip Build: {config.skip_build}")
    print(f"  Skip Validate: {config.skip_validate}")
    print()

    # Phase 1: Dependency Check
    missing = check_dependencies()
    if missing:
        return 1

    # Phase 2: Kernel Build
    build_minutes = 0
    build_seconds = 0

    if not config.skip_build:
        rc, build_minutes, build_seconds = run_kernel_build(script_dir, config)
        if rc != 0:
            return 1
    else:
        print()
        print("=" * 60)
        print("Phase 2: Skipping kernel build (--skip-build)")
        print("=" * 60)

    # Phase 3: Validation
    if not config.skip_validate:
        rc = run_validation(script_dir, config.kernel_version)
        if rc != 0:
            return 1
    else:
        print()
        print("=" * 60)
        print("Phase 3: Skipping validation (--skip-validate)")
        print("=" * 60)

    # Phase 4: Organize artifacts
    organize_artifacts(repo_root, config, build_minutes, build_seconds)

    # Summary
    end_time = time.time()
    total = int(end_time - start_time)
    total_minutes = total // 60
    total_seconds = total % 60

    print()
    print("+" + "=" * 62 + "+")
    print("|                     Workflow Complete                          |")
    print("+" + "=" * 62 + "+")
    print()
    print("Summary:")
    print(f"  Total Time: {total_minutes}m {total_seconds}s")
    print(f"  Artifacts: {repo_root}/artifacts/minivim/")
    print()
    print("Next Steps:")
    print(f"  1. Review artifacts in {repo_root}/artifacts/minivim/")
    print("  2. Test kernel boot with QEMU (if available)")
    print("  3. Run benchmarks: python3 scripts/benchmarks/boot_latency_bench.py")
    print("  4. Update documentation: docs/virtualization/minivim-kernel.md")
    print("  5. Attach artifacts to release bundle")
    print()

    return 0


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Complete ARMv7 6.17.x kernel build and validation workflow"
    )
    parser.add_argument(
        "--skip-build",
        action="store_true",
        help="Skip kernel build"
    )
    parser.add_argument(
        "--skip-validate",
        action="store_true",
        help="Skip validation"
    )
    parser.add_argument(
        "--kernel-version",
        default="6.17.14",
        help="Kernel version"
    )

    args = parser.parse_args()

    # Determine jobs and compiler
    try:
        jobs = os.cpu_count() or 4
    except Exception:
        jobs = 4

    cc = ""
    if shutil.which("clang") and shutil.which("ccache"):
        cc = "ccache clang"

    config = WorkflowConfig(
        kernel_version=args.kernel_version,
        skip_build=args.skip_build,
        skip_validate=args.skip_validate,
        jobs=jobs,
        cc=cc
    )

    return run_workflow(config)


if __name__ == "__main__":
    sys.exit(main())
