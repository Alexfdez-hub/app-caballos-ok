# Operación de prueba en Android

Este recorrido prepara centros, equinos, permisos y un piloto `TEST_ONLY` desde la app. No aplica nada al proyecto alojado. No crea usuarios remotos. No verifica identidad, no cobra y no inventa un máximo de bienestar.

La compuerta es la fila `test_operator_gate`, que la migración deja apagada. `supabase/seed.sql` la enciende solo en un reset local. En el proyecto alojado permanece apagada y Perfil no muestra la pantalla.

## Preparar la base local

1. Instalar la CLI de Supabase. Docker ya puede estar presente.
2. En este repositorio: `npx supabase start`. La base local de esta copia ya está en la migración 044 y la compuerta está encendida. No hagas otro `db reset`: borra la base local.
3. `.env.supabase.local` debe llevar la URL que el teléfono puede alcanzar y la clave anónima. No usar `service_role`. En esta copia la URL de Wi-Fi es `http://192.168.1.35:54321`.
4. `127.0.0.1` solo vale en el propio ordenador. El túnel de Expo publica el paquete de la app, no el puerto 54321. El teléfono tiene que estar en la misma red que `192.168.1.35`. Si está en la red del cable, cambia el host a `10.30.55.246` y conserva la clave.
5. Cuando quieras dejar el proyecto alojado: `npm run start:local -- --tunnel`.

Eso sustituye el paquete que ahora apunta al proyecto alojado. La sesión del proyecto alojado no vale en la base local.

## Cuentas

Hacen falta dos cuentas locales, cada una con identidad de adulto: nombre, apellidos, fecha de nacimiento y mercado. Crearlas o recuperarlas en el teléfono depende del PR #62, que no está en esta rama. Entrar con correo y contraseña de una cuenta local que ya existe no depende de #62.

No hay contraseñas en este documento.

| Quién | Qué hace |
| --- | --- |
| Propietario | Perfil → Operación de prueba. Crea el centro, registra el equino, afilia, concede permisos, publica la ventana y abre el piloto. |
| Jinete | Explorar, solicitar, iniciar y finalizar. |
| Responsable | La cuenta con rol `ADMIN` o `MANAGER` y permiso `MANAGE_BOOKINGS`. Confirma en Actividad. |
| Lectura del resultado | El jinete ve su fila. El centro la ve solo si además tiene `VIEW_ACTIVITY`. |

## Orden en la pantalla

1. Crear un centro cuyo nombre empiece por `TEST_ONLY `.
2. En Mis equinos, crear un equino con el mismo prefijo. Volver y registrarlo.
3. Asignar a la otra cuenta un rol del centro. El correo es el de acceso.
4. Afiliar el equino al centro como `SCHOOL`. Eso no es propiedad ni permiso.
5. Conceder `MANAGE_AVAILABILITY`, `MANAGE_BOOKINGS`, `MANAGE_REQUIREMENTS` y `VIEW_ACTIVITY`.
6. Crear el servicio `TEST_ONLY` con una duración en minutos. Esa duración parte la ventana; no es un tope de bienestar.
7. Enlazar servicio y equino. No se añaden evaluación, Sesión Cero ni aprobación del propietario.
8. Guardar una ventana futura, por ejemplo `2026-12-02T09:00:00Z` a `2026-12-02T12:00:00Z`.
9. Marcar el equino visible dentro del piloto y abrir un código que empiece por `TEST_ONLY`.
10. Con el jinete, avanzar Explorar de siete en siete días hasta esa fecha. Solicitar una vez. Confirmar con la cuenta responsable. Iniciar y finalizar.
11. Actividad → Resultado autorizado muestra equino, centro, estado y sesión.

Un bloque `REST`, `VET`, `OWNER_USE` o `MANUAL_BLOCK` ocupa el equino en ese intervalo. No hay un descanso calculado.

La elegibilidad operable es la de un adulto con fecha de nacimiento, sin requisitos extra en el equino y con la ventana cubriendo la franja. Un menor sigue exigiendo consentimiento de tutor. Esta pantalla no lo sustituye.

## Retirada

En la misma pantalla, Retirar datos de prueba. Solo cierra lo que esa cuenta administra: sus centros `TEST_ONLY`, los equinos de los que es gestora principal y los pilotos que quedan sin sujetos activos. No toca el centro de otra cuenta. Conserva `audit_events`, el historial del piloto, las personas y las cuentas. No borra el bloque de ocupación de una reserva. Un bloqueo manual debe usar un intervalo distinto de la ventana de reserva.

## Qué no hace este tren

- No enciende la compuerta en el proyecto alojado.
- No fusiona #62 ni #72.
- No inventa máximo de bienestar, horario de apertura, entrega exterior, seguro ni KYC.
- No permite autoasignarse un centro o un equino ajeno.
- La foto de la sesión sigue sin acción.
