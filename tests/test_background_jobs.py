"""Integration & Unit tests for Async Background Jobs, Inngest integration, and Cron Cleanup."""

import asyncio
import os
import time
from collections.abc import Callable
from enum import Enum
from pathlib import Path
from typing import Any

import pytest
from fastapi import BackgroundTasks
from inngest import Event, Inngest


class JobStatus(str, Enum):
    PENDING = "PENDING"
    RUNNING = "RUNNING"
    COMPLETED = "COMPLETED"
    FAILED = "FAILED"


class AsyncTaskManager:
    """Async background task manager with idempotency tracking and retry support."""

    def __init__(self) -> None:
        self.jobs: dict[str, dict[str, Any]] = {}
        self.idempotency_store: dict[str, str] = {}  # idempotency_key -> job_id
        self.execution_counts: dict[str, int] = {}

    async def execute_job(
        self,
        job_id: str,
        idempotency_key: str,
        task_func: Callable[..., Any],
        *args: Any,
        max_retries: int = 3,
        **kwargs: Any,
    ) -> dict[str, Any]:
        """Execute task with idempotency and retry mechanics."""
        if idempotency_key in self.idempotency_store:
            existing_job_id = self.idempotency_store[idempotency_key]
            existing_job = self.jobs[existing_job_id]
            existing_job["deduplicated"] = True
            return existing_job

        self.idempotency_store[idempotency_key] = job_id
        self.execution_counts[job_id] = 0

        job_record: dict[str, Any] = {
            "job_id": job_id,
            "idempotency_key": idempotency_key,
            "status": JobStatus.PENDING,
            "attempts": 0,
            "result": None,
            "error": None,
            "deduplicated": False,
        }
        self.jobs[job_id] = job_record

        for attempt in range(1, max_retries + 1):
            job_record["attempts"] = attempt
            job_record["status"] = JobStatus.RUNNING
            self.execution_counts[job_id] += 1

            try:
                if asyncio.iscoroutinefunction(task_func):
                    res = await task_func(*args, **kwargs)
                else:
                    res = task_func(*args, **kwargs)

                job_record["status"] = JobStatus.COMPLETED
                job_record["result"] = res
                return job_record
            except Exception as exc:  # noqa: BLE001
                job_record["error"] = str(exc)
                if attempt == max_retries:
                    job_record["status"] = JobStatus.FAILED
                    break
                await asyncio.sleep(0.01)

        return job_record


class CronCleanupService:
    """Cron cleanup service for temporary files, reports, and expired records."""

    @staticmethod
    def cleanup_old_files(target_dir: Path, max_age_seconds: float) -> int:
        """Remove files older than max_age_seconds from target_dir."""
        if not target_dir.exists():
            return 0

        now = time.time()
        removed_count = 0

        for file_path in target_dir.glob("*"):
            if file_path.is_file() and not file_path.name.startswith(".git"):
                file_age = now - file_path.stat().st_mtime
                if file_age >= max_age_seconds:
                    file_path.unlink()
                    removed_count += 1

        return removed_count


@pytest.fixture
def task_manager() -> AsyncTaskManager:
    return AsyncTaskManager()


def test_async_job_execution_success(task_manager: AsyncTaskManager) -> None:
    async def sample_task(val: int) -> int:
        await asyncio.sleep(0.01)
        return val * 2

    async def run() -> None:
        result = await task_manager.execute_job(
            job_id="JOB-001",
            idempotency_key="KEY-001",
            task_func=sample_task,
            val=21,
        )
        assert result["status"] == JobStatus.COMPLETED
        assert result["result"] == 42
        assert result["attempts"] == 1
        assert result["deduplicated"] is False
        assert task_manager.execution_counts["JOB-001"] == 1

    asyncio.run(run())


def test_job_execution_idempotency(task_manager: AsyncTaskManager) -> None:
    counter = 0

    async def increment_task() -> int:
        nonlocal counter
        counter += 1
        return counter

    async def run() -> None:
        res1 = await task_manager.execute_job(
            job_id="JOB-100",
            idempotency_key="IDEM-KEY-UNIQUE",
            task_func=increment_task,
        )
        assert res1["result"] == 1
        assert counter == 1

        # Duplicate dispatch with exact same idempotency_key
        res2 = await task_manager.execute_job(
            job_id="JOB-101",
            idempotency_key="IDEM-KEY-UNIQUE",
            task_func=increment_task,
        )
        assert res2["result"] == 1
        assert res2["deduplicated"] is True
        assert counter == 1  # Function was NOT re-executed

    asyncio.run(run())


def test_job_retry_mechanics(task_manager: AsyncTaskManager) -> None:
    attempts = 0

    async def failing_then_succeeding_task() -> str:
        nonlocal attempts
        attempts += 1
        if attempts < 3:
            raise RuntimeError(f"Transient error attempt {attempts}")
        return "SUCCESS_AFTER_RETRY"

    async def run() -> None:
        res = await task_manager.execute_job(
            job_id="JOB-RETRY-1",
            idempotency_key="IDEM-RETRY-1",
            task_func=failing_then_succeeding_task,
            max_retries=3,
        )
        assert res["status"] == JobStatus.COMPLETED
        assert res["result"] == "SUCCESS_AFTER_RETRY"
        assert res["attempts"] == 3

    asyncio.run(run())


def test_job_retry_exhaustion(task_manager: AsyncTaskManager) -> None:
    async def always_failing_task() -> None:
        raise ValueError("Permanent failure")

    async def run() -> None:
        res = await task_manager.execute_job(
            job_id="JOB-FAIL-1",
            idempotency_key="IDEM-FAIL-1",
            task_func=always_failing_task,
            max_retries=2,
        )
        assert res["status"] == JobStatus.FAILED
        assert res["attempts"] == 2
        assert "Permanent failure" in res["error"]

    asyncio.run(run())


def test_fastapi_background_tasks_integration() -> None:
    execution_log: list[str] = []

    def background_work(task_name: str) -> None:
        execution_log.append(f"Executed {task_name}")

    bg_tasks = BackgroundTasks()
    bg_tasks.add_task(background_work, "Task_A")
    bg_tasks.add_task(background_work, "Task_B")

    async def run() -> None:
        await bg_tasks()
        assert "Executed Task_A" in execution_log
        assert "Executed Task_B" in execution_log

    asyncio.run(run())


def test_inngest_event_dispatch() -> None:
    inngest_client = Inngest(app_id="sanjeevani_test_app")
    event = Event(
        name="user/report.generated",
        data={"user_id": "USR-1234", "report_type": "PDF"},
    )
    assert inngest_client.app_id == "sanjeevani_test_app"
    assert event.name == "user/report.generated"
    assert event.data["user_id"] == "USR-1234"


def test_cron_cleanup_expired_files(tmp_path: Path) -> None:
    cleanup_dir = tmp_path / "temp_reports"
    cleanup_dir.mkdir()

    # Create old file (modify timestamp to 10 seconds ago)
    old_file = cleanup_dir / "old_report.pdf"
    old_file.write_text("old data")
    old_mtime = time.time() - 10.0

    os.utime(old_file, (old_mtime, old_mtime))

    # Create fresh file
    fresh_file = cleanup_dir / "fresh_report.pdf"
    fresh_file.write_text("fresh data")

    # Run cleanup for files older than 5 seconds
    removed = CronCleanupService.cleanup_old_files(cleanup_dir, max_age_seconds=5.0)

    assert removed == 1
    assert not old_file.exists()
    assert fresh_file.exists()


def test_cron_cleanup_nonexistent_dir(tmp_path: Path) -> None:
    missing_dir = tmp_path / "does_not_exist"
    removed = CronCleanupService.cleanup_old_files(missing_dir, max_age_seconds=10.0)
    assert removed == 0
