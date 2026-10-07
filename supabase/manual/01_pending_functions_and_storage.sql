-- =====================================================================
-- PENDING ON "3 Salons" (vqkrvbtndnnxpcemkuce): run once in the Supabase SQL Editor.
-- The approval prompt for this migration was not answered (the tool asks a human for any SQL that
-- contains DELETE/DROP POLICY), so these 4 functions and the photo/video bucket are not live yet.
--
-- What it is: the exact same SQL as supabase/migrations/20261007000400 + 000500 (tested: 112 DB checks,
-- 33 browser checks). The DELETEs only replace one professional's own working hours, one time-off row,
-- one gallery item, or the salon's opening hours, after the caller's identity has been checked.
-- It does not delete any existing data when you run it. Safe to re-run.
--
-- Until it runs, these dashboard buttons answer "permission denied": Save hours, Remove time off,
-- Delete photo, Save salon hours, and photo/video uploads.
-- =====================================================================

create or replace function public.salon_dash_hours_save(p_salon uuid, p_professional uuid, p_rows jsonb)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare m app.memberships; pro uuid; before jsonb; n int;
begin
  m := app.my_membership(p_salon);
  pro := app.scope_pro(m, p_professional);
  if pro is null then perform app.fail('professional_required', 'Choose a professional.'); end if;
  select coalesce(jsonb_agg(to_jsonb(w)), '[]'::jsonb) into before from app.working_hours w where w.professional_id = pro;
  delete from app.working_hours where professional_id = pro;
  insert into app.working_hours (professional_id, weekday, opens, closes)
  select pro, h.weekday, h.opens, h.closes from app.validate_hours(p_rows) h;
  -- upcoming bookings that now fall outside the new hours are kept, but reported
  select count(*) into n from app.bookings k where k.professional_id = pro and k.status in ('pending','confirmed')
    and k.starts_at > now() and not exists (select 1 from app.working_hours w where w.professional_id = pro
      and w.weekday = extract(dow from (k.starts_at at time zone (select timezone from app.salons where id = p_salon)))
      and (k.starts_at at time zone (select timezone from app.salons where id = p_salon))::time >= w.opens
      and (k.ends_at at time zone (select timezone from app.salons where id = p_salon))::time <= w.closes);
  perform app.audit(p_salon, pro, auth.uid(), app.actor_label(m), 'hours.updated', 'professional', pro::text,
                    jsonb_build_object('before', before, 'after', p_rows));
  return jsonb_build_object('ok', true, 'bookings_outside_hours', n);
end $$;

create or replace function public.salon_dash_time_off_delete(p_id uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare t app.time_off; m app.memberships; uid uuid := auth.uid();
begin
  if uid is null then perform app.fail('not_signed_in', 'Please sign in.'); end if;
  select * into t from app.time_off where id = p_id;
  if t.id is not null then
    select * into m from app.memberships where user_id = uid and salon_id = t.salon_id and status = 'active';
  end if;
  if t.id is null or m.id is null or not (m.role = 'owner' or (t.professional_id is not null and t.professional_id = m.professional_id)) then
    perform app.fail('not_found', 'Not found.');
  end if;
  delete from app.time_off where id = t.id;
  perform app.audit(t.salon_id, t.professional_id, uid, app.actor_label(m), 'time_off.removed', 'time_off', t.id::text,
                    jsonb_build_object('starts_at', t.starts_at, 'ends_at', t.ends_at));
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.salon_dash_gallery_delete(p_item uuid)
returns jsonb language plpgsql volatile security definer set search_path = '' as $$
declare g app.gallery_items; m app.memberships;
begin
  g := app.gallery_for_caller(p_item);
  m := app.my_membership(g.salon_id);
  delete from app.gallery_items where id = g.id;
  perform app.audit(g.salon_id, g.professional_id, auth.uid(), app.actor_label(m), 'gallery.removed', 'gallery', g.id::text);
  return jsonb_build_object('ok', true, 'storage_path', g.storage_path);
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
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('salon_dash_hours_save','salon_dash_time_off_delete','salon_dash_gallery_delete','salon_owner_salon_hours_save') loop
    execute format('revoke all on function %s from public, anon, service_role', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
