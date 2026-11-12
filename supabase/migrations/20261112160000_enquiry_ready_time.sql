-- Bridal enquiry form: "Time to be ready" (optional) under the event date.
-- Stored on the enquiry and returned to the Studio. The two functions are patched in place
-- (same technique as earlier migrations) so later edits to them are kept. Re-runnable.
alter table app.enquiries add column if not exists ready_time time;

do $$
declare d text;
begin
  d := pg_get_functiondef('public.salon_public_enquiry(text,jsonb)'::regprocedure);
  if position('ready_time' in d) = 0 then
    if length(d) - length(replace(d, E'  returning * into e;', '')) <> length(E'  returning * into e;') then
      raise exception 'salon_public_enquiry anchor not found exactly once';
    end if;
    d := replace(d, E'  returning * into e;',
      E'  returning * into e;\n  if coalesce(a->>''ready_time'', '''') <> '''' then\n    update app.enquiries set ready_time = app.parse_time(a->>''ready_time'') where id = e.id;\n  end if;');
    execute d;
  end if;

  d := pg_get_functiondef('public.salon_dash_enquiries(uuid,uuid,text)'::regprocedure);
  if position('ready_time' in d) = 0 then
    if position('''event_date'', e.event_date,' in d) = 0 then raise exception 'salon_dash_enquiries anchor not found'; end if;
    d := replace(d, '''event_date'', e.event_date,', '''event_date'', e.event_date, ''ready_time'', to_char(e.ready_time, ''HH24:MI''),');
    execute d;
  end if;
end $$;
