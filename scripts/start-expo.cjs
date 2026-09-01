const { copyFileSync, existsSync, readFileSync } = require('fs');
const { spawn } = require('child_process');
const { resolve } = require('path');

const PLACEHOLDER_HOSTS = new Set(['your-project.supabase.co']);
const PLACEHOLDER_KEYS = new Set([
  'your-anon-or-publishable-key',
  'your-local-anon-or-publishable-key',
  'your-remote-anon-or-publishable-key',
]);

const target = process.argv[2];
const extraArgs = process.argv.slice(3);
const checkOnly = extraArgs.includes('--check-env');
const expoArgs = extraArgs.filter((arg) => arg !== '--check-env');

if (target !== 'local' && target !== 'remote') {
  console.error('Usage: node scripts/start-expo.cjs <local|remote> [...expo args]');
  process.exit(1);
}

const source = resolve(`.env.supabase.${target}`);

if (!existsSync(source)) {
  console.error(
    `Missing ${source}. Copy .env.supabase.${target}.example and add the real project URL and anon or publishable key.`,
  );
  process.exit(1);
}

function readEnvValue(file, key) {
  const line = readFileSync(file, 'utf8')
    .split(/\r?\n/)
    .find((entry) => entry.replace(/^\uFEFF/, '').startsWith(`${key}=`));

  if (!line) {
    return '';
  }

  return line.replace(/^\uFEFF/, '').slice(`${key}=`.length).trim();
}

function assertUsableEnv(file, envTarget) {
  const rawUrl = readEnvValue(file, 'EXPO_PUBLIC_SUPABASE_URL');
  const rawKey = readEnvValue(file, 'EXPO_PUBLIC_SUPABASE_ANON_KEY').replace(/^<|>$/g, '');

  if (!rawUrl || !rawKey) {
    console.error(
      `[env] ${file} must define EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY.`,
    );
    process.exit(1);
  }

  let parsed;
  try {
    parsed = new URL(rawUrl);
  } catch {
    console.error(`[env] EXPO_PUBLIC_SUPABASE_URL in ${file} is not a valid URL.`);
    process.exit(1);
  }

  if (PLACEHOLDER_HOSTS.has(parsed.hostname)) {
    console.error(
      `[env] ${file} still uses the example host ${parsed.hostname}. Replace it with the real project URL before start:${envTarget}.`,
    );
    process.exit(1);
  }

  if (PLACEHOLDER_KEYS.has(rawKey)) {
    console.error(
      `[env] ${file} still uses an example anon/publishable key. Put the real key in that file.`,
    );
    process.exit(1);
  }

  if (envTarget === 'remote') {
    if (parsed.protocol !== 'https:') {
      console.error(`[env] start:remote requires an https URL. Host in ${file}: ${parsed.host}`);
      process.exit(1);
    }

    if (parsed.hostname === '127.0.0.1' || parsed.hostname === 'localhost') {
      console.error(`[env] start:remote cannot use loopback (${parsed.hostname}).`);
      process.exit(1);
    }
  }

  console.log(`[env] ${envTarget} target host ${parsed.host}`);
}

assertUsableEnv(source, target);

if (checkOnly) {
  process.exit(0);
}

copyFileSync(source, resolve('.env.local'));
console.log(`[env] Expo will load .env.local from .env.supabase.${target}`);

const child = spawn('npx', ['expo', 'start', '--clear', ...expoArgs], {
  stdio: 'inherit',
  shell: true,
  cwd: process.cwd(),
});

child.on('exit', (code, signal) => {
  if (signal) {
    process.exit(1);
  }
  process.exit(code ?? 1);
});
