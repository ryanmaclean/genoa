#!/usr/bin/env python3
"""Build MiniVim kernel in Alpine Docker.

Avoids macOS Make issues by building in a Linux container.
"""

import argparse
import os
import subprocess
import sys
from pathlib import Path


# Colors for output
GREEN = '\033[0;32m'
NC = '\033[0m'


def log(msg: str) -> None:
    """Print log message."""
    print(f"{GREEN}[INFO]{NC} {msg}")


def build_in_docker(arch: str, kernel_version: str, repo_root: Path) -> int:
    """Build kernel in Alpine Docker container.

    Args:
        arch: Target architecture.
        kernel_version: Kernel version.
        repo_root: Repository root path.

    Returns:
        Exit code.
    """
    log(f"Building kernel {kernel_version} in Alpine Docker...")

    script = f'''
apk add --no-cache build-base linux-headers flex bison bc perl elfutils-dev openssl-dev

mkdir -p artifacts/minivim/work
cd artifacts/minivim/work

# Download kernel if needed
if [ ! -d linux-{kernel_version} ]; then
  wget -q https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-{kernel_version}.tar.xz
  tar xf linux-{kernel_version}.tar.xz
  rm linux-{kernel_version}.tar.xz
fi

cd linux-{kernel_version}
make mrproper
make ARCH={arch} tinyconfig

# Merge kernel configs
scripts/kconfig/merge_config.sh -m .config \\
  /work/scripts/benchmarks/kernel-configs/minivim-base.config \\
  /work/scripts/benchmarks/kernel-configs/minivim-{arch}.config

yes '' | make ARCH={arch} olddefconfig
make ARCH={arch} -j$(nproc) bzImage

# Copy output
mkdir -p /work/bench-images/minivim
cp arch/x86/boot/bzImage /work/bench-images/minivim/vmlinuz-{kernel_version}-musl

echo '=== Build Complete ==='
ls -lh /work/bench-images/minivim/vmlinuz-{kernel_version}-musl
'''

    result = subprocess.run(
        [
            "docker", "run", "--rm",
            "-v", f"{repo_root}:/work",
            "-w", "/work",
            "alpine:latest",
            "sh", "-c", script
        ]
    )

    return result.returncode


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Build MiniVim kernel in Alpine Docker"
    )
    parser.add_argument(
        "arch",
        nargs="?",
        default="x86_64",
        help="Target architecture"
    )
    parser.add_argument(
        "kernel_version",
        nargs="?",
        default="6.17.4",
        help="Kernel version"
    )

    args = parser.parse_args()

    script_dir = Path(__file__).parent.resolve()
    repo_root = script_dir.parent.parent

    return build_in_docker(args.arch, args.kernel_version, repo_root)


if __name__ == "__main__":
    sys.exit(main())
