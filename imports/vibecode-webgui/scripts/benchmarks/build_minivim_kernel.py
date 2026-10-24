#!/usr/bin/env python3
"""Build a minimal kernel + initramfs tuned for vi launch benchmarks.

Usage: ./build_minivim_kernel.py [x86_64|arm64|armv7] [kernel_version]
"""

import argparse
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


SUPPORTED_ARCHES = ["x86_64", "arm64", "armv7"]

# Colors for output
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
NC = '\033[0m'


@dataclass
class BuildConfig:
    """Build configuration."""

    arch: str = "x86_64"
    kernel_version: str = "6.12.10"
    build_root: Path = Path()
    src_dir: Path = Path()
    config_dir: Path = Path()
    skip_mrproper: bool = False
    jobs: int = 4


def log(msg: str) -> None:
    """Print log message."""
    print(f"{GREEN}[INFO]{NC} {msg}")


def error(msg: str) -> None:
    """Print error message."""
    print(f"{RED}[ERROR]{NC} {msg}", file=sys.stderr)


def warning(msg: str) -> None:
    """Print warning message."""
    print(f"{YELLOW}[WARNING]{NC} {msg}")


def run_command(
    cmd: list[str],
    cwd: Optional[Path] = None,
    check: bool = True,
    capture: bool = False,
    env: Optional[dict] = None
) -> tuple[int, str, str]:
    """Run a command."""
    try:
        merged_env = os.environ.copy()
        if env:
            merged_env.update(env)

        result = subprocess.run(
            cmd,
            cwd=cwd,
            check=check,
            capture_output=capture,
            text=True,
            env=merged_env
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
    jobs_env = os.environ.get("MINIVIM_JOBS")
    if jobs_env:
        try:
            return int(jobs_env)
        except ValueError:
            pass

    # Try nproc
    if shutil.which("nproc"):
        rc, stdout, _ = run_command(["nproc"], capture=True, check=False)
        if rc == 0:
            try:
                return int(stdout.strip())
            except ValueError:
                pass

    # Try sysctl (macOS)
    if shutil.which("sysctl"):
        rc, stdout, _ = run_command(
            ["sysctl", "-n", "hw.logicalcpu"],
            capture=True,
            check=False
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
        log(f"Downloading kernel {config.kernel_version}...")
        rc, _, stderr = run_command(
            ["curl", "-L", url, "-o", str(tarball_path)],
            check=False
        )
        if rc != 0:
            error(f"Failed to download kernel: {stderr}")
            return False

    if not config.src_dir.exists():
        log("Extracting kernel source...")
        rc, _, stderr = run_command(
            ["tar", "-C", str(config.build_root), "--no-same-owner", "-xf", str(tarball_path)],
            check=False
        )
        if rc != 0:
            error(f"Failed to extract kernel: {stderr}")
            return False

    return True


def save_cpu_info(config: BuildConfig) -> None:
    """Save CPU info for logging."""
    cpu_info_file = config.build_root / f"cpuinfo-{config.arch}.txt"

    if shutil.which("lscpu"):
        rc, stdout, _ = run_command(["lscpu"], capture=True, check=False)
        if rc == 0:
            cpu_info_file.write_text(stdout)
            return

    if config.arch == "x86_64" and shutil.which("sysctl"):
        rc, stdout, _ = run_command(
            ["sysctl", "-a"],
            capture=True,
            check=False
        )
        if rc == 0:
            lines = [l for l in stdout.splitlines() if "machdep.cpu" in l]
            cpu_info_file.write_text("\n".join(lines))


def get_defconfig(arch: str) -> str:
    """Get defconfig name for architecture."""
    if arch == "x86_64":
        return "x86_64_defconfig"
    elif arch == "arm64":
        return "defconfig"
    elif arch == "armv7":
        return "multi_v7_defconfig"
    return "defconfig"


def configure_kernel(config: BuildConfig) -> bool:
    """Configure the kernel."""
    make_bin = get_make_bin()

    # Clean if needed
    if not config.skip_mrproper:
        log("Running mrproper...")
        run_command(
            [make_bin, f"ARCH={config.arch}", "mrproper"],
            cwd=config.src_dir,
            check=False
        )

    # Create defconfig
    defconfig = get_defconfig(config.arch)
    log(f"Creating {defconfig}...")
    rc, _, stderr = run_command(
        [make_bin, f"ARCH={config.arch}", defconfig],
        cwd=config.src_dir,
        check=False
    )
    if rc != 0:
        error(f"Failed to create defconfig: {stderr}")
        return False

    # Merge config fragments
    merge_files = [
        config.config_dir / "minivim-base.config",
        config.config_dir / f"minivim-{config.arch}.config"
    ]

    existing_merge_files = [str(f) for f in merge_files if f.exists()]
    if existing_merge_files:
        log("Merging config fragments...")
        run_command(
            ["./scripts/kconfig/merge_config.sh", "-m", ".config"] + existing_merge_files,
            cwd=config.src_dir,
            check=False
        )

    # Check for initramfs source
    script_dir = Path(__file__).parent.resolve()
    root_dir = script_dir.parent.parent
    initramfs_src = root_dir / "bench-images" / "apple-vf" / "rootfs"
    if initramfs_src.is_dir():
        run_command(
            ["./scripts/config", "--set-str", "INITRAMFS_SOURCE", str(initramfs_src)],
            cwd=config.src_dir,
            check=False
        )

    # Finalize config
    run_command(
        [make_bin, f"ARCH={config.arch}", "olddefconfig"],
        cwd=config.src_dir,
        check=False
    )

    # Disable ORC for x86_64
    if config.arch == "x86_64":
        run_command(
            ["./scripts/config", "--disable", "UNWINDER_ORC", "--disable", "STACK_VALIDATION"],
            cwd=config.src_dir,
            check=False
        )
        run_command(
            [make_bin, f"ARCH={config.arch}", "olddefconfig"],
            cwd=config.src_dir,
            check=False
        )

    return True


def build_kernel(config: BuildConfig) -> bool:
    """Build the kernel."""
    make_bin = get_make_bin()

    # Build arguments based on architecture
    if config.arch == "x86_64":
        make_args = [f"ARCH={config.arch}", f"-j{config.jobs}", "bzImage"]
    elif config.arch == "arm64":
        make_args = [f"ARCH={config.arch}", f"-j{config.jobs}", "Image"]
    elif config.arch == "armv7":
        make_args = ["ARCH=arm", "CROSS_COMPILE=arm-linux-gnueabihf-", f"-j{config.jobs}", "zImage"]
    else:
        error(f"Unsupported architecture: {config.arch}")
        return False

    log(f"Building kernel for {config.arch} with {config.jobs} jobs...")
    rc, _, stderr = run_command(
        [make_bin] + make_args,
        cwd=config.src_dir,
        check=False
    )
    if rc != 0:
        error(f"Build failed: {stderr}")
        return False

    return True


def copy_artifacts(config: BuildConfig) -> bool:
    """Copy build artifacts."""
    if config.arch == "x86_64":
        src = config.src_dir / "arch" / "x86" / "boot" / "bzImage"
        dst = config.build_root / f"bzImage-{config.arch}-{config.kernel_version}"
    elif config.arch == "arm64":
        src = config.src_dir / "arch" / "arm64" / "boot" / "Image"
        dst = config.build_root / f"Image-{config.arch}-{config.kernel_version}"
    elif config.arch == "armv7":
        src = config.src_dir / "arch" / "arm" / "boot" / "zImage"
        dst = config.build_root / f"zImage-{config.arch}-{config.kernel_version}"
    else:
        return False

    if not src.exists():
        error(f"Kernel image not found: {src}")
        return False

    shutil.copy2(src, dst)
    log(f"Kernel copied to {dst}")

    return True


def build(config: BuildConfig) -> int:
    """Run the full build process.

    Args:
        config: Build configuration.

    Returns:
        Exit code.
    """
    config.build_root.mkdir(parents=True, exist_ok=True)

    if not download_kernel(config):
        return 1

    save_cpu_info(config)

    if not configure_kernel(config):
        return 1

    if not build_kernel(config):
        return 1

    if not copy_artifacts(config):
        return 1

    log(f"Kernel build complete. Artifacts saved in {config.build_root}.")
    return 0


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Build a minimal kernel for vi launch benchmarks"
    )
    parser.add_argument(
        "arch",
        nargs="?",
        default="x86_64",
        choices=SUPPORTED_ARCHES,
        help="Target architecture"
    )
    parser.add_argument(
        "kernel_version",
        nargs="?",
        default=os.environ.get("KERNEL_VERSION", "6.12.10"),
        help="Kernel version"
    )
    parser.add_argument(
        "--skip-mrproper",
        action="store_true",
        default=bool(os.environ.get("SKIP_MRPROPER")),
        help="Skip mrproper step"
    )

    args = parser.parse_args()

    if args.arch not in SUPPORTED_ARCHES:
        error(f"Unsupported architecture '{args.arch}'. Choose from: {', '.join(SUPPORTED_ARCHES)}")
        return 1

    # Determine paths
    script_dir = Path(__file__).parent.resolve()
    root_dir = script_dir.parent.parent
    build_root = root_dir / "bench-images" / "minivim"
    config_dir = script_dir / "kernel-configs"

    config = BuildConfig(
        arch=args.arch,
        kernel_version=args.kernel_version,
        build_root=build_root,
        src_dir=build_root / f"linux-{args.kernel_version}",
        config_dir=config_dir,
        skip_mrproper=args.skip_mrproper,
        jobs=get_jobs()
    )

    return build(config)


if __name__ == "__main__":
    sys.exit(main())
