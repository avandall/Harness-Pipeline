"""State Machine for Agent Ralph Loop (Layer 2 - Harness)."""

from enum import Enum
from typing import ClassVar


class PipelineState(str, Enum):
    ORIENT = "ORIENT"
    PLANNING = "PLANNING"
    EXECUTING = "EXECUTING"
    REVIEWING = "REVIEWING"
    COMMITTING = "COMMITTING"
    DONE = "DONE"
    BLOCKED = "BLOCKED"


class StateMachine:
    """State transition controller for autonomous tasks."""

    VALID_TRANSITIONS: ClassVar[dict[PipelineState, list[PipelineState]]] = {

        PipelineState.ORIENT: [PipelineState.PLANNING, PipelineState.BLOCKED],
        PipelineState.PLANNING: [PipelineState.EXECUTING, PipelineState.BLOCKED],
        PipelineState.EXECUTING: [PipelineState.REVIEWING, PipelineState.BLOCKED],
        PipelineState.REVIEWING: [PipelineState.COMMITTING, PipelineState.EXECUTING, PipelineState.BLOCKED],
        PipelineState.COMMITTING: [PipelineState.DONE, PipelineState.BLOCKED],
        PipelineState.DONE: [],
        PipelineState.BLOCKED: [PipelineState.ORIENT],
    }

    def __init__(self, initial_state: PipelineState = PipelineState.ORIENT):
        self._state: PipelineState = initial_state
        self._history: list[PipelineState] = [initial_state]

    @property
    def current_state(self) -> PipelineState:
        return self._state

    def transition_to(self, target_state: PipelineState) -> bool:
        """Attempt to transition to a new target state."""
        allowed = self.VALID_TRANSITIONS.get(self._state, [])
        if target_state in allowed:
            self._state = target_state
            self._history.append(target_state)
            return True
        raise ValueError(f"Invalid transition from {self._state} to {target_state}")
