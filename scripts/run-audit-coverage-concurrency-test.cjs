const { spawn, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const testsDir = path.join(root, 'supabase', 'tests');

const files = {
  setup: path.join(testsDir, '029_critical_audit_concurrency_setup.sql'),
  sessionA: path.join(testsDir, '029_critical_audit_concurrency_session_a.sql'),
  sessionB: path.join(testsDir, '029_critical_audit_concurrency_session_b.sql'),
  assert: path.join(testsDir, '029_critical_audit_concurrency_assert.sql'),
  cleanup: path.join(testsDir, '029_critical_audit_concurrency_cleanup.sql'),
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
  if (result.startedAt !== undefined) {
    console.log(`started_ms=${result.startedAt} elapsed_ms=${result.elapsedMs}`);
  }
  if (result.stdout) {
    process.stdout.write(result.stdout);
  }
  if (result.stderr) {
    process.stderr.write(result.stderr);
  }
}

function runSession(container, file, { waitFor = null, timeoutMs }) {
  const sql = fs.readFileSync(file, 'utf8');
  const startedAt = Date.now();
  const child = spawn('docker', psqlArgs(container), {
    cwd: root,
    windowsHide: true,
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  let stdout = '';
  let stderr = '';
  let waitResolved = false;
  let resolveGranted;
  let rejectGranted;

  const granted = new Promise((resolve, reject) => {
    resolveGranted = resolve;
    rejectGranted = reject;
  });

  if (!waitFor) {
    resolveGranted();
  }

  const done = new Promise((resolve) => {
    const timer = setTimeout(() => {
      child.kill();
      resolve({
        file: path.basename(file),
        status: 124,
        stdout,
        stderr: `${stderr}\nTimed out after ${timeoutMs}ms`,
        startedAt,
        elapsedMs: Date.now() - startedAt,
        timedOut: true,
      });
    }, timeoutMs);

    child.stdout.on('data', (chunk) => {
      stdout += chunk.toString('utf8');
      if (waitFor && !waitResolved && waitFor.test(stdout)) {
        waitResolved = true;
        resolveGranted();
      }
    });
    child.stderr.on('data', (chunk) => {
      stderr += chunk.toString('utf8');
    });
    child.on('close', (code) => {
      clearTimeout(timer);
      if (waitFor && !waitResolved) {
        rejectGranted(
          new Error(
            `${path.basename(file)} closed before matching ${waitFor}`,
          ),
        );
      }
      resolve({
        file: path.basename(file),
        status: code,
        stdout,
        stderr,
        startedAt,
        elapsedMs: Date.now() - startedAt,
        timedOut: false,
      });
    });
  });

  if (waitFor) {
    setTimeout(() => {
      if (!waitResolved) {
        rejectGranted(
          new Error(
            `${path.basename(file)} did not reach ${waitFor} within ${timeoutMs}ms`,
          ),
        );
      }
    }, timeoutMs);
  }

  child.stdin.write(sql);
  child.stdin.end();

  return { done, granted, startedAt };
}

function combined(result) {
  return `${result.stdout}\n${result.stderr}`;
}

function isDeadlock(result) {
  return /40P01|deadlock detected/i.test(combined(result));
}

function isLockTimeout(result) {
  return /55P03|canceling statement due to lock timeout/i.test(combined(result));
}

function isControlledActiveConflict(result) {
  return /Active guardian consent already exists/i.test(combined(result));
}

function isGrantSuccess(result) {
  return (
    result.status === 0 &&
    /v-race-[ab]/.test(result.stdout) &&
    /ACTIVE/.test(result.stdout)
  );
}

async function main() {
  const container = findContainer();
  if (!container) {
    console.error('Could not find the local Supabase database container.');
    process.exit(1);
  }

  console.log(`Using database container ${container}`);
  console.log(
    'Arrangement: session A grants and holds for 2s; session B waits. Exactly one guardian_consent_granted audit must remain.',
  );

  const setup = runSqlFile(container, files.setup);
  printResult('setup', setup);
  if (setup.status !== 0) {
    runSqlFile(container, files.cleanup);
    process.exit(1);
  }

  let sessionA;
  let sessionB;
  try {
    const a = runSession(container, files.sessionA, {
      waitFor: /session_a_after_grant/,
      timeoutMs: 20000,
    });
    await a.granted;
    console.log(
      `Session A acquired grant locks after ${Date.now() - a.startedAt}ms; starting session B.`,
    );

    const b = runSession(container, files.sessionB, {
      timeoutMs: 20000,
    });

    [sessionA, sessionB] = await Promise.all([a.done, b.done]);
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    runSqlFile(container, files.cleanup);
    process.exit(1);
  }

  printResult('session A', sessionA);
  printResult('session B', sessionB);

  const failures = [];

  if (sessionA.timedOut || sessionB.timedOut) {
    failures.push('A session timed out; possible hang or deadlock.');
  }
  if (isDeadlock(sessionA) || isDeadlock(sessionB)) {
    failures.push('Deadlock detected.');
  }
  if (isLockTimeout(sessionA) || isLockTimeout(sessionB)) {
    failures.push('Lock timeout fired; sessions did not serialize within 8s.');
  }

  const aWon = isGrantSuccess(sessionA);
  const bWon = isGrantSuccess(sessionB);
  const aLostControlled = isControlledActiveConflict(sessionA);
  const bLostControlled = isControlledActiveConflict(sessionB);

  if (aWon && bWon) {
    failures.push('Both sessions created a grant; duplicate ACTIVE consent.');
  } else if (!aWon && !bWon) {
    failures.push('Neither session granted consent.');
  } else if (aWon && !bLostControlled) {
    failures.push(
      'Session A won but session B did not return Active guardian consent already exists.',
    );
  } else if (bWon && !aLostControlled) {
    failures.push(
      'Session B won but session A did not return Active guardian consent already exists.',
    );
  }

  if (aWon && sessionB.elapsedMs < 1500) {
    failures.push(
      `Session B finished in ${sessionB.elapsedMs}ms and did not wait on session A's held lock.`,
    );
  }

  const assertion = runSqlFile(container, files.assert);
  printResult('final rows', assertion);
  if (assertion.status !== 0) {
    failures.push('Final row assertions failed.');
  }

  const cleanup = runSqlFile(container, files.cleanup);
  printResult('cleanup', cleanup);
  if (cleanup.status !== 0) {
    failures.push('Cleanup failed.');
  }

  if (failures.length > 0) {
    console.error('\n029 critical audit concurrency tests FAILED:');
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exit(1);
  }

  console.log('\n029 critical audit concurrency tests passed.');
  console.log(
    `Winner=${aWon ? 'A' : 'B'} loser_controlled_error=yes session_b_wait_ms=${sessionB.elapsedMs}`,
  );
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
