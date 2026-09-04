ARCHITECTURE_CONFLICT

Current frozen rule:
Architecture 2.1 §25 names target buckets `avatars` and `equine-media`
and states only that `session-evidence`, qualification documents and
assessment documents will not be public. §22 says evidence/docs are
private and that equines may be publicly readable only if publishable.
`equines.visibility_status = PUBLIC` is stored publication intent only
(011) and does not grant Storage read. AI_INSTRUCTIONS says published
equine media *may* be public by design. No Product Owner decision names
avatar visibility, equine-media public URL vs signed URL, or the
writable path owner (PERSON vs ACCOUNT vs PRIMARY_MANAGER vs Center).

Implementation problem:
Phase 14A must create the five target buckets and bind every allowed
Storage operation to canonical ACCOUNT/PERSON/domain authority. For
avatars and equine-media the access path itself is not frozen: making
either bucket public, granting `TO authenticated` folder writes, or
binding paths to `auth.uid()` would invent visibility or ownership.

Why cannot implement:
The issue forbids inventing public visibility or path ownership. It
also forbids making a bucket public unless Architecture 2.1 explicitly
establishes that visibility. The unpublished/public equine-media split
and the avatar write/read subject are therefore not safely derivable.

Options:
1. Keep both buckets private with no client INSERT/SELECT/UPDATE/DELETE
   policies (deny-by-default) until Product Owner names visibility and
   the PERSON/ACCOUNT/manager/center write path.
2. Make `equine-media` public because AI_INSTRUCTIONS allows published
   media to be public — this invents a public URL for unpublished
   equines and ignores 011's "PUBLIC is intent only" rule.
3. Bind avatars to `auth.uid()` folders — this collapses PERSON and
   ACCOUNT and breaks minors without accounts.

Recommended option:
Option 1. 027 creates the buckets as private, adds no client policies
for them, and continues the three frozen-private document/evidence
buckets with domain-UUID paths. Product Owner should name, in one
decision: avatar public/private; equine-media public vs private vs
publishable-only; writable path subject (PERSON, guardian, manager,
Center); and whether signed URLs are allowed later.
