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

Hay tres estados distintos. No se mezclan:

- Repositorio: archivos de migración `001`–`032` y `035`–`043`. No hay `033` ni `034`.
- Remoto comunicado por el Product Owner el 18-oct-2026, en la nota de `docs/MIGRATION_STATUS.md`: el proyecto `efkauegdlmfkonzwyyiv` está normalizado en las versiones exactas `042` y `043`. Este trabajo no ha vuelto a consultar ese proyecto y no convierte ese aviso en una verificación nueva.
- Este cierre no despliega esquema. La frase de que `042` sigue sin desplegar no está vigente. La advertencia equivalente de `docs/VERTICAL_MVP_SMOKE.md` queda marcada como histórica.

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

## Comprobaciones

Tres grupos distintos. Este archivo no ejecuta ninguno de los pasos del recorrido.

### Declaradas en local

Sobre el código de Inicio, en el commit que lo introdujo y de nuevo en esta corrección documental:

- `npm run typecheck`
- `npm run test:auth`

Esas órdenes no abren una base de datos. El resultado ejecutado en esta corrección se anota en el pull request, no aquí como si fuera un smoke.

### SQL en CI

Este handoff no ejecuta `npm run test:sql` ni otro SQL. La evidencia SQL, si existe, es el job de CI del pull request. Este documento no copia ese resultado y no afirma que haya pasado.

### No ejecutadas

Smoke de Android, smoke remoto de `docs/VERTICAL_REMOTE_SMOKE.md`, fixture, piloto, túnel, Bugbot, Autofix, fusión y despliegue. No se han hecho en este trabajo.

## Recorrido local, sin ejecutarlo

Solo en una base local que ya tenga las migraciones del repositorio hasta `043`. El fixture es local: hace falta `app.vertical_fixture_local=1` y el rol `postgres`. No se instala en el proyecto alojado. Este párrafo no autoriza a lanzar esos comandos desde aquí.

Son tres pasos separados. Expo no entra en la transacción de instalación.

1. En la base local: `BEGIN`, la configuración local, `vertical_fixture_install`, y `COMMIT`. Ese `COMMIT` tiene que estar hecho antes de que Expo, también desde otra conexión, vea el fixture. `127.0.0.1` no le sirve al teléfono. `ROLLBACK` en lugar de `COMMIT` descarta la instalación. Después de ese `ROLLBACK` no se continúa el smoke sobre esas filas: no han quedado.
2. Recorrido de Expo, solo después de ese `COMMIT`.
3. Retirada posterior, en una transacción local nueva: `BEGIN`, la misma configuración local, `vertical_fixture_retire()`, y `COMMIT`.

Explorar abre una ventana de siete días: desde las 00:00 UTC del día actual hasta las 00:00 UTC siete días después. Cada control de siete días desplaza el inicio y el fin otros siete días. El servidor incluye una franja cuando su inicio es mayor o igual que el inicio de la ventana y su fin es menor o igual que el fin de la ventana.

Partiendo del 20-oct-2026 UTC, la ventana inicial es `2026-10-20T00:00:00Z`–`2026-10-27T00:00:00Z`. Seis avances dejan `2026-12-01T00:00:00Z`–`2026-12-08T00:00:00Z`. Esa ventana incluye el 2-dic-2026. La franja guardada sigue siendo `2026-12-02 09:00:00+00`–`12:00:00+00`. No se cambian esa fecha ni las migraciones.

El recorrido, cuando alguien lo ejecute fuera de este documento: Explorar → solicitar → confirmar → iniciar → finalizar. La sesión terminada queda en Actividad → Historial. Inicio muestra otra próxima reserva, o el vacío si no queda ninguna. No muestra la reserva que acaba de completarse.

## Para ChatGPT o Codex

Leer antes de proponer código: `AI_INSTRUCTIONS.md`, `docs/DATA_ARCHITECTURE.md`, `docs/MIGRATION_STATUS.md`, `docs/PRODUCT_DECISION_LOG.md` y este archivo.

No reabrir el modelo legacy `users` / `horses` / `bookings`. No desactivar RLS. No poner `service_role` en Expo. No tratar un `DECISION_REQUIRED` como implementado porque el esquema ya tenga una tabla. Si una regla congelada no se puede cumplir, parar con `ARCHITECTURE_CONFLICT`.

El procedimiento de prueba en Android, y lo que este entorno no tiene instalado, está en `docs/ANDROID_PO_PROCEDURE.md`. Ese archivo no ejecuta el smoke ni declara el MVP validado.
