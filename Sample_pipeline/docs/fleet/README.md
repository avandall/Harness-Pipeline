# Optional next layer — fleet visibility (NOT included here)
The original harness grew an extra layer for teams: a **fleet** contract (local `status.json` + snapshot + heartbeat
hooks in the runners) reporting every migration across many laptops to a hosted dashboard (queue, leases, feedback,
Slack alerts), kept in a *separate* repository so theme clones don't inherit it. The runners in this playbook carry the
hook points as no-ops (see the `fleet_*` fallbacks in `scripts/ralph.sh`), so the layer can be added without changing the
work contract. Lesson: build the single-machine harness first; make observability additive.
