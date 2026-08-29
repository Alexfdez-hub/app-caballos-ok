# MIGRATION & REFACTOR PLAN v1.0

**Basado en:** Data Architecture 2.1 — Frozen MVP0  
**Objetivo:** refactor progresivo sin reescritura total  
**Implementación:** Cursor  
**Estado:** Phase 2C en implementación; Phase 3A requiere aprobación posterior

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

Construir directamente sobre `persons` + `user_accounts`. Crear provisioning,
onboarding y perfil de identidad sin reintroducir `users.role`.

Migration prevista: `006_identity_integration`.

Secuencia de migrations actualizada:

```text
001_extensions_and_core
002_markets
003_persons_accounts
004_policies
005_legacy_retirement
006_identity_integration
007_guardians
008_centers
009_center_memberships
010_equines
011_equine_ownership_management
012_equine_center_relations
013_disciplines
014_qualifications
015_assessments
016_equine_requirements
017_services
018_zero_sessions_authorizations
019_calendar
020_bookings
021_booking_functions
022_sessions
023_activity
024_reviews_incidents
025_audit
026_storage_policies
027_rls_security_tests
```

## 8. Phase 3B — Centers

Crear centers, languages, memberships. Onboarding de centro de piloto controlado. Roles: ADMIN/MANAGER/INSTRUCTOR/ASSESSOR.

## 9. Phase 4 — Equines

Crear equines/media/ownership/management/center assignments/permissions. Migrar horses progresivamente. No inventar datos ausentes.

## 10. Phase 5 — Riders / disciplines / qualifications

Crear rider profiles, disciplines/translations, qualification systems/levels, rider qualifications. Activación Rider requiere `RIDER_POLICY`.

## 11. Phase 6 — Assessments

Crear assessments + discipline results + restrictions. Assessor debe tener membership válido y no puede autoevaluarse.

## 12. Phase 7 — Guardians/minors

Crear guardian relationships/consents. Menor puede existir como person sin Auth. Implementar `grant_guardian_consent()`. P0: menor sin consentimiento requerido no confirma actividad.

## 13. Phase 8 — Requirements/services/trust

Crear equine requirements, center services, service-equines, Zero Sessions y rider-equine authorizations.

## 14. Phase 9 — Calendar

Crear availability rules + calendar blocks. Calendar blocks = ocupación canónica. Añadir exclusión/race protection en PostgreSQL. Test concurrencia obligatorio.

## 15. Phase 10 — Bookings/eligibility

Crear bookings + booking requirements. Implementar `check_booking_eligibility`, `create_booking_request`, `confirm_booking`. Confirmación atómica + calendar block + policy snapshot.

## 16. Phase 11 — Verified sessions

Crear sessions/events/evidence/equine activities. Implementar start/end session. Timer server-authoritative. Offline sólo para booking confirmado con permit.

## 17. Phase 12 — Reviews/incidents/audit

Crear reviews, incidents, audit_events.

## 18. Phase 13 — Storage security

Buckets objetivo: avatars, equine-media, qualification-documents, session-evidence, assessment-documents. Evidence privada.

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

**Siguiente fase prevista tras aprobar Phase 2C:** Phase 3A — Identity integration.
