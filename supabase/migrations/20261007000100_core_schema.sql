-- =====================================================================
-- Shahina Ahmed Luxury Salon — core schema (schema `app`)
--
-- Design
--   * All tables live in the private schema `app`, which is NOT exposed by the
--     Supabase Data API. Browsers never read tables directly.
--   * Every read/write goes through SECURITY DEFINER functions in `public`
--     (see later migrations). Each function resolves the caller from auth.uid()
--     and the protected app.memberships table, never from client input or
--     user metadata.
--   * RLS is enabled on every table (deny by default). No table grants to
--     anon/authenticated.
--   * Booking overlap is impossible at the database level (exclusion constraint).
--   * Re-runnable: IF NOT EXISTS / CREATE OR REPLACE.
-- =====================================================================

create schema if not exists extensions;
create extension if not exists btree_gist with schema extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists app;
revoke all on schema app from public;

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table if not exists app.salons (
  id                 uuid primary key default gen_random_uuid(),
  slug               text not null unique check (slug ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
  name               text not null,
  tagline            text,
  timezone           text not null default 'Europe/London',
  country_code       text not null default '44' check (country_code ~ '^[0-9]{1,3}$'),
  booking_mode       text not null default 'preview' check (booking_mode in ('closed','preview','live')),
  slot_interval_min  int  not null default 15  check (slot_interval_min between 5 and 120),
  min_notice_min     int  not null default 120 check (min_notice_min between 0 and 20160),
  max_days_ahead     int  not null default 90  check (max_days_ahead between 1 and 365),
  city               text,
  address            text,          -- NULL = not confirmed; never shown as fact
  phone              text,
  whatsapp           text,
  email              text,
  instagram_url      text,
  booking_policy     text,          -- deposit / cancellation text shown before submit; NULL = none configured
  hours_confirmed    boolean not null default false,  -- public opening hours shown only when true
  sms_connected      boolean not null default false,  -- no outbound integration yet
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table if not exists app.professionals (
  id             uuid primary key default gen_random_uuid(),
  salon_id       uuid not null references app.salons(id) on delete cascade,
  slug           text not null check (slug ~ '^[a-z0-9][a-z0-9-]{1,62}$'),
  display_name   text not null,
  short_name     text not null,
  specialty      text,
  bio            text,
  instagram_url  text,
  logo_path      text,              -- public static asset, e.g. /brand/pros/sofia-mua.png
  color          text not null default 'bronze' check (color in ('bronze','rose','slate','plum','sage')),
  sort_order     int not null default 0,
  is_public      boolean not null default true,
  online_booking boolean not null default true,
  active         boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (salon_id, slug),
  unique (salon_id, id)
);

create table if not exists app.memberships (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  salon_id        uuid not null references app.salons(id) on delete cascade,
  role            text not null check (role in ('owner','professional')),
  professional_id uuid,
  status          text not null default 'active' check (status in ('active','disabled')),
  display_name    text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (user_id, salon_id),
  foreign key (salon_id, professional_id) references app.professionals(salon_id, id),
  check (role = 'owner' or professional_id is not null)
);
create unique index if not exists memberships_one_active_login_per_profile
  on app.memberships (salon_id, professional_id) where status = 'active' and professional_id is not null;

create table if not exists app.invitations (
  id              uuid primary key default gen_random_uuid(),
  salon_id        uuid not null references app.salons(id) on delete cascade,
  role            text not null check (role in ('owner','professional')),
  professional_id uuid,
  email           text not null,
  code_hash       text not null unique,
  expires_at      timestamptz not null,
  used_at         timestamptz,
  used_by         uuid references auth.users(id) on delete set null,
  revoked_at      timestamptz,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  foreign key (salon_id, professional_id) references app.professionals(salon_id, id),
  check (role = 'owner' or professional_id is not null)
);

create table if not exists app.services (
  id                uuid primary key default gen_random_uuid(),
  salon_id          uuid not null references app.salons(id) on delete cascade,
  professional_id   uuid not null,
  name              text not null check (length(btrim(name)) between 2 and 80),
  description       text,
  category          text not null default 'other'
                    check (category in ('hair','makeup','hair_makeup','hijab','saree','bridal','other')),
  duration_min      int  not null default 60 check (duration_min between 5 and 720),
  buffer_min        int  not null default 0  check (buffer_min between 0 and 240),
  price_pence       int  check (price_pence >= 0),
  price_kind        text not null default 'fixed' check (price_kind in ('fixed','from','enquire')),
  bookable_online   boolean not null default true,
  details_confirmed boolean not null default false,   -- duration/buffer confirmed by the owner
  active            boolean not null default true,
  sort_order        int not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  unique (salon_id, id),
  unique (professional_id, id),
  foreign key (salon_id, professional_id) references app.professionals(salon_id, id) on delete cascade,
  check (price_kind = 'enquire' or price_pence is not null),
  check (price_kind <> 'enquire' or bookable_online = false)
);
create unique index if not exists services_name_per_pro on app.services (professional_id, lower(name));

create table if not exists app.opening_hours (        -- salon-level opening hours
  salon_id uuid not null references app.salons(id) on delete cascade,
  weekday  smallint not null check (weekday between 0 and 6),   -- 0 = Sunday
  opens    time not null,
  closes   time not null,
  primary key (salon_id, weekday, opens),
  check (closes > opens)
);

create table if not exists app.working_hours (        -- each professional's own schedule
  professional_id uuid not null references app.professionals(id) on delete cascade,
  weekday         smallint not null check (weekday between 0 and 6),
  opens           time not null,
  closes          time not null,
  primary key (professional_id, weekday, opens),
  check (closes > opens)
);

create table if not exists app.time_off (
  id              uuid primary key default gen_random_uuid(),
  salon_id        uuid not null references app.salons(id) on delete cascade,
  professional_id uuid,                                -- NULL = whole salon closed
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  reason          text,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  foreign key (salon_id, professional_id) references app.professionals(salon_id, id) on delete cascade,
  check (ends_at > starts_at)
);
create index if not exists time_off_lookup on app.time_off (salon_id, professional_id, starts_at, ends_at);

-- One client record PER PROFESSIONAL. A person who books two professionals has two
-- separate records, so one professional's notes/history never reach the other.
create table if not exists app.clients (
  id                   uuid primary key default gen_random_uuid(),
  salon_id             uuid not null references app.salons(id) on delete cascade,
  professional_id      uuid not null,
  name                 text not null,
  phone                text not null,
  email                text,
  notes                text,
  marketing_consent    boolean not null default false,
  marketing_consent_at timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  unique (professional_id, phone),
  unique (professional_id, id),
  foreign key (salon_id, professional_id) references app.professionals(salon_id, id) on delete cascade
);

create table if not exists app.bookings (
  id                      uuid primary key default gen_random_uuid(),
  salon_id                uuid not null references app.salons(id) on delete cascade,
  professional_id         uuid not null,
  service_id              uuid not null,
  client_id               uuid not null,
  ref                     text not null,
  starts_at               timestamptz not null,
  ends_at                 timestamptz not null,
  block_end               timestamptz not null,       -- ends_at + buffer
  status                  text not null default 'pending'
                          check (status in ('pending','confirmed','declined','cancelled','completed','no_show','expired')),
  source                  text not null default 'website'
                          check (source in ('website','dashboard','phone','walk_in','other')),
  -- snapshot of the service at booking time (catalogue edits never change existing bookings)
  service_name            text not null,
  duration_min            int  not null,
  buffer_min              int  not null,
  price_pence             int,
  price_kind              text not null,
  customer_note           text,
  internal_note           text,
  status_reason           text,
  manage_token_hash       text unique,
  manage_token_expires_at timestamptz,
  version                 int not null default 1,
  confirmed_at            timestamptz,
  cancelled_at            timestamptz,
  completed_at            timestamptz,
  created_by              uuid references auth.users(id) on delete set null,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),
  unique (salon_id, ref),
  foreign key (salon_id, professional_id) references app.professionals(salon_id, id),
  foreign key (professional_id, service_id) references app.services(professional_id, id),
  foreign key (professional_id, client_id) references app.clients(professional_id, id),
  check (ends_at > starts_at and block_end >= ends_at),
  -- The hard guarantee: one professional can never hold two active bookings at once.
  constraint bookings_no_overlap exclude using gist (
    professional_id with =,
    tstzrange(starts_at, block_end, '[)') with &&
  ) where (status in ('pending','confirmed'))
);
create index if not exists bookings_salon_time on app.bookings (salon_id, starts_at);
create index if not exists bookings_pro_time on app.bookings (professional_id, starts_at);
create index if not exists bookings_client on app.bookings (client_id, starts_at);

create table if not exists app.enquiries (
  id               uuid primary key default gen_random_uuid(),
  salon_id         uuid not null references app.salons(id) on delete cascade,
  professional_id  uuid,                              -- NULL = no preference (owner only)
  kind             text not null default 'bridal' check (kind in ('bridal','general')),
  name             text not null,
  phone            text not null,
  email            text,
  event_date       date,
  event_location   text,
  services_wanted  text,
  message          text,
  status           text not null default 'new' check (status in ('new','contacted','booked','closed')),
  internal_note    text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  foreign key (salon_id, professional_id) references app.professionals(salon_id, id)
);
create index if not exists enquiries_lookup on app.enquiries (salon_id, professional_id, created_at desc);

-- Outbox. Rows are written for every customer/professional communication the system
-- would send. With no SMS/email integration connected, status stays 'not_connected'.
create table if not exists app.notifications (
  id              bigint generated always as identity primary key,
  salon_id        uuid not null references app.salons(id) on delete cascade,
  professional_id uuid,
  booking_id      uuid references app.bookings(id) on delete cascade,
  enquiry_id      uuid references app.enquiries(id) on delete cascade,
  audience        text not null check (audience in ('customer','professional')),
  channel         text not null default 'sms' check (channel in ('sms','email')),
  purpose         text not null,
  to_addr         text,
  body            text not null,
  status          text not null default 'not_connected'
                  check (status in ('not_connected','queued','sent','failed','skipped','cancelled')),
  dedupe_key      text unique,
  last_error      text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);
create index if not exists notifications_lookup on app.notifications (salon_id, professional_id, created_at desc);

create table if not exists app.audit_log (
  id              bigint generated always as identity primary key,
  salon_id        uuid not null references app.salons(id) on delete cascade,
  professional_id uuid,
  actor_user_id   uuid,
  actor_label     text not null,                      -- 'owner', 'professional', 'customer', 'system'
  action          text not null,
  entity          text not null,
  entity_id       text,
  detail          jsonb not null default '{}'::jsonb,
  created_at      timestamptz not null default now()
);
create index if not exists audit_lookup on app.audit_log (salon_id, created_at desc);
create index if not exists audit_entity on app.audit_log (entity, entity_id);

create table if not exists app.idempotency (
  salon_id   uuid not null references app.salons(id) on delete cascade,
  key        text not null,
  result     jsonb,
  created_at timestamptz not null default now(),
  primary key (salon_id, key)
);

create table if not exists app.rate_events (
  id         bigint generated always as identity primary key,
  bucket     text not null,
  created_at timestamptz not null default now()
);
create index if not exists rate_events_bucket on app.rate_events (bucket, created_at);

create table if not exists app.gallery_items (
  id              uuid primary key default gen_random_uuid(),
  salon_id        uuid not null references app.salons(id) on delete cascade,
  professional_id uuid not null,
  storage_path    text not null unique,
  media_type      text not null default 'image' check (media_type in ('image','video')),
  alt_text        text not null default '',
  caption         text,
  published       boolean not null default true,
  sort_order      int not null default 0,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  foreign key (salon_id, professional_id) references app.professionals(salon_id, id) on delete cascade
);

-- ---------------------------------------------------------------------
-- Row level security: on everywhere, nothing granted. Access is only through
-- the audited SECURITY DEFINER functions.
-- ---------------------------------------------------------------------
do $$
declare t record;
begin
  for t in select tablename from pg_tables where schemaname = 'app' loop
    execute format('alter table app.%I enable row level security', t.tablename);
    execute format('revoke all on table app.%I from public', t.tablename);
  end loop;
end $$;

do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema app from anon, authenticated';
    execute 'revoke all on all tables in schema app from anon, authenticated';
    execute 'revoke all on all sequences in schema app from anon, authenticated';
  end if;
end $$;
