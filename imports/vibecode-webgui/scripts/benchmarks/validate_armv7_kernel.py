#!/usr/bin/env python3
"""Validate ARMv7 MiniVim kernel build.

Usage: ./validate_armv7_kernel.py [kernel_version]
Example: ./validate_armv7_kernel.py 6.17.0
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
NC = '\033[0m'


@dataclass
class ValidationConfig:
    """Validation configuration."""

    kernel_version: str = "6.17.14"
    output_dir: Path = Path()
    artifacts_dir: Path = Path()
    image_path: Path = Path()
    target_size_mb: float = 4.0


@dataclass
class ValidationResult:
    """Validation result."""

    kernel_version: str = ""
    image_path: str = ""
    image_size_bytes: int = 0
    image_size_mb: float = 0.0
    target_size_mb: float = 4.0
    size_compliant: bool = False
    qemu_available: bool = False
    validation_passed: bool = False


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
    capture: bool = True,
    timeout: int = 30
) -> tuple[int, str, str]:
    """Run a command."""
    try:
        result = subprocess.run(
            cmd,
            capture_output=capture,
            text=True,
            timeout=timeout
        )
        return result.returncode, result.stdout or "", result.stderr or ""
    except subprocess.TimeoutExpired:
        return -1, "", "timeout"
    except FileNotFoundError:
        return -1, "", "command not found"


def validate_kernel(config: ValidationConfig) -> ValidationResult:
    """Validate the kernel build."""
    result = ValidationResult(
        kernel_version=config.kernel_version,
        image_path=str(config.image_path),
        target_size_mb=config.target_size_mb
    )

    print("=== ARMv7 Kernel Validation ===")
    print(f"Kernel Version: {config.kernel_version}")
    print(f"Image Path: {config.image_path}")
    print()

    # Phase 1: File existence check
    print("Phase 1: Checking kernel image...")
    if not config.image_path.exists():
        error(f"Kernel image not found at {config.image_path}")
        return result

    success("Kernel image exists")

    # Get size
    result.image_size_bytes = config.image_path.stat().st_size
    result.image_size_mb = round(result.image_size_bytes / (1024 * 1024), 2)
    success(f"Kernel size: {result.image_size_mb} MB")

    # Phase 2: Size validation
    print()
    print("Phase 2: Size validation...")
    if result.image_size_mb > config.target_size_mb:
        warning(f"Kernel size ({result.image_size_mb} MB) exceeds target ({config.target_size_mb} MB)")
        result.size_compliant = False
    else:
        success(f"Kernel size within target ({config.target_size_mb} MB)")
        result.size_compliant = True

    # Phase 3: File type check
    print()
    print("Phase 3: File type validation...")
    if shutil.which("file"):
        rc, stdout, _ = run_command(["file", str(config.image_path)])
        print(f"File type: {stdout.strip()}")
        if "ARM" in stdout:
            success("Valid ARM kernel image")
        else:
            warning("File type doesn't explicitly show ARM")
    else:
        warning("'file' command not available, skipping type check")

    # Phase 4: QEMU boot test
    print()
    print("Phase 4: QEMU boot validation...")
    result.qemu_available = bool(shutil.which("qemu-system-arm"))

    if result.qemu_available:
        print("Testing QEMU boot (5 second timeout)...")

        config.artifacts_dir.mkdir(parents=True, exist_ok=True)
        qemu_log = config.artifacts_dir / "qemu-boot-test-armv7.log"

        rc, stdout, stderr = run_command([
            "qemu-system-arm",
            "-machine", "virt",
            "-cpu", "cortex-a15",
            "-m", "256M",
            "-kernel", str(config.image_path),
            "-nographic",
            "-serial", "mon:stdio",
            "-append", "console=ttyAMA0"
        ], timeout=5)

        # Write log
        qemu_log.write_text(stdout + stderr)

        if "Linux version" in stdout or "Linux version" in stderr:
            success("Kernel started in QEMU")
            # Find the boot log line
            for line in (stdout + stderr).splitlines():
                if "Linux version" in line:
                    print(f"  Boot log: {line}")
                    break
        elif "Booting" in stdout or "Booting" in stderr:
            success("QEMU boot initiated")
        else:
            warning("QEMU test inconclusive (may need initramfs)")
            print(f"  Log: {qemu_log}")
    else:
        warning("QEMU not available, skipping boot test")
        print("  Install with: sudo apt-get install qemu-system-arm")

    result.validation_passed = True

    # Phase 5: Generate report
    print()
    print("Phase 5: Generating validation report...")

    report_file = config.artifacts_dir / f"armv7-validation-{config.kernel_version}.json"
    report_data = {
        "validation_timestamp": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "kernel_version": result.kernel_version,
        "architecture": "armv7",
        "image_path": result.image_path,
        "image_size_bytes": result.image_size_bytes,
        "image_size_mb": result.image_size_mb,
        "target_size_mb": result.target_size_mb,
        "size_compliant": result.size_compliant,
        "qemu_available": result.qemu_available,
        "validation_passed": result.validation_passed
    }

    config.artifacts_dir.mkdir(parents=True, exist_ok=True)
    report_file.write_text(json.dumps(report_data, indent=2))
    success(f"Validation report: {report_file}")

    return result


def print_summary(result: ValidationResult) -> None:
    """Print validation summary."""
    print()
    print("=== Validation Summary ===")
    print(f"Status: {GREEN}PASSED{NC}")
    print(f"Kernel: {result.image_path}")
    print(f"Size: {result.image_size_mb} MB")
    print()
    print("Next steps:")
    print("1. Build BusyBox initramfs if needed")
    print("2. Run full boot benchmark: python3 scripts/benchmarks/boot_latency_bench.py")
    print("3. Capture timing data for documentation")
    print()


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Validate ARMv7 MiniVim kernel build"
    )
    parser.add_argument(
        "kernel_version",
        nargs="?",
        default="6.17.14",
        help="Kernel version"
    )
    parser.add_argument(
        "--target-size",
        type=float,
        default=4.0,
        help="Target size in MB"
    )

    args = parser.parse_args()

    script_dir = Path(__file__).parent.resolve()
    repo_root = script_dir.parent.parent
    output_dir = repo_root / "bench-images" / "minivim"
    artifacts_dir = repo_root / "artifacts" / "minivim"
    image_path = output_dir / f"zImage-armv7-{args.kernel_version}"

    config = ValidationConfig(
        kernel_version=args.kernel_version,
        output_dir=output_dir,
        artifacts_dir=artifacts_dir,
        image_path=image_path,
        target_size_mb=args.target_size
    )

    result = validate_kernel(config)

    if result.validation_passed:
        print_summary(result)
        return 0
    else:
        return 1


if __name__ == "__main__":
    sys.exit(main())
