from __future__ import annotations
"""Shared utilities for benchmark scripts.

This module provides common functionality used across benchmark scripts:
- Logging with colors
- Subprocess execution helpers
- Statistics calculations
- Platform detection
- Timing utilities
- JSON result handling
- Datadog metrics emission
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

# Datadog Unified Service Tagging
_dd_service = "bench-benchmark-utils"
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


# Datadog APM tracing
try:
    from ddtrace import patch_all
    patch_all()
except ImportError:
    pass  # ddtrace not installed


import json
import os
import platform
import shutil
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable, TypeVar

# Re-export DogStatsD helpers for convenience
try:
    from ._dogstatsd import DogStatsDSender, emit_duration_metrics, sanitize_label
except ImportError:
    from _dogstatsd import DogStatsDSender, emit_duration_metrics, sanitize_label

__all__ = [
    "REPO_ROOT",
    "SCRIPT_DIR",
    "BenchmarkError",
    "Colors",
    "log",
    "success",
    "warn",
    "error",
    "run_cmd",
    "run_cmd_output",
    "check_command",
    "ms_now",
    "calc_stats",
    "calc_percentile",
    "get_timestamp",
    "get_iso_timestamp",
    "HardwareInfo",
    "get_hardware_info",
    "detect_cpu_count",
    "detect_make_binary",
    "BenchmarkResult",
    "save_results",
    "load_results",
    "DogStatsDSender",
    "emit_duration_metrics",
    "sanitize_label",
    "file_size_bytes",
    "file_size_human",
    "wait_for_condition",
    "wait_for_http",
]

SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent


class BenchmarkError(RuntimeError):
    """Custom exception for benchmark errors."""


class Colors:
    """ANSI color codes for terminal output."""
    GREEN = "\033[0;32m"
    RED = "\033[0;31m"
    YELLOW = "\033[1;33m"
    BLUE = "\033[0;34m"
    NC = "\033[0m"  # No Color

    @classmethod
    def disable(cls) -> None:
        """Disable colors (for non-TTY output)."""
        cls.GREEN = ""
        cls.RED = ""
        cls.YELLOW = ""
        cls.BLUE = ""
        cls.NC = ""


# Disable colors if not a TTY
if not sys.stdout.isatty():
    Colors.disable()


def _timestamp() -> str:
    """Get current time formatted for logging."""
    return datetime.now().strftime("%H:%M:%S")


def log(msg: str) -> None:
    """Log a message with timestamp."""
    print(f"[{_timestamp()}] {msg}")


def success(msg: str) -> None:
    """Log a success message."""
    print(f"{Colors.GREEN}\u2713{Colors.NC} {msg}")


def warn(msg: str) -> None:
    """Log a warning message."""
    print(f"{Colors.YELLOW}\u26a0{Colors.NC} {msg}")


def error(msg: str) -> None:
    """Log an error message."""
    print(f"{Colors.RED}\u2717{Colors.NC} {msg}")


def run_cmd(
    cmd: list[str],
    check: bool = True,
    capture: bool = False,
    timeout: float | None = None,
    cwd: Path | str | None = None,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    """Run a command and return the result.

    Args:
        cmd: Command and arguments as a list
        check: Raise exception on non-zero exit code
        capture: Capture stdout/stderr
        timeout: Timeout in seconds
        cwd: Working directory
        env: Environment variables (merged with current env)

    Returns:
        CompletedProcess result

    Raises:
        BenchmarkError: If command not found or execution fails
    """
    full_env = os.environ.copy()
    if env:
        full_env.update(env)

    try:
        return subprocess.run(
            cmd,
            check=check,
            capture_output=capture,
            text=True,
            timeout=timeout,
            cwd=cwd,
            env=full_env,
        )
    except FileNotFoundError as exc:
        raise BenchmarkError(f"Command not found: {cmd[0]}") from exc
    except subprocess.TimeoutExpired as exc:
        raise BenchmarkError(f"Command timed out after {timeout}s: {' '.join(cmd)}") from exc
    except subprocess.CalledProcessError as exc:
        if check:
            raise BenchmarkError(f"Command failed with code {exc.returncode}: {' '.join(cmd)}") from exc
        raise


def run_cmd_output(
    cmd: list[str],
    timeout: float | None = None,
    cwd: Path | str | None = None,
    env: dict[str, str] | None = None,
) -> str:
    """Run a command and return its stdout.

    Args:
        cmd: Command and arguments as a list
        timeout: Timeout in seconds
        cwd: Working directory
        env: Environment variables

    Returns:
        stdout as string (stripped)

    Raises:
        BenchmarkError: If command fails
    """
    result = run_cmd(cmd, capture=True, timeout=timeout, cwd=cwd, env=env)
    return result.stdout.strip()


def check_command(cmd: str) -> bool:
    """Check if a command is available in PATH."""
    return shutil.which(cmd) is not None


def ms_now() -> int:
    """Get current time in milliseconds."""
    return int(time.time() * 1000)


def calc_stats(samples: list[float | int]) -> dict[str, float]:
    """Calculate statistics from a list of samples.

    Args:
        samples: List of numeric samples

    Returns:
        Dictionary with min, max, avg, p50, p95, p99, stdev
    """
    if not samples:
        return {
            "min": 0.0,
            "max": 0.0,
            "avg": 0.0,
            "p50": 0.0,
            "p95": 0.0,
            "p99": 0.0,
            "stdev": 0.0,
        }

    sorted_samples = sorted(samples)
    n = len(sorted_samples)

    return {
        "min": float(sorted_samples[0]),
        "max": float(sorted_samples[-1]),
        "avg": statistics.mean(samples),
        "p50": calc_percentile(sorted_samples, 50),
        "p95": calc_percentile(sorted_samples, 95),
        "p99": calc_percentile(sorted_samples, 99),
        "stdev": statistics.stdev(samples) if n > 1 else 0.0,
    }


def calc_percentile(sorted_samples: list[float | int], percentile: int) -> float:
    """Calculate percentile from sorted samples.

    Args:
        sorted_samples: Pre-sorted list of samples
        percentile: Percentile to calculate (0-100)

    Returns:
        Percentile value
    """
    if not sorted_samples:
        return 0.0

    n = len(sorted_samples)
    idx = int(percentile / 100 * n)
    idx = max(0, min(idx, n - 1))
    return float(sorted_samples[idx])


def get_timestamp() -> str:
    """Get timestamp in format YYYYMMDD_HHMMSS."""
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def get_iso_timestamp() -> str:
    """Get ISO 8601 timestamp in UTC."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


@dataclass
class HardwareInfo:
    """Hardware information for benchmarks."""
    chip: str = "Unknown"
    logical_cpus: int = 1
    physical_cpus: int = 1
    performance_cores: int = 0
    efficiency_cores: int = 0
    memory_gb: int = 0
    os_name: str = ""
    os_version: str = ""
    arch: str = ""
    is_apple_silicon: bool = False

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary."""
        return {
            "chip": self.chip,
            "logical_cpus": self.logical_cpus,
            "physical_cpus": self.physical_cpus,
            "performance_cores": self.performance_cores,
            "efficiency_cores": self.efficiency_cores,
            "memory_gb": self.memory_gb,
            "os_name": self.os_name,
            "os_version": self.os_version,
            "arch": self.arch,
            "is_apple_silicon": self.is_apple_silicon,
        }


def get_hardware_info() -> HardwareInfo:
    """Detect hardware information."""
    info = HardwareInfo(
        os_name=platform.system(),
        os_version=platform.release(),
        arch=platform.machine(),
    )

    if platform.system() == "Darwin":
        # macOS
        try:
            info.chip = run_cmd_output(["sysctl", "-n", "machdep.cpu.brand_string"])
            info.is_apple_silicon = "Apple M" in info.chip
        except (BenchmarkError, subprocess.CalledProcessError):
            pass

        try:
            info.logical_cpus = int(run_cmd_output(["sysctl", "-n", "hw.logicalcpu"]))
        except (BenchmarkError, ValueError):
            pass

        try:
            info.physical_cpus = int(run_cmd_output(["sysctl", "-n", "hw.physicalcpu"]))
        except (BenchmarkError, ValueError):
            pass

        try:
            info.performance_cores = int(run_cmd_output(["sysctl", "-n", "hw.perflevel0.physicalcpu"]))
        except (BenchmarkError, ValueError):
            pass

        try:
            info.efficiency_cores = int(run_cmd_output(["sysctl", "-n", "hw.perflevel1.physicalcpu"]))
        except (BenchmarkError, ValueError):
            pass

        try:
            mem_bytes = int(run_cmd_output(["sysctl", "-n", "hw.memsize"]))
            info.memory_gb = mem_bytes // (1024 * 1024 * 1024)
        except (BenchmarkError, ValueError):
            pass

    elif platform.system() == "Linux":
        # Linux
        try:
            info.logical_cpus = os.cpu_count() or 1
            info.physical_cpus = info.logical_cpus
        except Exception:
            pass

        try:
            with open("/proc/meminfo") as f:
                for line in f:
                    if line.startswith("MemTotal:"):
                        mem_kb = int(line.split()[1])
                        info.memory_gb = mem_kb // (1024 * 1024)
                        break
        except (FileNotFoundError, ValueError, IndexError):
            pass

        try:
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if line.startswith("model name"):
                        info.chip = line.split(":")[1].strip()
                        break
        except (FileNotFoundError, ValueError, IndexError):
            pass

    return info


def detect_cpu_count() -> int:
    """Detect the number of CPUs available for parallel builds."""
    if platform.system() == "Darwin":
        try:
            return int(run_cmd_output(["sysctl", "-n", "hw.logicalcpu"]))
        except (BenchmarkError, ValueError):
            pass

    if check_command("nproc"):
        try:
            return int(run_cmd_output(["nproc"]))
        except (BenchmarkError, ValueError):
            pass

    return os.cpu_count() or 4


def detect_make_binary() -> str:
    """Detect the make binary to use (gmake on macOS, make elsewhere)."""
    if check_command("gmake"):
        return "gmake"
    return "make"


@dataclass
class BenchmarkResult:
    """Container for benchmark results."""
    benchmark_id: str
    timestamp: str = field(default_factory=get_iso_timestamp)
    hardware: dict[str, Any] = field(default_factory=dict)
    configuration: dict[str, Any] = field(default_factory=dict)
    results: list[dict[str, Any]] = field(default_factory=list)
    summary: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        """Convert to dictionary for JSON serialization."""
        return {
            "benchmark_id": self.benchmark_id,
            "timestamp": self.timestamp,
            "hardware": self.hardware,
            "configuration": self.configuration,
            "results": self.results,
            "summary": self.summary,
        }


def save_results(results: BenchmarkResult | dict[str, Any], path: Path) -> None:
    """Save benchmark results to JSON file.

    Args:
        results: BenchmarkResult or dictionary
        path: Output file path
    """
    path.parent.mkdir(parents=True, exist_ok=True)

    data = results.to_dict() if isinstance(results, BenchmarkResult) else results

    with open(path, "w") as f:
        json.dump(data, f, indent=2)

    log(f"Results saved to: {path}")


def load_results(path: Path) -> dict[str, Any]:
    """Load benchmark results from JSON file.

    Args:
        path: Input file path

    Returns:
        Dictionary of results

    Raises:
        BenchmarkError: If file not found or invalid JSON
    """
    if not path.exists():
        raise BenchmarkError(f"Results file not found: {path}")

    try:
        with open(path) as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise BenchmarkError(f"Invalid JSON in {path}: {exc}") from exc


def file_size_bytes(path: Path | str) -> int:
    """Get file size in bytes."""
    return Path(path).stat().st_size


def file_size_human(size_bytes: int) -> str:
    """Convert bytes to human-readable format."""
    for unit in ["B", "KB", "MB", "GB", "TB"]:
        if abs(size_bytes) < 1024.0:
            return f"{size_bytes:.1f}{unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.1f}PB"


T = TypeVar("T")


def wait_for_condition(
    condition: Callable[[], T | None],
    timeout_seconds: float = 30.0,
    poll_interval: float = 0.1,
    description: str = "condition",
) -> T:
    """Wait for a condition to become true.

    Args:
        condition: Callable that returns a truthy value when condition is met, None/False otherwise
        timeout_seconds: Maximum time to wait
        poll_interval: Time between checks
        description: Description for error messages

    Returns:
        The truthy value returned by condition

    Raises:
        BenchmarkError: If timeout is reached
    """
    start = time.monotonic()
    deadline = start + timeout_seconds

    while time.monotonic() < deadline:
        result = condition()
        if result:
            return result
        time.sleep(poll_interval)

    raise BenchmarkError(f"Timeout waiting for {description} after {timeout_seconds}s")


def wait_for_http(
    url: str,
    timeout_seconds: float = 30.0,
    poll_interval: float = 0.1,
) -> int:
    """Wait for an HTTP endpoint to become available.

    Args:
        url: URL to check
        timeout_seconds: Maximum time to wait
        poll_interval: Time between checks

    Returns:
        Time in milliseconds until endpoint was ready

    Raises:
        BenchmarkError: If timeout is reached
    """
    import urllib.request
    import urllib.error

    start_ms = ms_now()

    def check() -> int | None:
        try:
            with urllib.request.urlopen(url, timeout=1) as resp:
                if resp.status < 500:
                    return ms_now() - start_ms
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError):
            pass
        return None

    return wait_for_condition(check, timeout_seconds, poll_interval, f"HTTP {url}")