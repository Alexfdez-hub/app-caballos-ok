const { spawn, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const testsDir = path.join(root, 'supabase', 'tests');
const files = {
  setup: path.join(testsDir, '028_zero_session_approval_concurrency_setup.sql'),
  sessionA: path.join(testsDir, '028_zero_session_approval_concurrency_session_a.sql'),
  sessionB: path.join(testsDir, '028_zero_session_approval_concurrency_session_b.sql'),
  assert: path.join(testsDir, '028_zero_session_approval_concurrency_assert.sql'),
  cleanup: path.join(testsDir, '028_zero_session_approval_concurrency_cleanup.sql'),
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
  const result = runSync('docker', ['ps', '--format', '{{.Names}}']);
  if (result.status !== 0) return null;
  return result.stdout.split(/\r?\n/).map((name) => name.trim()).find(
    (name) => name.includes('supabase_db') || /-db$/.test(name) || name.endsWith('_db'),
  );
}

function psqlArgs(container) {
  return ['exec', '-i', container, 'psql', '-U', 'postgres', '-d', 'postgres',
    '-v', 'ON_ERROR_STOP=1', '-f', '-'];
}

function runFile(container, file) {
  return runSync('docker', psqlArgs(container), {
    input: fs.readFileSync(file, 'utf8'),
  });
}

function startSession(container, file, waitFor) {
  const child = spawn('docker', psqlArgs(container), {
    cwd: root,
    windowsHide: true,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  let stdout = '';
  let stderr = '';
  let release;
  let rejectRelease;
  const reached = new Promise((resolve, reject) => {
    release = resolve;
    rejectRelease = reject;
  });
  const done = new Promise((resolve) => {
    const timer = setTimeout(() => {
      child.kill();
      resolve({ status: 124, stdout, stderr: `${stderr}\nTimed out` });
    }, 20000);
    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString('utf8');
      if (waitFor && waitFor.test(stdout)) release();
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString('utf8');
    });
    child.on('close', (status) => {
      clearTimeout(timer);
      if (waitFor && !waitFor.test(stdout)) rejectRelease(new Error('Session A did not acquire the approval lock'));
      resolve({ status, stdout, stderr });
    });
  });
  if (!waitFor) release();
  child.stdin.end(fs.readFileSync(file, 'utf8'));
  return { reached, done };
}

async function main() {
  const container = findContainer();
  if (!container) {
    console.error('Could not find the local Supabase database container.');
    process.exit(1);
  }

  const setup = runFile(container, files.setup);
  if (setup.status !== 0) {
    process.stderr.write(setup.stderr || 'Concurrency setup failed.');
    runFile(container, files.cleanup);
    process.exit(1);
  }

  let a;
  let b;
  try {
    const sessionA = startSession(container, files.sessionA, /approval_a_holding/);
    await sessionA.reached;
    const sessionB = startSession(container, files.sessionB, null);
    [a, b] = await Promise.all([sessionA.done, sessionB.done]);
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    runFile(container, files.cleanup);
    process.exit(1);
  }

  const assertion = runFile(container, files.assert);
  const cleanup = runFile(container, files.cleanup);
  const bOutput = `${b.stdout}\n${b.stderr}`;
  const passed = a.status === 0
    && /approval_a_committed/.test(a.stdout)
    && b.status !== 0
    && /already approved with different facts/i.test(bOutput)
    && assertion.status === 0
    && cleanup.status === 0
    && !/deadlock detected/i.test(`${a.stderr}\n${b.stderr}`);

  if (!passed) {
    process.stdout.write(`Session A:\n${a.stdout}\n${a.stderr}\n`);
    process.stdout.write(`Session B:\n${b.stdout}\n${b.stderr}\n`);
    process.stdout.write(`Assertion:\n${assertion.stdout}\n${assertion.stderr}\n`);
    process.exit(1);
  }

  console.log('028 concurrent Zero Session approval serialized with one winner.');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
