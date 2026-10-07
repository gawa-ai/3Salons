# Permission matrix and evidence

Identity always comes from the signed-in Supabase user (`auth.uid()`), then `app.memberships`
(role + professional). The browser never decides access. Another profile's record returns exactly the
same `not_found` error as a record that does not exist, so even its existence is not revealed.

| Data / action | Public visitor | Staff (Sofia / Shirin / Sabiha) | Owner (Shahina) |
|---|---|---|---|
| Published profiles, services, prices, free slots | ✔ | ✔ | ✔ |
| Create booking request (provisional) / bridal enquiry | ✔ (validated, rate-limited, honeypot) | ✔ manual booking for **self** | ✔ for any professional |
| View / cancel own booking via private link | ✔ (token holder only, no contact details shown) | — | — |
| Bookings, calendar | ✖ | **own only** | all, or filter by professional |
| Confirm / decline / complete / no-show / reschedule | ✖ | own only, cannot reassign | all, can reassign (contact details only, never notes) |
| Client records and notes | ✖ | **own clients only** (separate record per professional) | all |
| Enquiries | ✖ | addressed to them only | all, incl. "no preference" |
| Messages log (SMS "Not connected") | ✖ | own only | all |
| Reports / overview counts | ✖ | own only, no per-profile breakdown | combined + per profile |
| Services | ✖ | own: duration/description/visibility, **not price** | all incl. price |
| Working hours, time off | ✖ | own | all + close whole salon |
| Gallery (storage folder) | view published | own folder only | all |
| Team, invitations, disable login | ✖ | ✖ | ✔ |
| Salon settings, opening hours, booking mode | ✖ | ✖ | ✔ |
| Activity log (audit trail) | ✖ | ✖ | ✔ |
| Tables in schema `app` directly | ✖ (no grants, RLS on) | ✖ | ✖ (only via functions) |
| `salon_internal_*` (edge function only) | ✖ | ✖ | ✖ |

## Evidence

**VERIFIED locally** (throwaway Postgres 16, `tests/db/run.sh`, 112/112, run repeatedly):
checks 37–42 cover anon and no-membership denial. Checks 44–69 cover cross-profile denial on bookings, clients, messages, overview, report, team, audit and settings, including attempts to widen the professional filter. Checks 77 and 86–89 confirm staff cannot reassign, change prices or change ownership fields. Checks 102–105 cover disabled logins and storage folders. Check 112 runs two concurrent requests for one slot and gets exactly one booking.

**VERIFIED in the browser** (`tests/e2e/run.cjs`, 33/33, real SQL behind a mock HTTP layer): S1–S7 confirm that staff have no All selector and no owner pages, that Sofia never sees Shirin's client, and that a token cannot widen scope.

**VERIFIED live on "3 Salons"** (2026-10-07, one transaction, rolled back; `QA` fixtures removed, counts re-checked at 0):

| Live check | Result |
|---|---|
| Visitor books Shirin (Party Hair) | `ok`, stored as `pending` |
| Second request overlapping it | `slot_taken` |
| Visitor calls a dashboard function | `permission denied` |
| Sofia opens Shirin's booking | `not_found` |
| Sofia confirms Shirin's booking | `not_found` |
| Sofia lists bookings / clients with Shirin's id | `forbidden`, no data |
| Sofia's overview contains Shirin's client | no |
| Sofia opens owner Team page | `forbidden` |
| Sofia reads `app.bookings` directly | `permission denied for table bookings` |
| Shirin confirms her own booking | `ok`, status `confirmed` |
| Function audit (42 `salon_*` functions) | all SECURITY DEFINER with empty search_path; anon can run only `salon_public_*`; `salon_internal_*` not callable by users; 0 table grants; RLS on all 16 tables |

## Supabase advisors (explained)

- *RLS enabled, no policy* (INFO, 16 tables): intentional. The tables deny all direct access, and data is reached only through the checked functions.
- *SECURITY DEFINER executable by anon/authenticated* (WARN): this is the API by design. Each function enforces identity inside it, as the live checks above show. Anon can run only the 8 `salon_public_*` functions.
- *Unindexed foreign keys* (INFO): fixed by migration `20261007001100_fk_indexes.sql`.
