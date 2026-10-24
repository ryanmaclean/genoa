#!/usr/bin/env python3
"""Build BusyBox with musl static linking.

Builds a minimal static BusyBox binary for initramfs use.
"""

import argparse
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class BuildConfig:
    """Build configuration."""

    arch: str = "x86_64"
    version: str = "1.36.1"
    build_root: Path = Path()
    src_dir: Path = Path()


# Colors for output
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
RED = '\033[0;31m'
NC = '\033[0m'


def log(msg: str) -> None:
    """Print log message."""
    print(f"{GREEN}[INFO]{NC} {msg}")


def error(msg: str) -> None:
    """Print error message."""
    print(f"{RED}[ERROR]{NC} {msg}", file=sys.stderr)


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


def set_bool_config(config_path: Path, key: str, value: str) -> None:
    """Set a boolean config option in .config file."""
    content = config_path.read_text()
    lines = content.splitlines()
    new_lines = []
    found = False

    for line in lines:
        if line.startswith(f"{key}="):
            new_lines.append(f"{key}={value}")
            found = True
        elif line == f"# {key} is not set":
            new_lines.append(f"{key}={value}")
            found = True
        else:
            new_lines.append(line)

    if not found:
        new_lines.append(f"{key}={value}")

    config_path.write_text("\n".join(new_lines) + "\n")


def set_string_config(config_path: Path, key: str, value: str) -> None:
    """Set a string config option in .config file."""
    content = config_path.read_text()
    lines = content.splitlines()
    new_lines = []
    found = False

    for line in lines:
        if line.startswith(f'{key}="'):
            new_lines.append(f'{key}="{value}"')
            found = True
        elif line == f"# {key} is not set":
            new_lines.append(f'{key}="{value}"')
            found = True
        else:
            new_lines.append(line)

    if not found:
        new_lines.append(f'{key}="{value}"')

    config_path.write_text("\n".join(new_lines) + "\n")


def disable_config(config_path: Path, key: str) -> None:
    """Disable a config option in .config file."""
    content = config_path.read_text()
    lines = content.splitlines()
    new_lines = []
    found = False

    for line in lines:
        if line.startswith(f"{key}="):
            new_lines.append(f"# {key} is not set")
            found = True
        else:
            new_lines.append(line)

    if not found:
        new_lines.append(f"# {key} is not set")

    config_path.write_text("\n".join(new_lines) + "\n")


def download_busybox(config: BuildConfig) -> bool:
    """Download BusyBox source."""
    tarball = f"busybox-{config.version}.tar.bz2"
    tarball_path = config.build_root / tarball
    url = f"https://busybox.net/downloads/{tarball}"

    if not tarball_path.exists():
        log(f"Downloading BusyBox {config.version}...")
        rc, _, stderr = run_command(
            ["curl", "-LO", url],
            cwd=config.build_root,
            check=False
        )
        if rc != 0:
            error(f"Failed to download: {stderr}")
            return False

    if not config.src_dir.exists():
        log("Extracting BusyBox...")
        rc, _, stderr = run_command(
            ["tar", "-xf", tarball],
            cwd=config.build_root,
            check=False
        )
        if rc != 0:
            error(f"Failed to extract: {stderr}")
            return False

    return True


def configure_busybox(config: BuildConfig) -> bool:
    """Configure BusyBox build."""
    log("Configuring BusyBox...")

    # Clean and create defconfig
    run_command(["make", "distclean"], cwd=config.src_dir, check=False, capture=True)
    rc, _, stderr = run_command(
        ["make", "defconfig"],
        cwd=config.src_dir,
        check=False,
        capture=True
    )
    if rc != 0:
        error(f"Failed to create defconfig: {stderr}")
        return False

    config_path = config.src_dir / ".config"

    # Enable static build
    set_bool_config(config_path, "CONFIG_STATIC", "y")

    # Network utilities
    set_bool_config(config_path, "CONFIG_UDHCPC", "y")
    set_string_config(config_path, "CONFIG_UDHCPC_DEFAULT_SCRIPT", "/udhcpc.script")
    set_bool_config(config_path, "CONFIG_IP", "y")

    # Shell
    set_bool_config(config_path, "CONFIG_SH_IS_ASH", "y")
    set_bool_config(config_path, "CONFIG_ASH", "y")

    # Core utilities
    for opt in ["CONFIG_LS", "CONFIG_CAT", "CONFIG_ECHO", "CONFIG_GREP",
                "CONFIG_TAR", "CONFIG_CP", "CONFIG_MKDIR", "CONFIG_MV",
                "CONFIG_RM", "CONFIG_PWD", "CONFIG_SLEEP", "CONFIG_INIT",
                "CONFIG_PING"]:
        set_bool_config(config_path, opt, "y")

    # Disable unnecessary features
    for opt in ["CONFIG_TC", "CONFIG_FEATURE_IP_TUNNEL", "CONFIG_FEATURE_SYSLOG",
                "CONFIG_FEATURE_IPV6", "CONFIG_SYSLOGD", "CONFIG_KLOGD"]:
        disable_config(config_path, opt)

    # Run oldconfig
    log("Running oldconfig...")
    proc = subprocess.Popen(
        ["make", "oldconfig"],
        cwd=config.src_dir,
        stdin=subprocess.PIPE,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL
    )
    # Send empty responses to accept defaults
    proc.communicate(input=b"\n" * 100)

    return True


def build_busybox(config: BuildConfig) -> bool:
    """Build BusyBox."""
    log(f"Building BusyBox for {config.arch}...")

    # Determine cross-compile settings
    make_args = []
    if config.arch == "arm64":
        make_args = ["ARCH=arm64", "CROSS_COMPILE=aarch64-linux-gnu-"]
    elif config.arch == "armv7":
        make_args = ["ARCH=arm", "CROSS_COMPILE=arm-linux-gnueabihf-"]

    # Get number of CPUs
    try:
        nproc = os.cpu_count() or 4
    except Exception:
        nproc = 4

    # Build
    rc, _, stderr = run_command(
        ["make", f"-j{nproc}"] + make_args,
        cwd=config.src_dir,
        check=False,
        capture=True
    )
    if rc != 0:
        error(f"Build failed: {stderr}")
        return False

    # Install
    rootfs_dir = config.build_root / "rootfs"
    rc, _, stderr = run_command(
        ["make", "install", f"CONFIG_PREFIX={rootfs_dir}"] + make_args,
        cwd=config.src_dir,
        check=False
    )
    if rc != 0:
        error(f"Install failed: {stderr}")
        return False

    return True


def build(config: BuildConfig) -> int:
    """Run the full build process.

    Args:
        config: Build configuration.

    Returns:
        Exit code.
    """
    config.build_root.mkdir(parents=True, exist_ok=True)

    if not download_busybox(config):
        return 1

    if not configure_busybox(config):
        return 1

    if not build_busybox(config):
        return 1

    rootfs_dir = config.build_root / "rootfs"
    log(f"BusyBox rootfs stored in {rootfs_dir}")

    return 0


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Build BusyBox with musl static linking"
    )
    parser.add_argument(
        "arch",
        nargs="?",
        default="x86_64",
        choices=["x86_64", "arm64", "armv7"],
        help="Target architecture"
    )
    parser.add_argument(
        "--version",
        default=os.environ.get("BUSYBOX_VERSION", "1.36.1"),
        help="BusyBox version"
    )

    args = parser.parse_args()

    # Determine paths
    script_dir = Path(__file__).parent.resolve()
    root_dir = script_dir.parent.parent
    build_root = root_dir / "bench-images" / "busybox"

    config = BuildConfig(
        arch=args.arch,
        version=args.version,
        build_root=build_root,
        src_dir=build_root / f"busybox-{args.version}"
    )

    return build(config)


if __name__ == "__main__":
    sys.exit(main())
