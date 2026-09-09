import { activePage } from './migration-state.mjs';

const result = activePage(process.argv[2] || 'migrations');
if (!result.pass) {
  for (const error of result.errors) console.error(error);
  process.exit(1);
}
if (result.dir) process.stdout.write(result.dir);
