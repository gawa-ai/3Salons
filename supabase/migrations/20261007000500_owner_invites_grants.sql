-- =====================================================================
-- Owner administration, invitation-based provisioning, grants, storage.
-- =====================================================================

-- ---------------------------------------------------------------------
-- Invitations
-- Codes are shown once and stored only as a SHA-256 hash.
create or replace function app.create_invitation(p_salon uuid, p_role text, p_professional uuid, p_email text,
                                                 p_created_by uuid default null, p_days int default 7)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare v_code text; v_email text := lower(btrim(coalesce(p_email, ''))); i app.invitations;
begin
  if p_role not in ('owner','professional') then perform app.fail('invalid_role', 'Unknown role.'); end if;
  if not app.valid_email(v_email) then perform app.fail('email_invalid', 'Enter a valid email address.'); end if;
  if p_role = 'professional' then
    if p_professional is null or not exists (select 1 from app.professionals where id = p_professional and salon_id = p_salon) then
      perform app.fail('professional_required', 'Choose the profile this login is for.');
    end if;
    if exists (select 1 from app.memberships where salon_id = p_salon and professional_id = p_professional
               and status = 'active' and role = 'professional') then
      perform app.fail('already_has_login', 'This profile already has an active login. Disable it first to invite someone new.');
    end if;
  end if;
  -- only one open invitation per profile/role at a time
  update app.invitations set revoked_at = now()
   where salon_id = p_salon and role = p_role and professional_id is not distinct from p_professional
     and used_at is null and revoked_at is null;
  v_code := app.random_code();
  insert into app.invitations (salon_id, role, professional_id, email, code_hash, expires_at, created_by)
  values (p_salon, p_role, p_professional, v_email, app.hash_token(app.norm_code(v_code)),
          now() + make_interval(days => least(greatest(coalesce(p_days, 7), 1), 30)), p_created_by)
  returning * into i;
  perform app.audit(p_salon, p_professional, p_created_by, case when p_created_by is null then 'system' else 'owner' end,
                    'invitation.created', 'invitation', i.id::text, jsonb_build_object('role', p_role, 'email', v_email));
  return jsonb_build_object('ok', true, 'code', v_code, 'email', v_email, 'expires_at', i.expires_at, 'id', i.id);
end $$;

-- Bootstrap helper for the SQL editor only (not exposed through the API):
--   select app.create_owner_invitation('shahina-ahmed', 'owner@example.com');
create or replace function app.create_owner_invitation(p_salon_slug text, p_email text)
returns text language plpgsql volatile set search_path = '' as $$
declare s app.salons := app.resolve_salon(p_salon_slug); r jsonb;
begin
  if exists (select 1 from app.memberships where salon_id = s.id and role = 'owner' and status = 'active') then
    perform app.fail('owner_exists', 'This salon already has an active owner. Use the dashboard instead.');
  end if;
  r := app.create_invitation(s.id, 'owner', (select id from app.professionals where salon_id = s.id and slug = s.slug),
                             p_email, null, 7);
  return 'Invitation code for ' || (r->>'email') || ': ' || (r->>'code') || '  (expires ' || (r->>'expires_at') || ')';
end $$;

create or replace function app.find_invitation(p_code text, p_lock boolean)
returns app.invitations language plpgsql set search_path = '' as $$
declare i app.invitations; h text := app.hash_token(app.norm_code(p_code));
begin
  if length(app.norm_code(p_code)) <> 16 then perform app.fail('invite_invalid', 'This invitation code is not valid.'); end if;
  if p_lock then select * into i from app.invitations where code_hash = h for update;
  else select * into i from app.invitations where code_hash = h; end if;
  if i.id is null or i.revoked_at is not null then perform app.fail('invite_invalid', 'This invitation code is not valid.'); end if;
  if i.used_at is not null then perform app.fail('invite_used', 'This invitation has already been used.'); end if;
  if i.expires_at < now() then perform app.fail('invite_expired', 'This invitation has expired. Ask the owner for a new one.'); end if;
  return i;
end $$;

create or replace function app.accept_invitation(p_code text, p_user uuid, p_email text, p_name text)
returns jsonb language plpgsql volatile set search_path = '' as $$
declare i app.invitations; mem app.memberships; s app.salons;
begin
  i := app.find_invitation(p_code, true);
  if lower(btrim(coalesce(p_email, ''))) <> i.email then
    perform app.fail('invite_email_mismatch', 'Use the email address the invitation was sent to.');
  end if;
  if exists (select 1 from app.memberships where user_id = p_user and salon_id = i.salon_id) then
    perform app.fail('already_member', 'This account already has access to the salon.');
  end if;
  if i.role = 'professional' and exists (select 1 from app.memberships where salon_id = i.salon_id
       and professional_id = i.professional_id and status = 'active' and role = 'professional') then
    perform app.fail('already_has_login', 'This profile already has an active login.');
  end if;
  if i.role = 'owner' and exists (select 1 from app.memberships where salon_id = i.salon_id and role = 'owner' and status = 'active') then
    perform app.fail('owner_exists', 'This salon already has an owner.');
  end if;
  insert into app.memberships (user_id, salon_id, role, professional_id, display_name)
  values (p_user, i.salon_id, i.role, i.professional_id, app.clean_text(p_name, 80))
  returning * into mem;
  update app.invitations set used_at = now(), used_by = p_user where id = i.id;
  perform app.audit(i.salon_id, i.professional_id, p_user, i.role, 'invitation.accepted', 'membership', mem.id::text,
                    jsonb_build_object('role', i.role, 'email', i.email));
  select * into s from app.salons where id = i.salon_id;
  return jsonb_build_object('ok', true, 'role', i.role, 'salon', s.slug);
end $$;

-- Signed-in user redeems a code (e.g. an account that already existed).
create or replace function public.salon_claim_invite(p_code text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare uid uuid := auth.uid(); v_email text;
begin
  if uid is null then perform app.fail('not_signed_in', 'Please sign in.'); end if;
  perform app.rate_check('claim:' || uid::text, 10, interval '1 hour');
  select email into v_email from auth.users where id = uid;
  return app.accept_invitation(p_code, uid, v_email, null);
end $$;

-- Used only by the accept-invite Edge Function (service_role).
create or replace function public.salon_internal_invite_check(p_code text, p_email text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare i app.invitations; v_code text; v_detail text;
begin
  i := app.find_invitation(p_code, false);
  if lower(btrim(coalesce(p_email, ''))) <> i.email then
    perform app.fail('invite_email_mismatch', 'Use the email address the invitation was sent to.');
  end if;
  return jsonb_build_object('ok', true, 'role', i.role);
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

create or replace function public.salon_internal_invite_accept(p_code text, p_user uuid, p_email text, p_name text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare v_code text; v_detail text;
begin
  return app.accept_invitation(p_code, p_user, p_email, p_name);
exception when sqlstate 'P0001' then
  get stacked diagnostics v_code = message_text, v_detail = pg_exception_detail;
  return app.err_json(v_code, v_detail);
end $$;

-- ---------------------------------------------------------------------
-- Owner administration
create or replace function public.salon_owner_team(p_salon uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships;
begin
  m := app.require_owner(p_salon);
  return jsonb_build_object('ok', true,
    'professionals', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', p.id, 'slug', p.slug, 'display_name', p.display_name, 'short_name', p.short_name,
        'specialty', p.specialty, 'bio', p.bio, 'instagram_url', p.instagram_url, 'logo_path', p.logo_path,
        'color', p.color, 'sort_order', p.sort_order, 'is_public', p.is_public, 'online_booking', p.online_booking,
        'active', p.active,
        'members', (select coalesce(jsonb_agg(jsonb_build_object('membership_id', mm.id, 'role', mm.role,
                       'status', mm.status, 'email', u.email, 'last_sign_in_at', u.last_sign_in_at,
                       'is_me', mm.user_id = m.user_id) order by mm.created_at), '[]'::jsonb)
                    from app.memberships mm join auth.users u on u.id = mm.user_id
                    where mm.salon_id = p_salon and mm.professional_id = p.id),
        'invitations', (select coalesce(jsonb_agg(jsonb_build_object('id', i.id, 'email', i.email, 'role', i.role,
                           'expires_at', i.expires_at, 'created_at', i.created_at) order by i.created_at desc), '[]'::jsonb)
                        from app.invitations i where i.salon_id = p_salon and i.professional_id = p.id
                          and i.used_at is null and i.revoked_at is null and i.expires_at > now()))
        order by p.sort_order, p.display_name), '[]'::jsonb)
      from app.professionals p where p.salon_id = p_salon),
    'owners', (select coalesce(jsonb_agg(jsonb_build_object('membership_id', mm.id, 'email', u.email,
                 'status', mm.status, 'is_me', mm.user_id = m.user_id)), '[]'::jsonb)
               from app.memberships mm join auth.users u on u.id = mm.user_id
               where mm.salon_id = p_salon and mm.role = 'owner'));
end $$;

create or replace function public.salon_owner_invite(p_salon uuid, p_professional uuid, p_email text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships;
begin
  m := app.require_owner(p_salon);
  perform app.rate_check('invite:' || m.user_id::text, 30, interval '1 hour');
  -- staff logins only; the owner account is created once through the SQL bootstrap
  return app.create_invitation(p_salon, 'professional', p_professional, p_email, m.user_id, 7);
end $$;

create or replace function public.salon_owner_invite_revoke(p_invite uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare i app.invitations; m app.memberships;
begin
  select * into i from app.invitations where id = p_invite;
  if i.id is null then perform app.fail('not_found', 'Not found.'); end if;
  m := app.require_owner(i.salon_id);
  update app.invitations set revoked_at = now() where id = i.id and used_at is null;
  perform app.audit(i.salon_id, i.professional_id, m.user_id, 'owner', 'invitation.revoked', 'invitation', i.id::text);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.salon_owner_member_status(p_membership uuid, p_status text)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare t app.memberships; m app.memberships;
begin
  select * into t from app.memberships where id = p_membership;
  if t.id is null then perform app.fail('not_found', 'Not found.'); end if;
  m := app.require_owner(t.salon_id);
  if p_status not in ('active','disabled') then perform app.fail('invalid_status', 'Unknown status.'); end if;
  if t.user_id = m.user_id then perform app.fail('forbidden', 'You cannot change your own access.'); end if;
  if t.role = 'owner' then perform app.fail('forbidden', 'Owner access cannot be changed here.'); end if;
  if p_status = 'active' and exists (select 1 from app.memberships where salon_id = t.salon_id
       and professional_id = t.professional_id and status = 'active' and id <> t.id and role = 'professional') then
    perform app.fail('already_has_login', 'Another login is already active for this profile.');
  end if;
  update app.memberships set status = p_status, updated_at = now() where id = t.id;
  perform app.audit(t.salon_id, t.professional_id, m.user_id, 'owner', 'membership.' || p_status, 'membership', t.id::text);
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.salon_owner_professional_save(p_salon uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; a jsonb := coalesce(p_payload, '{}'::jsonb); p app.professionals; before jsonb;
begin
  m := app.require_owner(p_salon);
  if coalesce(a->>'id', '') = '' then
    insert into app.professionals (salon_id, slug, display_name, short_name, specialty, color, sort_order)
    values (p_salon, lower(a->>'slug'), app.clean_text(a->>'display_name', 80),
            coalesce(app.clean_text(a->>'short_name', 40), app.clean_text(a->>'display_name', 40)),
            app.clean_text(a->>'specialty', 120), coalesce(a->>'color', 'sage'), coalesce((a->>'sort_order')::int, 99))
    returning * into p;
    perform app.audit(p_salon, p.id, m.user_id, 'owner', 'professional.created', 'professional', p.id::text, to_jsonb(p));
    return jsonb_build_object('ok', true, 'id', p.id);
  end if;
  select * into p from app.professionals where id = (a->>'id')::uuid and salon_id = p_salon for update;
  if p.id is null then perform app.fail('not_found', 'Not found.'); end if;
  before := to_jsonb(p);
  update app.professionals set
    display_name = coalesce(app.clean_text(a->>'display_name', 80), display_name),
    short_name = coalesce(app.clean_text(a->>'short_name', 40), short_name),
    specialty = case when a ? 'specialty' then app.clean_text(a->>'specialty', 120) else specialty end,
    bio = case when a ? 'bio' then app.clean_text(a->>'bio', 1200) else bio end,
    instagram_url = case when a ? 'instagram_url' then app.clean_text(a->>'instagram_url', 200) else instagram_url end,
    color = coalesce(a->>'color', color),
    sort_order = coalesce((a->>'sort_order')::int, sort_order),
    is_public = coalesce((a->>'is_public')::boolean, is_public),
    online_booking = coalesce((a->>'online_booking')::boolean, online_booking),
    active = coalesce((a->>'active')::boolean, active),
    updated_at = now()
  where id = p.id returning * into p;
  if p.instagram_url is not null and p.instagram_url !~* '^https://(www\.)?instagram\.com/' then
    perform app.fail('invalid_url', 'Instagram links must start with https://www.instagram.com/');
  end if;
  perform app.audit(p_salon, p.id, m.user_id, 'owner', 'professional.updated', 'professional', p.id::text,
                    jsonb_build_object('before', before, 'after', to_jsonb(p)));
  return jsonb_build_object('ok', true, 'id', p.id);
end $$;

create or replace function public.salon_owner_settings(p_salon uuid)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships; s app.salons;
begin
  m := app.require_owner(p_salon);
  select * into s from app.salons where id = p_salon;
  return jsonb_build_object('ok', true, 'settings', to_jsonb(s) - 'created_at');
end $$;

create or replace function public.salon_owner_settings_save(p_salon uuid, p_payload jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; a jsonb := coalesce(p_payload, '{}'::jsonb); s app.salons; before jsonb;
begin
  m := app.require_owner(p_salon);
  select * into s from app.salons where id = p_salon for update;
  before := to_jsonb(s);
  if a ? 'booking_mode' and a->>'booking_mode' not in ('closed','preview','live') then
    perform app.fail('invalid_mode', 'Unknown booking mode.');
  end if;
  if a ? 'email' and coalesce(a->>'email', '') <> '' and not app.valid_email(a->>'email') then
    perform app.fail('email_invalid', 'Check the email address.');
  end if;
  if a ? 'instagram_url' and coalesce(a->>'instagram_url', '') <> '' and a->>'instagram_url' !~* '^https://(www\.)?instagram\.com/' then
    perform app.fail('invalid_url', 'Instagram links must start with https://www.instagram.com/');
  end if;
  update app.salons set
    name = coalesce(app.clean_text(a->>'name', 120), name),
    tagline = case when a ? 'tagline' then app.clean_text(a->>'tagline', 200) else tagline end,
    city = case when a ? 'city' then app.clean_text(a->>'city', 80) else city end,
    address = case when a ? 'address' then app.clean_text(a->>'address', 300) else address end,
    phone = case when a ? 'phone' then app.clean_text(a->>'phone', 40) else phone end,
    whatsapp = case when a ? 'whatsapp' then app.clean_text(a->>'whatsapp', 40) else whatsapp end,
    email = case when a ? 'email' then lower(app.clean_text(a->>'email', 254)) else email end,
    instagram_url = case when a ? 'instagram_url' then app.clean_text(a->>'instagram_url', 200) else instagram_url end,
    booking_policy = case when a ? 'booking_policy' then app.clean_text(a->>'booking_policy', 2000) else booking_policy end,
    booking_mode = coalesce(a->>'booking_mode', booking_mode),
    min_notice_min = coalesce((a->>'min_notice_min')::int, min_notice_min),
    max_days_ahead = coalesce((a->>'max_days_ahead')::int, max_days_ahead),
    slot_interval_min = coalesce((a->>'slot_interval_min')::int, slot_interval_min),
    hours_confirmed = coalesce((a->>'hours_confirmed')::boolean, hours_confirmed),
    updated_at = now()
  where id = p_salon returning * into s;
  perform app.audit(p_salon, null, m.user_id, 'owner', 'settings.updated', 'salon', p_salon::text,
                    jsonb_build_object('before', before, 'after', to_jsonb(s)));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.salon_owner_salon_hours_save(p_salon uuid, p_rows jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; before jsonb;
begin
  m := app.require_owner(p_salon);
  select coalesce(jsonb_agg(to_jsonb(h)), '[]'::jsonb) into before from app.opening_hours h where h.salon_id = p_salon;
  delete from app.opening_hours where salon_id = p_salon;
  insert into app.opening_hours (salon_id, weekday, opens, closes)
  select p_salon, h.weekday, h.opens, h.closes from app.validate_hours(p_rows) h;
  perform app.audit(p_salon, null, m.user_id, 'owner', 'salon_hours.updated', 'salon', p_salon::text,
                    jsonb_build_object('before', before, 'after', p_rows));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.salon_owner_audit(p_salon uuid, p_professional uuid default null, p_limit int default 200)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare m app.memberships;
begin
  m := app.require_owner(p_salon);
  return jsonb_build_object('ok', true, 'items', (
    select coalesce(jsonb_agg(x.j order by x.id desc), '[]'::jsonb) from (
      select a.id, jsonb_build_object('id', a.id, 'at', a.created_at, 'actor', a.actor_label,
               'actor_email', u.email, 'action', a.action, 'entity', a.entity, 'entity_id', a.entity_id,
               'professional', p.display_name, 'detail', a.detail) j
      from app.audit_log a
      left join auth.users u on u.id = a.actor_user_id
      left join app.professionals p on p.id = a.professional_id
      where a.salon_id = p_salon and (p_professional is null or a.professional_id = p_professional)
      order by a.id desc limit least(greatest(coalesce(p_limit, 200), 1), 1000)) x));
end $$;

-- ---------------------------------------------------------------------
-- Storage helper used by storage.objects policies (portfolio uploads).
-- Path layout: <salon_id>/<professional_id>/<file>
create or replace function app.storage_can_write(p_name text)
returns boolean language plpgsql stable security definer set search_path = '' as $$
declare parts text[] := string_to_array(coalesce(p_name, ''), '/'); v_salon uuid; v_pro uuid; m app.memberships;
begin
  if auth.uid() is null or array_length(parts, 1) <> 3 then return false; end if;
  begin
    v_salon := parts[1]::uuid; v_pro := parts[2]::uuid;
  exception when others then return false;
  end;
  if not exists (select 1 from app.professionals where id = v_pro and salon_id = v_salon) then return false; end if;
  select * into m from app.memberships where user_id = auth.uid() and salon_id = v_salon and status = 'active';
  return m.id is not null and app.can_see(m, v_pro);
end $$;

-- ---------------------------------------------------------------------
-- Grants: nothing by default; then exactly what each audience needs.
-- ---------------------------------------------------------------------
revoke execute on all functions in schema app from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    -- functions created later in public by this role are NOT callable by default
    execute 'alter default privileges in schema public revoke execute on functions from public, anon, authenticated';
    execute 'alter default privileges in schema app revoke execute on functions from public, anon, authenticated';
  end if;
end $$;
do $$
declare f record; has_roles boolean := exists (select 1 from pg_roles where rolname = 'anon');
begin
  for f in
    select p.oid::regprocedure as sig, p.proname
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname like 'salon\_%'
  loop
    execute format('revoke all on function %s from public', f.sig);
    if has_roles then
      execute format('revoke all on function %s from anon, authenticated, service_role', f.sig);
      if f.proname like 'salon\_public\_%' then
        execute format('grant execute on function %s to anon, authenticated', f.sig);
      elsif f.proname like 'salon\_internal\_%' then
        execute format('grant execute on function %s to service_role', f.sig);
      else
        execute format('grant execute on function %s to authenticated', f.sig);
      end if;
    end if;
  end loop;
  if has_roles then
    -- storage policies call this helper as the signed-in user
    execute 'grant usage on schema app to authenticated';
    execute 'grant execute on function app.storage_can_write(text) to authenticated';
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Storage bucket + policies (Supabase only; skipped on plain Postgres)
-- ---------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage')
     and exists (select 1 from pg_tables where schemaname = 'storage' and tablename = 'buckets') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('portfolio', 'portfolio', true, 52428800,
            array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime'])
    on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
                                   allowed_mime_types = excluded.allowed_mime_types;

    execute 'drop policy if exists "portfolio insert own folder" on storage.objects';
    execute 'drop policy if exists "portfolio update own folder" on storage.objects';
    execute 'drop policy if exists "portfolio delete own folder" on storage.objects';
    execute 'drop policy if exists "portfolio select own folder" on storage.objects';
    execute $p$create policy "portfolio insert own folder" on storage.objects for insert to authenticated
             with check (bucket_id = 'portfolio' and app.storage_can_write(name))$p$;
    execute $p$create policy "portfolio update own folder" on storage.objects for update to authenticated
             using (bucket_id = 'portfolio' and app.storage_can_write(name))
             with check (bucket_id = 'portfolio' and app.storage_can_write(name))$p$;
    execute $p$create policy "portfolio delete own folder" on storage.objects for delete to authenticated
             using (bucket_id = 'portfolio' and app.storage_can_write(name))$p$;
    execute $p$create policy "portfolio select own folder" on storage.objects for select to authenticated
             using (bucket_id = 'portfolio' and app.storage_can_write(name))$p$;
  end if;
end $$;
