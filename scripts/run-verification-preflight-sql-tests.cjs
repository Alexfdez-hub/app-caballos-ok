const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');

const root = path.join(__dirname, '..');
const preflightPath = path.join(
  root,
  'docs',
  'VERIFICATION_READONLY_PREFLIGHT_041.sql',
);
const testPath = path.join(
  root,
  'supabase',
  'tests',
  '041_verification_readonly_preflight_test.sql',
);

const checks = [
  'technical_principal',
  'transaction_is_read_only',
  'schema_exact_041',
  'bootstrap_signature',
  'bootstrap_not_client_executable',
  'clean_start_inventory',
  'two_distinct_active_accounts',
  'both_identity_markets_es',
  'applicant_open_case_set',
  'ownership_effective_row',
  'management_effective_row',
  'management_valid_until_null',
  'reviewer_has_no_conflict',
  'evidence_predicate_read',
  'section_b_remains_unauthorized',
];
const verdicts = new Set(['PASS', 'STOP', 'OPERATOR_ESCALATION_REQUIRED']);

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

function preflightFor(addressA, addressB) {
  const original = fs.readFileSync(preflightPath, 'utf8');
  if (/\bmax\s*\(\s*(person_id|account_id)\s*\)/i.test(original)) {
    fail('Preflight still aggregates uuid columns with max().');
  }
  if (!original.includes('array_agg(person_id)') || !original.includes('array_agg(account_id)')) {
    fail('Preflight does not extract uuid values with array_agg.');
  }
  const statements = original
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0 && !line.startsWith('--'));
  if (statements[0] !== 'begin read only;') {
    fail('Preflight does not start a READ ONLY transaction.');
  }
  if (statements[statements.length - 1] !== 'rollback;') {
    fail('Preflight does not end with ROLLBACK.');
  }

  const sql = original
    .split('<address-of-A-typed-in-this-session>')
    .join(addressA)
    .split('<address-of-B-typed-in-this-session>')
    .join(addressB);
  const restored = sql
    .split(addressA)
    .join('<address-of-A-typed-in-this-session>')
    .split(addressB)
    .join('<address-of-B-typed-in-this-session>');
  if (restored !== original) {
    fail('Preflight substitution changed more than the two address placeholders.');
  }
  return sql;
}

function loadHarness() {
  const source = fs.readFileSync(testPath, 'utf8');
  if (/^\\[a-z]/im.test(source)) {
    fail('041_verification_readonly_preflight_test.sql contains psql meta-commands.');
  }
  const begin = source.indexOf('-- BEGIN STANDALONE_CLEANUP');
  const end = source.indexOf('-- END STANDALONE_CLEANUP');
  if (begin < 0 || end < begin) {
    fail('Preflight SQL harness is missing its standalone cleanup block.');
  }
  const cleanup = source
    .slice(begin, end)
    .replace('-- BEGIN STANDALONE_CLEANUP', '')
    .trim();
  const body = `${source.slice(0, begin)}${source.slice(end + '-- END STANDALONE_CLEANUP'.length)}`;
  const executable = body.split('-- RUN_CLEANUP').join(cleanup);

  const scenarios = [];
  const parts = executable.split(/^-- RUN_PREFLIGHT (\S+) (\S+)\s*$/m);
  if (parts.length < 4 || (parts.length - 1) % 3 !== 0) {
    fail('Preflight SQL harness has no RUN_PREFLIGHT scenarios.');
  }
  let prelude = parts[0];
  for (let index = 1; index < parts.length; index += 3) {
    const addressA = parts[index];
    const addressB = parts[index + 1];
    const after = parts[index + 2];
    const expectations = [];
    const marks = [];
    const details = [];
    const directive = /^-- EXPECT(?:_(MARK|DETAIL))? (\S+) (.+)\s*$/;
    for (const line of prelude.split(/\r?\n/)) {
      const match = directive.exec(line.trim());
      if (!match) {
        continue;
      }
      if (match[1] === 'MARK') {
        marks.push({ check: match[2], value: match[3].trim() });
      } else if (match[1] === 'DETAIL') {
        details.push({ check: match[2], value: match[3].trim() });
      } else {
        expectations.push({ check: match[2], value: match[3].trim() });
      }
    }
    scenarios.push({
      addressA,
      addressB,
      expectations,
      marks,
      details,
      sql: `${prelude}\n${preflightFor(addressA, addressB)}\n`,
    });
    prelude = after;
  }
  scenarios[scenarios.length - 1].sql += prelude;
  return { cleanup, scenarios };
}

function parseVerdicts(stdout) {
  return stdout
    .split(/\r?\n/)
    .map((line) => line.split('|'))
    .filter((columns) => checks.includes(columns[1]))
    .map((columns) => ({
      check: columns[1],
      verdict: columns[2],
      mark: columns[3],
      detail: columns.slice(4).join('|'),
    }));
}

function assertScenarios(stdout, scenarios) {
  const rows = parseVerdicts(stdout);
  if (rows.length !== scenarios.length * checks.length) {
    fail(
      `Expected ${scenarios.length * checks.length} verdict rows and found ${rows.length}.`,
      { status: 1, stdout },
    );
  }

  scenarios.forEach((scenario, scenarioIndex) => {
    const group = rows.slice(
      scenarioIndex * checks.length,
      (scenarioIndex + 1) * checks.length,
    );
    const seen = new Set(group.map((row) => row.check));
    if (seen.size !== checks.length) {
      fail(`Scenario ${scenarioIndex + 1} did not return each documented check once.`, {
        status: 1,
        stdout,
      });
    }
    for (const row of group) {
      if (!verdicts.has(row.verdict)) {
        fail(
          `Scenario ${scenarioIndex + 1} returned an undocumented verdict ${row.verdict} for ${row.check}.`,
          { status: 1, stdout },
        );
      }
    }
    for (const expected of scenario.expectations) {
      const row = group.find((candidate) => candidate.check === expected.check);
      if (!row || row.verdict !== expected.value) {
        fail(
          `Scenario ${scenarioIndex + 1} ${expected.check}: expected ${expected.value} and found ${row ? row.verdict : 'no row'}.`,
          { status: 1, stdout },
        );
      }
    }
    for (const expected of scenario.marks) {
      const row = group.find((candidate) => candidate.check === expected.check);
      if (!row || row.mark !== expected.value) {
        fail(
          `Scenario ${scenarioIndex + 1} ${expected.check}: expected mark ${expected.value} and found ${row ? row.mark : 'no row'}.`,
          { status: 1, stdout },
        );
      }
    }
    for (const expected of scenario.details) {
      const row = group.find((candidate) => candidate.check === expected.check);
      if (!row || !row.detail.includes(expected.value)) {
        fail(
          `Scenario ${scenarioIndex + 1} ${expected.check}: detail did not include ${expected.value}.`,
          { status: 1, stdout },
        );
      }
    }
  });
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
    '-A',
    '-t',
    '-F',
    '|',
    '-P',
    'footer=off',
    '-f',
    '-',
  ];
}

function executeSql(sql, cleanup) {
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
      const dockerResult = run('docker', psqlArgs(container), {
        input: sql,
      });
      if (!succeeded(dockerResult)) {
        run('docker', psqlArgs(container), { input: cleanup });
        fail('Verification preflight SQL tests failed via docker exec.', dockerResult);
      }
      return dockerResult.stdout;
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
    fail('Local Supabase status did not include a Postgres URL.');
  }
  const dbUrl = dbUrlLine.slice(dbUrlLine.indexOf('=') + 1).replace(/^"|"$/g, '');
  const psqlResult = run(
    'psql',
    [dbUrl, '-v', 'ON_ERROR_STOP=1', '-A', '-t', '-F', '|', '-P', 'footer=off', '-f', '-'],
    { input: sql },
  );
  if (!succeeded(psqlResult)) {
    run(
      'psql',
      [dbUrl, '-v', 'ON_ERROR_STOP=1', '-f', '-'],
      { input: cleanup },
    );
    fail('Verification preflight SQL tests failed via psql.', psqlResult);
  }
  return psqlResult.stdout;
}

const harness = loadHarness();
const script = harness.scenarios.map((scenario) => scenario.sql).join('\n');
const stdout = executeSql(script, harness.cleanup);
assertScenarios(stdout, harness.scenarios);
console.log('041 verification readonly preflight SQL tests passed.');
