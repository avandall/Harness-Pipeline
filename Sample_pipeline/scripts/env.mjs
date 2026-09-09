import { existsSync, readFileSync } from 'node:fs';

export function parseEnv(text) {
  const values = {};
  for (const raw of String(text || '').split('\n')) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const match = line.replace(/^export\s+/, '').match(/^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$/);
    if (!match) continue;
    const [, key, rawValue] = match;
    let value = rawValue.trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      const quote = value[0];
      value = value.slice(1, -1);
      if (quote === '"') value = value.replace(/\\n/g, '\n').replace(/\\"/g, '"').replace(/\\\\/g, '\\');
    } else {
      value = value.replace(/\s+#.*$/, '').trim();
    }
    values[key] = value;
  }
  return values;
}

// Explicit process/command environment wins over repository .env values.
export function loadEnv(file = '.env', base = process.env) {
  const env = { ...base };
  if (!existsSync(file)) return env;
  const fromFile = parseEnv(readFileSync(file, 'utf8'));
  for (const [key, value] of Object.entries(fromFile)) {
    if (env[key] == null) env[key] = value;
  }
  return env;
}

export const substituteEnv = (value, env) => String(value || '').replace(/__(SHOPIFY_[A-Z0-9_]+)__/g,
  (placeholder, key) => env[key] == null || env[key] === '' ? placeholder : env[key]);

export function unresolvedEnv(value) {
  return [...new Set(String(value || '').match(/__(SHOPIFY_[A-Z0-9_]+)__/g) || [])];
}

export function requireResolvedHttpUrl(value, label) {
  const unresolved = unresolvedEnv(value);
  if (unresolved.length) throw new Error(`${label} has unresolved environment placeholder(s): ${unresolved.join(', ')}`);
  let parsed;
  try { parsed = new URL(value); } catch { throw new Error(`${label} is not a valid URL: ${value || '(empty)'}`); }
  if (!['http:', 'https:'].includes(parsed.protocol)) throw new Error(`${label} must use http or https`);
  return parsed.href;
}
