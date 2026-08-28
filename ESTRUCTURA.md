## 🗄️ Esquema de Base de Datos (Fase 1) - MVP App Caballos

### 1. `users` (Perfiles, KYC y DAC7)
- `id` (uuid, PK): ID único vinculado a Supabase Auth.
- `role` (text): 'jinete' o 'propietario'.
- `full_name` (text): Nombre completo.
- `kyc_status` (text): Estado validación Stripe Identity (ej. 'pending', 'verified').
- `federation_number` (text): Número de licencia (jinetes).
- `galope_level` (int): Nivel de galope validado (jinetes).
- `waiver_signed_at` (timestamp): Fecha de firma de exención legal.
- `tax_id` (text): NIF para DAC7 (propietarios).
- `tax_address` (text): Dirección fiscal (propietarios).
- `stripe_account_id` (text): ID de cuenta conectada en Stripe.

### 2. `horses` (Activos y Bienestar)
- `id` (uuid, PK): Identificador del caballo.
- `owner_id` (uuid, FK): Relación con la tabla `users`.
- `name` (text): Nombre del caballo.
- `level_required` (int): Nivel de galope mínimo exigido.
- `discipline` (text): Salto, Doma, etc.
- `price_per_session` (numeric): Coste base de alquiler.
- `facility_fee` (numeric): Canon de pista de la hípica.

### 3. `horse_media` (Multimedia y Ubicación de equipo)
- `id` (uuid, PK)
- `horse_id` (uuid, FK)
- `media_url` (text): Enlace al archivo.
- `media_type` (text): 'photo' o 'video'.
- `is_tack_location` (boolean): Indica si el vídeo muestra dónde está la montura.

### 4. `bookings` (Reservas y Finanzas)
- `id` (uuid, PK)
- `horse_id` (uuid, FK)
- `rider_id` (uuid, FK)
- `start_time` (timestamp): Inicio del bloque reservado.
- `end_time` (timestamp): Fin del bloque reservado.
- `total_price` (numeric): Coste total procesado.
- `stripe_payment_intent` (text): Referencia de la retención/fianza en Stripe.
- `status` (text): 'pending', 'confirmed', 'active', 'completed', 'cancelled'.

### 5. `session_logs` (El Parquímetro Ecuestre)
- `id` (uuid, PK)
- `booking_id` (uuid, FK)
- `check_in_time` (timestamp): Momento exacto de inicio real.
- `check_in_location` (geography): Coordenadas GPS validadas en la hípica.
- `check_out_time` (timestamp): Fin de la monta.
- `checkout_photo_url` (text): URL de la foto de prueba del caballo en el box.
- `offline_sync` (boolean): `true` si el checkout se guardó sin internet.

### 6. `reviews` (Reputación y Feedback)
- `id` (uuid, PK)
- `booking_id` (uuid, FK)
- `reviewer_id` (uuid, FK)
- `reviewee_id` (uuid, FK)
- `rating` (int): 1 a 5 estrellas.
- `comment` (text): Texto de la valoración.