const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const testFile = path.join(root, 'supabase', 'tests', '038_verification_predicates_test.sql');

if (!fs.existsSync(testFile)) {
  console.error(`Missing SQL test file: ${testFile}`);
  process.exit(1);
}

const sql = fs.readFileSync(testFile, 'utf8');

function run(command, args, options = {}) {
  return spawnSync(command, args, {
    cwd: root,
    encoding: 'utf8',
    windowsHide: true,
    ...options,
  });
}

function fail(message, result) {
  if (message) console.error(message);
  if (result?.stdout) process.stdout.write(result.stdout);
  if (result?.stderr) process.stderr.write(result.stderr);
  process.exit(result?.status ?? 1);
}

const dockerNames = run('docker', ['ps', '--format', '{{.Names}}']);
if (dockerNames.status !== 0) {
  fail('Could not list Docker containers.', dockerNames);
}

const container = dockerNames.stdout
  .split(/\r?\n/)
  .map((name) => name.trim())
  .find((name) => name.includes('supabase_db') || /-db$/.test(name) || name.endsWith('_db'));

if (!container) {
  fail('Could not find the local Supabase database container.');
}

const dockerResult = run(
  'docker',
  ['exec', '-i', container, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-f', '-'],
  { input: sql, stdio: ['pipe', 'inherit', 'inherit'] },
);

if (dockerResult.status !== 0) {
  fail('Verification predicate SQL tests failed.', dockerResult);
}

console.log('038 verification predicate SQL tests passed.');
