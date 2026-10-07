# Shahina Ahmed Luxury Salon: website, booking at private dashboards

Hiwalay na project ito. Hindi ito SimplyBooked. Sarili nitong repo (`gawa-ai/3salons`), Supabase project ("3 Salons", `vqkrvbtndnnxpcemkuce`, eu-west-1) at Netlify site (`3salon.netlify.app`).

- **Owner vs artists:** si Shahina Ahmed ang owner at brand ng tatlong salon. Hindi siya bookable artist at wala siyang artist page.
- **Public website** (`/`): tatlong artist (Sofia MUA, Shirin Jal, Mi Hijabby Sabiha), presyo mula sa client, Instagram, gallery (lalabas kapag may na-upload), about, contact, bridal enquiry.
- **Booking** (`/book`): pili ng artist → service → araw at oras → details → review. **Provisional** ang bawat online booking hanggang i-confirm ng artist. May private link ang client (`/manage#t=…`) para makita o ma-cancel ang booking.
- **Dashboards** (`/signin` → `/studio`):
  - **Owner (Shahina):** buong salon (walang sariling professional profile). May selector na *All professionals* o isang professional, combined calendar, Team (invites), Settings, Reports, Activity log.
  - **Staff (Sofia MUA, Shirin Jal, Mi Hijabby Sabiha):** sariling bookings, calendar, clients, notes, services (duration lang, hindi presyo), hours, time off at gallery lang.
  - Ang paghihiwalay ay ipinapatupad ng **database**, hindi ng browser. Walang role picker, URL parameter o tab na nagbibigay ng access.

## Paano gumagana

```
Browser (static HTML/JS, strict CSP, walang inline script/style)
   │  publishable key + JWT ng naka-sign-in na user (Supabase Auth)
   ▼
Supabase PostgREST → public.salon_* functions (SECURITY DEFINER, search_path = '')
                        │  identity = auth.uid() → app.memberships (role + professional)
                        ▼
                     schema "app" (hindi exposed sa API, RLS on, walang table grants)
                        • bookings_no_overlap (exclusion constraint) → imposible ang double booking
                        • advisory lock bawat professional → walang deadlock sa sabayang booking
                        • idempotency + rate limits + honeypot
                        • audit trail; outbox ng SMS na "Not connected" (walang naipapadala)
Edge function accept-invite → gumagawa ng user mula sa one-time invitation code
```

## Files

| Path | Ano ito |
|---|---|
| `supabase/migrations/*.sql` | Buong database: schema, booking engine, public API, dashboard API, invites, grants, seed. Non-destructive at puwedeng i-run nang paulit-ulit. |
| `supabase/functions/accept-invite/` | Edge function para sa invitation sign-up (service role sa server lang). |
| `supabase/manual/01_pending_functions_and_storage.sql` | **Kailangang i-run ni JG** (tingnan ang Status). |
| `supabase/manual/02_owner_invitation.sql` | Gumagawa ng owner invitation code para kay Shahina. |
| `supabase/manual/simplybooked_cleanup.sql` | Pag-alis ng salon rows sa **SimplyBooked** prod. Naka-ROLLBACK by default; si JG ang magpapatakbo. |
| `web/` | Frontend (TypeScript + esbuild, walang framework). `npm run check` = typecheck + build. |
| `brand/` | Original na SVG wordmark/monogram, PNG exports, OG image, at ang mga **orihinal** na logo ng artists (hindi binago). |
| `tests/db/` | 114 database checks + concurrency; 7 checks para sa SimplyBooked cleanup script. |
| `tests/e2e/` | 33 browser checks (Playwright) laban sa totoong SQL; screenshots sa `docs/screenshots/`. |
| `docs/` | `STUDIO_GUIDE.md` (para kay Shahina at sa artists), `BUILD_STATE.md`, `PERMISSIONS.md`, `MISSING_INFO.md`, `ACCEPTANCE.md`, test results. |

## Setup (sunod-sunod)

1. **Database.** Naka-apply na sa "3 Salons" ang lahat ng migrations maliban sa `supabase/manual/01_pending_functions_and_storage.sql`. I-paste ito sa SQL Editor at i-run nang isang beses.
2. **Netlify.** Sa site na `3salon`, gawin ang Site configuration → Build & deploy → Link repository → `gawa-ai/3salons` (branch `main`). Ang `netlify.toml` na ang bahala sa build (`web/`, publish `dist`, Node 22). Walang secret na kailangan, dahil publishable key lang ang nasa build.
3. **Supabase Auth** (Dashboard → Authentication):
   - URL Configuration: Site URL `https://3salon.netlify.app`. Redirect URLs: `https://3salon.netlify.app/reset`.
   - Sign In / Providers: i-off ang "Allow new users to sign up". Invitation code lang ang daan para makapasok.
   - SMTP: maglagay ng custom SMTP para gumana ang password reset emails sa totoong users.
4. **Owner.** I-run ang `supabase/manual/02_owner_invitation.sql` (palitan ang email). Ibigay kay Shahina ang code nang pribado. Pupunta siya sa `/join`. Pagkatapos, siya ang mag-iimbita kina Sofia, Shirin at Sabiha mula sa **Team** page.
5. **Go-live.** Sundin ang `docs/ACCEPTANCE.md`. Naka-`preview` ang `booking_mode` at walang SMS. Hindi ito bubuksan sa publiko hanggang pumasa ang checklist at kumpirmado ang hours, durations at policy.

## Mga test (local, throwaway Postgres 16)

```bash
bash tests/db/run.sh                         # 114 checks (incl. cross-profile denial, concurrency, DST)
bash tests/db/30_simplybooked_cleanup.sh     # 7 checks para sa cleanup script
NODE_PATH=/opt/npm-tools/node_modules node tests/e2e/run.cjs   # 33 browser checks + screenshots
```

## Seguridad

- Walang service-role key sa frontend o sa repo. Ang `accept-invite` ay gumagamit ng `SUPABASE_SERVICE_ROLE_KEY` na awtomatikong nasa Supabase Edge runtime.
- Hindi kailanman ipapadala sa chat ang mga secret.
- Hindi ginalaw ang SimplyBooked. Ang cleanup script ay inihanda at na-test lang nang local.
