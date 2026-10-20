# Handoff de revisión — MVP vertical

**Fecha:** 2026-10-20
**Para:** revisión humana, y después ChatGPT o Codex si hace falta una segunda lectura.
**Este documento no autoriza** pagos, KYC, publicación abierta, un despliegue remoto ni cerrar un `DECISION_REQUIRED`.

## Qué es el MVP que queda cerrado

El MVP implementable con la arquitectura congelada es el recorrido vertical ya descrito en `docs/VERTICAL_MVP_SMOKE.md`, más la identidad, los tutores, el pasaporte, los equinos privados y la verificación manual que ya tenían RPC de llamador.

Cadena que el código cubre:

```text
cuenta autenticada
→ persona con nombre, apellidos, fecha de nacimiento y mercado
→ equino privado declarado y foto privada
→ reclamación de identidad, propiedad o gestión (no verifica por sí sola)
→ franja derivada de un piloto administrado OPEN
→ solicitud de reserva (no confirmada por el cliente)
→ confirmación por quien tiene MANAGE_BOOKINGS
→ inicio y fin de sesión
→ historial personal
```

Inicio muestra la próxima reserva y el número de solicitudes abiertas leyendo `list_my_activity()`. No inventa nombres de equino ni de centro: esa RPC no los devuelve. El detalle con nombres sigue en Actividad → Puedes confirmar y en Explorar.

## Pantallas que ya existen

| Área | Pantalla | Escritura |
| --- | --- | --- |
| Acceso | Auth, olvidar contraseña, nueva contraseña | Supabase Auth |
| Identidad | Onboarding, error, editar identidad | `ensure_my_identity`, `complete_my_identity` |
| Inicio | Home | solo lectura de `list_my_activity` |
| Explorar | lista y detalle de franja | `request_bookable_slot`, `get_my_booking_request` |
| Actividad | próximas, confirmar, solicitudes, agenda, cerradas, historial | `confirm_booking`, `start_session`, `end_session` |
| Pasaporte | perfil de jinete | `upsert_my_rider_profile` |
| Perfil | centros, equinos, alta, detalle, fotos, tutores, verificación, revisión piloto | RPC de llamador ya existentes |

Capas: pantalla → hook → servicio → RPC. El cliente no fuerza `CONFIRMED`, `ACTIVE` ni `COMPLETED`.

## Reglas que siguen en el servidor

Quedan en PostgreSQL, con tests SQL en `supabase/tests/` y scripts `npm run test:*`:

- persona distinta de cuenta; participante distinto de quien reserva;
- propiedad distinta de gestión y de asignación a centro;
- evaluación distinta de Sesión Cero; aceptación de política distinta de consentimiento de tutor;
- menor sin atajo de consentimiento;
- RLS deny-by-default;
- doble reserva por restricción y bloqueo, no por un SELECT seguido de INSERT;
- evidencia de sesión, cualificación y evaluación en buckets privados;
- marketplace cerrado fuera de un sujeto ACTIVE de un piloto OPEN.

Migraciones en el repositorio: `001`–`032` y `035`–`043`. No hay `033` ni `034`.

## Cambio de este cierre

- `src/screens/HomeScreen.tsx` deja de pintar vacíos fijos cuando ya hay actividad del llamador.
- `summarizeHomeActivity` elige la próxima reserva por `startsAt` y cuenta solicitudes abiertas. Tiene test en `src/features/activity/activityBuckets.test.ts`.
- Avisos sigue vacío a propósito: no hay RPC de avisos.
- «Cerca de ti» no recomienda centros. Las recomendaciones de IA están fuera de MVP0.

## Qué no se ha programado, y por qué hay que parar

No es código pendiente. Son decisiones abiertas en `docs/PRODUCT_DECISION_LOG.md` y `docs/MANUAL_VERIFICATION_MVP0_DESIGN.md`:

- proveedor KYC, base legal, DPIA y retención;
- catálogo legal de evidencias y caducidad;
- seguro y reservas de pago reales (`LEGAL_AND_INSURANCE_REVIEW_REQUIRED`);
- máximo de bienestar, horarios y cesión interna del calendario;
- publicación, alta de servicios y marketplace fuera del piloto;
- Stripe, DAC7, equivalencias internacionales, motor veterinario, RBAC genérico y SaaS de hípica.

Tampoco hay RPC de llamador para aceptar una política, crear una cualificación verificada, evaluar a un jinete, aprobar una Sesión Cero ni subir la foto de inicio o fin de sesión. Esas acciones siguen siendo de servidor o de un tren posterior. No se añade un CRUD de cliente para saltarlas.

`submit_review` y `report_incident` existen, pero `list_my_activity` no devuelve el equino ni el centro a propósito. Una pantalla de reseña necesitaría una lectura nueva y un tren propio. No forma parte de este cierre.

## Cómo revisar

1. Tests de cliente, sin base de datos: `npm run test:auth`.
2. Tipo: `npm run typecheck`.
3. Tests SQL: `npm run test:sql` contra una base local con las migraciones `001`–`043`. No ejecutarlos en el proyecto alojado desde este handoff.
4. Recorrido manual, solo en local y con el fixture de `docs/VERTICAL_MVP_SMOKE.md`: Explorar → solicitar → confirmar → iniciar → finalizar → ver la próxima fila en Inicio.
5. El proyecto alojado `efkauegdlmfkonzwyyiv` no recibe este cambio de esquema. Expo contra ese proyecto no llama a `list_bookable_offers` hasta un despliegue autorizado de `042`.

## Para ChatGPT o Codex

Leer antes de proponer código: `AI_INSTRUCTIONS.md`, `docs/DATA_ARCHITECTURE.md`, `docs/MIGRATION_STATUS.md`, `docs/PRODUCT_DECISION_LOG.md` y este archivo.

No reabrir el modelo legacy `users` / `horses` / `bookings`. No desactivar RLS. No poner `service_role` en Expo. No tratar un `DECISION_REQUIRED` como implementado porque el esquema ya tenga una tabla. Si una regla congelada no se puede cumplir, parar con `ARCHITECTURE_CONFLICT`.
