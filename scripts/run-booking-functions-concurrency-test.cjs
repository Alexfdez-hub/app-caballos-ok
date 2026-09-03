const { spawn, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const testsDir = path.join(root, 'supabase', 'tests');

const files = {
  setup: path.join(testsDir, '022_booking_functions_concurrency_setup.sql'),
  sessionA: path.join(testsDir, '022_booking_functions_concurrency_session_a.sql'),
  sessionB: path.join(testsDir, '022_booking_functions_concurrency_session_b.sql'),
  assert: path.join(testsDir, '022_booking_functions_concurrency_assert.sql'),
  policySessionB: path.join(
    testsDir,
    '022_booking_functions_concurrency_policy_session_b.sql',
  ),
  policyAssert: path.join(
    testsDir,
    '022_booking_functions_concurrency_policy_assert.sql',
  ),
  cleanup: path.join(testsDir, '022_booking_functions_concurrency_cleanup.sql'),
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
      if (waitFor && !waitResolved && waitFor.test(stderr)) {
        waitResolved = true;
        resolveGranted();
      }
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

function isControlledEligibilityFail(result) {
  return /Booking is not currently eligible to confirm|A CONFIRMED booking cannot persist PENDING requirement rows/i.test(
    combined(result),
  );
}

function isConfirmSuccess(result) {
  return (
    result.status === 0 &&
    /99100000-0000-0000-0000-00000000b001/.test(result.stdout) &&
    /session_a_committed/.test(result.stdout)
  );
}

async function runHandshake(container, testCase) {
  console.log(`\n----- ${testCase.name} -----`);
  console.log(testCase.arrangement);

  const setup = runSqlFile(container, files.setup);
  printResult(`${testCase.name} setup`, setup);
  if (setup.status !== 0) {
    runSqlFile(container, files.cleanup);
    return [`${testCase.name}: setup failed.`];
  }

  let sessionA;
  let sessionB;
  try {
    const a = runSession(container, files.sessionA, {
      waitFor: /confirm_eval_lock_held/,
      timeoutMs: 20000,
    });
    await a.granted;
    console.log(
      `${testCase.name}: session A held the eval lock after ${Date.now() - a.startedAt}ms; starting session B.`,
    );

    const b = runSession(container, testCase.sessionB, {
      timeoutMs: 20000,
    });

    [sessionA, sessionB] = await Promise.all([a.done, b.done]);
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    runSqlFile(container, files.cleanup);
    return [
      `${testCase.name}: handshake aborted before both sessions finished.`,
    ];
  }

  printResult(`${testCase.name} session A`, sessionA);
  printResult(`${testCase.name} session B`, sessionB);

  const failures = [];

  if (sessionA.timedOut || sessionB.timedOut) {
    failures.push(`${testCase.name}: a session timed out.`);
  }
  if (isDeadlock(sessionA) || isDeadlock(sessionB)) {
    failures.push(`${testCase.name}: deadlock detected.`);
  }
  if (isLockTimeout(sessionA) || isLockTimeout(sessionB)) {
    failures.push(`${testCase.name}: lock timeout fired.`);
  }
  if (sessionB.status !== 0) {
    failures.push(testCase.sessionBFailure);
  }

  const aConfirmed = isConfirmSuccess(sessionA);
  const aFailedClosed = isControlledEligibilityFail(sessionA);

  if (!aConfirmed && !aFailedClosed) {
    failures.push(
      `${testCase.name}: session A neither confirmed from the earlier snapshot nor failed closed.`,
    );
  }

  const assertion = runSqlFile(container, testCase.assert);
  printResult(`${testCase.name} final rows`, assertion);
  if (assertion.status !== 0) {
    failures.push(`${testCase.name}: final row assertions failed.`);
  }

  const cleanup = runSqlFile(container, files.cleanup);
  printResult(`${testCase.name} cleanup`, cleanup);
  if (cleanup.status !== 0) {
    failures.push(`${testCase.name}: cleanup failed.`);
  }

  if (failures.length === 0) {
    console.log(
      aConfirmed
        ? `${testCase.name}: CONFIRMED from the earlier snapshot.`
        : `${testCase.name}: fail-closed; later mutation did not leave CONFIRMED + PENDING.`,
    );
  }

  return failures;
}

async function main() {
  const container = findContainer();
  if (!container) {
    console.error('Could not find the local Supabase database container.');
    process.exit(1);
  }

  console.log(`Using database container ${container}`);
  console.log(
    'Pause lives only in the test-only probe, not in public.confirm_booking.',
  );

  const cases = [
    {
      name: 'MIN_AGE',
      arrangement:
        'Session A materializes one confirm evaluation; session B inserts MIN_AGE before persist.',
      sessionB: files.sessionB,
      assert: files.assert,
      sessionBFailure:
        'MIN_AGE: session B did not insert the post-eval MIN_AGE requirement.',
    },
    {
      name: 'policy-revocation',
      arrangement:
        'Session A materializes eligibility + policy snapshot; session B deletes that acceptance before persist.',
      sessionB: files.policySessionB,
      assert: files.policyAssert,
      sessionBFailure:
        'policy-revocation: session B did not revoke the post-eval policy acceptance.',
    },
  ];

  const failures = [];
  for (const testCase of cases) {
    const caseFailures = await runHandshake(container, testCase);
    failures.push(...caseFailures);
  }

  if (failures.length > 0) {
    console.error('\n022 booking-functions concurrency tests FAILED:');
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exit(1);
  }

  console.log('\n022 booking-functions concurrency tests passed.');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
