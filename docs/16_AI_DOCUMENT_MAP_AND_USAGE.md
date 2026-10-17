# APP CABALLOS --- MAPA DOCUMENTAL Y GUÍA DE USO PARA AGENTES IA

**Fecha:** 2026-09-01\
**Propósito:** documento resumen para que cualquier agente IA entienda
qué archivos existen, para qué se utilizan, qué autoridad tiene cada uno
y en qué orden deben consultarse.

------------------------------------------------------------------------

## 1. Árbol documental

``` text
App Caballos - AI Handoff/
│
├── START_HERE_FOR_AI.md
│   └─ Puerta de entrada.
│      Indica el orden inicial de lectura y las reglas de relevo.
│
├── 00_PROJECT_HANDOFF.md
│   └─ Resumen ejecutivo.
│      Producto, stack, estado, Git, Supabase y punto actual del proyecto.
│
├── 01_PRODUCT_VISION_AND_PRD.md
│   └─ QUÉ estamos construyendo.
│      Visión del ecosistema, actores, propuesta de valor y MVP0/MVP1/MVP2.
│
├── 02_ARCHITECTURE_2_1.md
│   └─ Resumen rápido de la arquitectura congelada.
│      Invariantes principales y modelo conceptual.
│
├── 03_SECURITY_AND_BUSINESS_RULES.md
│   └─ REGLAS QUE NO SE PUEDEN SALTAR.
│      Menores, consentimiento, validación, permisos, RLS, Session Zero y tests P0.
│
├── 04_IMPLEMENTATION_STATUS.md
│   └─ QUÉ ESTÁ HECHO AHORA.
│      Fases completadas, migrations, branch/commit y pendientes reales.
│
├── 05_AI_AGENT_INSTRUCTIONS.md
│   └─ Guía resumida de CÓMO debe trabajar el agente.
│
├── 06_NEXT_PHASES.md
│   └─ QUÉ HACER DESPUÉS.
│      Roadmap técnico por dependencias.
│
├── 07_DECISION_LOG.md
│   └─ POR QUÉ se tomaron decisiones importantes.
│      Evita reabrir o deshacer decisiones ya cerradas.
│
├── 08_DATA_ARCHITECTURE_2_1_FULL.md
│   └─ FUENTE DE VERDAD ARQUITECTÓNICA PRINCIPAL.
│      Tablas, relaciones, estados, constraints, RLS, RPC,
│      policies, consentimientos, bookings, calendario,
│      sesiones, storage y tests.
│
├── 09_ARCHITECTURE_VALIDATION_2_0_FULL.md
│   └─ TRAZABILIDAD DE LA ARQUITECTURA.
│      Casos reales que explican por qué Architecture 2.1 quedó como quedó.
│
├── 10_AI_INSTRUCTIONS_FULL.md
│   └─ Reglas completas y permanentes para agentes de implementación.
│
├── 11_MIGRATION_PLAN_SUMMARY_HISTORICAL.md
│   └─ Resumen histórico del antiguo plan de migración.
│      Contexto; no prevalece sobre el estado actual.
│
├── 12_PRD_v1_1_HISTORICAL.pdf
│   └─ PRD histórico.
│      Recuperación de ideas/requisitos antiguos; no autoridad actual.
│
├── 13_POLICY_AND_CONSENT_MODEL_RECONSTRUCTED.md
│   └─ MODELO FUNCIONAL ACTUAL DE POLÍTICAS Y CONSENTIMIENTOS.
│      Reconstruido desde fuentes vigentes; no es copia del original perdido.
│
├── 14_SOURCE_RECOVERY_STATUS.md
│   └─ INVENTARIO Y PROVENIENCIA.
│      Distingue originales, reconstruidos, históricos y documentos no localizados.
│
├── 15_MIGRATION_REFACTOR_PLAN_v1_0_FULL_ORIGINAL_91_POINTS.md
│   └─ PLAN ORIGINAL COMPLETO DE 91 PUNTOS.
│      Trazabilidad histórica y checklist de intención original.
│
├── App_Caballos_Checklist_Cumplimiento_2026-09-01.xlsx
│   └─ CONTROL DE CALIDAD / ACCEPTANCE.
│      Checklist vivo de cumplimiento de arquitectura, funciones,
│      roles, policies, consentimientos, seguridad y reglas de negocio.
│
└── App_Caballos_AI_Handoff_2026-09-01.zip
    └─ Copia portátil del handoff para migración/recovery.
```

------------------------------------------------------------------------

## 2. Jerarquía de autoridad

No todos los documentos tienen la misma autoridad. Un agente IA debe
resolver contradicciones siguiendo este orden:

### NIVEL 1 --- FUENTE DE VERDAD

1.  `08_DATA_ARCHITECTURE_2_1_FULL.md`
2.  Decisiones explícitas posteriores registradas en
    `07_DECISION_LOG.md`

Architecture 2.1 Frozen prevalece sobre documentos históricos salvo
decisión arquitectónica posterior explícita.

### NIVEL 2 --- REGLAS DE IMPLEMENTACIÓN Y NEGOCIO

-   `03_SECURITY_AND_BUSINESS_RULES.md`
-   `10_AI_INSTRUCTIONS_FULL.md`
-   `13_POLICY_AND_CONSENT_MODEL_RECONSTRUCTED.md`

Definen cómo aplicar la arquitectura: seguridad, menores, políticas,
consentimiento, autoridad del servidor, RLS y disciplina de
implementación.

### NIVEL 3 --- ESTADO Y EJECUCIÓN

-   `04_IMPLEMENTATION_STATUS.md`
-   `06_NEXT_PHASES.md`
-   `App_Caballos_Checklist_Cumplimiento_2026-09-01.xlsx`

Indican qué existe realmente, qué falta y cómo demostrar que una
funcionalidad cumple.

### NIVEL 4 --- EXPLICACIÓN Y TRAZABILIDAD

-   `09_ARCHITECTURE_VALIDATION_2_0_FULL.md`

Se utiliza cuando hay dudas sobre la intención de una regla o sobre los
casos reales que provocaron una decisión arquitectónica.

### NIVEL 5 --- DOCUMENTOS HISTÓRICOS

-   `11_MIGRATION_PLAN_SUMMARY_HISTORICAL.md`
-   `12_PRD_v1_1_HISTORICAL.pdf`
-   `15_MIGRATION_REFACTOR_PLAN_v1_0_FULL_ORIGINAL_91_POINTS.md`

Sirven para entender de dónde viene el proyecto y recuperar requisitos.
No deben revertir decisiones posteriores.

------------------------------------------------------------------------

## 3. Flujo obligatorio de lectura para un agente que va a programar

``` text
START_HERE_FOR_AI
        ↓
00_PROJECT_HANDOFF
        ↓
01_PRODUCT_VISION_AND_PRD
        ↓
08_DATA_ARCHITECTURE_2_1_FULL
        ↓
03_SECURITY_AND_BUSINESS_RULES
        +
13_POLICY_AND_CONSENT_MODEL_RECONSTRUCTED
        ↓
10_AI_INSTRUCTIONS_FULL
        ↓
04_IMPLEMENTATION_STATUS
        ↓
06_NEXT_PHASES
        ↓
IMPLEMENTAR
        ↓
TESTEAR
        ↓
App_Caballos_Checklist_Cumplimiento
        ↓
ACTUALIZAR
04_IMPLEMENTATION_STATUS + 07_DECISION_LOG
```

`09_ARCHITECTURE_VALIDATION_2_0_FULL.md` debe consultarse cuando una
regla de Architecture 2.1 necesite contexto o aparezca una duda de
interpretación.

Los documentos históricos sólo deben consultarse para trazabilidad o
recuperación de requisitos.

------------------------------------------------------------------------

## 4. Reglas frozen que el agente debe recordar

-   PERSON != ACCOUNT.
-   Los roles/capacidades son relaciones de dominio, no un único
    `users.role`.
-   Una persona puede ser simultáneamente rider, owner, guardian y/o
    miembro de un centro.
-   OWNERSHIP != MANAGEMENT AUTHORITY.
-   PARTICIPANT != BOOKER.
-   ASSESSMENT != ZERO SESSION.
-   POLICY ACCEPTANCE != GUARDIAN CONSENT.
-   Un menor puede existir como PERSON sin cuenta.
-   Edad = DOB + fecha de actividad + reglas del mercado.
-   Ningún consentimiento obligatorio de menor puede quedar sólo en
    frontend.
-   Validación del centro no concede acceso universal a todos los
    equinos.
-   Availability rules != calendar occupancy.
-   La protección contra doble reserva debe ser
    transaccional/server-side.
-   El cliente solicita; el servidor decide operaciones críticas.
-   RLS deny-by-default.
-   `service_role`/Secret key nunca en Expo.
-   Evidencia sensible debe ser privada.
-   Las policies son versionadas y las aceptaciones históricas son
    auditables.
-   Una reserva confirmada conserva snapshot de requisitos/policies
    aplicados.
-   Cambios ordinarios posteriores no reescriben silenciosamente el
    pasado.

------------------------------------------------------------------------

## 5. Uso específico del modelo Policy & Consent

`13_POLICY_AND_CONSENT_MODEL_RECONSTRUCTED.md` debe consultarse antes de
implementar: - guardian relationships; - guardian consents; - activación
de capacidades Rider/Owner/Center/Assessor/Guardian; - acciones que
requieran policy acceptance; - booking requirements; - booking policy
snapshots; - reaceptación de nuevas versiones; - reglas de
consentimiento de menores; - UI que explique políticas o consentimientos
pendientes.

Es un documento reconstruido desde Architecture 2.1 y fuentes
posteriores. Si contradice Architecture 2.1 Frozen, prevalece
Architecture 2.1.

------------------------------------------------------------------------

## 6. Uso del checklist de cumplimiento

`App_Caballos_Checklist_Cumplimiento_2026-09-01.xlsx` es la lista de
aceptación del producto.

Un punto no debe marcarse `VERIFICADO` porque exista código. Debe
existir evidencia concreta, por ejemplo: - test SQL/RLS; - test
automático; - prueba E2E; - inspección de DB; - inspección UI; -
revisión arquitectónica; - revisión legal; - PR/commit verificable.

Flujo de estado:

`NO INICIADO → EN DESARROLLO → IMPLEMENTADO → VERIFICADO`

Los puntos P0 aplicables deben estar verificados antes de considerar
MVP0 listo.

------------------------------------------------------------------------

## 7. Uso de los documentos históricos

Regla fundamental:

> Los documentos históricos sirven para entender de dónde venimos; nunca
> deben hacer que un agente revierta una decisión posterior ya
> congelada.

Ejemplo: el Migration & Refactor Plan original contemplaba una
convivencia/migración progresiva con legacy. Posteriormente el proyecto
adoptó un clean break controlado y retiró el prototipo legacy. Un agente
no debe reconstruir tablas o flujos antiguos sólo porque aparezcan en el
plan histórico.

------------------------------------------------------------------------

## 8. Protocolo ante contradicción

Si un agente detecta una incompatibilidad real entre una tarea y
Architecture 2.1, no debe improvisar.

Debe detenerse y reportar:

``` text
ARCHITECTURE_CONFLICT

Current frozen rule:
Implementation problem:
Why cannot implement:
Options:
Recommended option:
```

No modificar la arquitectura frozen hasta recibir una decisión
explícita.

------------------------------------------------------------------------

## 9. Regla de actualización documental

Después de cada hito importante: 1. actualizar
`04_IMPLEMENTATION_STATUS.md`; 2. actualizar `07_DECISION_LOG.md` si
hubo una decisión nueva; 3. actualizar `06_NEXT_PHASES.md` si cambia el
orden de trabajo; 4. actualizar el checklist con evidencia real; 5.
actualizar `14_SOURCE_RECOVERY_STATUS.md` si se recupera documentación;
6. mantener este mapa documental si se añaden, renombran o retiran
archivos.

------------------------------------------------------------------------

## 10. Estado de uso recomendado para el próximo agente

Antes de continuar código, el agente debe leer este mapa y las fuentes
de Nivel 1--3 correspondientes a la fase que vaya a implementar.

Para backend, seguridad, RLS, migrations, policies o menores, la lectura
de `08_DATA_ARCHITECTURE_2_1_FULL.md`,
`03_SECURITY_AND_BUSINESS_RULES.md`, `10_AI_INSTRUCTIONS_FULL.md` y
`13_POLICY_AND_CONSENT_MODEL_RECONSTRUCTED.md` es obligatoria.

Para frontend/UI sobre una arquitectura ya definida, debe respetar las
mismas invariantes y consultar `04_IMPLEMENTATION_STATUS.md` para no
inventar backend ni datos que todavía no existen.

Live repository phase reports that implement Architecture 2.1 live under
`docs/` (`PHASE_13B_AUDIT_REPORT.md`, `PHASE_13C_CRITICAL_AUDIT_REPORT.md`,
`PHASE_14A_STORAGE_SECURITY_REPORT.md`,
`PHASE_14B_SECURITY_GATE_REPORT.md`, `MIGRATION_STATUS.md`,
`REMOTE_DEPLOYMENT_027_029.md`). GitHub live state wins over stale
planning documents.

**Live status (recorded 2026-10-15, Stage 0.1):** the procedure base is
`origin/main` `5ed38a93f712069e8be45bd8573d6a5762b57b6a`. Migrations
`036` through `041` are on that `main`. The last authorized remote
record, in `docs/VERIFICATION_NEXT_TRAIN_STAGE0.md` and not re-queried
here, is project `efkauegdlmfkonzwyyiv` with migration `041` deployed.
This stage does not re-count grants, cohort rows, or audit rows, and it
does not execute the pilot. The live read-only procedure is
`docs/VERIFICATION_READONLY_PILOT_RUNBOOK_041.md`. The Stage 4B.4 smoke
runbook is a historical handoff and is not the procedure. Identity
completion still requires an explicit selectable country. Migration
`042` adds a local derived-slot read and booking request limited to an
OPEN administered pilot. After that pilot closes, only the caller's own
request key remains readable, and that read does not write. It does not
open the marketplace and it is not a remote deploy. Payments, KYC, and
insurance review stay closed.

The Level 1–3 handoff documents named above are maintained outside this
repository. GitHub agents must also read `docs/DATA_ARCHITECTURE.md`,
`docs/MIGRATION_STATUS.md`, the phase reports,
`docs/EQUINE_CREATE_AND_MEDIA_PROPOSAL.md`,
`docs/IDENTITY_AND_EQUINE_VERIFICATION_PLAN.md`,
`docs/PHASE_IDENTITY_MARKET_CAPTURE_REPORT.md`,
`docs/MANUAL_VERIFICATION_MVP0_DESIGN.md`,
`docs/PRODUCT_DECISION_LOG.md`,
`docs/VERIFICATION_FOUNDATION_STAGE0.md`,
`docs/VERIFICATION_PREDICATES_STAGE3.md`,
`docs/VERIFICATION_STATUS_UI_STAGE4A.md`,
`docs/VERIFICATION_REVIEWER_UI_STAGE4B.md`,
`docs/VERIFICATION_REVIEWER_BOOTSTRAP_STAGE4B1.md`,
`docs/VERIFICATION_GRANT_LIFECYCLE_STAGE4B2.md`,
`docs/VERIFICATION_REVIEWER_READ_UI_STAGE4B3.md`,
`docs/VERIFICATION_REVIEWER_PILOT_SMOKE_STAGE4B4.md`,
`docs/VERIFICATION_COHORT_MIGRATION_041.md`,
`docs/VERIFICATION_PILOT_SUBMIT_STAGE0.md`,
`docs/VERIFICATION_RELATION_CLAIMS.md`,
`docs/VERIFICATION_NEXT_TRAIN_STAGE0.md`,
`docs/VERIFICATION_READONLY_PILOT_RUNBOOK_041.md`,
`docs/VERIFICATION_READONLY_PREFLIGHT_041.md`, and
`docs/VERTICAL_MVP_SMOKE.md`.

The consolidated read-only preflight script is
`docs/VERIFICATION_READONLY_PREFLIGHT_041.sql`. It is not authorized to
run on the remote project, and it does not authorize section B of the
runbook.

For the Spain review pilot, signatures and permissions come from
migrations `036`–`041`. The live procedure is the `041` runbook above.
`docs/PILOT_RUNBOOK.md` is the local fictitious-market journey, not that
pilot. These stage handoffs keep their original text and carry a
supersession warning: `docs/VERIFICATION_REVIEWER_UI_STAGE4B.md`,
`docs/VERIFICATION_REVIEWER_BOOTSTRAP_STAGE4B1.md`,
`docs/VERIFICATION_GRANT_LIFECYCLE_STAGE4B2.md`,
`docs/VERIFICATION_REVIEWER_READ_UI_STAGE4B3.md`,
`docs/VERIFICATION_REVIEWER_PILOT_SMOKE_STAGE4B4.md`,
`docs/VERIFICATION_PILOT_SUBMIT_STAGE0.md`,
`docs/VERIFICATION_COHORT_MIGRATION_041.md`, and
`docs/VERIFICATION_NEXT_TRAIN_STAGE0.md`. Do not execute a bootstrap,
a cohort, a grant, or a smoke from those files. The decision log is append-only. It records
closed product direction separately from open legal, privacy and insurance
reviews, from `DECISION_REQUIRED`, from `ARCHITECTURE_CONFLICT`, and from
`LEGAL_AND_INSURANCE_REVIEW_REQUIRED`. A later entry can authorize one named slice. It does not authorize
work beyond that slice. An entry that records existing behavior does not
authorize an operation that has not been executed. Authentication,
civil-identity verification, declared ownership, verified ownership and
verified management authority are distinct. A privately declared equine
may be completed and photographed, but publication, service enablement,
real booking and payment require backend-enforced verification gates.
The manual verification design is a proposal with open
`DECISION_REQUIRED` items. It does not authorize implementation.

------------------------------------------------------------------------

**Finalidad de este documento:** permitir que Cursor, Grok, GPT u otro
agente pueda incorporarse al proyecto sin depender de la memoria de una
conversación y sin confundir fuentes vigentes con documentos históricos.
