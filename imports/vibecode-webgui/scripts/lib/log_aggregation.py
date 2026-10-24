#!/usr/bin/env python3
try:
    import os as _os

    _c = __import__("ddtrace").config
    _s = _os.path.basename(__file__).replace(".py", "")
    _c.service = _s
    _c.requests.service = _s
    __import__("ddtrace").patch_all()
except (ImportError, Exception):
    pass


# -- VibeCode Telemetry --
import sys
import os

try:
    sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), "../")))
    from vibecode.telemetry import init_telemetry

    tracer = init_telemetry(os.path.basename(__file__))
except ImportError:
    pass
# ------------------------

"""Datadog Log Aggregation Module.

Provides centralized logging functionality for all deployment scripts.
"""

import atexit
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from enum import IntEnum
from pathlib import Path
from typing import Any, Dict, Optional

# Configuration
LOG_AGGREGATION_ENABLED = (
    os.environ.get("DD_LOG_AGGREGATION_ENABLED", "true").lower() == "true"
)
LOG_SERVICE_NAME = os.environ.get("DD_SERVICE", "vibecode-webgui")
LOG_ENVIRONMENT = os.environ.get("DD_ENV", "development")
LOG_VERSION = os.environ.get("DD_VERSION", "1.0.0")
DD_API_KEY = os.environ.get("DD_API_KEY", "")


class LogLevel(IntEnum):
    """Log levels."""

    DEBUG = 0
    INFO = 1
    WARN = 2
    ERROR = 3


# Current log level
CURRENT_LOG_LEVEL = LogLevel(int(os.environ.get("DD_LOG_LEVEL", str(LogLevel.INFO))))

# Global log file path
LOG_FILE: Optional[Path] = None


def _get_timestamp() -> str:
    """Get current UTC timestamp in ISO format."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _get_script_name() -> str:
    """Get the current script name."""
    return Path(sys.argv[0]).name if sys.argv else "unknown"


def init_log_aggregation() -> bool:
    """Initialize log aggregation.

    Returns:
        True if successful, False otherwise.
    """
    global LOG_AGGREGATION_ENABLED, LOG_FILE

    if not LOG_AGGREGATION_ENABLED:
        print("Log aggregation disabled")
        return False

    print("Initializing Datadog log aggregation...")

    # Check required environment variables
    if not DD_API_KEY:
        print("Warning: DD_API_KEY not set, log aggregation disabled")
        LOG_AGGREGATION_ENABLED = False
        return False

    # Create log directory if it doesn't exist
    log_dir = Path("/tmp/datadog-logs")
    log_dir.mkdir(parents=True, exist_ok=True)

    # Initialize log file with metadata
    script_name = _get_script_name()
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    LOG_FILE = log_dir / f"{script_name}-{timestamp}.log"

    metadata = {
        "service": LOG_SERVICE_NAME,
        "env": LOG_ENVIRONMENT,
        "version": LOG_VERSION,
        "timestamp": _get_timestamp(),
    }

    with open(LOG_FILE, "w") as f:
        f.write(json.dumps(metadata) + "\n")

    print(f"Log aggregation initialized: {LOG_FILE}")
    return True


def get_log_aggregation() -> bool:
    """Backward-compatible helper for legacy scripts."""
    return init_log_aggregation()


def send_log_to_datadog(level: str, message: str, context: Dict[str, Any]) -> bool:
    """Send log to Datadog.

    Args:
        level: Log level.
        message: Log message.
        context: Additional context dictionary.

    Returns:
        True if successful, False otherwise.
    """
    if not LOG_AGGREGATION_ENABLED:
        return False

    log_entry = {
        "timestamp": _get_timestamp(),
        "level": level,
        "message": message,
        "service": LOG_SERVICE_NAME,
        "env": LOG_ENVIRONMENT,
        "version": LOG_VERSION,
        "script": _get_script_name(),
        "context": context,
    }

    # Write to local log file
    if LOG_FILE and LOG_FILE.exists():
        with open(LOG_FILE, "a") as f:
            f.write(json.dumps(log_entry) + "\n")

    # Send to Datadog Logs API
    try:
        subprocess.run(
            [
                "curl",
                "-s",
                "-X",
                "POST",
                f"https://http-intake.logs.datadoghq.com/v1/input/{DD_API_KEY}",
                "-H",
                "Content-Type: application/json",
                "-d",
                json.dumps(log_entry),
            ],
            capture_output=True,
            timeout=5,
        )
        return True
    except (subprocess.TimeoutExpired, subprocess.SubprocessError, FileNotFoundError):
        return False


def log_debug(message: str) -> None:
    """Log a debug message."""
    if CURRENT_LOG_LEVEL <= LogLevel.DEBUG:
        print(f"DEBUG: {message}")
        send_log_to_datadog("DEBUG", message, {"component": _get_script_name()})


def log_info(message: str) -> None:
    """Log an info message."""
    if CURRENT_LOG_LEVEL <= LogLevel.INFO:
        print(f"INFO: {message}")
        send_log_to_datadog("INFO", message, {"component": _get_script_name()})


def log_warn(message: str) -> None:
    """Log a warning message."""
    if CURRENT_LOG_LEVEL <= LogLevel.WARN:
        print(f"WARN: {message}")
        send_log_to_datadog("WARN", message, {"component": _get_script_name()})


def log_error(message: str) -> None:
    """Log an error message."""
    if CURRENT_LOG_LEVEL <= LogLevel.ERROR:
        print(f"ERROR: {message}")
        send_log_to_datadog(
            "ERROR", message, {"component": _get_script_name(), "error": True}
        )


def log_script_start(script_name: str, parameters: str = "") -> None:
    """Log script start event."""
    log_info(f"Script started: {script_name}")
    send_log_to_datadog(
        "INFO",
        "Script execution started",
        {"script": script_name, "parameters": parameters, "event": "script_start"},
    )


def log_script_end(script_name: str, exit_code: int, duration: float) -> None:
    """Log script end event."""
    if exit_code == 0:
        log_info(f"Script completed successfully: {script_name} ({duration:.2f}s)")
        send_log_to_datadog(
            "INFO",
            "Script execution completed",
            {
                "script": script_name,
                "exit_code": exit_code,
                "duration": duration,
                "event": "script_end",
            },
        )
    else:
        log_error(
            f"Script failed: {script_name} (exit code: {exit_code}, duration: {duration:.2f}s)"
        )
        send_log_to_datadog(
            "ERROR",
            "Script execution failed",
            {
                "script": script_name,
                "exit_code": exit_code,
                "duration": duration,
                "event": "script_end",
                "error": True,
            },
        )


def log_deployment_event(
    event_type: str, component: str, status: str, details: str = ""
) -> None:
    """Log a deployment event."""
    log_info(f"Deployment event: {event_type} - {component} ({status})")
    send_log_to_datadog(
        "INFO",
        "Deployment event",
        {
            "event_type": event_type,
            "component": component,
            "status": status,
            "details": details,
            "event": "deployment",
        },
    )


def log_kubernetes_event(
    operation: str, resource: str, namespace: str, status: str
) -> None:
    """Log a Kubernetes event."""
    log_info(f"Kubernetes event: {operation} {resource} in {namespace} ({status})")
    send_log_to_datadog(
        "INFO",
        "Kubernetes operation",
        {
            "operation": operation,
            "resource": resource,
            "namespace": namespace,
            "status": status,
            "event": "kubernetes",
        },
    )


def log_database_event(
    operation: str, database: str, status: str, details: str = ""
) -> None:
    """Log a database event."""
    log_info(f"Database event: {operation} on {database} ({status})")
    send_log_to_datadog(
        "INFO",
        "Database operation",
        {
            "operation": operation,
            "database": database,
            "status": status,
            "details": details,
            "event": "database",
        },
    )


def log_performance_metric(
    metric_name: str, value: float, unit: str, tags: str = ""
) -> None:
    """Log a performance metric."""
    log_debug(f"Performance metric: {metric_name} = {value} {unit}")
    send_log_to_datadog(
        "INFO",
        "Performance metric",
        {
            "metric_name": metric_name,
            "value": value,
            "unit": unit,
            "tags": tags,
            "event": "performance",
        },
    )


def cleanup_log_aggregation() -> None:
    """Cleanup function for log aggregation."""
    if LOG_FILE and LOG_FILE.exists():
        try:
            # Count log entries
            line_count = sum(1 for _ in open(LOG_FILE))

            send_log_to_datadog(
                "INFO",
                "Script execution summary",
                {
                    "total_log_entries": line_count,
                    "log_file": str(LOG_FILE),
                    "event": "script_summary",
                },
            )

            # Clean up old log files (keep last day's worth)
            log_dir = Path("/tmp/datadog-logs")
            if log_dir.exists():
                for old_log in log_dir.glob("*.log"):
                    if old_log != LOG_FILE:
                        # Check if file is older than 1 day
                        import time

                        if (time.time() - old_log.stat().st_mtime) > 86400:
                            old_log.unlink()
        except (OSError, IOError, Exception):
            pass  # Ignore cleanup errors


# Register cleanup on exit
atexit.register(cleanup_log_aggregation)
