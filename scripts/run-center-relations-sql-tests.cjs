const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const relativeTestFile = path.join(
  'supabase',
  'tests',
  '013_equine_center_relations_test.sql',
);
const testFile = path.join(root, relativeTestFile);

if (!fs.existsSync(testFile)) {
  console.error(`Missing SQL test file: ${testFile}`);
  process.exit(1);
}

const sql = fs.readFileSync(testFile, 'utf8');
if (/^\\[a-z]/im.test(sql)) {
  console.error(
    '013_equine_center_relations_test.sql still contains psql meta-commands.',
  );
  process.exit(1);
}

function run(command, args, options = {}) {
  return spawnSync(command, args, {
    cwd: root,
    encoding: 'utf8',
    windowsHide: true,
    ...options,
  });
}

function fail(message, result) {
  if (message) {
    console.error(message);
  }
  if (result?.stdout) {
    process.stdout.write(result.stdout);
  }
  if (result?.stderr) {
    process.stderr.write(result.stderr);
  }
  process.exit(result?.status ?? 1);
}

function succeeded(result) {
  return result.status === 0;
}

const dockerNames = run('docker', ['ps', '--format', '{{.Names}}']);
if (succeeded(dockerNames)) {
  const container = dockerNames.stdout
    .split(/\r?\n/)
    .map((name) => name.trim())
    .find(
      (name) =>
        name.includes('supabase_db') ||
        /-db$/.test(name) ||
        name.endsWith('_db'),
    );

  if (container) {
    const dockerResult = run(
      'docker',
      [
        'exec',
        '-i',
        container,
        'psql',
        '-U',
        'postgres',
        '-d',
        'postgres',
        '-v',
        'ON_ERROR_STOP=1',
        '-f',
        '-',
      ],
      { input: sql, stdio: ['pipe', 'inherit', 'inherit'] },
    );

    if (!succeeded(dockerResult)) {
      fail('Center-relations SQL tests failed via docker exec.', dockerResult);
    }

    console.log('013 equine–center relations SQL tests passed.');
    process.exit(0);
  }
}

const status = run('npx', ['supabase', 'status', '-o', 'env'], {
  shell: true,
});
if (!succeeded(status)) {
  fail(
    'Could not find the local Supabase database container or CLI status.',
    status,
  );
}

const dbUrlLine = status.stdout
  .split(/\r?\n/)
  .find((line) => line.startsWith('POSTGRES_URL=') || line.startsWith('DB_URL='));

if (!dbUrlLine) {
  console.error('Local Supabase status did not include a Postgres URL.');
  process.exit(1);
}

const dbUrl = dbUrlLine.slice(dbUrlLine.indexOf('=') + 1).replace(/^"|"$/g, '');
const psqlResult = run('psql', [dbUrl, '-v', 'ON_ERROR_STOP=1', '-f', '-'], {
  input: sql,
  stdio: ['pipe', 'inherit', 'inherit'],
});

if (!succeeded(psqlResult)) {
  fail('Center-relations SQL tests failed via psql.', psqlResult);
}

console.log('013 equine–center relations SQL tests passed.');
