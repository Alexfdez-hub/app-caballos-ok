# Informe de arquitectura actual

**Proyecto:** app-caballos-ok  
**Tipo:** aplicación cliente Expo (React Native) para alquiler ecuestre  
**Idioma de interfaz:** español  
**Fecha de inspección:** 29 de agosto de 2026

Este documento describe únicamente lo que existe en el repositorio y lo que el cliente asume del backend.

---

## 1. Resumen

La app es un cliente móvil/web construido con Expo SDK 54 y React Native 0.81. No hay servidor propio, ni API intermedia, ni migraciones SQL en el repo. Toda persistencia y autenticación van a un proyecto Supabase (`efkauegdlmfkonzwyyiv`) mediante el cliente JavaScript y llamadas HTTP a Storage.

El dominio de producto en pantalla es: registro e inicio de sesión, catálogo de caballos ajenos, reserva por fecha/hora, listado de reservas del jinete, y gestión de caballos propios (alta, edición, baja, foto).

---

## 2. Stack y runtime

| Pieza | Versión / detalle |
| --- | --- |
| Entrada | `index.js` → `registerRootComponent(App)` |
| UI | React 19.1, React Native 0.81.5, `react-native-web` 0.21 |
| Framework | Expo `~54.0.0` |
| Navegación | React Navigation 7 (`native-stack` + `bottom-tabs`) |
| Backend BaaS | `@supabase/supabase-js` ^2.112 |
| Sesión local | `@react-native-async-storage/async-storage` |
| Fecha/hora | `@react-native-community/datetimepicker` (plugin en `app.json`) |
| Imágenes | `expo-image-picker` |
| Iconos | `@expo/vector-icons` (`Ionicons`) |

Scripts npm: `expo start`, `--android`, `--ios`, `--web`.

`package.json` conserva metadatos de plantilla (`expo-template-blank`, versión 57.0.11). `app.json` nombra la app `HelloWorld`, slug `expo-template-blank`, orientación portrait, tema claro.

No hay TypeScript, tests, CI, variables de entorno (`.env` está en `.gitignore` pero las credenciales viven en código), ni capa de estado global (Redux, Zustand, Context de auth, etc.).

---

## 3. Árbol de código

```
app-caballos-ok/
├── index.js                 # registro del root Expo
├── App.js                   # stack de navegación raíz
├── supabase.js              # cliente único de Supabase
├── app.json                 # config Expo
├── package.json
├── src/screens/             # todas las pantallas; no hay carpetas de componentes, hooks ni servicios
│   ├── LoginScreen.js
│   ├── HomeScreen.js        # tabs (no es un dashboard plano)
│   ├── SearchScreen.js
│   ├── HorseDetailScreen.js
│   ├── BookingsScreen.js
│   ├── ProfileScreen.js
│   ├── OwnerHorsesScreen.js
│   ├── OwnerRegisterHorseScreen.js
│   └── OwnerEditHorseScreen.js
└── assets/                  # iconos Expo
```

Patrón de código: pantallas monolíticas con `StyleSheet` inline, llamadas directas a `supabase` y `Alert` para errores. No hay módulos compartidos de UI, validación ni acceso a datos.

---

## 4. Navegación

### 4.1 Stack raíz (`App.js`)

Ruta inicial: `Login`. Cabeceras ocultas en `Login` y `Home`; el resto muestra título y «Volver».

| Ruta | Componente | Título de cabecera |
| --- | --- | --- |
| `Login` | `LoginScreen` | — |
| `Home` | `HomeScreen` | — (tabs con su propio header) |
| `HorseDetail` | `HorseDetailScreen` | Detalles del Caballo |
| `RegisterHorse` | `OwnerRegisterHorseScreen` | Nuevo Caballo |
| `OwnerHorses` | `OwnerHorsesScreen` | Mis Caballos Registrados |
| `OwnerEditHorse` | `OwnerEditHorseScreen` | Editar Caballo |

Las pantallas de propietario y detalle cuelgan del stack raíz, no de los tabs. Desde un tab, `navigation.navigate('HorseDetail' | 'RegisterHorse' | 'OwnerHorses')` resuelve en el stack padre.

No hay listener de sesión al arrancar: siempre se muestra `Login`, aunque AsyncStorage pueda tener un token persistido.

### 4.2 Tabs (`HomeScreen.js`)

Tres pestañas con iconos Ionicons (activo/inactivo) y tint `#111`:

| Tab | Componente |
| --- | --- |
| Buscar | `SearchScreen` |
| Reservas | `BookingsScreen` |
| Perfil | `ProfileScreen` |

En el mismo archivo queda definido `BookingsDummy` (texto «Tus reservas activas») y no se usa: el tab Reservas apunta a `BookingsScreen`.

### 4.3 Flujos

```
Login ──signIn──► Home (tabs)
  │                 ├─ Buscar ──tap──► HorseDetail ──insert booking──► atrás
  │                 ├─ Reservas (lista del rider)
  │                 └─ Perfil ──► RegisterHorse | OwnerHorses ──► OwnerEditHorse
  │                         └──signOut──► Login (replace)
  └──signUp──► permanece en Login (alerta de verificar correo)
```

---

## 5. Autenticación y sesión

Cliente en `supabase.js`:

- URL y **anon key** embebidas en el fuente.
- Auth: `storage: AsyncStorage`, `autoRefreshToken: true`, `persistSession: true`, `detectSessionInUrl: false` (adecuado a RN, no a OAuth vía URL).

`LoginScreen`:

- `signInWithPassword({ email, password })` → alerta de bienvenida y `navigation.replace('Home')`.
- `signUp({ email, password })` → alerta para revisar el correo; no navega.
- Sin recuperación de contraseña, OAuth, ni roles en UI.

`ProfileScreen`: `getUser()` para mostrar email; `signOut()` y `replace('Login')`.

Pantallas de datos vuelven a llamar `getUser()` en cada carga. No hay gate de autenticación en el navegador ni redirección si el token caduca a mitad de uso (salvo el fallo de la query).

---

## 6. Backend asumido (Supabase)

El repo no define el esquema. El cliente usa estas superficies:

### 6.1 Auth

Usuarios de Supabase Auth. El id de `user.id` se usa como `owner_id` y `rider_id`. No hay lectura de una tabla `users` / perfiles.

### 6.2 Tabla `horses`

Operaciones: `select *`, `insert`, `update` por `id`, `delete` por `id`, filtro `owner_id` y `neq('owner_id', user.id)` en búsqueda.

Campos leídos o escritos en UI:

| Campo | Uso |
| --- | --- |
| `id` | claves de lista, delete, update, reserva |
| `owner_id` | alta y filtro de catálogo / inventario |
| `name` | listados, detalle, reservas |
| `discipline` | formularios y cards (fallback «General») |
| `level_required` | alta/edición/detalle |
| `price_per_session` | alta/edición/detalle/reservas |
| `max_daily_sessions` | alta/edición; se muestra en inventario del dueño (no se aplica en reservas) |
| `facility_fee` | alta/edición; se muestra en detalle si `> 0` |
| `media_url` | URL pública de foto |

### 6.3 Tabla `bookings`

Insert desde detalle:

- `horse_id`, `rider_id`, `session_date` (ISO del `Date` del picker), `status: 'pendiente'`.

Select desde Reservas (jinete):

```
id, session_date, status, horses ( name, discipline, price_per_session )
```

filtro `.eq('rider_id', user.id)`. Join embebido de PostgREST hacia `horses`. `price_per_session` se pide pero no se pinta. No hay listado para el propietario, ni update/cancel de estado, ni cobro.

### 6.4 Storage

Bucket `horse-images`. Subida con `POST {supabaseUrl}/storage/v1/object/horse-images/{timestamp}.{ext}` y `Authorization: Bearer <access_token>`. Cuerpo: `FormData` con un campo de nombre vacío y `{ uri, name, type }`. URL pública vía `supabase.storage.from('horse-images').getPublicUrl(filePath)`.

Si la URI ya es `http`, en edición no se vuelve a subir.

---

## 7. Comportamiento por pantalla

### Login

Formulario email/contraseña, botones «Iniciar Sesión» y «Crear Cuenta», spinner mientras hay request. Estilo: fondo `#f5f5f5`, primario negro, secundario borde negro.

### Buscar

Carga caballos cuyo `owner_id` no es el usuario actual. Pull-to-refresh. Cards con imagen o placeholder, nombre, disciplina, precio. Vacío: mensaje de que no hay caballos de otros propietarios.

### Detalle de caballo

Params: `{ horse }` (objeto completo, no refetch). Foto, nombre, precio, nivel, disciplina, canon de pista. DateTimePicker nativo (fecha y hora, `minimumDate` hoy). En iOS el picker puede quedar visible (`showPicker` no se cierra en iOS). Confirmación inserta reserva y vuelve atrás.

### Reservas

Lista de reservas del usuario autenticado como rider. Badge de `status` en mayúsculas, fecha/hora, bloque estático «Pase de Acceso Digital Válido». Sin acciones. `useEffect` al montar; no recarga al enfocar el tab.

### Perfil

Email, atajos a registrar y gestionar caballos, logout rojo. Cualquier usuario autenticado ve las acciones de propietario (no hay rol).

### Mis caballos

`useFocusEffect` recarga al enfocar. Lista propia, editar (pasa `horse` por params), baja con confirmación. Pull-to-refresh.

### Alta / edición de caballo

Campos: nombre, disciplina, nivel, precio, máximo diario (default 2), canon (default 0), foto de galería. Validación mínima: nombre, precio y nivel. Tras guardar, `goBack`.

---

## 8. Estilo y UX

- Paleta: fondos gris claro / blanco, texto `#111` / `#666`, acento de precio verde `#2ecc71`, logout y baja `#ff3b30`, editar `#007AFF`.
- Cards con `elevation` / sombra iOS.
- Copy y placeholders en español.
- Emojis en algunos botones y en el texto del pase digital.
- Sin diseño system, theming ni componentes reutilizados entre pantallas (estilos duplicados en search/owner list).

---

## 9. Datos y límites de diseño actuales

- **Cliente gordo:** cada pantalla habla con Supabase; no hay repositorio ni tipos.
- **Identidad:** un mismo usuario es rider (busca/reserva) y owner (CRUD caballos) a la vez.
- **Catálogo:** el dueño no ve sus propios caballos en Buscar; el resto del mundo sí (salvo RLS en el proyecto remoto, no visible aquí).
- **Reserva:** un timestamp único (`session_date`), no intervalo inicio/fin; estado fijo `'pendiente'` al crear; `max_daily_sessions` no se consulta al reservar.
- **Multimedia:** una URL en la fila del caballo, no galería ni vídeo.
- **Navegación de auth:** arranque siempre en Login; sesión persistida no restaura la ruta Home sola.
- **Secretos:** anon key y URL en `supabase.js` (la anon key es pública por diseño de Supabase; el riesgo real depende de RLS en el proyecto).

---

## 10. Dependencias declaradas y uso

| Dependencia | Uso efectivo |
| --- | --- |
| `@react-navigation/native` + stack + tabs + `safe-area-context` + `screens` | Navegación |
| `@supabase/supabase-js` | Auth, PostgREST, URL de storage |
| `@react-native-async-storage/async-storage` | Persistencia de sesión Supabase |
| `@react-native-community/datetimepicker` | Fecha/hora en detalle |
| `expo-image-picker` | Galería en alta/edición |
| `expo-status-bar` | No aparece importado en las pantallas leídas |
| `react-native-web` / `react-dom` | Target web de Expo |

---

## 11. Diagrama de runtime

```
┌─────────────┐     Auth / REST / Storage      ┌──────────────────┐
│  Expo App   │ ─────────────────────────────► │  Supabase Cloud  │
│  (JS only)  │                                │  Auth            │
│             │ ◄── JWT en AsyncStorage        │  Postgres        │
│  Screens    │                                │    horses        │
│  + supabase │                                │    bookings      │
│    client   │                                │  Storage         │
└─────────────┘                                │    horse-images  │
                                               └──────────────────┘
```

No hay workers, colas, pagos, notificaciones push ni geolocalización en el código actual.
