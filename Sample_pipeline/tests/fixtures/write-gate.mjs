#!/usr/bin/env node
// Test-only helper: create internally consistent v2 report evidence for throwaway runner fixtures.
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { gateEvidence, requiredReportIds } from '../../scripts/migration-state.mjs';

const pageDir = process.argv[2];
const cwd = process.argv[3] || process.cwd();
if (!pageDir) throw new Error('usage: write-gate.mjs <migration-page-dir> [repo-root]');
const hash = (value) => createHash('sha256').update(value).digest('hex');
const contractPath = path.join(pageDir, 'contract.json');
const contract = JSON.parse(readFileSync(contractPath, 'utf8'));
const evidence = gateEvidence(contractPath, { cwd });
const reportsDir = path.join(pageDir, 'reports');
mkdirSync(reportsDir, { recursive: true });
const reports = [];
for (const id of requiredReportIds(contract)) {
  const [viewport, mode] = id.split(':');
  const file = `${viewport}${mode === 'overlay' ? '.overlay' : ''}.section.json`;
  const report = {
    version: 2,
    contractHash: evidence.contractHash,
    themeHash: evidence.themeHash,
    evidenceHash: evidence.evidenceHash,
    viewport,
    mode,
    overallPass: true,
    sections: [{ section: 'fixture', pass: true }],
  };
  writeFileSync(path.join(reportsDir, file), `${JSON.stringify(report, null, 2)}\n`);
  reports.push({ id, file, sha256: hash(readFileSync(path.join(reportsDir, file))) });
}
const deltasPath = path.join(pageDir, 'visual-deltas.md');
const gate = {
  version: 2,
  page: contract.page,
  contractHash: evidence.contractHash,
  themeHash: evidence.themeHash,
  evidenceHash: evidence.evidenceHash,
  reports,
  deltaHash: hash(readFileSync(deltasPath)),
  openDeltas: 0,
  visualPass: true,
};
writeFileSync(path.join(pageDir, 'gate.json'), `${JSON.stringify(gate, null, 2)}\n`);
