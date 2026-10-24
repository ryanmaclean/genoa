#!/usr/bin/env python3
"""Convenience wrapper for MiniVim kernel builds pinned to Linux 6.17.14.

Usage: ./build_minivim_kernel_617.py [arch] [kernel_version]
Example: ./build_minivim_kernel_617.py x86_64
"""

import os
import subprocess
import sys
from pathlib import Path


DEFAULT_KERNEL_VERSION = "6.17.14"


def main() -> int:
    """Main entry point."""
    script_dir = Path(__file__).parent.resolve()

    arch = sys.argv[1] if len(sys.argv) > 1 else "x86_64"

    if len(sys.argv) >= 3:
        kernel_version = sys.argv[2]
    else:
        kernel_version = os.environ.get("KERNEL_VERSION", DEFAULT_KERNEL_VERSION)

    # Execute the main build script
    build_script = script_dir / "build_minivim_kernel.py"

    result = subprocess.run(
        [sys.executable, str(build_script), arch, kernel_version],
        env=os.environ
    )

    return result.returncode


if __name__ == "__main__":
    sys.exit(main())
