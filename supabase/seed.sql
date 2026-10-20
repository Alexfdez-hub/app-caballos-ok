-- Phase 2B intentionally seeds no market, policy document, or policy
-- acceptance. Those values require Product Owner approval and must not
-- be fabricated.
--
-- The local test-operator switch is not product data. Supabase applies
-- this file on a local reset and does not apply it to a hosted project.

update public.test_operator_gate
   set enabled = true
 where singleton;
