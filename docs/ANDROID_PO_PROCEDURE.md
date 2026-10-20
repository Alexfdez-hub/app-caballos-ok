# Procedimiento Android para el Product Owner

**Fecha:** 2026-10-20
**PR:** #72
**Este archivo no ejecuta el recorrido, no abre un túnel y no declara el MVP validado.**

## Qué está listo en la app

Con una sesión ya abierta, el recorrido de producto es:

Acceso → identidad → equino privado y foto → Explorar → solicitar una franja, sin pago → confirmar con la cuenta responsable → iniciar → finalizar → Actividad → Historial.

Inicio lee `list_my_activity()`. Muestra la próxima reserva y el número de solicitudes abiertas. Una reserva completada no vuelve a Inicio: queda en Historial. Si la lectura falla, Inicio no presenta esa ausencia como una lista vacía.

No hay cámara, foto de sesión, cronómetro oficial, avisos, pagos, KYC ni reseñas.

## Qué se puede probar sin piloto

Sin un piloto `OPEN`, estas pantallas siguen siendo reales:

- cuenta, identidad y pasaporte;
- alta de equino privado y su foto privada;
- tutores, centros y verificación en «Solicitud pendiente»;
- Actividad de las reservas de esa cuenta;
- Inicio, con la próxima reserva de esa cuenta o el vacío correspondiente.

Una lista vacía es el resultado correcto en estos casos:

- Explorar, si no hay un sujeto ACTIVE de un piloto OPEN dentro de la ventana de siete días;
- Actividad → Puedes confirmar, si la cuenta no tiene `MANAGE_BOOKINGS`;
- Inicio → Próxima actividad, si no hay una reserva confirmada o en curso todavía dentro de su ventana;
- Inicio → Pendientes, si no hay solicitudes abiertas;
- el caballo `TEST_ONLY Private Equine`, que no debe aparecer en Explorar.

## Bloqueo de este entorno

Inspección de la máquina de este trabajo:

- no hay Docker;
- no hay Supabase local ni `supabase` en el PATH;
- no hay `.env.supabase.local` ni `.env.supabase.remote`;
- no hay `cloudflared`;
- Expo está en `node_modules`, pero no hay un Metro en marcha.

Sin Docker y sin el archivo de entorno local, el smoke `TEST_ONLY` no puede ejecutarse aquí. No se sustituye por el proyecto alojado.

La solución mínima, en el ordenador donde se vaya a probar:

1. Instalar Docker y la CLI de Supabase.
2. `supabase start` en este repositorio y aplicar las migraciones hasta `043`.
3. Copiar `.env.supabase.local.example` a `.env.supabase.local` y poner la URL local y la clave anónima local. No usar `service_role`.
4. Si el teléfono no es el mismo ordenador, cambiar la URL a una dirección que el teléfono alcance. `127.0.0.1` no le sirve.

Eso prepara el entorno. No crea la hípica ni abre el túnel.

## Comandos reproducibles

No contienen secretos. No se han ejecutado en este trabajo.

```bash
cp .env.supabase.local.example .env.supabase.local
npm run start:local -- --tunnel
```

`npm run start:local` copia `.env.supabase.local` a `.env.local` y arranca Expo. El túnel de Expo publica el paquete de JavaScript. No publica Supabase. Hace falta otra autorización para abrirlo.

## Recorrido, solo después de un COMMIT local

Los tres pasos siguen separados. Este documento no los lanza.

1. Transacción local: `BEGIN`, `app.vertical_fixture_local=1`, `vertical_fixture_install` con dos usuarios de Auth ya existentes, `COMMIT`.
2. Expo, solo después de ese `COMMIT`. Entrar con el jinete. En Explorar, avanzar de siete en siete días hasta la ventana que incluye el 2-dic-2026. Solicitar una franja. Entrar con el propietario responsable y confirmar. Volver al jinete, iniciar y finalizar. La sesión queda en Historial. Inicio muestra otra próxima reserva, o vacío si no queda ninguna.
3. Transacción local nueva: `BEGIN`, la misma configuración, `vertical_fixture_retire()`, `COMMIT`.

`ROLLBACK` en el paso 1 descarta la instalación. No se continúa el smoke sobre esas filas.

## Dependencia que no se fusiona

El PR #62 sigue en borrador y no está contenido en esta rama. Conserva el arreglo de envíos duplicados y de enlaces de Auth en Expo Go. Hace falta para crear o recuperar una cuenta abriendo el correo en el mismo teléfono. No hace falta para continuar un recorrido con dos cuentas que ya tienen sesión. No se fusiona ni se cierra desde aquí.

## Operaciones que necesitan autorización

| Operación | Entorno | Efecto | Retirada |
| --- | --- | --- | --- |
| `supabase start` y migraciones locales hasta `043` | Postgres local | Crea la base local | Parar Supabase local y borrar ese volumen |
| Crear dos cuentas desde la app | Auth local | Dos usuarios reales en esa base | No las borra el fixture |
| Instalar el fixture | Postgres local, tras `COMMIT` | Centro, propietario, caballo y jinete `TEST_ONLY` | `vertical_fixture_retire()` y `COMMIT` en otra transacción |
| `npm run start:local -- --tunnel` | Ordenador y Expo Go | Publica el paquete JS | Cerrar el proceso |
| Túnel o URL alcanzable para el puerto `54321` | Red del teléfono | El teléfono llama a Supabase | Cerrar ese túnel |
| SQL, piloto o fixture en el proyecto alojado | Remoto | No autorizado por este procedimiento | No aplica |
