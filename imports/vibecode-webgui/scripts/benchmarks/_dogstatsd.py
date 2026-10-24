"""Shared DogStatsD helpers for benchmark scripts."""
from __future__ import annotations

import socket
from typing import Iterable

# Datadog APM tracing
try:
    import ddtrace
    ddtrace.patch_all()
except ImportError:
    pass


class DogStatsDSender:
  """Minimal DogStatsD/StatsD client."""

  def __init__(
      self,
      host: str = "127.0.0.1",
      port: int = 8125,
      enabled: bool = False,
      prefix: str | None = None,
      default_tags: Iterable[str] | None = None,
  ) -> None:
    self.address = (host, port)
    self.enabled = enabled
    self.prefix = prefix.rstrip(".") if prefix else None
    self.default_tags = list(default_tags or [])
    self.sock: socket.socket | None = None

  def _maybe_sock(self) -> socket.socket | None:
    if not self.enabled:
      return None
    if self.sock is None:
      try:
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
      except OSError:
        self.enabled = False
        return None
    return self.sock

  def _metric_name(self, name: str) -> str:
    if self.prefix:
      return f"{self.prefix}.{name}"
    return name

  @staticmethod
  def _format_tags(tags: list[str] | None) -> str:
    if not tags:
      return ""
    return "|#" + ",".join(tags)

  def _send(self, payload: str) -> None:
    sock = self._maybe_sock()
    if not sock:
      return
    try:
      sock.sendto(payload.encode("utf-8"), self.address)
    except OSError:
      self.enabled = False

  def timing(self, name: str, value_seconds: float, tags: list[str] | None = None) -> None:
    metric = self._metric_name(name)
    payload = f"{metric}:{value_seconds * 1000:.6f}|ms{self._format_tags(self.default_tags + (tags or []))}"
    self._send(payload)

  def gauge(self, name: str, value_seconds: float, tags: list[str] | None = None) -> None:
    metric = self._metric_name(name)
    payload = f"{metric}:{value_seconds * 1000:.6f}|g{self._format_tags(self.default_tags + (tags or []))}"
    self._send(payload)


def sanitize_label(label: str) -> str:
  return (
      label.lower()
      .replace(" ", "_")
      .replace("/", "_")
      .replace("(", "")
      .replace(")", "")
      .replace(":", "")
  )


def emit_duration_metrics(results: list[dict], sender: DogStatsDSender) -> None:
  if not sender.enabled:
    return
  for entry in results:
    tags = list(entry.get("tags", []))
    tags.append(f"label:{sanitize_label(entry['label'])}")
    samples = entry.get("samples", [])
    for idx, sample in enumerate(samples):
      sender.timing("duration", sample, tags + [f"sample:{idx}"])
    sender.gauge("duration.avg", entry["avg_seconds"], tags)
    sender.gauge("duration.min", entry["min_seconds"], tags)
    sender.gauge("duration.max", entry["max_seconds"], tags)
