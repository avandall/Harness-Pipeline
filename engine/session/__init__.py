"""Session management and durable event logging layer."""

from engine.session.compactor import truncate_log
from engine.session.event_log import EventLog, EventType

__all__ = ["EventLog", "EventType", "truncate_log"]
