# Phase 9B — Zero Session approval report

**Migration:** `supabase/migrations/028_zero_session_approval.sql`
**Branch:** `refactor/phase-9b-zero-session-approval`
**Base:** accepted Phase 14A / migration 027 HEAD `a3dd18fed7b5ef27d7aba31c6c0c517f8d23c69c`
**Status:** implemented; stacked PR and complete Quality Gate pending

## Scope

Phase 9B adds the authenticated `approve_zero_session(uuid, text, text)`
RPC. It is the only client-callable approval path in this phase. Direct
authenticated table updates remain revoked.

The RPC locks the target row, derives the evaluator from `auth.uid()`
through the active ACCOUNT → PERSON relation, derives `performed_at` on
the server, and permits only `APPROVED` or
`APPROVED_WITH_RESTRICTIONS` from `PENDING`.

Approval requires an active rider, equine and Center, an active
`ASSESSOR` membership, effective `ASSESS_RIDERS`, applicable actor and
participant policy acceptances, and market-aware guardian relationship
and equestrian-activity consent for a minor. It rejects self-approval,
future sessions and cross-context authority.

Approval remains distinct from assessment and rider-equine
authorization. It never creates an authorization.

## Historical and concurrency guarantees

- The target row is serialized with `FOR UPDATE`.
- An exact replay by the original evaluator is a read-only idempotent
  success and preserves the original timestamp.
- A conflicting replay fails with a serialization error.
- Final result, evaluator, performed time and notes are immutable.
- The existing participant/equine/Center/requester identity remains
  immutable.

## Security

The RPC is `SECURITY DEFINER` with fixed
`search_path = pg_catalog, public`. `PUBLIC` and `anon` execution are
revoked; only `authenticated` receives `EXECUTE`. Actor identity,
authorization and server time cannot be supplied by the caller.

## Verification

`supabase/tests/028_zero_session_approval_test.sql` covers grants,
anonymous and unrelated callers, future sessions, minors and consent,
invalid transitions, successful adult/minor approvals, immutable
history, idempotent/conflicting replay, authority revocation and the
absence of automatic authorization.

The `028_zero_session_approval_concurrency_*` fixtures and
`scripts/run-zero-session-approval-concurrency-test.cjs` race two
different evaluators against one row and require exactly one committed
winner without deadlock or duplicate side effects.

Earlier phase suites 016–027 no longer assert that the now-delivered
`approve_zero_session` RPC is absent. Their own phase-specific negative
assertions remain intact.

Local static checks pass. PostgreSQL execution and the complete GitHub
Quality Gate remain required before this phase may be marked Ready or
Phase 13C may start.

## Excluded

- No authorization issuance or assessment mutation.
- No client table CRUD or audit feed.
- No remote deployment, merge or migration 029.
