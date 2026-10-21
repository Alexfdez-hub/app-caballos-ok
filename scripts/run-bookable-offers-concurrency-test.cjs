const { spawn, spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const testsDir = path.join(root, 'supabase', 'tests');

const files = {
  setup: path.join(testsDir, '042_bookable_offers_concurrency_setup.sql'),
  sessionA: path.join(testsDir, '042_bookable_offers_concurrency_session_a.sql'),
  sessionB: path.join(testsDir, '042_bookable_offers_concurrency_session_b.sql'),
  assert: path.join(testsDir, '042_bookable_offers_concurrency_assert.sql'),
  tzA: path.join(testsDir, '042_bookable_offers_concurrency_tz_a.sql'),
  tzB: path.join(testsDir, '042_bookable_offers_concurrency_tz_b.sql'),
  tzAssert: path.join(testsDir, '042_bookable_offers_concurrency_tz_assert.sql'),
  otherA: path.join(testsDir, '042_bookable_offers_concurrency_other_a.sql'),
  otherB: path.join(testsDir, '042_bookable_offers_concurrency_other_b.sql'),
  otherAssert: path.join(testsDir, '042_bookable_offers_concurrency_other_assert.sql'),
  cleanup: path.join(testsDir, '042_bookable_offers_concurrency_cleanup.sql'),
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
    'supabase_admin',
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
  if (result.elapsedMs !== undefined) {
    console.log(`elapsed_ms=${result.elapsedMs}`);
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
        rejectGranted(new Error(`${path.basename(file)} closed before ${waitFor}`));
      }
      resolve({
        file: path.basename(file),
        status: code,
        stdout,
        stderr,
        elapsedMs: Date.now() - startedAt,
        timedOut: false,
      });
    });
  });

  child.stdin.write(sql);
  child.stdin.end();

  return { granted, done, startedAt };
}

function assertInheritedMigrations() {
  const baseProbe = runSync('git', [
    'cat-file',
    '-e',
    'origin/main:supabase/migrations/042_bookable_offers.sql',
  ]);
  if (baseProbe.status !== 0) {
    console.log(
      'Migrations 001-042 check NOT RUN here: origin/main is not available. The App quality inherited-migration step remains the CI assertion.',
    );
    return [];
  }

  const diff = runSync('git', [
    'diff',
    '--name-status',
    'origin/main',
    '--',
    'supabase/migrations',
  ]);
  if (diff.status !== 0) {
    return ['Could not diff migrations against origin/main.'];
  }

  const failures = [];
  const lines = diff.stdout.split(/\r?\n/).filter(Boolean);
  for (const line of lines) {
    const [status, filePath] = line.split('\t');
    if (
      status === 'A' &&
      (filePath === 'supabase/migrations/043_bookable_offer_request_serialization.sql' ||
        filePath === 'supabase/migrations/044_test_operator_local.sql')
    ) {
      continue;
    }
    failures.push(`Migrations 001-042 must stay unchanged (${status} ${filePath}).`);
  }
  if (failures.length === 0) {
    console.log('Migrations 001-042 are unchanged versus origin/main.');
  }
  return failures;
}

async function runPair(container, fileA, fileB, waitFor) {
  const a = runSession(container, fileA, {
    waitFor,
    timeoutMs: 20000,
  });
  await a.granted;
  const b = runSession(container, fileB, { timeoutMs: 20000 });
  return Promise.all([a.done, b.done]);
}

async function main() {
  const container = findContainer();
  if (!container) {
    console.error('Could not find the local Supabase database container.');
    process.exit(1);
  }

  console.log(`Using database container ${container}`);
  const failures = assertInheritedMigrations();
  console.log(
    'Arrangement: same account waits; a second TimeZone uses the same instants; a second account does not wait.',
  );

  const setup = runSqlFile(container, files.setup);
  printResult('setup', setup);
  if (setup.status !== 0) {
    runSqlFile(container, files.cleanup);
    process.exit(1);
  }

  let sessionA;
  let sessionB;
  let tzA;
  let tzB;
  let otherA;
  let otherB;
  try {
    [sessionA, sessionB] = await runPair(
      container,
      files.sessionA,
      files.sessionB,
      /session_a_holding/,
    );
    [tzA, tzB] = await runPair(
      container,
      files.tzA,
      files.tzB,
      /session_tz_a_holding/,
    );
    [otherA, otherB] = await runPair(
      container,
      files.otherA,
      files.otherB,
      /session_other_a_holding/,
    );
  } catch (error) {
    console.error(error instanceof Error ? error.message : error);
    runSqlFile(container, files.cleanup);
    process.exit(1);
  }

  printResult('same account A', sessionA);
  printResult('same account B', sessionB);
  printResult('timezone A', tzA);
  printResult('timezone B', tzB);
  printResult('other account A', otherA);
  printResult('other account B', otherB);

  for (const result of [sessionA, sessionB, tzA, tzB, otherA, otherB]) {
    if (result.timedOut) {
      failures.push(`${result.file} timed out.`);
    }
    if (result.status !== 0) {
      failures.push(`${result.file} failed.`);
    }
  }
  if (!/CREATED/.test(sessionA.stdout) || !/REPLAYED/.test(sessionB.stdout)) {
    failures.push('Same account must return one CREATED and one REPLAYED.');
  }
  if (sessionB.elapsedMs < 1500) {
    failures.push(
      `Same-account session B finished in ${sessionB.elapsedMs}ms and did not wait.`,
    );
  }
  if (!/CREATED/.test(tzA.stdout) || !/REPLAYED/.test(tzB.stdout)) {
    failures.push('Different session timezones must still return CREATED and REPLAYED.');
  }
  if (tzB.elapsedMs < 1500) {
    failures.push(
      `Timezone session B finished in ${tzB.elapsedMs}ms and did not share the UTC lock.`,
    );
  }
  if (!/CREATED/.test(otherA.stdout) || !/CREATED/.test(otherB.stdout)) {
    failures.push('Different accounts must each receive CREATED.');
  }
  if (otherB.elapsedMs >= 1500) {
    failures.push(
      `Other-account session B took ${otherB.elapsedMs}ms and was serialized with the first account.`,
    );
  }

  const assertion = runSqlFile(container, files.assert);
  printResult('same account rows', assertion);
  if (assertion.status !== 0) {
    failures.push('Same-account row assertions failed.');
  }
  const tzAssertion = runSqlFile(container, files.tzAssert);
  printResult('timezone rows', tzAssertion);
  if (tzAssertion.status !== 0) {
    failures.push('Timezone row assertions failed.');
  }
  const otherAssertion = runSqlFile(container, files.otherAssert);
  printResult('other account rows', otherAssertion);
  if (otherAssertion.status !== 0) {
    failures.push('Different-account row assertions failed.');
  }

  const cleanup = runSqlFile(container, files.cleanup);
  printResult('cleanup', cleanup);
  if (cleanup.status !== 0) {
    failures.push('Cleanup failed.');
  }

  if (failures.length > 0) {
    console.error('\n042 bookable-offer concurrency tests FAILED:');
    for (const failure of failures) {
      console.error(`- ${failure}`);
    }
    process.exit(1);
  }

  console.log('\n042 bookable-offer concurrency tests passed.');
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
