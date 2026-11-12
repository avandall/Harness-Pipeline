"""Unit tests for the real-time visual telemetry dashboard."""

import importlib.util
import json
import urllib.request
import threading
from pathlib import Path

_SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "dashboard.py"
_spec = importlib.util.spec_from_file_location("dashboard", _SCRIPT)
assert _spec and _spec.loader
db = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(db)


def test_worker_colors():
    c0 = db.get_worker_colors(0)
    c1 = db.get_worker_colors(1)
    c2 = db.get_worker_colors(2)
    assert c0["primary"] != c1["primary"]
    assert c1["primary"] != c2["primary"]
    assert "bg" in c0 and "border" in c0


def test_collect_telemetry_structure():
    data = db.collect_telemetry()
    assert "stats" in data
    assert "workers" in data
    assert "tasks" in data
    assert "events" in data
    stats = data["stats"]
    assert "total_tasks" in stats
    assert "done_tasks" in stats
    assert "completion_pct" in stats


def test_dashboard_http_server(tmp_path):
    # Start server on a random high test port
    test_port = 8899
    server = db.ThreadingHTTPServer(("127.0.0.1", test_port), db.DashboardRequestHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        # Test index.html HTML response
        with urllib.request.urlopen(f"http://127.0.0.1:{test_port}/") as resp:
            assert resp.status == 200
            assert "text/html" in resp.headers.get("Content-Type", "")
            body = resp.read().decode("utf-8")
            assert "Ralph Loop Orchestrator" in body
            assert "workersGrid" in body

        # Test /api/telemetry JSON endpoint
        with urllib.request.urlopen(f"http://127.0.0.1:{test_port}/api/telemetry") as resp:
            assert resp.status == 200
            assert "application/json" in resp.headers.get("Content-Type", "")
            payload = json.loads(resp.read().decode("utf-8"))
            assert "stats" in payload
            assert "workers" in payload
    finally:
        server.shutdown()
        server.server_close()

