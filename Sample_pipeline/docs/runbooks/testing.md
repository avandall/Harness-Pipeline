# Runbook: Tests (Playwright, back-pressure)
> Tests are **real runnable `tests/*.test.js`** that guard each implementation and prevent regression. They are planned in
> the evidence pack (`interactions.md` names them) and implemented during Execute — never pre-created as fake proof.

- Run: `npx playwright test` (config: `playwright.config.js`, headless). Types: behavioural (rendered preview: hover,
  sticky, video, forms), structural (theme files: schema present, root attributes), and the harness's own offline suites
  (`npm run test:orchestration`, `tests/migration-state.test.js`, `tests/visual-gate.test.js`, `tests/demo-panel.test.js`).
- Every test documents **what it guards and why** in a header comment — future fresh-context loops have no memory.
- A green test proves non-regression, never fidelity; fidelity is the gate's job.
