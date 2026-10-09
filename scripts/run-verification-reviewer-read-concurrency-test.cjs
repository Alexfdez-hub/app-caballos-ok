const { spawn, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const testsDir = path.join(root, 'supabase', 'tests');

const scenarios = [
  {
    label: 'suspend-versus-open',
    setup: '040_verification_reviewer_read_concurrency_setup.sql',
    sessionA: '040_verification_reviewer_read_concurrency_session_a.sql',
    sessionB: '040_verification_reviewer_read_concurrency_session_b.sql',
    assert: '040_verification_reviewer_read_concurrency_assert.sql',
    cleanup: '040_verification_reviewer_read_concurrency_cleanup.sql',
  },
];

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
  const sql = fs.readFileSync(path.join(testsDir, file), 'utf8');
  const result = runSync('docker', psqlArgs(container), { input: sql });
  return {
    file,
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
  const sql = fs.readFileSync(path.join(testsDir, file), 'utf8');
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
        file,
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
        file,
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

  for (const scenario of scenarios) {
    const setup = runSqlFile(container, scenario.setup);
    printResult(`${scenario.label} setup`, setup);
    if (setup.status !== 0) {
      runSqlFile(container, scenario.cleanup);
      process.exit(1);
    }

    const [sessionA, sessionB] = await Promise.all([
      runSession(container, scenario.sessionA, 20000),
      runSession(container, scenario.sessionB, 20000),
    ]);
    printResult(`${scenario.label} session A`, sessionA);
    printResult(`${scenario.label} session B`, sessionB);

    const assert = runSqlFile(container, scenario.assert);
    printResult(`${scenario.label} assert`, assert);

    const cleanup = runSqlFile(container, scenario.cleanup);
    printResult(`${scenario.label} cleanup`, cleanup);

    if (
      sessionA.status !== 0 ||
      sessionB.status !== 0 ||
      assert.status !== 0 ||
      cleanup.status !== 0
    ) {
      process.exit(1);
    }
  }

  console.log('Verification reviewer read concurrency tests passed.');
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});
