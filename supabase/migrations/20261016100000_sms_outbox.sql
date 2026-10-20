-- SMS outbox: claim/complete functions + columns. Re-runnable. No secrets in this file.
-- Does NOT change salons.sms_connected and does NOT touch existing not_connected rows.

alter table app.notifications
  add column if not exists attempts int not null default 0,
  add column if not exists next_attempt_at timestamptz,
  add column if not exists locked_at timestamptz,
  add column if not exists sent_at timestamptz,
  add column if not exists provider_message_id text;

-- Which SMS types are allowed to send (cost control). Anything else is marked 'skipped'.
alter table app.salons
  add column if not exists sms_purposes jsonb not null
  default '{"confirmed":true,"reminder":true,"deposit_request":true}'::jsonb;

create index if not exists notifications_sms_queue_idx
  on app.notifications (id)
  where channel = 'sms' and status = 'queued';

-- Claim a batch. A lock older than 5 min means a worker died mid-send: the send state is unknown,
-- so we mark it failed instead of resending (never double-text a customer).
create or replace function public.sms_claim(p_limit int default 10)
returns table(nid bigint, dest text, msg text, purp text, tries int, purposes jsonb)
language plpgsql security definer set search_path = ''
as $$
begin
  update app.notifications n
     set status = 'failed',
         last_error = 'unknown_send_state: worker stopped mid-send, check provider before resending',
         locked_at = null, updated_at = now()
   where n.channel = 'sms' and n.status = 'queued'
     and n.locked_at is not null and n.locked_at < now() - interval '5 minutes';

  return query
  with c as (
    select n.id
      from app.notifications n
      join app.salons s on s.id = n.salon_id
     where n.channel = 'sms' and n.status = 'queued' and n.locked_at is null
       and (n.next_attempt_at is null or n.next_attempt_at <= now())
       and (s.sms_connected or n.purpose = 'sms_test')
     order by n.id
     limit greatest(1, least(p_limit, 25))
       for update of n skip locked
  )
  update app.notifications n
     set locked_at = now(), attempts = n.attempts + 1, updated_at = now()
    from c, app.salons s
   where n.id = c.id and s.id = n.salon_id
  returning n.id, n.to_addr, n.body, n.purpose, n.attempts, s.sms_purposes;
end $$;

-- Record the result. outcome: sent | failed | retry | skipped
create or replace function public.sms_complete(
  p_id bigint, p_outcome text, p_provider_id text default null, p_error text default null)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if p_outcome not in ('sent', 'failed', 'retry', 'skipped') then
    raise exception 'bad outcome';
  end if;
  update app.notifications n
     set status = case p_outcome
                    when 'sent' then 'sent'
                    when 'skipped' then 'skipped'
                    when 'failed' then 'failed'
                    when 'retry' then case when n.attempts >= 3 then 'failed' else 'queued' end
                  end,
         sent_at = case when p_outcome = 'sent' then now() else n.sent_at end,
         provider_message_id = coalesce(p_provider_id, n.provider_message_id),
         last_error = case when p_outcome = 'sent' then null else left(p_error, 500) end,
         next_attempt_at = case when p_outcome = 'retry' then now() + (n.attempts * n.attempts) * interval '2 minutes' end,
         locked_at = null,
         updated_at = now()
   where n.id = p_id and n.status = 'queued';
end $$;

do $$
begin
  execute 'revoke all on function public.sms_claim(int) from public, anon, authenticated';
  execute 'revoke all on function public.sms_complete(bigint, text, text, text) from public, anon, authenticated';
  execute 'grant execute on function public.sms_claim(int) to service_role';
  execute 'grant execute on function public.sms_complete(bigint, text, text, text) to service_role';
end $$;
