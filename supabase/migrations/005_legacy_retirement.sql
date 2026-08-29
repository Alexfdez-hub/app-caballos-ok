-- Phase 2C: retire the original prototype database contract.
--
-- Verified dependency order:
--   auth.users.on_auth_user_created -> public.handle_new_user()
--   public.bookings -> public.horses and public.users
--   public.horses -> public.users
--
-- Architecture 2.1 tables created by migrations 001-004 do not reference
-- these legacy objects. Deliberately avoid CASCADE so any unexpected external
-- dependency aborts the migration instead of being removed implicitly.

drop trigger if exists on_auth_user_created on auth.users;
drop function if exists public.handle_new_user();

drop table if exists public.bookings;
drop table if exists public.horses;
drop table if exists public.users;
