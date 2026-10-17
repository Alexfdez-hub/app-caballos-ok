import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const sql = readFileSync(
  new URL('../../../docs/VERIFICATION_READONLY_PREFLIGHT_041.sql', import.meta.url),
  'utf8',
);
const doc = readFileSync(
  new URL('../../../docs/VERIFICATION_READONLY_PREFLIGHT_041.md', import.meta.url),
  'utf8',
);

const statementLines = sql
  .split(/\r?\n/)
  .map((line) => line.trim())
  .filter((line) => line.length > 0 && !line.startsWith('--'));

test('readonly preflight is one read-only transaction', () => {
  assert.equal(statementLines[0], 'begin read only;');
  assert.equal(statementLines[statementLines.length - 1], 'rollback;');
  assert.equal(sql.includes('commit'), false);
  assert.equal(/\b(insert|update|delete|alter|drop|truncate|merge|create)\b/i.test(sql), false);
});

test('readonly preflight does not call mutating verification functions', () => {
  const calls = [
    'public.create_verification_review_cohort',
    'public.add_verification_review_cohort_case',
    'public.close_verification_review_cohort_composition',
    'public.suspend_verification_review_grant',
    'public.close_verification_review_grant',
    'public.review_identity_case',
    'public.review_equine_ownership_claim',
    'public.review_equine_management_claim',
    'select public.bootstrap_verification_review_grant',
  ];

  for (const call of calls) {
    assert.equal(sql.includes(call), false, call);
  }
});

test('readonly preflight keeps placeholders and hides identifiers', () => {
  assert.equal(sql.includes('<address-of-A-typed-in-this-session>'), true);
  assert.equal(sql.includes('<address-of-B-typed-in-this-session>'), true);
  assert.equal(sql.includes('@'), false);
  assert.equal(
    /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i.test(sql),
    false,
  );
  assert.equal(sql.includes('verification_case_evidence_is_sufficient'), true);
  assert.equal(sql.includes("'IDENTITY_CASE'"), true);
  assert.equal(sql.includes("'OWNERSHIP_CLAIM'"), true);
  assert.equal(sql.includes("'MANAGEMENT_CLAIM'"), true);
  assert.equal(sql.includes('IDENTITY_PROVIDER_REFERENCE'), false);
  assert.equal(sql.includes('storage_path'), false);
  assert.equal(/\bmax\s*\(\s*person_id\s*\)/i.test(sql), false);
  assert.equal(/\bmax\s*\(\s*account_id\s*\)/i.test(sql), false);
  assert.equal(sql.includes('array_agg(person_id)'), true);
  assert.equal(sql.includes('array_agg(account_id)'), true);
  assert.equal(sql.includes('array_agg(country_code)'), true);
});

test('readonly preflight emits only the three verdicts', () => {
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

  for (const check of checks) {
    assert.equal(sql.includes(`'${check}'`), true, check);
    assert.equal(doc.includes(`\`${check}\``), true, check);
  }

  assert.equal(sql.includes("'PASS'"), true);
  assert.equal(sql.includes("'STOP'"), true);
  assert.equal(sql.includes("'OPERATOR_ESCALATION_REQUIRED'"), true);
  assert.equal(sql.includes("'DECISION_REQUIRED'"), true);
  assert.equal(sql.includes("'ARCHITECTURE_CONFLICT'"), true);
  assert.equal(doc.includes('no ejecuta el preflight remoto'), true);
  assert.equal(doc.includes('no elige solución'), true);
});
