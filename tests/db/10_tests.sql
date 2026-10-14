-- =====================================================================
-- Functional + permission test suite (THROWAWAY database only).
-- Calls the API exactly as the browser does: as role anon/authenticated with
-- JWT claims, so grants AND scope checks are both exercised.
-- =====================================================================
\set ON_ERROR_STOP 1
set client_min_messages = notice;

create or replace function pg_temp.check(p_ok boolean, p_name text, p_info jsonb default null)
returns void language plpgsql as $$
begin
  if coalesce(p_ok, false) then raise notice 'PASS  %', p_name;
  else raise exception 'FAIL  % :: %', p_name, coalesce(p_info::text, ''); end if;
end $$;

-- run SQL as the current role, capture result or error
create or replace function pg_temp.q(p_sql text)
returns jsonb language plpgsql as $$
declare r jsonb;
begin
  execute p_sql into r;
  return jsonb_build_object('res', r);
exception when others then
  return jsonb_build_object('err', sqlerrm, 'state', sqlstate);
end $$;

create or replace function pg_temp.login(p_uid uuid)
returns void language sql as $$
  select set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', 'authenticated')::text end, false)
$$;
grant execute on all functions in schema pg_temp to anon, authenticated, service_role;

-- ---------------------------------------------------------------- fixtures
select id as salon from app.salons where slug = 'shahina-ahmed' \gset
select id as p_sofia from app.professionals where slug = 'sofia-mua' \gset
select id as p_shirin from app.professionals where slug = 'shirin-jal' \gset
select id as p_sabiha from app.professionals where slug = 'mi-hijabby-sabiha' \gset
select id as s_sofia_makeup from app.services where professional_id = :'p_sofia' and name = 'Party Makeup' \gset
select id as s_sofia_saree from app.services where professional_id = :'p_sofia' and name = 'Saree Styling' \gset
select id as s_sofia_bridal from app.services where professional_id = :'p_sofia' and name = 'Bridal' \gset
select id as s_shirin_hair from app.services where professional_id = :'p_shirin' and name = 'Party Hair' \gset
select id as s_shirin_hijab from app.services where professional_id = :'p_shirin' and name = 'Party Hijab' \gset
select id as s_sabiha_hijab from app.services where professional_id = :'p_sabiha' and name = 'Party Hijab' \gset

-- a day 3-9 days out (London) and the DST-change Sunday
select to_char((now() at time zone 'Europe/London')::date + 4, 'YYYY-MM-DD') as d1 \gset
select to_char((now() at time zone 'Europe/London')::date + 5, 'YYYY-MM-DD') as d2 \gset

insert into auth.users (id, email) values
  ('00000000-0000-4000-8000-0000000000a1', 'owner@test.local'),
  ('00000000-0000-4000-8000-0000000000b1', 'sofia@test.local'),
  ('00000000-0000-4000-8000-0000000000c1', 'shirin@test.local'),
  ('00000000-0000-4000-8000-0000000000d1', 'sabiha@test.local'),
  ('00000000-0000-4000-8000-0000000000e1', 'stranger@test.local');
\set u_owner  '00000000-0000-4000-8000-0000000000a1'
\set u_sofia  '00000000-0000-4000-8000-0000000000b1'
\set u_shirin '00000000-0000-4000-8000-0000000000c1'
\set u_sabiha '00000000-0000-4000-8000-0000000000d1'
\set u_strange '00000000-0000-4000-8000-0000000000e1'

-- ---------------------------------------------------------------- 1. provisioning
select substring(app.create_owner_invitation('shahina-ahmed', 'Owner@Test.local') from ': ([A-Z0-9-]{19})') as owner_code \gset
set role service_role;
select pg_temp.check((pg_temp.q(format($$select public.salon_internal_invite_check(%L, 'other@test.local')$$, :'owner_code'))#>>'{res,error}') = 'invite_email_mismatch',
  '01 invite bound to its email');
select pg_temp.check((pg_temp.q(format($$select public.salon_internal_invite_accept(%L, %L, 'owner@test.local', 'Shahina')$$, :'owner_code', :'u_owner'))#>>'{res,ok}') = 'true',
  '02 owner accepts invitation (edge-function path)');
select pg_temp.check((pg_temp.q(format($$select public.salon_internal_invite_accept(%L, %L, 'owner@test.local', 'x')$$, :'owner_code', :'u_strange'))#>>'{res,error}') = 'invite_used',
  '03 invitation code is single use');
reset role;
select pg_temp.check((pg_temp.q($$select to_jsonb(app.create_owner_invitation('shahina-ahmed','second@test.local'))$$)->>'err') = 'owner_exists',
  '04 SQL bootstrap refuses a second owner');

set role authenticated;
select pg_temp.login(:'u_owner');
select (pg_temp.q(format($$select public.salon_owner_invite(%L, %L, 'sofia@test.local')$$, :'salon', :'p_sofia'))#>>'{res,code}') as c_sofia \gset
select (pg_temp.q(format($$select public.salon_owner_invite(%L, %L, 'shirin@test.local')$$, :'salon', :'p_shirin'))#>>'{res,code}') as c_shirin \gset
select (pg_temp.q(format($$select public.salon_owner_invite(%L, %L, 'sabiha@test.local')$$, :'salon', :'p_sabiha'))#>>'{res,code}') as c_sabiha \gset
select pg_temp.check(length(:'c_sofia') = 19 and length(:'c_shirin') = 19, '05 owner creates staff invitations');
reset role;
select pg_temp.check((select count(*) from app.invitations where code_hash = :'c_sofia' or code_hash like '%' || replace(:'c_sofia','-','') || '%') = 0,
  '06 invitation codes are stored hashed only');

set role authenticated;
select pg_temp.login(:'u_sofia');
select pg_temp.check((pg_temp.q(format($$select public.salon_claim_invite(%L)$$, :'c_sofia'))#>>'{res,role}') = 'professional', '07 Sofia redeems her code');
select pg_temp.check((pg_temp.q(format($$select public.salon_owner_invite(%L, %L, 'evil@test.local')$$, :'salon', :'p_shirin'))->>'err') = 'forbidden',
  '08 staff cannot create invitations');
select pg_temp.login(:'u_shirin');
select pg_temp.check((pg_temp.q(format($$select public.salon_claim_invite(%L)$$, :'c_sofia'))->>'err') = 'invite_used', '09 cannot reuse another person''s code');
select pg_temp.check((pg_temp.q(format($$select public.salon_claim_invite(%L)$$, :'c_sabiha'))->>'err') = 'invite_email_mismatch', '10 code only works for its email');
select pg_temp.check((pg_temp.q(format($$select public.salon_claim_invite(%L)$$, :'c_shirin'))#>>'{res,ok}') = 'true', '11 Shirin redeems her code');
select pg_temp.login(:'u_sabiha');
select pg_temp.check((pg_temp.q(format($$select public.salon_claim_invite(%L)$$, :'c_sabiha'))#>>'{res,ok}') = 'true', '12 Sabiha redeems her code');

-- ---------------------------------------------------------------- 2. public site (anon)
reset role; set role anon; select pg_temp.login(null);
select public.salon_public_profile('shahina-ahmed') as prof \gset
select pg_temp.check((:'prof'::jsonb)->>'ok' = 'true' and jsonb_array_length((:'prof'::jsonb)->'professionals') = 4 and (:'prof'::jsonb)#>>'{professionals,0,slug}' = 'shahina-ahmed', '13 public profile lists Shahina first plus the 3 artists');
select pg_temp.check((:'prof'::jsonb)#>'{salon,hours}' = 'null'::jsonb and (:'prof'::jsonb)#>>'{salon,address}' = '199 Preston New Road, Blackburn, BB2 6BN',
  '14 unconfirmed hours are not published; confirmed address is');
select pg_temp.check((select bool_and(s->>'price_pence' is null) from jsonb_array_elements((:'prof'::jsonb)->'professionals') p,
                       jsonb_array_elements(p->'services') s where s->>'price_kind' = 'enquire'), '15 bridal shows no price (enquire)');
select pg_temp.check(position('client' in (:'prof')) = 0 and position('phone":"+' in (:'prof')) = 0, '16 public profile carries no client data');

-- legacy data: the first seed's 'shahina-ahmed' professional is hidden by owner_not_bookable, then restored by shahina_professional_gallery
reset role;
\i ../../supabase/migrations/20261007001200_owner_not_bookable.sql
select pg_temp.check((select not active and not is_public and not online_booking from app.professionals where slug = 'shahina-ahmed')
  and (select not bool_or(v.active) from app.services v join app.professionals p on p.id = v.professional_id where p.slug = 'shahina-ahmed'),
  '16a owner_not_bookable hides the legacy profile (nothing deleted, re-runnable)');
\i ../../supabase/migrations/20261007001800_shahina_professional_gallery.sql
\i ../../supabase/migrations/20261007001800_shahina_professional_gallery.sql
set role anon; select pg_temp.login(null);
select pg_temp.check(jsonb_array_length(public.salon_public_profile('shahina-ahmed')->'professionals') = 4
  and (select x->>'slug' from jsonb_array_elements(public.salon_public_profile('shahina-ahmed')->'professionals') x limit 1) = 'shahina-ahmed',
  '16b Shahina is restored as the first public professional (re-runnable)');
reset role;
select pg_temp.check((select count(*) from app.gallery_items g join app.professionals p on p.id = g.professional_id where p.slug = 'shahina-ahmed') = 18,
  '16c Shahina gallery has 18 items (17 earlier + the featured photo) and re-running adds no duplicates');

-- client feedback round 1: copy, name, address and a gallery limited to the four photos the client sent
select pg_temp.check((select count(*) from app.gallery_items where published and storage_path like '/gallery/%') = 4
  and (select count(*) from app.gallery_items where storage_path like '/gallery/%') = 46
  and (select count(distinct professional_id) from app.gallery_items where published and storage_path like '%/featured-1.jpg') = 4,
  '16d only the four featured photos are published; the other 42 are hidden, not deleted');
select pg_temp.check((select display_name from app.professionals where slug = 'sofia-mua') = 'Sofia Musa'
  and (select tagline from app.salons where slug = 'shahina-ahmed') = 'Your Beauty. Your Style. Your Special Moment.'
  and (select address from app.salons where slug = 'shahina-ahmed') = '199 Preston New Road, Blackburn, BB2 6BN',
  '16e Sofia Musa, new headline and the confirmed address are in place (slug unchanged)');
-- owner edits survive a re-run: a custom headline, and a photo uploaded through Studio (non-static path)
update app.salons set tagline = 'Custom headline.' where slug = 'shahina-ahmed';
insert into app.gallery_items (salon_id, professional_id, storage_path, media_type, alt_text)
select p.salon_id, p.id, p.salon_id || '/' || p.id || '/owner-upload.jpg', 'image', 'Owner upload' from app.professionals p where p.slug = 'sofia-mua';
\i ../../supabase/migrations/20261013194500_client_feedback_round1.sql
select pg_temp.check((select tagline from app.salons where slug = 'shahina-ahmed') = 'Custom headline.'
  and (select published from app.gallery_items where storage_path like '%/owner-upload.jpg'),
  '16f re-running the migration keeps an owner-edited headline and owner-uploaded photos');
update app.salons set tagline = 'Your Beauty. Your Style. Your Special Moment.' where slug = 'shahina-ahmed';
delete from app.gallery_items where storage_path like '%/owner-upload.jpg';
set role anon; select pg_temp.login(null);
select pg_temp.check(jsonb_array_length(public.salon_public_gallery('shahina-ahmed')->'items') = 4, '16g the public gallery returns exactly the four featured photos');
reset role;
\i ../../supabase/migrations/20261014050000_client_feedback_round2.sql
\i ../../supabase/migrations/20261014050000_client_feedback_round2.sql
select pg_temp.check((select display_name from app.professionals where slug = 'mi-hijabby-sabiha') = 'Sabiha Patel'
  and (select specialty from app.professionals where slug = 'shirin-jal') = 'Hair and Makeup Artist / Hijab Stylist'
  and (select specialty from app.professionals where slug = 'mi-hijabby-sabiha') = 'Hijab Stylist',
  '16h Sabiha Patel and the four roles are in place (re-run safe)');
select pg_temp.check((select count(*) from app.services sv join app.professionals p on p.id = sv.professional_id
                       where p.slug = 'shahina-ahmed' and sv.name = 'Training' and sv.price_kind = 'enquire' and not sv.bookable_online) = 1
  and (select count(*) from app.services where description like '%for parties and occasions%' or description like 'Bridal styling%') = 0
  and (select description from app.services sv join app.professionals p on p.id = sv.professional_id where p.slug = 'shahina-ahmed' and sv.name = 'Party Hair') = 'Hair extensions available at an extra cost',
  '16i Training is enquiry-only (one row), old descriptions cleared, extension note kept');
select pg_temp.check((select caption from app.gallery_items where storage_path = '/gallery/shahina-ahmed/featured-1.jpg') = 'Makeup by Shahina Ahmed, hijab by Sabiha Patel'
  and (select sort_order from app.gallery_items where storage_path = '/gallery/shahina-ahmed/featured-1.jpg') = 1,
  '16j Shahina photo is first and credits hijab by Sabiha Patel');
-- (run.sh re-applies every migration, restoring the original notify_booking; re-apply the email one first)
\i ../../supabase/migrations/20261014110000_client_feedback_round3c_email.sql
set role anon; select pg_temp.login(null);

select public.salon_public_slots('shahina-ahmed', 'sofia-mua', :'s_sofia_makeup', :'d1') as sl \gset
select pg_temp.check(jsonb_array_length((:'sl'::jsonb)->'slots') = 29, '17 60-min service 10:00-18:00 gives 29 start times', :'sl'::jsonb);
select pg_temp.check((select bool_and(x ?& array['time','label'] and (select count(*) from jsonb_object_keys(x)) = 2)
                      from jsonb_array_elements((:'sl'::jsonb)->'slots') x), '18 slots expose only time + label');
select pg_temp.check((public.salon_public_slots('shahina-ahmed', 'sofia-mua', :'s_sofia_bridal', :'d1'))->>'error' = 'enquiry_only', '19 bridal cannot be booked online');
select pg_temp.check((public.salon_public_slots('shahina-ahmed', 'sofia-mua', :'s_shirin_hair', :'d1'))->>'error' = 'service_not_found', '20 service must belong to the chosen professional');
select pg_temp.check(jsonb_array_length((public.salon_public_days('shahina-ahmed', 'sofia-mua', :'s_sofia_makeup', null, 14))->'days') >= 13, '21 day picker returns open days');

-- booking
select public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d1','time','11:00','name','Amira Khan','phone','07700 900111','email','amira@example.com','note','Soft glam, please',
  'idempotency_key','idem-public-0000000001')) as b1 \gset
select pg_temp.check((:'b1'::jsonb)->>'ok' = 'true' and (:'b1'::jsonb)->>'status' = 'pending' and length((:'b1'::jsonb)->>'manage_token') > 20,
  '22 public booking is PROVISIONAL (pending) with a private manage link', :'b1'::jsonb);
select pg_temp.check((:'b1'::jsonb)->>'price_label' = '£50', '23 price computed on the server');
select pg_temp.check((public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d1','time','11:00','name','Amira Khan','phone','07700 900111','email','amira@example.com','note','Soft glam, please',
  'idempotency_key','idem-public-0000000001')))->>'duplicate' = 'true', '24 double-submit returns the same booking');
select pg_temp.check((public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d1','time','11:30','name','Other Person','phone','07700 900222','idempotency_key','idem-public-0000000002')))->>'error' = 'slot_taken',
  '25 overlapping time refused (pending holds the slot)');
select pg_temp.check((public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d1','time','12:00','name','Other Person','phone','07700 900222','idempotency_key','idem-public-0000000003')))->>'error' = 'slot_taken',
  '26 15-min buffer respected (11:00 + 60 + 15 → 12:15)');
select pg_temp.check((public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d1','time','12:15','name','Other Person','phone','07700 900222','idempotency_key','idem-public-0000000004')))->>'ok' = 'true',
  '27 slot right after the buffer is free');
select pg_temp.check((public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d1','time','14:00','name','Bot','phone','07700 900333','company','Acme','idempotency_key','idem-public-0000000005')))->>'error' = 'rejected',
  '28 honeypot field rejects bots');
select pg_temp.check((public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d1','time','14:00','name','No Phone','phone','123','idempotency_key','idem-public-0000000006')))->>'error' = 'phone_required',
  '29 invalid phone refused');
select pg_temp.check((public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',to_char((now() at time zone 'Europe/London')::date, 'YYYY-MM-DD'),'time',to_char((now() at time zone 'Europe/London') + interval '30 minutes', 'HH24:MI'),
  'name','Rush','phone','07700 900444','idempotency_key','idem-public-0000000007')))->>'ok' = 'false',
  '30 minimum notice enforced');
select pg_temp.check((public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d1','time','19:00','name','Late','phone','07700 900444','idempotency_key','idem-public-0000000008')))->>'error' = 'slot_unavailable',
  '31 outside working hours refused');
select pg_temp.check((public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d1','time','15:00','name','x','phone','07700 900444','idempotency_key','idem-public-0000000009')))->>'error' = 'name_required',
  '32 name required');
-- same customer books Shirin too (separate client record per professional)
select public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','shirin-jal','service',:'s_shirin_hair',
  'date',:'d1','time','11:00','name','Amira Khan','phone','+447700900111','idempotency_key','idem-public-0000000010')) as b2 \gset
select pg_temp.check((:'b2'::jsonb)->>'ok' = 'true', '33 same time with a different professional is allowed');
select public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','mi-hijabby-sabiha','service',:'s_sabiha_hijab',
  'date',:'d2','time','10:00','name','Noor Ali','phone','07700 900555','idempotency_key','idem-public-0000000011')) as b3 \gset
select pg_temp.check((:'b3'::jsonb)->>'ok' = 'true', '34 Sabiha booking');
select pg_temp.check((public.salon_public_enquiry('shahina-ahmed', jsonb_build_object('professional','shirin-jal','name','Hana Bride',
  'phone','07700 900666','event_date', to_char(now() + interval '200 days','YYYY-MM-DD'),'message','Bridal hijab and makeup',
  'idempotency_key','idem-enquiry-000000001')))->>'ok' = 'true', '35 bridal enquiry saved');
select pg_temp.check((public.salon_public_enquiry('shahina-ahmed', jsonb_build_object('professional','any','name','Zara Any',
  'phone','07700 900777','idempotency_key','idem-enquiry-000000002')))->>'ok' = 'true', '36 no-preference enquiry saved');

-- grants: anon cannot reach private functions or tables
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_bookings(%L)$$, :'salon'))->>'state') = '42501', '37 anon cannot call dashboard functions');
select pg_temp.check((pg_temp.q($$select to_jsonb(count(*)) from app.bookings$$)->>'state') = '42501', '38 anon cannot read tables');
select pg_temp.check((pg_temp.q($$select public.salon_internal_invite_accept('x', gen_random_uuid(), 'a@b.co', 'x')$$)->>'state') = '42501', '39 anon cannot call internal functions');

-- ---------------------------------------------------------------- 3. scoped dashboards
reset role; set role authenticated;
select pg_temp.login(:'u_strange');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_bookings(%L)$$, :'salon'))->>'err') = 'forbidden', '40 signed-in user without membership is refused');
select pg_temp.check((pg_temp.q($$select to_jsonb(count(*)) from app.bookings$$)->>'state') = '42501', '41 authenticated cannot read tables directly');
select pg_temp.check((pg_temp.q($$select public.salon_internal_invite_check('x','a@b.co')$$)->>'state') = '42501', '42 authenticated cannot call internal functions');

select pg_temp.login(:'u_owner');
select public.salon_dash_bookings(:'salon') as all_b \gset
select pg_temp.check(jsonb_array_length((:'all_b'::jsonb)->'items') = 4, '43 owner sees every profile''s bookings', :'all_b'::jsonb);
select (public.salon_dash_bookings(:'salon', :'p_sofia'))->'items' as own_b_owner \gset

select pg_temp.login(:'u_sofia');
select public.salon_dash_bookings(:'salon') as sofia_b \gset
select pg_temp.check(jsonb_array_length((:'sofia_b'::jsonb)->'items') = 2
  and (select bool_and(x->>'professional_id' = :'p_sofia') from jsonb_array_elements((:'sofia_b'::jsonb)->'items') x),
  '44 Sofia sees only her own bookings');
select pg_temp.check((:'sofia_b'::jsonb)->'items' = :'own_b_owner'::jsonb, '45 owner filtered to Sofia == Sofia''s own view');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_bookings(%L, %L)$$, :'salon', :'p_shirin'))->>'err') = 'forbidden',
  '46 Sofia cannot ask for Shirin''s bookings by changing the filter');
select pg_temp.check(jsonb_array_length((public.salon_dash_bookings(:'salon', null, null, null, null, '900111'))->'items') = 1,
  '47 Sofia''s phone search never returns Shirin''s matching booking');

reset role;
select id as bk_shirin from app.bookings where ref = (:'b2'::jsonb)->>'ref' \gset
select id as bk_sofia from app.bookings where ref = (:'b1'::jsonb)->>'ref' \gset
select id as bk_sabiha from app.bookings where ref = (:'b3'::jsonb)->>'ref' \gset
select client_id as cl_shirin from app.bookings where id = :'bk_shirin' \gset
select client_id as cl_sofia from app.bookings where id = :'bk_sofia' \gset
select pg_temp.check(:'cl_shirin' <> :'cl_sofia', '48 same person = separate client record per professional');
set role authenticated; select pg_temp.login(:'u_sofia');

select pg_temp.check((pg_temp.q(format($$select public.salon_dash_booking(%L)$$, :'bk_shirin'))->>'err') = 'not_found', '49 Sofia cannot open Shirin''s booking (looks non-existent)');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_booking(%L)$$, gen_random_uuid()))->>'err') = 'not_found', '50 ...same error as a booking that does not exist');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_booking_action(%L, 'cancel')$$, :'bk_shirin'))->>'err') = 'not_found', '51 Sofia cannot cancel Shirin''s booking');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_booking_note(%L, 'x')$$, :'bk_shirin'))->>'err') = 'not_found', '52 Sofia cannot write notes on Shirin''s booking');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_client(%L)$$, :'cl_shirin'))->>'err') = 'not_found', '53 Sofia cannot open Shirin''s client record');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_client_save(%L, '{"notes":"x"}')$$, :'cl_shirin'))->>'err') = 'not_found', '54 Sofia cannot edit Shirin''s client');
select pg_temp.check((select bool_and(x->>'professional_id' = :'p_sofia') from jsonb_array_elements((public.salon_dash_clients(:'salon'))->'items') x),
  '55 Sofia''s client list contains only her clients');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_clients(%L, %L)$$, :'salon', :'p_shirin'))->>'err') = 'forbidden', '56 client list filter cannot be widened');
select public.salon_dash_client_save(:'cl_sofia', '{"notes":"Prefers soft glam. PRIVATE-SOFIA-NOTE"}') as _ \gset
select pg_temp.check((select count(*) from jsonb_array_elements((public.salon_dash_messages(:'salon'))->'items') x
                      where x->>'professional_id' <> :'p_sofia') = 0, '57 Sofia''s messages are scoped');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_messages(%L, %L)$$, :'salon', :'p_shirin'))->>'err') = 'forbidden', '58 messages filter cannot be widened');
select pg_temp.check((select count(*) from jsonb_array_elements((public.salon_dash_enquiries(:'salon'))->'items')) = 0, '59 Sofia sees no other profile''s / unassigned enquiries');
select pg_temp.check((pg_temp.q(format($$select public.salon_owner_team(%L)$$, :'salon'))->>'err') = 'forbidden', '60 staff cannot open team admin');
select pg_temp.check((pg_temp.q(format($$select public.salon_owner_audit(%L)$$, :'salon'))->>'err') = 'forbidden', '61 staff cannot read audit trail');
select pg_temp.check((pg_temp.q(format($$select public.salon_owner_settings_save(%L, '{"booking_mode":"live"}')$$, :'salon'))->>'err') = 'forbidden', '62 staff cannot change salon settings');
select pg_temp.check((select jsonb_array_length((public.salon_me())#>'{memberships,0,professionals}'))  = 1, '63 staff session lists only their own profile');
select pg_temp.check((select (public.salon_dash_overview(:'salon'))->'by_professional') = 'null'::jsonb, '64 staff overview has no per-profile breakdown');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_overview(%L, %L)$$, :'salon', :'p_shirin'))->>'err') = 'forbidden', '65 overview metrics cannot be widened');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_report(%L, %L)$$, :'salon', :'p_shirin'))->>'err') = 'forbidden', '66 report cannot be widened');

select pg_temp.login(:'u_shirin');
select pg_temp.check(position('PRIVATE-SOFIA-NOTE' in (public.salon_dash_client(:'cl_shirin'))::text) = 0, '67 Sofia''s client note never reaches Shirin');
select pg_temp.login(:'u_owner');
select pg_temp.check(jsonb_array_length((public.salon_dash_enquiries(:'salon'))->'items') = 2, '68 owner sees all enquiries incl. no-preference');
select pg_temp.login(:'u_shirin');
select pg_temp.check(jsonb_array_length((public.salon_dash_enquiries(:'salon'))->'items') = 1, '69 Shirin sees only the enquiry addressed to her');

-- ---------------------------------------------------------------- 4. confirm / decline workflow
select pg_temp.login(:'u_sofia');
select (public.salon_dash_booking(:'bk_sofia'))#>>'{booking,version}' as v_sofia \gset
select pg_temp.check((public.salon_dash_booking_action(:'bk_sofia', 'confirm', null, :'v_sofia'::int))#>>'{booking,status}' = 'confirmed', '70 Sofia confirms her request');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_booking_action(%L, 'decline', null, %s)$$, :'bk_sofia', :'v_sofia'))->>'err') = 'stale', '71 stale version refused');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_booking_action(%L, 'complete')$$, :'bk_sofia'))->>'err') = 'not_started', '72 cannot complete before it starts');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_booking_action(%L, 'confirm')$$, :'bk_sofia'))->>'err') = 'invalid_transition', '73 cannot confirm twice');
select pg_temp.check(exists (select 1 from jsonb_array_elements((public.salon_dash_booking(:'bk_sofia'))->'messages') x
                    where x->>'purpose' = 'confirmed' and x->>'status' = 'not_connected'), '74 confirmation message recorded as Not Connected (nothing sent)');
select pg_temp.login(:'u_sabiha');
select pg_temp.check((public.salon_dash_booking_action(:'bk_sabiha', 'decline', 'Fully booked that morning'))#>>'{booking,status}' = 'declined', '75 Sabiha declines her request');
reset role; set role anon; select pg_temp.login(null);
select pg_temp.check((public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','mi-hijabby-sabiha','service',:'s_sabiha_hijab',
  'date',:'d2','time','10:00','name','Someone Else','phone','07700 900888','idempotency_key','idem-public-0000000012')))->>'ok' = 'true',
  '76 declined booking releases the slot');

-- ---------------------------------------------------------------- 5. reschedule / reassign
reset role; set role authenticated; select pg_temp.login(:'u_sofia');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_booking_reschedule(%L, %L, '15:00', %L, %L)$$, :'bk_sofia', :'d1', :'p_shirin', :'s_shirin_hair'))->>'err') = 'forbidden',
  '77 staff cannot reassign to another professional');
select pg_temp.check((public.salon_dash_booking_reschedule(:'bk_sofia', :'d1', '15:00'))#>>'{booking,local_time}' = '15:00', '78 Sofia reschedules her own booking');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_booking_reschedule(%L, %L, '12:00')$$, :'bk_sofia', :'d1'))->>'err') = 'slot_taken',
  '79 reschedule onto an occupied slot refused');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_booking_reschedule(%L, %L, '07:00', null, null, true)$$, :'bk_sofia', :'d1'))->>'err') is null,
  '80 explicit outside-hours override works for the professional');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_booking_reschedule(%L, %L, '12:30', null, null, true)$$, :'bk_sofia', :'d1'))->>'err') = 'slot_taken',
  '81 override never allows an overlap');
select pg_temp.login(:'u_owner');
select pg_temp.check((public.salon_dash_booking_reschedule(:'bk_sofia', :'d1', '15:00', :'p_shirin', :'s_shirin_hair'))#>>'{booking,professional_id}' = :'p_shirin',
  '82 owner reassigns Sofia''s booking to Shirin (revalidated)');
select pg_temp.login(:'u_sofia');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_booking(%L)$$, :'bk_sofia'))->>'err') = 'not_found', '83 reassigned booking leaves Sofia''s view');
select pg_temp.login(:'u_shirin');
select pg_temp.check((public.salon_dash_booking(:'bk_sofia'))#>>'{booking,status}' = 'confirmed'
  and position('PRIVATE-SOFIA-NOTE' in (public.salon_dash_booking(:'bk_sofia'))::text) = 0, '84 ...appears for Shirin without Sofia''s private notes');
select pg_temp.login(:'u_owner');
select pg_temp.check(exists (select 1 from jsonb_array_elements((public.salon_owner_audit(:'salon'))->'items') x where x->>'action' = 'booking.reassigned'),
  '85 reassignment recorded in the audit trail');

-- ---------------------------------------------------------------- 6. services / hours / time off
select pg_temp.login(:'u_sofia');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_service_save(%L, jsonb_build_object('id', %L, 'price_pence', 1))$$, :'salon', :'s_sofia_makeup'))->>'err') = 'forbidden',
  '86 staff cannot change prices');
select pg_temp.check((public.salon_dash_service_save(:'salon', jsonb_build_object('id', :'s_sofia_makeup', 'duration_min', 75)))->>'ok' = 'true', '87 staff can change own duration');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_service_save(%L, jsonb_build_object('id', %L, 'duration_min', 10))$$, :'salon', :'s_shirin_hair'))->>'err') = 'not_found',
  '88 staff cannot touch another profile''s service');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_service_save(%L, jsonb_build_object('id', %L, 'professional_id', %L))$$, :'salon', :'s_sofia_makeup', :'p_shirin'))->>'err') = 'forbidden',
  '89 ownership field cannot be changed');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_hours_save(%L, %L, '[]')$$, :'salon', :'p_shirin'))->>'err') = 'forbidden', '90 staff cannot edit another profile''s hours');
select pg_temp.check((public.salon_dash_time_off_add(:'salon', :'p_sofia', ((:'d2')::date + time '13:00') at time zone 'Europe/London',
                       ((:'d2')::date + time '18:00') at time zone 'Europe/London', 'Wedding'))->>'ok' = 'true', '91 Sofia adds time off');
select pg_temp.check(not exists (select 1 from jsonb_array_elements((public.salon_dash_slots(:'salon', :'p_sofia', :'s_sofia_makeup', :'d2'))->'slots') x
                     where x->>'time' >= '12:00'), '92 time off removes slots (incl. ones overlapping the start)');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_time_off_add(%L, null, now() + interval '1 day', now() + interval '2 days')$$, :'salon'))->>'err') = 'forbidden',
  '93 only the owner can close the whole salon');
select pg_temp.login(:'u_owner');
select pg_temp.check((public.salon_dash_service_save(:'salon', jsonb_build_object('id', :'s_sofia_makeup', 'details_confirmed', true)))->>'ok' = 'true', '94 owner confirms service details');

-- ---------------------------------------------------------------- 7. reports reconcile
select pg_temp.check(
  ((public.salon_dash_report(:'salon', null, :'d1', :'d2'))#>>'{totals,total}')::int =
  (select sum(((public.salon_dash_report(:'salon', p.id, :'d1', :'d2'))#>>'{totals,total}')::int)
     from unnest(array[:'p_sofia', :'p_shirin', :'p_sabiha']::uuid[]) p(id))
  and ((public.salon_dash_report(:'salon', null, :'d1', :'d2'))#>>'{totals,booked_value_pence}')::int =
  (select sum(((public.salon_dash_report(:'salon', p.id, :'d1', :'d2'))#>>'{totals,booked_value_pence}')::int)
     from unnest(array[:'p_sofia', :'p_shirin', :'p_sabiha']::uuid[]) p(id)),
  '95 combined report == sum of per-profile reports');

-- ---------------------------------------------------------------- 8. manual booking + customer link
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_booking_create(%L, %s)$$, :'salon',
  quote_literal(jsonb_build_object('professional_id', :'p_sofia', 'service_id', :'s_shirin_hair', 'date', :'d1', 'time', '16:00', 'name', 'Walk In', 'phone', '07700 900999')::text)))->>'err') = 'service_not_found',
  '96 manual booking validates service ownership');
select pg_temp.check((public.salon_dash_booking_create(:'salon', jsonb_build_object('professional_id', :'p_sofia', 'service_id', :'s_sofia_saree',
  'date', :'d1', 'time', '16:30', 'name', 'Walk In', 'phone', '07700 900999', 'source', 'phone')))#>>'{booking,status}' = 'confirmed', '97 owner creates a confirmed phone booking');
reset role; set role anon; select pg_temp.login(null);
select pg_temp.check((public.salon_public_manage((:'b2'::jsonb)->>'manage_token'))#>>'{booking,ref}' = (:'b2'::jsonb)->>'ref', '98 manage link shows the booking');
select pg_temp.check((public.salon_public_manage((:'b2'::jsonb)->>'manage_token'))#>>'{booking,client_phone}' is null, '99 manage link exposes no contact details');
select pg_temp.check((public.salon_public_manage('not-a-real-token-xxxxxxxxxxxxxxxx'))->>'error' = 'link_invalid', '100 forged link refused');
select pg_temp.check((public.salon_public_manage_cancel((:'b2'::jsonb)->>'manage_token'))#>>'{booking,status}' = 'cancelled', '101 customer cancels with the link');

-- ---------------------------------------------------------------- 9. disable access, storage, expiry
reset role; set role authenticated; select pg_temp.login(:'u_owner');
select (select x->>'membership_id' from jsonb_array_elements((public.salon_owner_team(:'salon'))->'professionals') p,
        jsonb_array_elements(p->'members') x where p->>'id' = :'p_sabiha') as m_sabiha \gset
select pg_temp.check((public.salon_owner_member_status(:'m_sabiha', 'disabled'))->>'ok' = 'true', '102 owner disables a login');
select pg_temp.login(:'u_sabiha');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_bookings(%L)$$, :'salon'))->>'err') = 'forbidden', '103 disabled login loses access immediately');
select pg_temp.login(:'u_sofia');
select pg_temp.check(app.storage_can_write(:'salon' || '/' || :'p_sofia' || '/look1.jpg') and not app.storage_can_write(:'salon' || '/' || :'p_shirin' || '/look1.jpg')
  and not app.storage_can_write('../' || :'p_sofia' || '/x.jpg'), '104 storage: own folder only');
select pg_temp.check((pg_temp.q(format($$select public.salon_dash_gallery_add(%L, %L, %L)$$, :'salon', :'p_sofia', :'salon' || '/' || :'p_shirin' || '/x.jpg'))->>'err') = 'invalid_path',
  '105 gallery entry must point at own folder');
select pg_temp.check((public.salon_dash_gallery_add(:'salon', :'p_sofia', :'salon' || '/' || :'p_sofia' || '/look1.jpg', 'image', 'Soft glam'))->>'ok' = 'true', '106 gallery item added');
reset role; set role anon;
select pg_temp.check(exists (select 1 from jsonb_array_elements((public.salon_public_gallery('shahina-ahmed', 'sofia-mua'))->'items') x where x->>'storage_path' like '%/look1.jpg'), '107 published gallery item is public');
reset role;
-- a pending request whose time has passed becomes expired
insert into app.clients (salon_id, professional_id, name, phone) values (:'salon', :'p_shirin', 'Past Pending', '+447700900123');
insert into app.bookings (salon_id, professional_id, service_id, client_id, ref, starts_at, ends_at, block_end, status, service_name, duration_min, buffer_min, price_pence, price_kind)
select :'salon', :'p_shirin', :'s_shirin_hijab', c.id, 'PASTPD', now() - interval '3 hours', now() - interval '150 minutes', now() - interval '135 minutes', 'pending', 'Party Hijab', 30, 15, 3000, 'fixed'
from app.clients c where c.phone = '+447700900123';
set role authenticated; select pg_temp.login(:'u_shirin');
select public.salon_dash_overview(:'salon') as _ \gset
reset role;
select pg_temp.check((select status from app.bookings where ref = 'PASTPD') = 'expired', '108 unconfirmed past request expires');

-- ---------------------------------------------------------------- 10. DST (Europe/London)
set role authenticated; select pg_temp.login(:'u_owner');
select pg_temp.check(jsonb_array_length((public.salon_dash_slots(:'salon', :'p_shirin', :'s_shirin_hair', '2026-10-25'))->'slots') = 29
  and jsonb_array_length((public.salon_dash_slots(:'salon', :'p_shirin', :'s_shirin_hair', '2027-03-28'))->'slots') = 29,
  '109 clock-change Sundays (Oct + Mar) keep a normal 10:00-18:00 grid');
select (public.salon_dash_booking_create(:'salon', jsonb_build_object('professional_id', :'p_shirin', 'service_id', :'s_shirin_hair',
  'date', '2026-10-25', 'time', '10:00', 'name', 'Dst Test', 'phone', '07700 901000')))#>>'{booking,id}' as dst1 \gset
select (public.salon_dash_booking_create(:'salon', jsonb_build_object('professional_id', :'p_shirin', 'service_id', :'s_shirin_hair',
  'date', '2026-10-24', 'time', '10:00', 'name', 'Dst Test', 'phone', '07700 901000')))#>>'{booking,id}' as dst0 \gset
reset role;
select pg_temp.check((select starts_at from app.bookings where id = :'dst1') = '2026-10-25 10:00:00+00'
  and (select starts_at from app.bookings where id = :'dst0') = '2026-10-24 09:00:00+00'
  and (select ends_at - starts_at from app.bookings where id = :'dst1') = interval '60 minutes',
  '110 10:00 local stored correctly either side of the clock change (GMT vs BST)');

select pg_temp.check((select count(*) from app.bookings b1, app.bookings b2 where b1.id < b2.id and b1.professional_id = b2.professional_id
   and b1.status in ('pending','confirmed') and b2.status in ('pending','confirmed')
   and tstzrange(b1.starts_at, b1.block_end) && tstzrange(b2.starts_at, b2.block_end)) = 0, '111 no overlapping active bookings exist anywhere');

reset role;
\i ../../supabase/migrations/20261014090000_client_feedback_round3a.sql
select pg_temp.check((select app.message_body('confirmed', sa, pr, k, cl) like '%at Shahina Ahmed, 199 Preston New Road, Blackburn, BB2 6BN. Ref%'
                        from app.bookings k join app.salons sa on sa.id = k.salon_id join app.professionals pr on pr.id = k.professional_id
                        join app.clients cl on cl.id = k.client_id limit 1),
  '16k customer texts include the studio address');

-- 16l confirmation text: contact number only when the salon has one (no placeholder ever)
\i ../../supabase/migrations/20261014100000_client_feedback_round3b_contact.sql
select pg_temp.check(
  (select app.message_body('confirmed', sa, pr, k, cl) not like '%Questions?%'
                        from app.bookings k join app.salons sa on sa.id = k.salon_id join app.professionals pr on pr.id = k.professional_id
                        join app.clients cl on cl.id = k.client_id where sa.phone is null limit 1) is not false,
  '16l no contact line while salon phone is empty');
update app.salons set phone = '+44 1254 000000' where phone is null;
select pg_temp.check(
  (select app.message_body('confirmed', sa, pr, k, cl) like '%Questions? Call +44 1254 000000.%'
                        from app.bookings k join app.salons sa on sa.id = k.salon_id join app.professionals pr on pr.id = k.professional_id
                        join app.clients cl on cl.id = k.client_id limit 1),
  '16m confirmation text includes salon phone when set');

-- 16n customer messages are also recorded by email when the client gave an email address
select pg_temp.check((select email_connected from app.salons limit 1) = false, '16n email sending is off by default');
select pg_temp.check(
  exists (select 1 from app.notifications e where e.channel = 'email' and e.audience = 'customer' and e.purpose = 'request_received'
            and e.to_addr = 'amira@example.com' and e.status = 'not_connected')
  and not exists (select 1 from app.notifications e where e.channel = 'email'
            and not exists (select 1 from app.notifications s2 where s2.booking_id = e.booking_id and s2.channel = 'sms'
                              and s2.purpose = e.purpose and s2.audience = 'customer' and s2.body = e.body))
  and not exists (select 1 from app.notifications e where e.channel = 'email' and e.audience <> 'customer'),
  '16o customer email rows exist (not sent while email is off), match their text, and are never made for artists');

-- =====================================================================
-- Deposit flow (round 4): accept -> deposit requested -> received -> confirmed; expiry releases the slot
-- =====================================================================
reset role;
-- (the 16k/16l re-applications above restore an older message_body; re-apply the deposit migration last)
\i ../../supabase/migrations/20261014120000_deposit_flow.sql
\i ../../supabase/migrations/20261015010000_deposit_message_format.sql
select pg_temp.check((select count(*) from app.services where category in ('hair','hijab') and price_kind <> 'enquire' and deposit_pence <> 1000) = 0
  and (select count(*) from app.services where category in ('makeup','saree','bridal')) > 0
  and (select count(*) from app.services where category in ('makeup','saree','bridal') and deposit_pence <> 0) = 0,
  'D1 hair and hijab default to a 10 pound deposit; makeup, saree and bridal are left for the owner to set');

set role authenticated; select pg_temp.login(:'u_owner');
select public.salon_owner_deposits_save(:'salon', jsonb_build_object('hours', 24,
  'services', jsonb_build_array(jsonb_build_object('id', :'s_sofia_makeup', 'deposit_pence', 1000)))) as dsave \gset
reset role;
select pg_temp.check((:'dsave'::jsonb)->>'ok' = 'true'
  and (select deposit_pence from app.services where id = :'s_sofia_makeup') = 1000, 'D2 owner sets a per-service deposit');

set role anon; select pg_temp.login(null);
select public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d1','time','15:00','name','Dina Deposit','phone','07700 900801','email','dina@example.com',
  'idempotency_key','idem-deposit-000000001')) as dk1 \gset
select (:'dk1'::jsonb)->>'manage_token' as dk1_token \gset
reset role;
select id as dk1_id from app.bookings where ref = (:'dk1'::jsonb)->>'ref' \gset
select pg_temp.check((:'dk1'::jsonb)->>'ok' = 'true'
  and (select status || '/' || deposit_status || '/' || deposit_pence from app.bookings where id = :'dk1_id') = 'pending/none/1000',
  'D3 booking snapshots the deposit and starts pending with no deposit asked yet', :'dk1'::jsonb);

set role authenticated; select pg_temp.login(:'u_sofia');
select pg_temp.q(format($$select public.salon_dash_booking_action(%L, 'confirm')$$, :'dk1_id')) as dr0 \gset
reset role;
select pg_temp.check((:'dr0'::jsonb)->>'err' = 'deposit_details_missing'
  and (select status from app.bookings where id = :'dk1_id') = 'pending',
  'D4 cannot ask for a deposit until the owner has typed the payment details', :'dr0'::jsonb);

set role authenticated; select pg_temp.login(:'u_owner');
select public.salon_owner_deposits_save(:'salon', jsonb_build_object('instructions',
  'Pay to: Test Bank, sort code 00-00-00, account 12345678, name Test Studio Ltd.')) as dsave2 \gset
select pg_temp.login(:'u_sofia');
select public.salon_dash_booking_action(:'dk1_id', 'confirm') as dr1 \gset
reset role;
select pg_temp.check((:'dr1'::jsonb)->>'deposit_requested' = 'true'
  and (select status || '/' || deposit_status from app.bookings where id = :'dk1_id') = 'pending/requested'
  and (select deposit_due_at between now() + interval '23 hours 55 minutes' and now() + interval '24 hours 5 minutes'
         from app.bookings where id = :'dk1_id'),
  'D5 accepting keeps the booking pending, holds the slot and starts a 24 hour deposit window', :'dr1'::jsonb);
select pg_temp.check((select body like '%non refundable deposit%' and body like '%£10%' and body like '%within 24 hours%'
                        and body like '%deducted on the day%' and body like '%Test Bank, sort code 00-00-00%'
                        and body like '%ref ' || b.ref || '%' and body not like '%{%'
                        from app.notifications n join app.bookings b on b.id = n.booking_id
                       where n.booking_id = :'dk1_id' and n.purpose = 'deposit_request' and n.channel = 'sms'),
  'D6 deposit request text carries amount, wording, payment details and reference');
select pg_temp.check(exists (select 1 from app.notifications where booking_id = :'dk1_id' and purpose = 'deposit_request'
                               and channel = 'email' and to_addr = 'dina@example.com'),
  'D7 the same request is recorded by email too');
select pg_temp.check((select count(*) from app.notifications where booking_id = :'dk1_id' and purpose = 'confirmed') = 0,
  'D8 no confirmation text before the deposit is received');

set role anon; select pg_temp.login(null);
select public.salon_public_manage(:'dk1_token') as mg1 \gset
select pg_temp.check((:'mg1'::jsonb)#>>'{booking,deposit_instructions}' like 'Pay to: Test Bank%'
  and (:'mg1'::jsonb)#>>'{booking,deposit_label}' = '£10', 'D9 customer manage page shows the payment details while a deposit is due');
select pg_temp.check((public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d1','time','15:00','name','Other Person','phone','07700 900802','idempotency_key','idem-deposit-000000002')))->>'error' = 'slot_taken',
  'D10 the slot stays held while the deposit is awaited');

set role authenticated; select pg_temp.login(:'u_sofia');
select public.salon_dash_booking_action(:'dk1_id', 'deposit_received') as dr2 \gset
reset role;
select pg_temp.check((:'dr2'::jsonb)->>'ok' = 'true'
  and (select status || '/' || deposit_status from app.bookings where id = :'dk1_id') = 'confirmed/received'
  and exists (select 1 from app.notifications where booking_id = :'dk1_id' and purpose = 'deposit_received'
                and body like '%received your £10 deposit%' and body like '%is confirmed%'),
  'D11 deposit received confirms the booking and tells the customer', :'dr2'::jsonb);

-- expiry: a second request, deposit never paid (uses the last free start time of that day)
set role anon; select pg_temp.login(null);
select (public.salon_public_slots('shahina-ahmed', 'sofia-mua', :'s_sofia_makeup', :'d1'))->'slots'->-1->>'time' as dk2_time \gset
select public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d1','time',:'dk2_time','name','Eli Expire','phone','07700 900803',
  'idempotency_key','idem-deposit-000000003')) as dk2 \gset
reset role;
select id as dk2_id from app.bookings where ref = (:'dk2'::jsonb)->>'ref' \gset
set role authenticated; select pg_temp.login(:'u_sofia');
select public.salon_dash_booking_action(:'dk2_id', 'confirm') as dr3 \gset
reset role;
update app.bookings set deposit_due_at = now() - interval '1 minute' where id = :'dk2_id';
select app.expire_all();
select pg_temp.check((select status from app.bookings where id = :'dk2_id') = 'expired'
  and exists (select 1 from app.notifications where booking_id = :'dk2_id' and purpose = 'deposit_expired' and channel = 'sms')
  and (select status from app.bookings where id = :'dk1_id') = 'confirmed',
  'D12 unpaid deposit expires the booking and tells the customer; paid bookings are untouched');
set role anon; select pg_temp.login(null);
select pg_temp.check((public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d1','time',:'dk2_time','name','Next Customer','phone','07700 900804','idempotency_key','idem-deposit-000000004')))->>'ok' = 'true',
  'D13 the expired slot is released for other customers');

-- permissions and privacy
set role authenticated; select pg_temp.login(:'u_sofia');
select pg_temp.q(format($$select public.salon_owner_deposits_save(%L, '{"hours": 48}')$$, :'salon')) as dperm \gset
select pg_temp.check((:'dperm'::jsonb) ? 'err', 'D14 artists cannot change deposit settings', :'dperm'::jsonb);
set role anon; select pg_temp.login(null);
select pg_temp.q(format($$select public.salon_owner_deposits(%L)$$, :'salon')) as dperm2 \gset
select pg_temp.check((:'dperm2'::jsonb) ? 'err', 'D15 visitors cannot read deposit settings', :'dperm2'::jsonb);
reset role;
select pg_temp.check(not exists (select 1 from app.audit_log where detail::text like '%sort code%' or detail::text like '%12345678%'),
  'D16 payment details never appear in the audit log');

-- private phone: only after the booking is confirmed, never public
update app.salons set private_phone = '+44 7700 900000';
select pg_temp.check((select app.message_body('confirmed', sa, pr, k, cl) like '%Questions? Call +44 7700 900000.%'
                        and app.message_body('deposit_received', sa, pr, k, cl) like '%Questions? Call +44 7700 900000.%'
                        and app.message_body('deposit_request', sa, pr, k, cl) like E'%\nMakeup Artist\n%\n+44 7700 900000'
                        and app.message_body('request_received', sa, pr, k, cl) not like '%900000%'
                        from app.bookings k join app.salons sa on sa.id = k.salon_id join app.professionals pr on pr.id = k.professional_id
                        join app.clients cl on cl.id = k.client_id where k.id = :'dk1_id'),
  'D17 the private number goes in confirmed, deposit-request and deposit-received texts, never in the provisional request text');
set role anon; select pg_temp.login(null);
select public.salon_public_profile('shahina-ahmed')::text as prof_txt \gset
select public.salon_public_manage(:'dk1_token') as mg2 \gset
select public.salon_public_book('shahina-ahmed', jsonb_build_object('professional','sofia-mua','service',:'s_sofia_makeup',
  'date',:'d2','time','10:00','name','Pia Pending','phone','07700 900805','idempotency_key','idem-deposit-000000005')) as dk3 \gset
select public.salon_public_manage((:'dk3'::jsonb)->>'manage_token') as mg3 \gset
select pg_temp.check(:'prof_txt' not like '%900000%' and :'prof_txt' not like '%Test Bank%',
  'D18 the website profile never exposes the private number or the payment details');
select pg_temp.check((:'mg2'::jsonb)#>>'{salon,private_phone}' = '+44 7700 900000' and (:'mg3'::jsonb)#>>'{salon,private_phone}' is null,
  'D19 the client sees the private number on their booking page only once confirmed');
set role authenticated; select pg_temp.login(:'u_owner');
select public.salon_owner_settings_save(:'salon', jsonb_build_object('tagline', 'Your Beauty. Your Style.', 'private_phone', '+44 7700 900000')) as ssave \gset
reset role;
select pg_temp.check((:'ssave'::jsonb)->>'ok' = 'true'
  and not exists (select 1 from app.audit_log where detail::text like '%Test Bank%' or detail::text like '%900000%' or detail::text like '%12345678%'),
  'D20 saving settings keeps payment details and the private number out of the audit log');

-- Round 5: the deposit message keeps Shahina's own layout (line breaks, her block at the bottom)
select pg_temp.check((select app.message_body('deposit_request', sa, pr, k, cl) like E'Hi %,\n\n% is available for %.\n\nPlease note all bookings take place at the studio unless discussed otherwise\n(Please see below for address)\n\nTo secure your booking please pay a £% non refundable deposit within 24 hours, which will be deducted on the day.\n\n%Please leave your ref {ref} as the payment reference.\n\n' || sa.name || E'\nMakeup Artist\n199 %'
                        from app.bookings k join app.salons sa on sa.id = k.salon_id join app.professionals pr on pr.id = k.professional_id
                        join app.clients cl on cl.id = k.client_id where k.id = :'dk1_id'),
  'D21 deposit message layout matches the client wording, line by line');
\echo ALL_TESTS_PASSED
