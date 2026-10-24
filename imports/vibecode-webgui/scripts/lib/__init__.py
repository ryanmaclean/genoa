# scripts/lib/__init__.py
# Expose modules for testing
# Datadog Unified Service Tagging
_dd_service = "--init--"
_dd_env = __import__("os").environ.get("DD_ENV", "development")
_dd_version = __import__("os").environ.get("DD_VERSION", "0.1.0")
try:
    from ddtrace import config as _dd_config, patch_all as _dd_patch, tracer as _dd_tracer
    _dd_config.service = _dd_service
    _dd_config.env = _dd_env
    _dd_config.version = _dd_version
    _dd_tracer.set_tags({"team": "platform", "component": "library"})
    _dd_patch()
except ImportError:
    pass
from . import datadog_logging
