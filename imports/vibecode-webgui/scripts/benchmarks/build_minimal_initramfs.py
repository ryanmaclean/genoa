#!/usr/bin/env python3
"""Build minimal BusyBox initramfs for Apple VF fast boot experiments.

Target: Sub-2MB initramfs with /healthz endpoint.
"""

import argparse
import gzip
import os
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


# Colors for output
GREEN = '\033[0;32m'
NC = '\033[0m'


@dataclass
class BuildConfig:
    """Build configuration."""

    arch: str = "arm64"
    output_dir: Path = Path()
    busybox_version: str = "1.36.1"


def log(msg: str) -> None:
    """Print log message."""
    print(f"{GREEN}[INFO]{NC} {msg}")


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


def build_busybox(config: BuildConfig, root_dir: Path) -> Optional[Path]:
    """Build or locate BusyBox binary."""
    busybox_src = root_dir / "bench-images" / "busybox" / f"busybox-{config.busybox_version}"
    busybox_bin = busybox_src / "busybox"

    if not busybox_bin.exists():
        log("Building BusyBox...")
        build_script = root_dir / "scripts" / "benchmarks" / "build_busybox_musl.py"
        if build_script.exists():
            subprocess.run(
                [sys.executable, str(build_script), config.arch]
            )
        else:
            # Try the shell script
            shell_script = root_dir / "scripts" / "benchmarks" / "build-busybox-musl.sh"
            if shell_script.exists():
                subprocess.run(["bash", str(shell_script), config.arch])

    if busybox_bin.exists():
        return busybox_bin

    return None


def create_rootfs(config: BuildConfig, busybox_bin: Path) -> Path:
    """Create the rootfs structure."""
    rootfs = config.output_dir / "rootfs"

    # Clean and create directories
    if rootfs.exists():
        shutil.rmtree(rootfs)

    for d in ["bin", "sbin", "etc", "proc", "sys", "dev", "tmp", "var/run"]:
        (rootfs / d).mkdir(parents=True, exist_ok=True)

    log("Creating minimal rootfs...")

    # Copy BusyBox
    busybox_dst = rootfs / "bin" / "busybox"
    shutil.copy2(busybox_bin, busybox_dst)
    busybox_dst.chmod(0o755)

    # Create essential symlinks
    bin_cmds = ["sh", "ash", "init", "mount", "umount", "mkdir", "cat", "echo",
                "ls", "ps", "kill", "sleep", "ip", "ifconfig", "route", "ping",
                "wget", "httpd", "nc"]
    for cmd in bin_cmds:
        link = rootfs / "bin" / cmd
        if not link.exists():
            link.symlink_to("busybox")

    sbin_cmds = ["init", "halt", "reboot", "poweroff"]
    for cmd in sbin_cmds:
        link = rootfs / "sbin" / cmd
        if not link.exists():
            link.symlink_to("../bin/busybox")

    return rootfs


def create_init_script(rootfs: Path) -> None:
    """Create the init script."""
    init_script = '''#!/bin/sh
# Minimal init for Apple VF fast boot benchmark
# Target: Boot to /healthz in < 3s

# Mount essential filesystems
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
mount -t tmpfs tmpfs /tmp
mount -t tmpfs tmpfs /var/run

# Configure network (static IP for deterministic boot)
ip link set lo up
ip link set eth0 up 2>/dev/null || true

# Try DHCP first, fall back to static
if ! ip addr show eth0 | grep -q "inet "; then
  # Use static IP for Apple VF NAT (10.0.2.x range)
  ip addr add 10.0.2.15/24 dev eth0
  ip route add default via 10.0.2.2
fi

# Create /healthz response file
mkdir -p /www
echo "ok" > /www/healthz
cat > /www/index.html << 'HTML'
<!DOCTYPE html>
<html><head><title>Apple VF Fast Boot</title></head>
<body><h1>VM Ready</h1><p>Boot complete.</p></body>
</html>
HTML

# Start HTTP server for /healthz endpoint
# BusyBox httpd serves /www on port 80
httpd -p 3000 -h /www &

# Signal boot complete
echo "Boot complete - /healthz ready on port 3000"

# Keep init running
exec /bin/sh
'''

    init_path = rootfs / "init"
    init_path.write_text(init_script)
    init_path.chmod(0o755)


def create_etc_files(rootfs: Path) -> None:
    """Create minimal /etc files."""
    (rootfs / "etc" / "passwd").write_text("root:x:0:0:root:/:/bin/sh\n")
    (rootfs / "etc" / "group").write_text("root:x:0:\n")
    (rootfs / "etc" / "hostname").write_text("localhost\n")


def create_initramfs(rootfs: Path, output_file: Path) -> None:
    """Create the initramfs archive."""
    log("Creating initramfs...")

    # Use cpio to create archive
    result = subprocess.run(
        ["find", ".", "-print0"],
        cwd=rootfs,
        capture_output=True
    )

    cpio_result = subprocess.run(
        ["cpio", "--null", "-o", "-H", "newc"],
        input=result.stdout,
        cwd=rootfs,
        capture_output=True
    )

    # Compress with gzip
    with gzip.open(output_file, "wb", compresslevel=9) as f:
        f.write(cpio_result.stdout)


def get_size_human(path: Path) -> str:
    """Get human-readable file size."""
    size = path.stat().st_size
    for unit in ["B", "KB", "MB", "GB"]:
        if size < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def build(config: BuildConfig) -> int:
    """Run the full build process."""
    print("=== Building Minimal Initramfs for Apple VF Fast Boot ===")
    print(f"Architecture: {config.arch}")
    print(f"Output: {config.output_dir}")
    print()

    config.output_dir.mkdir(parents=True, exist_ok=True)

    script_dir = Path(__file__).parent.resolve()
    root_dir = script_dir.parent.parent

    # Build or find BusyBox
    busybox_bin = build_busybox(config, root_dir)
    if not busybox_bin or not busybox_bin.exists():
        print("Error: Could not find or build BusyBox")
        return 1

    # Create rootfs
    rootfs = create_rootfs(config, busybox_bin)

    # Create init script
    create_init_script(rootfs)

    # Create /etc files
    create_etc_files(rootfs)

    # Create initramfs
    output_file = config.output_dir / "initramfs-minimal.cpio.gz"
    create_initramfs(rootfs, output_file)

    # Report sizes
    rootfs_size = sum(f.stat().st_size for f in rootfs.rglob("*") if f.is_file())
    initramfs_size = output_file.stat().st_size

    print()
    print("=== Build Complete ===")
    print(f"Rootfs size: {rootfs_size / 1024:.1f} KB")
    print(f"Initramfs size: {get_size_human(output_file)}")
    print(f"Output: {output_file}")
    print()
    print("To test:")
    print(f"  MICROVM_INITRD={output_file} \\")
    print("  scripts/benchmarks/vscode_microvm.py measure")

    return 0


def main() -> int:
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Build minimal BusyBox initramfs for Apple VF fast boot"
    )
    parser.add_argument(
        "arch",
        nargs="?",
        default="arm64",
        help="Target architecture"
    )
    parser.add_argument(
        "--busybox-version",
        default=os.environ.get("BUSYBOX_VERSION", "1.36.1"),
        help="BusyBox version"
    )

    args = parser.parse_args()

    script_dir = Path(__file__).parent.resolve()
    root_dir = script_dir.parent.parent
    output_dir = root_dir / "bench-images" / "apple-vf-fastboot"

    config = BuildConfig(
        arch=args.arch,
        output_dir=output_dir,
        busybox_version=args.busybox_version
    )

    return build(config)


if __name__ == "__main__":
    sys.exit(main())
