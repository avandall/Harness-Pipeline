"""Durable append-only JSONL Event Log store (Layer 3 - Session)."""

from datetime import datetime, timezone
from enum import Enum
from pathlib import Path
from typing import Any

from pydantic import BaseModel, Field


class EventType(str, Enum):
    USER_INPUT = "USER_INPUT"
    MODEL_THOUGHT = "MODEL_THOUGHT"
    TOOL_CALL = "TOOL_CALL"
    TOOL_RESULT = "TOOL_RESULT"
    HUMAN_INTERVENTION = "HUMAN_INTERVENTION"
    STATE_CHANGE = "STATE_CHANGE"


class Event(BaseModel):
    timestamp: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).isoformat()
    )
    event_type: EventType
    step: int
    payload: dict[str, Any]


class EventLog:
    """Manages append-only JSONL event logs for deterministic state recovery."""

    def __init__(self, log_path: Path):
        self.log_path: Path = Path(log_path)
        self.log_path.parent.mkdir(parents=True, exist_ok=True)
        if not self.log_path.exists():
            self.log_path.touch()

    def append(self, event_type: EventType, step: int, payload: dict[str, Any]) -> Event:
        """Append a new event to the JSONL log file."""
        event = Event(event_type=event_type, step=step, payload=payload)
        with open(self.log_path, "a", encoding="utf-8") as f:
            f.write(event.model_dump_json() + "\n")
        return event

    def get_all_events(self) -> list[Event]:
        """Read all events from the event log file."""
        events: list[Event] = []
        if not self.log_path.exists():
            return events

        with open(self.log_path, "r", encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line:
                    events.append(Event.model_validate_json(line))
        return events

    def get_last_event(self) -> Event | None:
        """Return the most recent event logged, if any."""
        events = self.get_all_events()
        return events[-1] if events else None

    def get_step_count(self) -> int:
        """Get current step count based on logged events."""
        events = self.get_all_events()
        return events[-1].step if events else 0
