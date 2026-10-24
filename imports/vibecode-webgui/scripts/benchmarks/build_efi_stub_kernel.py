#!/usr/bin/env python3
"""Build EFI-stub kernel for Apple Virtualization Framework fast boot.

The EFI-stub kernel boots directly from EFI without GRUB.
"""

import argparse
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


# Colors for output
GREEN = '\033[0;32m'
RED = '\033[0;31m'
NC = '\033[0m'


@dataclass
class BuildConfig:
    """Build configuration."""

    arch: str = "arm64"
    kernel_version: str = "6.12.10"
    build_root: Path = Path()
    src_dir: Path = Path()
    config_dir: Path = Path()
    output_dir: Path = Path()
    jobs: int = 4
    skip_mrproper: bool = False


def log(msg: str) -> None:
    """Print log message."""
    print(f"{GREEN}[INFO]{NC} {msg}")


def error(msg: str) -> None:
    """Print error message."""
    print(f"{RED}[ERROR]{NC} {msg}", file=sys.stderr)


def run_command(
    cmd: list[str],
    cwd: Optional[Path] = None,
    check: bool = False,
    capture: bool = False
) -> tuple[int, str, str]:
    """Run a command."""
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            check=check,
            capture_output=capture,
            text=True
        )
        return result.returncode, result.stdout or "", result.stderr or ""
    except subprocess.CalledProcessError as e:
        return e.returncode, e.stdout or "", e.stderr or ""
    except FileNotFoundError:
        return -1, "", f"command not found: {cmd[0]}"


def get_make_bin() -> str:
    """Get the make binary to use."""
    if shutil.which("gmake"):
        return "gmake"
    return "make"


def get_jobs() -> int:
    """Get number of parallel jobs."""
    jobs_env = os.environ.get("KERNEL_JOBS")
    if jobs_env:
        try:
            return int(jobs_env)
        except ValueError:
            pass

    if shutil.which("nproc"):
        rc, stdout, _ = run_command(["nproc"], capture=True)
        if rc == 0:
            try:
                return int(stdout.strip())
            except ValueError:
                pass

    if shutil.which("sysctl"):
        rc, stdout, _ = run_command(
            ["sysctl", "-n", "hw.logicalcpu"],
            capture=True
        )
        if rc == 0:
            try:
                return int(stdout.strip())
            except ValueError:
                pass

    return 4


def download_kernel(config: BuildConfig) -> bool:
    """Download kernel source."""
    tarball = f"linux-{config.kernel_version}.tar.xz"
    tarball_path = config.build_root / tarball
    url = f"https://cdn.kernel.org/pub/linux/kernel/v6.x/{tarball}"

    if not tarball_path.exists():
        log("Downloading kernel source...")
        rc, _, stderr = run_command(
            ["curl", "-L", url, "-o", str(tarball_path)]
        )
        if rc != 0:
            error(f"Failed to download: {stderr}")
            return False

    if not config.src_dir.exists():
        log("Extracting kernel source...")
        rc, _, stderr = run_command(
            ["tar", "-C", str(config.build_root), "--no-same-owner", "-xf", str(tarball_path)]
        )
        if rc != 0:
            error(f"Failed to extract: {stderr}")
            return False

    return True


def configure_kernel(config: BuildConfig) -> bool:
    """Configure the kernel for EFI-stub."""
    make_bin = get_make_bin()

    # Clean if needed
    if not config.skip_mrproper:
        run_command(
            [make_bin, "ARCH=arm64", "mrproper"],
            cwd=config.src_dir
        )

    # Start with arm64 defconfig
    log("Configuring kernel...")
    rc, _, stderr = run_command(
        [make_bin, "ARCH=arm64", "defconfig"],
        cwd=config.src_dir
    )
    if rc != 0:
        error(f"Failed to create defconfig: {stderr}")
        return False

    # Merge config fragments
    base_config = config.config_dir / "minivim-base.config"
    arm64_config = config.config_dir / "minivim-arm64.config"
    efi_config = config.config_dir / "efi-stub-arm64.config"

    merge_files = [f for f in [base_config, arm64_config, efi_config] if f.exists()]
    for cfg in merge_files:
        run_command(
            ["./scripts/kconfig/merge_config.sh", "-m", ".config", str(cfg)],
            cwd=config.src_dir
        )

    # Ensure EFI-stub is enabled
    for opt in ["EFI", "EFI_STUB", "EFI_GENERIC_STUB"]:
        run_command(
            ["./scripts/config", "--enable", opt],
            cwd=config.src_dir
        )

    # Size optimizations
    run_command(
        ["./scripts/config", "--enable", "CC_OPTIMIZE_FOR_SIZE"],
        cwd=config.src_dir
    )
    for opt in ["DEBUG_KERNEL", "DEBUG_INFO", "MODULES"]:
        run_command(
            ["./scripts/config", "--disable", opt],
            cwd=config.src_dir
        )

    # Fast boot optimizations
    run_command(
        ["./scripts/config", "--enable", "PRINTK"],
        cwd=config.src_dir
    )
    run_command(
        ["./scripts/config", "--set-str", "DEFAULT_INIT", "/init"],
        cwd=config.src_dir
    )

    # Finalize config
    run_command(
        [make_bin, "ARCH=arm64", "olddefconfig"],
        cwd=config.src_dir
    )

    return True


def build_kernel(config: BuildConfig) -> bool:
    """Build the kernel."""
    make_bin = get_make_bin()

    log(f"Building kernel (this may take several minutes)...")
    rc, _, stderr = run_command(
        [make_bin, "ARCH=arm64", f"-j{config.jobs}", "Image"],
        cwd=config.src_dir
    )
    if rc != 0:
        error(f"Build failed: {stderr}")
        return False

    return True


def copy_artifacts(config: BuildConfig) -> bool:
    """Copy build artifacts."""
    src = config.src_dir / "arch" / "arm64" / "boot" / "Image"
    dst = config.output_dir / "vmlinux-efi-stub"

    if not src.exists():
        error(f"Kernel image not found: {src}")
        return False

    config.output_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)

    # Get size
    size = dst.stat().st_size
    size_mb = size / (1024 * 1024)

    log("=== Build Complete ===")
    log(f"Kernel: {dst}")
    log(f"Size: {size_mb:.1f} MB")
    print()
    print("To test fast boot:")
    print(f"  APPLEVF_KERNEL={dst} \\")
    print("  ./scripts/benchmarks/applevf_fastboot_bench.py bench 5")

    return True


def build(config: BuildConfig) -> int:
    """Run the full build process."""
    print("=== Building EFI-stub Kernel for Apple VF ===")
    print(f"Architecture: {config.arch}")
    print(f"Kernel version: {config.kernel_version}")
    print()

    if config.arch != "arm64":
        error("Apple VF on Apple Silicon requires arm64 architecture")
        return 1

    config.build_root.mkdir(parents=True, exist_ok=True)

    if not download_kernel(config):
        return 1

    if not configure_kernel(config):
        return 1

    if not build_kernel(config):
        return 1

    if not copy_artifacts(config):
        return 1

    return 0


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Build EFI-stub kernel for Apple VF fast boot"
    )
    parser.add_argument(
        "arch",
        nargs="?",
        default="arm64",
        help="Target architecture (only arm64 supported)"
    )
    parser.add_argument(
        "kernel_version",
        nargs="?",
        default="6.12.10",
        help="Kernel version"
    )
    parser.add_argument(
        "--skip-mrproper",
        action="store_true",
        default=bool(os.environ.get("SKIP_MRPROPER")),
        help="Skip mrproper step"
    )

    args = parser.parse_args()

    script_dir = Path(__file__).parent.resolve()
    root_dir = script_dir.parent.parent
    build_root = root_dir / "bench-images" / "apple-vf-fastboot"

    config = BuildConfig(
        arch=args.arch,
        kernel_version=args.kernel_version,
        build_root=build_root,
        src_dir=build_root / f"linux-{args.kernel_version}",
        config_dir=script_dir / "kernel-configs",
        output_dir=build_root,
        jobs=get_jobs(),
        skip_mrproper=args.skip_mrproper
    )

    return build(config)


if __name__ == "__main__":
    sys.exit(main())
