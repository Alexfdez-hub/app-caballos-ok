const { spawn, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const testsDir = path.join(root, 'supabase', 'tests');

const files = {
  setup: path.join(testsDir, '037_verification_review_concurrency_setup.sql'),
  sessionA: path.join(testsDir, '037_verification_review_concurrency_session_a.sql'),
  sessionB: path.join(testsDir, '037_verification_review_concurrency_session_b.sql'),
  assert: path.join(testsDir, '037_verification_review_concurrency_assert.sql'),
  cleanup: path.join(testsDir, '037_verification_review_concurrency_cleanup.sql'),
  subjectSetup: path.join(testsDir, '037_verification_review_subject_concurrency_setup.sql'),
  subjectSessionA: path.join(testsDir, '037_verification_review_subject_concurrency_session_a.sql'),
  subjectSessionB: path.join(testsDir, '037_verification_review_subject_concurrency_session_b.sql'),
  subjectAssert: path.join(testsDir, '037_verification_review_subject_concurrency_assert.sql'),
  subjectCleanup: path.join(testsDir, '037_verification_review_subject_concurrency_cleanup.sql'),
};

for (const file of Object.values(files)) {
  if (!fs.existsSync(file)) {
    console.error(`Missing concurrency test file: ${file}`);
    process.exit(1);
  }
}

function runSync(command, args, options = {}) {
  return spawnSync(command, args, {
    cwd: root,
    encoding: 'utf8',
    windowsHide: true,
    ...options,
  });
}

function findContainer() {
  const dockerNames = runSync('docker', ['ps', '--format', '{{.Names}}']);
  if (dockerNames.status !== 0) {
    return null;
  }

  return dockerNames.stdout
    .split(/\r?\n/)
    .map((name) => name.trim())
    .find(
      (name) =>
        name.includes('supabase_db') ||
        /-db$/.test(name) ||
        name.endsWith('_db'),
    );
}

function psqlArgs(container) {
  return [
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
  ];
}

function runSqlFile(container, file) {
  const sql = fs.readFileSync(file, 'utf8');
  const result = runSync('docker', psqlArgs(container), { input: sql });
  return {
    file: path.basename(file),
    status: result.status,
    stdout: result.stdout || '',
    stderr: result.stderr || '',
  };
}

function printResult(label, result) {
  console.log(`\n===== ${label} =====`);
  console.log(`exit=${result.status}`);
  if (result.stdout) {
    process.stdout.write(result.stdout);
  }
  if (result.stderr) {
    process.stderr.write(result.stderr);
  }
}

function runSession(container, file, timeoutMs) {
  const sql = fs.readFileSync(file, 'utf8');
  const child = spawn('docker', psqlArgs(container), {
    cwd: root,
    windowsHide: true,
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  let stdout = '';
  let stderr = '';

  const done = new Promise((resolve) => {
    const timer = setTimeout(() => {
      child.kill();
      resolve({
        file: path.basename(file),
        status: 124,
        stdout,
        stderr: `${stderr}\nTimed out after ${timeoutMs}ms`,
      });
    }, timeoutMs);

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString('utf8');
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString('utf8');
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({
        file: path.basename(file),
        status: code,
        stdout,
        stderr,
      });
    });
  });

  child.stdin.write(sql);
  child.stdin.end();
  return done;
}

async function main() {
  const container = findContainer();
  if (!container) {
    console.error('Could not find the local Supabase database container.');
    process.exit(1);
  }

  console.log(`Using database container ${container}`);

  const setup = runSqlFile(container, files.setup);
  printResult('setup', setup);
  if (setup.status !== 0) {
    runSqlFile(container, files.cleanup);
    process.exit(1);
  }

  const [sessionA, sessionB] = await Promise.all([
    runSession(container, files.sessionA, 20000),
    runSession(container, files.sessionB, 20000),
  ]);
  printResult('session A', sessionA);
  printResult('session B', sessionB);

  const assert = runSqlFile(container, files.assert);
  printResult('assert', assert);

  const cleanup = runSqlFile(container, files.cleanup);
  printResult('cleanup', cleanup);

  if (
    sessionA.status !== 0 ||
    sessionB.status !== 0 ||
    assert.status !== 0 ||
    cleanup.status !== 0
  ) {
    process.exit(1);
  }

  const subjectSetup = runSqlFile(container, files.subjectSetup);
  printResult('subject setup', subjectSetup);
  if (subjectSetup.status !== 0) {
    runSqlFile(container, files.subjectCleanup);
    process.exit(1);
  }

  const [subjectA, subjectB] = await Promise.all([
    runSession(container, files.subjectSessionA, 20000),
    runSession(container, files.subjectSessionB, 20000),
  ]);
  printResult('subject session A', subjectA);
  printResult('subject session B', subjectB);

  const subjectAssert = runSqlFile(container, files.subjectAssert);
  printResult('subject assert', subjectAssert);

  const subjectCleanup = runSqlFile(container, files.subjectCleanup);
  printResult('subject cleanup', subjectCleanup);

  if (
    subjectA.status !== 0 ||
    subjectB.status !== 0 ||
    subjectAssert.status !== 0 ||
    subjectCleanup.status !== 0
  ) {
    process.exit(1);
  }

  console.log('Verification review concurrency tests passed.');
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
