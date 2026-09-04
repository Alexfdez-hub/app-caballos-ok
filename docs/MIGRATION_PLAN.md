# MIGRATION & REFACTOR PLAN v1.0

**Basado en:** Data Architecture 2.1 — Frozen MVP0  
**Objetivo:** refactor progresivo sin reescritura total  
**Implementación:** Codex (Cursor/Grok may resume on a later train)
**Estado:** Phase 14B consolidated P0 security gate implemented on
the accepted Phase 13C HEAD `43b6ec63f620d97ea90b122474e0f2347142ee2f`
from `cursor/phase-029-critical-audit-d219`. Tests/docs only; no
`030_security_hardening.sql`. Do not merge. Do not deploy. Do not start 031.

**Current baseline (verified 2026-09-04):** `origin/main` HEAD is
`9d58d3605a931fd930520238276215cf17a51a38` (merge of PR #28). PRs
#19–#28 are merged. Migrations `001`–`026` exist on `main`. Product
Owner states remote project `efkauegdlmfkonzwyyiv` is aligned through
exact version `026`. This agent does not deploy and does not modify
remote. `023`–`026` are merged (PRs #25–#28). `027` is implemented on
the accepted parent and is not deployed. Historical reports that described
`023`–`026` as stacked/not deployed are preserved. `027` is the
accepted stacked parent through `028`; `029` is implemented on this branch.

**Historical (Phase 5A branch time):** earlier text described `011`–`014`
as stacked/not deployed and remote aligned through `010`. That was true
then. It is superseded by the merge of #11–#14 and remote alignment
through `014`. Phase 5A report is not rewritten.

Product Owner approved ownership/management `ACTIVE|ENDED`, assignment
`ACTIVE|ENDED`, permission `ACTIVE|REVOKED`, and discipline
`ACTIVE|INACTIVE` (2026-09-02). Product Owner named 019 authorization
status `ACTIVE|REVOKED` (2026-09-02).

## 1. Método

Cada fase:
`INSPECT → PLAN → IMPLEMENT → TEST → DOCUMENT → STOP`.

No continuar a la fase siguiente sin revisión.

## 2. Reglas permanentes

- Leer `AI_INSTRUCTIONS.md`, `docs/DATA_ARCHITECTURE.md`, `docs/MIGRATION_PLAN.md` y `docs/CURRENT_ARCHITECTURE_REPORT.md`.
- No cambiar arquitectura frozen sin autorización.
- No exponer secretos ni usar service_role en Expo.
- DB changes sólo con migrations.
- RLS obligatoria.
- Código nuevo TypeScript.
- No poner reglas críticas en screens.
- RPC/server-side para acciones críticas.
- No hacer cleanup ajeno a la fase.
- Actualizar `docs/MIGRATION_STATUS.md` y detenerse.

## 3. Phase 0 — Audit

**COMPLETADA Y APROBADA.**

Resultado: `docs/CURRENT_ARCHITECTURE_REPORT.md`.

## 4. Phase 1 — Technical Foundation

Objetivo: infraestructura, sin cambios de DB ni dominio.

Acciones:
1. TypeScript gradual.
2. Crear `src/app`, `features`, `services`, `types`, `config`, `utils`.
3. Supabase client → `src/services/supabase/client.ts`.
4. Variables `EXPO_PUBLIC_SUPABASE_URL` y `EXPO_PUBLIC_SUPABASE_ANON_KEY`.
5. AuthProvider.
6. Restaurar sesión persistida al arrancar.
7. `onAuthStateChange`.
8. Navigation gate autenticado/no autenticado.
9. Mantener login/sign-up/logout.
10. Corregir metadata residual de plantilla Expo.
11. No migrations.
12. No migrar horses/bookings/persons.
13. No rediseñar UI.
14. Ejecutar checks TypeScript/Expo.

Criterio: app arranca, login/logout funcionan, sesión persistida restaura Home y no hay cambios de DB.

## 5. Phase 2 — Migration infrastructure + identity/policies

Crear `supabase/migrations` y `seed.sql`.

Migrations:
- 001 extensions/core
- 002 markets
- 003 persons/accounts
- 004 policies

No crear centers/equines/bookings todavía.

## 6. Phase 2C — Clean baseline / legacy retirement

Retirar el prototipo original por decisión de producto, sin backfill:
- eliminar trigger/función Auth legacy;
- eliminar `public.bookings`, `public.horses`, `public.users`;
- retirar pantallas y dependencias exclusivas del prototipo;
- conservar infraestructura Expo, Supabase Auth/sesión y tablas 001–004.

Migration: `005_legacy_retirement`.

## 7. Phase 3A — Identity integration

**IMPLEMENTADA Y MERGEADA EN `main` (PR #4).** Migration `006_identity_integration`.

Construye directamente sobre `persons` + `user_accounts`. Provisioning,
onboarding y perfil de identidad sin `users.role`. Guardians no forman parte
de esta fase.

Secuencia de migrations actualizada:

```text
001_extensions_and_core
002_markets
003_persons_accounts
004_policies
005_legacy_retirement
006_identity_integration
007_guardians
008_rider_profiles
009_centers
010_center_memberships
011_equines
012_equine_ownership_management
013_equine_center_relations
014_disciplines
015_qualifications
016_assessments
017_equine_requirements
018_services
019_zero_sessions_authorizations
020_calendar
021_bookings
022_booking_functions
023_sessions
024_activity
025_reviews_incidents
026_audit
027_storage_policies
028_rls_security_tests
029_critical_audit
```

## 8. Phase 3B — Guardians / minors

**IMPLEMENTADA Y MERGEADA EN `main` (PR #5).** Migration `007_guardians.sql`.

Crear `guardian_relationships`, `guardian_consents`, reglas de edad por
mercado y RPCs de consentimiento. No implementar centros, bookings ni
autoridad de verificación.

## 8b. Phase 3C — Rider profile / Passport foundations

**IMPLEMENTADA Y MERGEADA EN `main` (PR #6).** Migration
`008_rider_profiles.sql`.

Product Owner authorized this phase before Centers. Occupies unused
migration number `008`. Planned Centers moves to `009_centers.sql`.

Creates person-owned `rider_profiles` (1:1 with `persons`) and self-service
RPCs for the authenticated adult caller. Does not create disciplines,
qualifications, assessments, centers, equines, Session Zero or
authorizations. Does not require `RIDER_POLICY` to create the foundation
record. Guardian-managed editing of a minor’s profile is deferred.

## 8c. Phase 3D — Centers foundation

**IMPLEMENTADA Y MERGEADA EN `main` (PR #7).** Migration `009_centers.sql`
desplegada en el proyecto linked `efkauegdlmfkonzwyyiv`. Histories local y
remota alineadas hasta `009`.

Creates `equestrian_centers` and `center_languages`. No client creation,
verification or public directory.

## 8d. Phase 3E — Center memberships

**IMPLEMENTADA Y MERGEADA EN `main` (PR #9).** Migration
`010_center_memberships.sql` desplegada en el proyecto linked
`efkauegdlmfkonzwyyiv`. Histories local y remota alineadas hasta `010`.

Creates `center_memberships` as PERSON + CENTER relationships with MVP0
roles `ADMIN|MANAGER|INSTRUCTOR|ASSESSOR`. Product Owner froze lifecycle
`ACTIVE|ENDED` for 010; `INVITED`/`PENDING`/`SUSPENDED` are not in this
migration. Caller-context read via `list_my_center_memberships()`.
Server-internal `has_active_center_role(...)`. No client
grant/revoke/bootstrap RPC. Invitations, first-admin onboarding, Center
Policy activation, assessments, services and bookings remain deferred.
Equines foundation is implemented separately as Phase 3F / migration `011`.

## 8e. Phase 3F — Equines foundation

**IMPLEMENTADA Y MERGEADA EN `main` (PR #11).** Migration `011_equines.sql`
is on `main`. Product Owner states remote is aligned through `014`.

Creates `equines` and `equine_media`. Frozen types `HORSE|PONY`. Product
Owner confirmed lifecycle `ACTIVE|INACTIVE|ARCHIVED|DECEASED`
(`DECEASED ≠ ARCHIVED`; `RETIRED` is not a token). Visibility
`PRIVATE|PUBLIC` (PUBLIC is stored intent only). Media type `PHOTO` only.
`birth_date` is optional and must not be after `created_at::date`. Age is
not stored. `storage_path` is unique metadata only; 011 does not create a
Storage bucket. RLS deny-by-default; no client table grants; no client RPC.
Ownership, management, center assignment, public directory, availability,
booking and media upload remain deferred.

## 9. Phase 4 — Equines ownership / center relations (histórico)

Architecture Phase 4 grouped equines + ownership + management + center
relations. Implementation numbering splits them:

- `011_equines` — foundation (merged PR #11)
- `012_equine_ownership_management` — merged PR #12. Product Owner
  approved stored lifecycle `ACTIVE|ENDED` (2026-09-02). Effective
  management also requires `valid_from <= now()`; `now()` is not in a CHECK.
- `013_equine_center_relations` — merged PR #13. Product Owner
  approved assignment `ACTIVE|ENDED` and permission `ACTIVE|REVOKED`.
  Effective permission also requires `granted_at <= now()`; `now()` is
  not in a CHECK.

Do not collapse ownership or management onto `equines`. Do not invent
owner/manager/center columns. Do not migrate legacy `horses` (retired in
005). Do not invent absent data.

## 10. Phase 5 — Disciplines / qualifications

`rider_profiles` foundations are implemented in Phase 3C.
`014_disciplines.sql` (`disciplines`, `discipline_translations`,
`equine_disciplines`) is merged (PR #14) and does not seed a catalog.
Product Owner approved stored lifecycle `ACTIVE|INACTIVE` (2026-09-02).
`sort_order` must be `>= 0`; duplicate non-negative values are allowed.
`015_qualifications.sql` (`qualification_systems`, `qualification_levels`,
`rider_qualifications`) is implemented on `refactor/phase-5b-qualifications`.
No seed. No equivalences. Rider verification states are frozen
`DECLARED|PENDING|VERIFIED|REJECTED|EXPIRED`. Sensitive Rider activation
still requires `RIDER_POLICY`; profile existence is not that activation.

## 11. Phase 6 — Assessments

**IMPLEMENTADA EN `refactor/phase-6a-rider-assessments` (stacked on PR #15).**
Migration `016_rider_assessments.sql`. Assessor must have an active
`ASSESSOR` membership at the assessment Center and cannot autoevaluate.
Historical rows remain if the assessor later leaves. No Zero Session,
authorization, eligibility or booking RPCs.

## 12. Phase 7 — Guardians/minors (histórico de numeración)

Cubierto por migration `007_guardians.sql` en Phase 3B. No crear una segunda
migración de guardians. El heading histórico no cambia el orden frozen.

## 13. Phase 8 — Requirements/services/trust

`017_equine_requirements.sql` is merged (PR #17).
`018_center_services.sql` is merged (PR #18).
`019_zero_sessions_authorizations.sql` is merged (PR #20).
`020_calendar.sql` is merged (PR #21).
`021_bookings.sql` is merged (PR #22).
`022_booking_functions.sql` is merged (PR #23).
`023_sessions.sql` is merged (PR #25).
`024_equine_activity.sql` is merged (PR #26).
`025_reviews_incidents.sql` is merged (PR #27).
`026_audit.sql` is merged (PR #28).

## 14. Phase 9 — Calendar

`020_calendar.sql` adds availability rules and calendar blocks. Calendar
blocks are canonical occupancy. ACTIVE same-equine overlapping
`tstzrange`s are excluded with gist. Recurrence is stored, not expanded.

## 15. Phase 10 — Bookings/eligibility

Crear bookings + booking requirements. Implementar `check_booking_eligibility`, `create_booking_request`, `confirm_booking`. Confirmación atómica + calendar block + policy snapshot.

## 16. Phase 11 — Verified sessions

`023_sessions.sql` is merged (PR #25). Start/end are
server-authoritative RPCs using `clock_timestamp()`. Offline start uses a server-issued confirmed
booking permit.

## 17. Phase 12 — Equine activity / reviews / incidents / audit

`024_equine_activity.sql` is merged (PR #26). Activity is
session-linked and append-only.
`025_reviews_incidents.sql` is merged (PR #27). Rating is frozen
1..5. Incident type/severity/status catalogs are not invented.
`026_audit.sql` is merged (PR #28). Only 023–025 critical
transitions are audited there. `029_critical_audit.sql` extends that
foundation for policy, consent, assessment, equine permission, Zero
Session approval and booking confirm/cancel.

## 18. Phase 13 — Storage security

`027_storage_policies.sql` is implemented on the accepted parent. Target
buckets `avatars`, `equine-media`, `qualification-documents`,
`session-evidence` and `assessment-documents` are private. Evidence
and document buckets bind INSERT/SELECT to domain authority. Avatars
and equine-media stay deny-by-default; see
`docs/ARCHITECTURE_CONFLICT_027_STORAGE_VISIBILITY.md`. This branch adds
`028_zero_session_approval.sql`, preserving the separation between
assessment, Zero Session and authorization and enforcing server actor,
time, policy, consent, authority, immutability, replay and concurrency
rules. This branch adds `029_critical_audit.sql` for the remaining
critical committed transitions. Do not merge or deploy the stacked train.

## 19. Phase 14 — Security test suite

Tests RLS, minors, assessments, permissions, booking transitions, double booking, evidence privacy.

## 20. Phase 15 — Transitional cleanup

Eliminar únicamente estructuras transitorias restantes tras su validación. El
prototipo original se retira en Phase 2C por decisión de producto.

## 21. Commits

Un commit por cambio lógico. Evitar commits gigantes.

## 22. Estado por fase

Después de cada fase actualizar `docs/MIGRATION_STATUS.md` con:
- PHASE
- STATUS
- DATE
- FILES CREATED/MODIFIED
- MIGRATIONS
- TESTS/CHECKS
- KNOWN ISSUES
- MANUAL STEPS
- NEXT PHASE

## 23. Prompt exacto para Phase 1

```text
Phase 0 has been reviewed and approved.

Implement PHASE 1 only: Technical Foundation.

Before modifying anything, read:
- docs/CURRENT_ARCHITECTURE_REPORT.md
- docs/DATA_ARCHITECTURE.md
- docs/MIGRATION_PLAN.md
- AI_INSTRUCTIONS.md

Goals:
1. Introduce TypeScript with a gradual migration strategy.
2. Create the approved src architecture:
   - app/
   - features/
   - services/
   - types/
   - config/
   - utils/
3. Move the Supabase client into src/services/supabase/client.ts.
4. Replace hardcoded Supabase config with EXPO_PUBLIC_SUPABASE_URL and EXPO_PUBLIC_SUPABASE_ANON_KEY.
5. Never introduce or expose service_role.
6. Add AuthProvider, initial session restoration, onAuthStateChange and auth navigation gate.
7. Preserve sign-in, sign-up and sign-out behaviour.
8. Correct residual Expo template metadata where appropriate.
9. Do NOT modify database schema.
10. Do NOT create migrations yet.
11. Do NOT migrate horses, bookings or domain identity yet.
12. Do NOT redesign UI.
13. Do NOT rename DB tables or columns.
14. Preserve runtime behaviour except fixing session restoration.
15. Remove BookingsDummy only if confirmed unused with zero runtime impact.
16. Run all available TypeScript/Expo checks.

Update docs/MIGRATION_STATUS.md and STOP after Phase 1.

Report files changed, dependencies, TypeScript config, env config, auth changes, checks, warnings and manual steps.
```

## 24. Governance

Product Owner decide reglas, alcance y aceptación. Arquitectura define modelo, datos, permisos e invariantes. Cursor implementa; no redefine.

**Siguiente fase prevista tras Phase 14B:**
Stop after the 030 security-gate Quality Gate and the issue #32 handoff.
Do not start 031. Do not merge or deploy.
