"""Unit tests for Core Engine components."""

import tempfile
from pathlib import Path

try:
    from pipeline.engine.harness.loop import RalphLoopRunner
    from pipeline.engine.observability.cost_tracker import CostTracker
    from pipeline.engine.security.hitl_gate import HumanInTheLoopGate
    from pipeline.engine.security.vault_proxy import SecretVaultProxy
    from pipeline.engine.session.compactor import truncate_log
    from pipeline.engine.session.event_log import EventLog, EventType
except ImportError:
    from engine.harness.loop import RalphLoopRunner  # type: ignore[no-redef]
    from engine.observability.cost_tracker import CostTracker  # type: ignore[no-redef]
    from engine.security.hitl_gate import HumanInTheLoopGate  # type: ignore[no-redef]
    from engine.security.vault_proxy import SecretVaultProxy  # type: ignore[no-redef]
    from engine.session.compactor import truncate_log  # type: ignore[no-redef]
    from engine.session.event_log import EventLog, EventType  # type: ignore[no-redef]


def test_log_compactor():
    verbose_log = "\n".join([f"Line {i}" for i in range(100)]) + "\nTraceback (most recent call last):\nE   ValueError: Invalid input"
    truncated = truncate_log(verbose_log, max_lines=5)
    assert "ValueError: Invalid input" in truncated
    assert len(truncated.split("\n")) <= 5


def test_event_log_append_and_read():
    with tempfile.TemporaryDirectory() as tmpdir:
        log_path = Path(tmpdir) / "test_session.jsonl"
        logger = EventLog(log_path)
        logger.append(EventType.USER_INPUT, step=1, payload={"input": "Start task"})

        events = logger.get_all_events()
        assert len(events) == 1
        assert events[0].event_type == EventType.USER_INPUT
        assert events[0].payload["input"] == "Start task"


def test_hitl_gate():
    gate = HumanInTheLoopGate()
    is_risk, _ = gate.inspect_action("SHELL", "git push origin main")
    assert is_risk is True

    is_risk_safe, _ = gate.inspect_action("SHELL", "pytest")
    assert is_risk_safe is False


def test_vault_proxy():
    vault = SecretVaultProxy({"SECRET_KEY": "sk-1234567890supersecret"})
    sanitized = vault.sanitize_output("Calling API with key sk-1234567890supersecret")
    assert "sk-1234567890supersecret" not in sanitized
    assert "[REDACTED_SECRET]" in sanitized


def test_cost_tracker():
    tracker = CostTracker()
    cost = tracker.record_usage("gemini-3.6-flash", prompt_tokens=1000, completion_tokens=500)
    assert cost > 0
    summary = tracker.get_summary()
    assert summary["total_tokens"] == 1500


def test_ralph_loop_runner_execution():
    with tempfile.TemporaryDirectory() as tmpdir:
        runner = RalphLoopRunner(task_id="TEST-001", workspace_dir=Path(tmpdir))
        res = runner.run_iteration("STATIC_CHECK", "ruff check .")
        assert res["status"] == "SUCCESS"
        assert runner.event_log.get_step_count() > 0
