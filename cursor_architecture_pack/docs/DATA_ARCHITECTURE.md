# DATA ARCHITECTURE 2.1 — FROZEN MVP0
## Plataforma Digital del Ecosistema Ecuestre

**Estado:** FROZEN PARA MVP0  
**Mercado inicial:** España  
**Frontend:** Expo + React Native + TypeScript  
**Backend:** Supabase + PostgreSQL + Supabase Auth

## 1. Principios frozen

1. `person` y `user_account` son conceptos distintos.
2. Una `person` puede existir sin cuenta; caso principal: menor gestionado por tutor.
3. Una persona puede tener múltiples roles simultáneamente.
4. Menores: ningún flujo ecuestre relevante puede eludir el consentimiento de tutor cuando sea obligatorio.
5. `equine` es la entidad genérica; `HORSE` y `PONY` son tipos.
6. Propiedad, gestión y ubicación/pupilaje son conceptos distintos.
7. Evaluación de hípica, Sesión Cero, autorización jinete-equino y consentimiento de tutor son conceptos independientes.
8. La compatibilidad depende de persona + equino + servicio + centro + tiempo + políticas.
9. PostgreSQL es autoridad para reservas, transiciones críticas y conflictos de calendario.
10. RLS es obligatoria y deny-by-default.
11. Las políticas por rol y sus aceptaciones están versionadas y auditadas.
12. Cursor implementa esta arquitectura; no debe rediseñarla.

## 2. Identidad

### `persons`
- `id uuid pk`
- `first_name text not null`
- `last_name text not null`
- `display_name text`
- `date_of_birth date not null`
- `country_code text`
- `status text not null default 'ACTIVE'`
- `created_at timestamptz default now()`
- `updated_at timestamptz default now()`

No almacenar edad; se calcula para la fecha de actividad.

### `user_accounts`
- `id uuid pk`
- `auth_user_id uuid unique not null -> auth.users(id)`
- `person_id uuid unique not null -> persons(id)`
- `preferred_locale text`
- `timezone text`
- `status text not null default 'ACTIVE'`
- timestamps

Usar `person_id` para identidad ecuestre y `user_account_id` sólo para acciones autenticadas/auditoría.

## 3. Roles

No existe `users.role` único. Los roles se derivan de relaciones:
- jinete → `rider_profiles`
- propietario → `equine_ownerships`
- tutor → `guardian_relationships`
- admin/manager/instructor/assessor → `center_memberships`

## 4. Jinetes y menores

### `rider_profiles`
- `person_id uuid pk/fk`
- `bio text`
- `experience_start_year smallint`
- `profile_visibility text`
- timestamps

### `guardian_relationships`
- `id uuid pk`
- `guardian_person_id uuid not null fk`
- `minor_person_id uuid not null fk`
- `relationship_type text`
- `verification_status text`
- `verified_at`, `expires_at`, `revoked_at`
- timestamps
- CHECK guardian != minor

Estados: `PENDING`, `VERIFIED`, `REJECTED`, `REVOKED`, `EXPIRED`.

### `guardian_consents`
- `id uuid pk`
- `guardian_relationship_id uuid not null fk`
- `guardian_person_id uuid not null fk`
- `minor_person_id uuid not null fk`
- `granted_by_account_id uuid not null fk -> user_accounts`
- `booking_id uuid null`
- `equine_id uuid null`
- `center_id uuid null`
- `consent_type text`
- `scope_type text`
- `terms_version text`
- `status text`
- `granted_at`, `expires_at`, `revoked_at`
- `metadata jsonb default '{}'`

Regla P0: policy acceptance ≠ guardian consent. El consentimiento debe comprobarse server-side para toda actividad ecuestre relevante cuando sea obligatorio, incluidas reservas, Sesión Cero, evaluación práctica y lecciones.

## 5. Hípicas

### `equestrian_centers`
- id, name, slug, description
- country_code, region, city, postal_code, address_line
- latitude, longitude
- timezone, default_currency
- verification_status, status
- timestamps

### `center_languages`
- `center_id`, `locale` PK compuesta

### `center_memberships`
- `id uuid pk`
- `center_id uuid fk`
- `person_id uuid fk`
- `role_code text`
- `status text`
- `joined_at`, `ended_at`, `created_at`

Roles MVP0: `ADMIN`, `MANAGER`, `INSTRUCTOR`, `ASSESSOR`.

## 6. Equinos

### `equines`
- `id uuid pk`
- `name text not null`
- `equine_type text not null` (`HORSE`, `PONY`)
- `birth_date date`
- `sex text`
- `breed text`
- `height_cm numeric`
- `description text`
- `temperament_description text`
- `status text`
- `visibility_status text`
- timestamps

### `equine_media`
- id, equine_id, storage_path, media_type, sort_order, is_primary, created_at

## 7. Propiedad y gestión

### `equine_ownerships`
Patrón explícito PERSON/CENTER; no introducir party genérico en MVP0.
- id, equine_id
- `owner_type` (`PERSON`,`CENTER`)
- `owner_person_id null`
- `owner_center_id null`
- `ownership_percentage`
- started_at, ended_at, status, created_at

CHECK: exactamente uno de los owner FK es no nulo y coincide con `owner_type`.

### `equine_management_assignments`
- id, equine_id
- manager_type
- manager_person_id / manager_center_id
- management_role
- valid_from, valid_until, status
- granted_by_person_id
- created_at

Roles: `PRIMARY_MANAGER`, `CO_MANAGER`, `AUTHORIZED_MANAGER`.
MVP0 exige un único `PRIMARY_MANAGER` activo para un equino publicable.

## 8. Equino ↔ centro

### `equine_center_assignments`
- id, equine_id, center_id
- assignment_type (`BOARDING`,`CENTER_OWNED`,`SCHOOL`,`TEMPORARY`,`OTHER`)
- started_at, ended_at, status, created_at

### `equine_center_permissions`
- id, equine_id, center_id
- granted_by_person_id
- permission_code
- granted_at, revoked_at, status

Permisos MVP0: `MANAGE_AVAILABILITY`, `MANAGE_BOOKINGS`, `ASSESS_RIDERS`, `APPROVE_RIDERS`, `MANAGE_REQUIREMENTS`, `VIEW_ACTIVITY`.

## 9. Disciplinas y cualificaciones

### `disciplines`
- id, code unique, status, sort_order

### `discipline_translations`
- discipline_id, locale, name, description

### `equine_disciplines`
- equine_id, discipline_id, experience_level, notes

### `qualification_systems`
- id, code unique, name, country_code, issuing_organization, status

### `qualification_levels`
- id, qualification_system_id, code, level_order, name, description, discipline_id, status

### `rider_qualifications`
- id, rider_person_id, qualification_level_id
- certificate_number, issued_at, expires_at
- verification_status (`DECLARED`,`PENDING`,`VERIFIED`,`REJECTED`,`EXPIRED`)
- verified_by_person_id, document_path, created_at

No hardcodear Galopes ni equivalencias internacionales automáticas.

## 10. Evaluaciones de hípica

### `rider_assessments`
- id, rider_person_id, center_id, assessor_person_id
- assessment_type
- performed_at, valid_until
- status (`DRAFT`,`PENDING`,`VALID`,`REJECTED`,`REVOKED`,`EXPIRED`)
- general_notes, timestamps

Tipos: `ACCESS_TEST`, `RIDING_LESSON`, `COURSE`, `PRACTICAL_TEST`, `OTHER`.

### `rider_assessment_disciplines`
- id, assessment_id, discipline_id, observed_level, supervision_required, notes

### `rider_assessment_restrictions`
- id, assessment_id, restriction_code, value_json, notes

La autoridad histórica de la evaluación es la hípica; si el evaluador se marcha, el histórico permanece.

## 11. Servicios y requisitos

### `center_services`
- id, center_id, service_type, name, description, default_duration_minutes, status, timestamps

MVP0: `EQUINE_SESSION`, `RIDER_ASSESSMENT`, `ZERO_SESSION`.

### `service_equines`
- id, service_id, equine_id
- enabled
- supervision_required
- requirements jsonb
- duration_limit_minutes
- authorization_policy
- status, created_at

### `equine_requirements`
- id, equine_id, requirement_type
- discipline_id, qualification_level_id
- numeric_value, boolean_value, text_value
- source_type (`OWNER`,`CENTER`,`MARKET`)
- source_id, status, created_at

Tipos MVP0: `MIN_AGE`, `MAX_AGE`, `MIN_QUALIFICATION`, `CENTER_ASSESSMENT_REQUIRED`, `ZERO_SESSION_REQUIRED`, `OWNER_APPROVAL_REQUIRED`, `SUPERVISION_REQUIRED`, `MIN_EXPERIENCE`.

## 12. Sesión Cero y autorización

### `zero_sessions`
- id, rider_person_id, equine_id, center_id
- requested_by_account_id
- scheduled_at, performed_at
- evaluator_person_id
- result (`PENDING`,`APPROVED`,`APPROVED_WITH_RESTRICTIONS`,`REJECTED`,`CANCELLED`)
- notes, created_at

### `rider_equine_authorizations`
- id, rider_person_id, equine_id
- authorization_type (`OWNER_APPROVAL`,`ZERO_SESSION`,`CENTER_DELEGATED_APPROVAL`)
- issued_by_person_id
- center_id
- source_zero_session_id
- status, valid_from, valid_until
- supervision_required
- restrictions_json
- created_at, revoked_at

## 13. Calendario

### `equine_availability_rules`
Disponibilidad potencial.
- id, equine_id, center_id
- starts_at, ends_at
- recurrence_rule
- status
- created_by_account_id, created_at
- CHECK ends_at > starts_at

### `equine_calendar_blocks`
Fuente canónica de ocupación.
- id, equine_id, center_id
- starts_at, ends_at
- block_type
- source_type, source_id
- status, created_at
- CHECK ends_at > starts_at

Tipos: `BOOKING`, `OWNER_USE`, `LESSON`, `COURSE`, `TRAIL_RIDE`, `VET`, `REST`, `MANUAL_BLOCK`, `OTHER`.

PostgreSQL debe impedir solapamientos incompatibles para el mismo equino mediante `tstzrange` + `EXCLUDE USING gist` o mecanismo transaccional equivalente.

## 14. Reservas

### `bookings`
- id
- `participant_person_id uuid not null`
- `booked_by_account_id uuid not null`
- equine_id, center_id, service_id
- starts_at, ends_at
- status
- eligibility_status
- `booking_policy_snapshot jsonb default '{}'`
- timestamps + confirmed_at/cancelled_at/completed_at
- CHECK ends_at > starts_at

Estados: `DRAFT`, `REQUESTED`, `PENDING_REQUIREMENTS`, `PENDING_APPROVAL`, `APPROVED`, `CONFIRMED`, `ACTIVE`, `COMPLETED`, `REJECTED`, `CANCELLED`, `EXPIRED`, `DISPUTED`.

### `booking_requirements`
- id, booking_id
- requirement_type
- source_type, source_id
- status (`PENDING`,`SATISFIED`,`WAIVED`,`FAILED`,`EXPIRED`)
- resolved_at, resolved_by_account_id
- metadata, created_at

Cambios ordinarios de política no deben mutar retroactivamente una reserva confirmada. El snapshot conserva las reglas aplicadas.

## 15. Elegibilidad

Unidad real:

`PERSON + EQUINE + SERVICE + CENTER + TIME + OWNER POLICY + CENTER POLICY + MARKET POLICY`

Resultados posibles:
- `ELIGIBLE`
- `ELIGIBLE_WITH_SUPERVISION`
- `REQUIRES_CENTER_ASSESSMENT`
- `REQUIRES_ZERO_SESSION`
- `REQUIRES_OWNER_APPROVAL`
- `REQUIRES_GUARDIAN_CONSENT`
- `QUALIFICATION_NOT_VERIFIED`
- `NOT_ELIGIBLE`

Puede devolver múltiples requisitos pendientes. Debe ser explicable a UI.

## 16. Políticas de usuario

### `policy_documents`
- id, policy_code, policy_type, role_code
- market_code, locale, version
- title, summary, content
- effective_from, effective_to
- status
- requires_reacceptance
- created_at
- UNIQUE(policy_code, market_code, locale, version)

Tipos: `TERMS_OF_SERVICE`, `PRIVACY_POLICY`, `RIDER_POLICY`, `OWNER_POLICY`, `CENTER_POLICY`, `ASSESSOR_POLICY`, `GUARDIAN_POLICY`, `ACTIVITY_POLICY`, `CENTER_RULES`.

### `policy_acceptances`
- id, policy_document_id
- person_id, user_account_id
- accepted_at
- acceptance_context, role_code
- center_id, booking_id
- metadata, created_at

La aceptación histórica no se borra al desactivar un rol.

## 17. Sesiones verificables

### `sessions`
- id
- booking_id UNIQUE
- equine_id
- participant_person_id
- center_id
- status
- started_at, ended_at
- start/end latitude/longitude
- started_offline, ended_offline
- sync_status
- timestamps

Estados: `READY`, `ACTIVE`, `ENDING`, `COMPLETED`, `PENDING_SYNC`, `REQUIRES_REVIEW`, `INVALIDATED`.

### `session_events`
- id, session_id, event_type
- occurred_at_device, received_at_server
- latitude, longitude
- device_id, offline
- metadata, created_at

Eventos: `CHECK_IN`, `START`, `PHOTO_START`, `END_REQUESTED`, `PHOTO_END`, `CHECK_OUT`, `SYNC`.

### `session_evidence`
- id, session_id, evidence_type, storage_path
- captured_at_device, received_at_server
- latitude, longitude
- status, created_at

Tipos: `START_PHOTO`, `END_PHOTO`, `INCIDENT_PHOTO`.
Evidencia no pública.

El timer visual no es autoridad; la duración oficial deriva de timestamps validados.

## 18. Offline

Sólo para una reserva previamente `CONFIRMED` con permiso temporal de sesión ligado a booking, participante, equino y ventana temporal.

No permitido plenamente offline: nueva reserva, nueva autorización, nuevo consentimiento, aprobación de jinete.

Al sincronizar: eventos locales → validación servidor → válido o `REQUIRES_REVIEW`. No eliminar evidencia inconsistente.

## 19. Actividad, reviews, incidentes, auditoría

### `equine_activities`
- id, equine_id, center_id
- activity_type
- booking_id, session_id
- starts_at, ends_at
- status, source
- created_by_account_id, created_at

### `reviews`
- id, booking_id, reviewer_person_id
- subject_type, subject_id
- rating CHECK 1..5
- comment, status, created_at

### `incidents`
- id, booking_id, session_id, equine_id
- reported_by_person_id, center_id
- incident_type, severity, description, status
- created_at, resolved_at

### `audit_events`
- id, actor_account_id, actor_person_id
- event_type, entity_type, entity_id
- metadata, occurred_at

Eventos clave: policy accepted, guardian consent, assessment validated, equine permission grant/revoke, zero session approval, booking confirmed/cancelled, session started/completed.

## 20. Mercados e internacionalización

### `markets`
- country_code PK
- default_currency, default_locale, timezone
- status, config jsonb, timestamps

### `market_age_rules`
- id, country_code
- legal_adult_age
- guardian_consent_required
- effective_from/effective_to
- config jsonb

Los valores legales concretos se validarán antes de producción. No hardcodear España en reglas universales.

## 21. RPC / funciones críticas

P0:
- `has_accepted_required_policy(...)`
- `check_booking_eligibility(...)`
- `create_booking_request(...)`
- `grant_guardian_consent(...)`
- `approve_zero_session(...)`
- `confirm_booking(...)`
- `start_session(...)`
- `end_session(...)`
- `create_safety_block(...)`

`confirm_booking()` debe ser atómica: revalida elegibilidad, consentimiento, autorizaciones, disponibilidad y calendario; crea calendar block; guarda snapshot; confirma; audita; rollback si algo falla.

## 22. RLS

Todas las tablas de negocio: `ENABLE ROW LEVEL SECURITY` y deny-by-default.

- personas/minores: privados salvo vistas/RPC controladas;
- equinos: lectura pública sólo si publicables;
- assessments: no auto-validación;
- consents: no insert arbitrario desde cliente;
- bookings: transiciones críticas sólo RPC;
- sessions: inicio/fin sólo funciones;
- evidence/docs: privados.

Nunca desactivar RLS para “hacer funcionar” una feature.

## 23. Constraints P0

- ends_at > starts_at
- height_cm > 0 cuando exista
- rating 1..5
- ownership_percentage 0..100
- ownership exactamente PERSON o CENTER
- management exactamente PERSON o CENTER
- guardian != minor
- `user_accounts.auth_user_id UNIQUE`
- `user_accounts.person_id UNIQUE` en MVP0
- `sessions.booking_id UNIQUE`
- un único PRIMARY_MANAGER activo por equino publicable
- no solapamiento incompatible en calendario
- FKs estructurales obligatorias

## 24. Índices P0

Índices prioritarios en:
- user_accounts.auth_user_id / person_id
- center_memberships.person_id / center_id
- equine_ownerships.equine_id
- equine_management_assignments.equine_id
- equine_center_assignments.equine_id / center_id
- rider_assessments.rider_person_id / center_id
- guardian_relationships guardian/minor
- guardian_consents minor/booking
- bookings participant/equine/center/starts_at/status
- equine_calendar_blocks equine/starts_at
- sessions.booking_id

## 25. Storage

Buckets objetivo:
- `avatars`
- `equine-media`
- `qualification-documents`
- `session-evidence`
- `assessment-documents`

`session-evidence`, qualification docs y assessment docs no serán públicos.

## 26. Arquitectura frontend

```text
Screen
↓
Hook / Use Case
↓
Domain Service
↓
Supabase / RPC
```

Objetivo de carpetas:

```text
src/
  app/navigation/
  app/providers/
  features/auth/
  features/persons/
  features/riders/
  features/guardians/
  features/centers/
  features/equines/
  features/qualifications/
  features/assessments/
  features/bookings/
  features/sessions/
  features/policies/
  services/supabase/
  services/storage/
  services/location/
  types/
  config/
  utils/
```

Código nuevo en TypeScript.

## 27. Orden de migrations

```text
001_extensions_and_core
002_markets
003_persons_accounts
004_policies
005_guardians
006_centers
007_center_memberships
008_equines
009_equine_ownership_management
010_equine_center_relations
011_disciplines
012_qualifications
013_assessments
014_equine_requirements
015_services
016_zero_sessions_authorizations
017_calendar
018_bookings
019_booking_functions
020_sessions
021_activity
022_reviews_incidents
023_audit
024_storage_policies
025_rls_security_tests
```

## 28. Migración del prototipo

Actual:
- Supabase Auth
- `horses`
- `bookings`
- bucket `horse-images`
- auth user id usado como owner_id/rider_id

Migración progresiva:
- crear persons + user_accounts para auth users existentes;
- `horses` → `equines`;
- owner_id → ownership + PRIMARY_MANAGER tras resolver user→account→person;
- media_url → equine_media;
- no inventar centro ni cualificaciones inexistentes;
- bookings antiguos sólo migrar si hay datos suficientes; no inventar información faltante.

## 29. Tests P0

Seguridad:
- no editar datos privados ajenos;
- no editar equino ajeno;
- centro no se autoasigna permisos;
- assessor no se autoevalúa;
- tutor no consiente por menor ajeno;
- menor no salta consentimiento;
- cliente no fuerza CONFIRMED;
- sesión no inicia sin booking válido;
- evidence no pública.

Negocio:
- doble reserva simultánea → una falla;
- assessment caducado no satisface;
- Zero Session rechazada no autoriza;
- VET block impide nueva sesión;
- supervisión requerida + uso autónomo incompatible;
- owner también rider funciona;
- cambio de hípica conserva histórico;
- policy pendiente bloquea acción sensible.

## 30. Fuera de MVP0

No implementar todavía:
- Stripe/pagos/payouts/fianzas
- fiscalidad/DAC7 automática
- equivalencias internacionales automáticas
- motor veterinario avanzado
- IA/recomendaciones
- microservicios/event sourcing
- RBAC genérico avanzado
- SaaS completo de hípica

## 31. Regla de cambio de arquitectura

Una decisión frozen sólo cambia por:
1. contradicción funcional real;
2. requisito legal obligatorio;
3. limitación técnica demostrada;
4. evidencia de piloto que invalide una hipótesis.

Si Cursor detecta conflicto debe reportarlo, no modificar silenciosamente la arquitectura.

## 32. Cadena de confianza

```text
IDENTIDAD
+ POLÍTICAS ACEPTADAS
+ CUALIFICACIONES
+ EVALUACIÓN HÍPICA
+ REGLAS EQUINO
+ ZERO SESSION CUANDO PROCEDA
+ AUTORIZACIÓN
+ TUTOR/CONSENTIMIENTO CUANDO PROCEDA
+ DISPONIBILIDAD
+ CALENDARIO
→ ELIGIBILIDAD
→ RESERVA CONFIRMADA
→ SESIÓN VERIFICABLE
→ ACTIVIDAD
→ HISTORIAL
→ REPUTACIÓN
```

**Estado final:** FROZEN MVP0. Fuente de verdad arquitectónica para Cursor.
