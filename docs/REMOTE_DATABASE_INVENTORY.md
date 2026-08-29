# Remote database inventory

**Phase:** 2A — Read-only remote schema inventory  
**Date:** 2026-08-29  
**Source file:** `supabase_remote_schema.sql`  
**Scope:** objects present in that dump only  
**Remote writes:** none (no `db push`, `db reset`, migration apply, seed, or dashboard changes)

This document does not infer objects that are absent from the dump.

---

## Dump coverage and limits

The dump:

- sets `search_path` to empty;
- creates/alters schema `public`;
- defines one function, three tables, constraints, RLS policies, grants, and default privileges.

It does **not** include:

- `CREATE EXTENSION` statements;
- `CREATE TYPE` / enums;
- `CREATE VIEW`;
- `CREATE INDEX` (except implicit unique indexes from primary keys);
- `CREATE TRIGGER`;
- `auth`, `storage`, `realtime`, or other non-public schemas;
- table/column comments;
- row data, row counts, or sample values;
- Auth provider/dashboard configuration;
- Storage buckets or Storage RLS;
- publications, subscriptions, or replica identity;
- cron, vault, graphql, or Edge Functions.

---

## UNVERIFIED REMOTE AREAS

The following cannot be confirmed from `supabase_remote_schema.sql`. Do not treat them as present or absent.

| Area | Why unverified |
| --- | --- |
| Auth configuration | Email confirmation, providers, MFA, JWT settings, redirects — not in dump |
| `auth.users` table shape | Only referenced as FK target `auth.users(id)`; no `auth` schema dump |
| Trigger attaching `handle_new_user` | Function exists and is written as a trigger function (`RETURNS trigger`, uses `NEW.id`); **no `CREATE TRIGGER` in the dump**. Likely lives on `auth.users` if it exists at all |
| Storage buckets | Client uses `horse-images`; dump has no Storage objects or policies |
| Storage RLS / bucket public flags | Not in dump |
| Extensions catalog | No `CREATE EXTENSION`. Usage evidence only: `extensions.uuid_generate_v4()` and `gen_random_uuid()` |
| Non-public schemas | `auth`, `storage`, `extensions` catalog, `private`, etc. not dumped |
| Indexes beyond PKs | None listed; cannot prove none exist outside dump |
| Views, materialized views, enums | None in dump; cannot prove none exist in other schemas |
| Row counts / orphan data | Schema-only |
| Realtime publication of tables | Not in dump |
| Network / dashboard secrets | Out of scope; not inspected |

---

## 1. Object inventory (from dump)

### 1.1 Extensions visible in the dump

No extension is created in the dump.

**Usage evidence only:**

- `extensions.uuid_generate_v4()` — default on `horses.id` (typical Supabase `uuid-ossp` in schema `extensions`).
- `gen_random_uuid()` — default on `bookings.id` (PostgreSQL built-in on current major versions; dump does not name an extension).

### 1.2 Enums / custom types

None.

Status and role values are `text` plus `CHECK` constraints.

### 1.3 Schemas

| Schema | Notes |
| --- | --- |
| `public` | Created if not exists; owner `pg_database_owner`; comment `standard public schema` |

### 1.4 Functions

| Name | Language | Security | Returns | Body summary |
| --- | --- | --- | --- | --- |
| `public.handle_new_user()` | plpgsql | `SECURITY DEFINER` | `trigger` | `INSERT INTO public.users (id, role) VALUES (NEW.id, 'jinete'); RETURN NEW;` |

Owner: `postgres`.  
Grants: `ALL` to `anon`, `authenticated`, `service_role`.

No other functions.

### 1.5 Triggers

None in the dump.

### 1.6 Views

None in the dump.

### 1.7 Tables — columns, defaults, constraints, indexes, RLS

#### `public.users`

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| `id` | `uuid` | NOT NULL | none |
| `role` | `text` | yes | none |
| `full_name` | `text` | yes | none |
| `kyc_status` | `text` | yes | `'pending'` |
| `federation_number` | `text` | yes | none |
| `galope_level` | `integer` | yes | none |
| `waiver_signed_at` | `timestamptz` | yes | none |
| `tax_id` | `text` | yes | none |
| `tax_address` | `text` | yes | none |
| `stripe_account_id` | `text` | yes | none |
| `created_at` | `timestamptz` | yes | `now()` |

- **PK:** `users_pkey` (`id`)
- **Unique (non-PK):** none
- **Check:** `users_role_check` — `role` IN (`jinete`, `propietario`)  
  Note: `NULL` `role` satisfies a CHECK in PostgreSQL (CHECK fails only when the expression is false).
- **FK:** `users_id_fkey` — `id` → `auth.users(id)` (no `ON DELETE` in dump → default `NO ACTION` / `RESTRICT`)
- **Indexes:** implicit unique index from PK only
- **RLS:** **enabled**

#### `public.horses`

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| `id` | `uuid` | NOT NULL | `extensions.uuid_generate_v4()` |
| `owner_id` | `uuid` | NOT NULL | none |
| `name` | `text` | NOT NULL | none |
| `level_required` | `integer` | NOT NULL | none |
| `discipline` | `text` | yes | none |
| `price_per_session` | `numeric` | NOT NULL | none |
| `facility_fee` | `numeric` | yes | `0` |
| `created_at` | `timestamptz` | yes | `now()` |
| `max_daily_sessions` | `integer` | yes | `2` |
| `media_url` | `text` | yes | none |

- **PK:** `horses_pkey` (`id`)
- **Unique (non-PK):** none
- **Check:** none
- **FK:** `horses_owner_id_fkey` — `owner_id` → `public.users(id)` (no `ON DELETE` in dump)
- **Indexes:** implicit unique index from PK only
- **RLS:** **enabled**

#### `public.bookings`

| Column | Type | Nullable | Default |
| --- | --- | --- | --- |
| `id` | `uuid` | NOT NULL | `gen_random_uuid()` |
| `horse_id` | `uuid` | NOT NULL | none |
| `rider_id` | `uuid` | NOT NULL | none |
| `session_date` | `timestamptz` | NOT NULL | none |
| `status` | `text` | yes | `'pendiente'` |
| `created_at` | `timestamptz` | NOT NULL | `timezone('utc', now())` |

- **PK:** `bookings_pkey` (`id`)
- **Unique (non-PK):** none
- **Check:** `bookings_status_check` — `status` IN (`pendiente`, `confirmada`, `completada`, `cancelada`)  
  `NULL` status is allowed by CHECK semantics.
- **FKs:**
  - `bookings_horse_id_fkey` — `horse_id` → `public.horses(id)` **ON DELETE CASCADE**
  - `bookings_rider_id_fkey` — `rider_id` → `public.users(id)` **ON DELETE CASCADE**
- **Indexes:** implicit unique index from PK only
- **RLS:** **enabled**

No other tables.

### 1.8 Foreign keys — `auth.users` and identity chain

```text
auth.users(id)
    ▲
    │  users_id_fkey
public.users(id)          ← same UUID as Auth user when handle_new_user runs as designed
    ▲                 ▲
    │                 │
    │ horses_owner_id_fkey          bookings_rider_id_fkey
    │ (no ON DELETE in dump)        ON DELETE CASCADE
public.horses(owner_id)   public.bookings(rider_id)
    ▲
    │ bookings_horse_id_fkey ON DELETE CASCADE
public.bookings(horse_id)
```

There is **no** FK from `horses.owner_id` or `bookings.rider_id` directly to `auth.users`. Both go through `public.users`. Because `public.users.id` is itself an FK to `auth.users.id`, those UUIDs are intended to be Auth user ids.

### 1.9 `owner_id` / `rider_id` usage

| Column | Table | Target | Meaning in remote schema |
| --- | --- | --- | --- |
| `owner_id` | `horses` | `public.users.id` | Equine “owner” = profile row keyed by Auth UUID |
| `rider_id` | `bookings` | `public.users.id` | Booking “rider” = same profile/Auth UUID |

Neither column points at a `persons` or `user_accounts` table (those tables do not exist in the dump).

### 1.10 RLS policies (all business tables in dump)

| Policy name | Table | Command | Using / with check |
| --- | --- | --- | --- |
| `Cualquiera puede ver los caballos` | `horses` | SELECT | `true` |
| `Los propietarios pueden insertar sus caballos` | `horses` | INSERT | WITH CHECK `auth.uid() = owner_id` |
| `Los propietarios pueden actualizar sus caballos` | `horses` | UPDATE | USING `auth.uid() = owner_id` |
| `Los propietarios pueden borrar sus caballos` | `horses` | DELETE | USING `auth.uid() = owner_id` |
| `Los usuarios pueden ver su propio perfil` | `users` | SELECT | USING `auth.uid() = id` |
| `Los usuarios pueden actualizar su propio perfil` | `users` | UPDATE | USING `auth.uid() = id` |
| `Usuarios pueden ver sus reservas` | `bookings` | SELECT | USING `auth.uid() = rider_id` |
| `Usuarios pueden crear sus reservas` | `bookings` | INSERT | WITH CHECK `auth.uid() = rider_id` |

**Policy gaps visible in dump (not inferred beyond dump):**

- `users`: no INSERT, no DELETE policy (inserts would need a definer trigger, service role, or bypass).
- `bookings`: no UPDATE, no DELETE policy.
- `bookings`: owners cannot SELECT bookings on their horses (only `rider_id = auth.uid()`).
- `horses` SELECT is world-readable at RLS level (`USING (true)`), including rows whose `owner_id` is the current user.
- No `FORCE ROW LEVEL SECURITY` statements.

### 1.11 Grants (dump)

Schema `public`: `USAGE` to `postgres`, `anon`, `authenticated`, `service_role`.

`handle_new_user`, `bookings`, `horses`, `users`: `GRANT ALL` to `anon`, `authenticated`, `service_role`.

Default privileges in `public` for role `postgres`: `ALL` on future sequences, functions, and tables to `postgres`, `anon`, `authenticated`, `service_role`.

RLS still filters `anon`/`authenticated` table access; `GRANT ALL` is not the same as bypassing RLS. Table owners and `service_role` behaviour are not fully specified in this dump.

---

## 2. Focus: horses, bookings, identity, RLS

### 2.1 `horses` (actual remote)

Live prototype catalog/inventory table. Identity of the owner is `owner_id` → `public.users` → `auth.users`. Commercial and listing fields live on the same row (`level_required`, `discipline`, `price_per_session`, `facility_fee`, `max_daily_sessions`, `media_url`). No center, type HORSE/PONY, ownership percentage, management assignment, or calendar columns.

UUID default differs from `bookings` (`uuid_generate_v4` vs `gen_random_uuid`).

### 2.2 `bookings` (actual remote)

One row = one `session_date` timestamp (not a start/end interval). Status is Spanish lowercase labels with a CHECK. Client-facing insert of `pendiente` is allowed by RLS. No `center_id`, `service_id`, `participant_person_id`, `booked_by_account_id`, eligibility, policy snapshot, or occupancy block table.

No unique/exclusion constraint on `(horse_id, session_date)` — double booking is not prevented in this schema.

Deleting a horse **cascades** all its bookings. Deleting a `public.users` row **cascades** that user’s bookings as rider.

### 2.3 Identity model on remote

A single `public.users` row, PK = Auth UUID, optional mutually exclusive `role` (`jinete` | `propietario`). Extra profile/compliance/payout-oriented columns exist on the same table. `handle_new_user` always inserts `role = 'jinete'` if the trigger is attached (attachment **unverified**).

This is **not** person ≠ user_account.

---

## 3. Comparison to documentation

### 3.1 vs `docs/CURRENT_ARCHITECTURE_REPORT.md`

The report described **client-assumed** backend, not a schema dump. Alignment and gaps:

| Topic | Report | Dump |
| --- | --- | --- |
| Tables used by app | `horses`, `bookings` | Same, **plus** `public.users` |
| Profile table | “No hay lectura de una tabla `users` / perfiles” | `public.users` exists with RLS; app still may not read it |
| `owner_id` / `rider_id` | Auth `user.id` | Same UUID **if** `public.users.id` = `auth.users.id`; FKs are to `public.users`, not directly to Auth |
| `horses` columns | Matches listed UI fields | Confirmed; plus `created_at` |
| `bookings` insert | `horse_id`, `rider_id`, `session_date`, `status` | Confirmed; plus `id`, `created_at`, status CHECK |
| RLS | “salvo RLS … no visible aquí” | RLS **enabled** on all three tables; policies listed above |
| Storage `horse-images` | Client uses it | **Not in dump** |

App-side items in the report (Expo metadata, AuthProvider, TypeScript) are Phase 0/1 client state and are out of scope for this inventory.

### 3.2 vs frozen `docs/DATA_ARCHITECTURE.md`

| Frozen concept | Remote dump |
| --- | --- |
| `persons` / `user_accounts` | Absent. `public.users` conflates Auth id, role, KYC, tax, Stripe, Galope |
| Multiple simultaneous roles | `users_role_check` allows only one of `jinete`/`propietario` (or NULL) |
| `equines` + type HORSE/PONY | `horses` only; no `equine_type` |
| Ownership ≠ management ≠ center | Single `owner_id` |
| `equine_media` | `horses.media_url` text |
| `bookings` with `participant_person_id`, `booked_by_account_id`, `starts_at`/`ends_at`, English statuses, RPC-only confirm | `rider_id` = Auth/profile UUID; one `session_date`; Spanish statuses; INSERT via RLS |
| `equine_calendar_blocks` + exclusion | Absent |
| Policy documents/acceptances | Absent (`waiver_signed_at` is a single timestamp, not versioned policy) |
| Markets, centers, guardians, assessments, sessions | Absent |
| RLS deny-by-default + public equine only if publishable | `horses` SELECT `USING (true)` |
| Target Storage buckets | Not in dump; frozen names differ from client `horse-images` |
| Prototype migration notes (§28) | Correct that Auth + `horses` + `bookings` + Auth ids as owner/rider exist; **omits** `public.users`, `handle_new_user`, extra profile columns, and FK graph through `public.users` |

No `ARCHITECTURE_CONFLICT` is raised: frozen architecture remains the target. Remote state is a prototype that must be migrated, not a reason to merge person and account.

---

## 4. Classification of discovered application objects

Legend: **KEEP** (remain as-is for MVP0), **ADAPT** (keep but change shape/policies later), **MIGRATE** (data/meaning moves to frozen tables), **LEGACY / CONTRACT LATER** (required for current app until Phase 15), **UNKNOWN / NEEDS PRODUCT OWNER DECISION**.

| Object | Classification | Notes |
| --- | --- | --- |
| Schema `public` | KEEP | Standard |
| `public.horses` table | LEGACY / CONTRACT LATER + MIGRATE | Live app contract; data → `equines` + related tables (Phase 4). Do not drop in Phase 2 |
| `horses.id` | MIGRATE | New `equines.id` may be same UUID to preserve FKs, or mapped — PO if remap |
| `horses.owner_id` | MIGRATE | → `equine_ownerships` + `PRIMARY_MANAGER` via user→account→person |
| `horses.name` | MIGRATE | → `equines.name` |
| `horses.level_required` | UNKNOWN / NEEDS PRODUCT OWNER DECISION | Integer on equine; frozen model uses qualifications/requirements, not this column |
| `horses.discipline` | UNKNOWN / NEEDS PRODUCT OWNER DECISION | Free text; frozen `disciplines` is coded + translations. Do not invent codes |
| `horses.price_per_session` | UNKNOWN / NEEDS PRODUCT OWNER DECISION | Frozen services/pricing not in Phase 2; no invent |
| `horses.facility_fee` | UNKNOWN / NEEDS PRODUCT OWNER DECISION | Same |
| `horses.max_daily_sessions` | UNKNOWN / NEEDS PRODUCT OWNER DECISION | Not occupancy; calendar is later. App does not enforce on booking |
| `horses.media_url` | MIGRATE | → `equine_media` / Storage path; bucket unverified |
| `horses.created_at` | MIGRATE | Map if present; nullable on remote |
| `horses` RLS policies | LEGACY / CONTRACT LATER + ADAPT | Keep working until equine RLS exists; SELECT `true` is not frozen “publishable only” |
| `public.bookings` table | LEGACY / CONTRACT LATER + MIGRATE | Migrate only if data is sufficient (frozen §28). Do not drop in Phase 2 |
| `bookings.horse_id` | MIGRATE | → `equine_id` after equine mapping |
| `bookings.rider_id` | MIGRATE / ADAPT | Must split into `participant_person_id` vs `booked_by_account_id`; today they are the same Auth UUID |
| `bookings.session_date` | ADAPT | No `ends_at`; backfill strategy needed before calendar/eligibility |
| `bookings.status` | ADAPT | Spanish set ≠ frozen English set; do not silently rewrite live rows |
| `bookings.created_at` | MIGRATE | Keep as created timestamp |
| `bookings` INSERT/SELECT RLS | LEGACY / CONTRACT LATER | Frozen: critical transitions via RPC, not client INSERT to CONFIRMED. Current INSERT of `pendiente` is the live contract |
| `bookings` missing UPDATE/DELETE policies | KEEP for now (document) | Do not add destructive client updates in Phase 2 |
| `public.users` table | ADAPT / MIGRATE | **Name collision** with frozen identity. Must not be dropped while FKs exist. Target is `persons` + `user_accounts`, not a single `users.role` |
| `users.id` | ADAPT | Becomes `user_accounts.auth_user_id` (and possibly `user_accounts.id` if 1:1). `persons.id` must be a **new** UUID — cannot stay equal to Auth id if a person can exist without an account |
| `users.role` | LEGACY / CONTRACT LATER | Frozen: do not extend mutually exclusive role. `handle_new_user` forces `jinete` |
| `users.full_name` | MIGRATE / UNKNOWN | Split `first_name`/`last_name` needs a rule; empty/null names block NOT NULL persons |
| `users.kyc_status` | UNKNOWN / NEEDS PRODUCT OWNER DECISION | Not in frozen MVP0 identity tables |
| `users.federation_number` | UNKNOWN / NEEDS PRODUCT OWNER DECISION | Qualification-like; do not invent verification |
| `users.galope_level` | UNKNOWN / NEEDS PRODUCT OWNER DECISION | Frozen: do not hardcode Galopes into DB internals |
| `users.waiver_signed_at` | UNKNOWN / NEEDS PRODUCT OWNER DECISION | ≠ versioned `policy_acceptances` |
| `users.tax_id` / `tax_address` | UNKNOWN / NEEDS PRODUCT OWNER DECISION | Fiscal automation is out of MVP0 |
| `users.stripe_account_id` | UNKNOWN / NEEDS PRODUCT OWNER DECISION | Stripe is deferred; do not build payouts |
| `users.created_at` | MIGRATE | Map to account/person timestamps |
| `users` SELECT/UPDATE RLS | LEGACY / CONTRACT LATER + ADAPT | Self-only; no INSERT policy in dump |
| `handle_new_user()` | ADAPT | Must later create `persons` + `user_accounts` (and not a single role). Trigger attachment unverified |
| PK indexes | KEEP | Until tables are replaced |
| `GRANT ALL` to `anon` on tables | ADAPT | Tighten in a later security phase; do not rely on grants instead of RLS |
| Default privileges ALL to `anon` | ADAPT | Risk for **new** tables created without RLS in the same schema |
| `auth.users` | KEEP as Auth source | Shape unverified; frozen `user_accounts.auth_user_id` → `auth.users` |

---

## 5. Risks, backfill, collisions, destructive ops, blockers

### 5.1 Migration risks

- **Identity 1:1 with Auth:** `public.users.id = auth.users.id` blocks “person without account” unless new `persons.id` values are created and mapped.
- **Mutually exclusive `role`:** contradicts simultaneous owner+rider (the app already treats every user as both).
- **`handle_new_user`:** if still attached, new Auth users get a `public.users` row with `jinete` only; Phase 2 identity functions must not fight this without a planned replacement.
- **Missing trigger in dump:** if the trigger is missing, `horses.owner_id` / `bookings.rider_id` inserts can fail FK to `public.users`.
- **Nullable `bookings.status`:** CHECK does not reject NULL.
- **No occupancy constraint:** overlapping `session_date` allowed.
- **CASCADE deletes:** horse delete removes bookings; user delete removes rider bookings.
- **Open horse catalog:** RLS SELECT `true` plus `GRANT` to `anon`.
- **UUID generators mixed** on `horses` vs `bookings` (operational inconsistency, not a blocker).

### 5.2 Backfill requirements (when identity/equine/booking phases run)

- One `persons` + one `user_accounts` per existing `auth`/`public.users` row that should keep using the app.
- `date_of_birth` NOT NULL on frozen `persons` — **no DOB on remote** → cannot invent; PO rule required (placeholder vs block vs collect later).
- `first_name` / `last_name` NOT NULL — only optional `full_name` exists.
- `horses` → `equines`: `equine_type` missing; do not invent HORSE vs PONY without a rule.
- `media_url` → `equine_media.storage_path`: parse URL vs store as-is; Storage bucket unverified.
- `owner_id` → ownership + PRIMARY_MANAGER after user→account→person.
- `bookings`: `ends_at` missing; `center_id` / `service_id` missing; status vocabulary mapping; `booked_by` vs participant identical today.
- Do not invent centers, qualifications, Galope systems, or consents.

### 5.3 Naming collisions

| Name | Collision |
| --- | --- |
| `public.users` | Frozen model uses `user_accounts` + `persons`, not `users`. Creating another `users` table is impossible. Dropping/renaming `public.users` **breaks** `horses` and `bookings` FKs |
| `bookings` | Frozen Phase 10 also uses `bookings`. Live table is a different shape. Cannot `CREATE TABLE bookings` without rename/migrate-in-place |
| `role` | Frozen forbids single `users.role`; column exists |
| Future `user_accounts` | No name clash with dump (table absent). Must not replace `public.users` until FKs retargeted |

### 5.4 Destructive operations to avoid

- DROP `horses`, `bookings`, `users`
- DROP or rewrite `handle_new_user` without a replacement path for sign-up
- Change FK targets without dual-write/backfill
- `ON DELETE CASCADE` experiments on production
- Disable RLS
- Rewrite `bookings.status` in place to frozen English enums while the Expo client still writes/reads Spanish values
- `db reset` / data wipe
- Mapping all Auth users to persons with fabricated DOB/names

### 5.5 Blockers for person / account separation

- PK of `public.users` is the Auth UUID.
- All business FKs hang off `public.users`, not a person id.
- No table for a person without Auth.
- `handle_new_user` only knows Auth `NEW.id`.
- App and RLS compare `auth.uid()` to `owner_id` / `rider_id` / `users.id`.

Phase 2 identity tables can be **added alongside** (CREATE → dual-key mapping). They must not replace `public.users` in the same step as the live FKs.

### 5.6 Blockers for later booking / calendar migration

- Single `session_date`, no duration, no `tstzrange`, no `equine_calendar_blocks`.
- No unique/exclusion on equine + time.
- Client INSERT allowed; frozen confirm is RPC + calendar block.
- Status vocabulary and nullable status.
- No `center_id` (calendar blocks are per equine+center in frozen model).
- Owner cannot see bookings under current RLS (product gap, not a schema dump extra).
- CASCADE from horse/user deletes occupancy history.

These do **not** block Phase 2A/2B **creating** `persons`/`user_accounts`/`markets`/`policies` as **new** tables, provided `bookings` is not replaced yet (Migration Plan: Phase 2 does not create bookings).

---

## 6. What this dump does not cover

Explicitly **not** inventoried here:

- Storage buckets, objects, MIME limits, public/private flags, Storage policies
- Auth schema, identities, sessions, MFA, hooks other than the public function definition
- Whether `handle_new_user` is actually bound to `auth.users`
- Private or extra schemas
- Extensions not referenced in SQL text
- Data volume and data quality
- Dashboard-only settings
- Edge Functions, webhooks, cron
- Realtime
- Network/IP allow lists

---

## 7. Recommended next phase (not started)

Phase 2B (when authorized): versioned migrations for extensions/core, markets, **new** `persons`/`user_accounts`, policies — **without** dropping `public.users` / `horses` / `bookings`, **without** applying until Product Owner approval, and **without** inventing DOB/names/centers.

No migrations were created in Phase 2A.
