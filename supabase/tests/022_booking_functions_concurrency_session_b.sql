-- Session B: hold persist gate, wait until A finished eval, then activate
-- an unmet requirement and release persist.
set statement_timeout = '20s';
begin;
select pg_advisory_lock(22022022);
select 'session_b_holding' as marker;
select pg_advisory_lock(22022021);

insert into public.equine_requirements (
  equine_id, requirement_type, numeric_value, source_type, status
)
select equine.id, 'MIN_AGE', 99, 'CENTER', 'ACTIVE'
  from public.equines as equine
 where equine.name = 'phase11b-conc-school';

select pg_advisory_unlock(22022022);
select pg_advisory_unlock(22022021);
commit;
select 'session_b_mutated' as marker;
