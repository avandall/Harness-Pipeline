"""OpenTelemetry Tracer for Pipeline execution (Layer 6 - Observability)."""

import time


class PipelineTracer:
    """Simple lightweight tracer for tracking step latency and execution events."""

    def __init__(self, service_name: str = "enterprise-agent-pipeline"):
        self.service_name: str = service_name
        self._spans: dict[str, float] = {}

    def start_span(self, span_name: str) -> None:
        """Start a timer for a named execution span."""
        self._spans[span_name] = time.time()

    def end_span(self, span_name: str) -> float | None:
        """End span timer and return duration in seconds."""
        start_time = self._spans.pop(span_name, None)
        if start_time is not None:
            return round(time.time() - start_time, 4)
        return None
