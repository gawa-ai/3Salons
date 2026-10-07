# HANDOFF — Shahina Ahmed salon site (para sa bagong tab)

Basahin muna ito, tapos `docs/BUILD_STATE.md`, `docs/ACCEPTANCE.md`, `docs/MISSING_INFO.md`. Huwag magsimula nang hindi alam ang mga rules sa ibaba.

## 1. Ano ito
Website + booking system ng **Shahina Ahmed** (brand/owner lang, HINDI bookable artist) sa Blackburn. Tatlong artists: **Sofia MUA** (makeup), **Shirin Jal** (hair & makeup), **Mi Hijabby Sabiha** (hijab styling). Owner dashboard (All professionals / per-artist), staff dashboards na naka-scope sa sariling data, invitation-based auth, provisional bookings, bridal enquiries.

- Repo: `gawa-ai/3Salons` (working copy `/home/claude/3salons`), branch main. Huling commit sa session na ito: `783c78b`.
- Live site: https://3salon.netlify.app (Netlify deploy mula sa GitHub push; HINDI ko ito mabuksan/ma-verify mula sa workspace).
- Supabase project "3 Salons": `vqkrvbtndnnxpcemkuce` (eu-west-1). Supabase MCP (`execute_sql`, `apply_migration`, `deploy_edge_function`) gumagana.
- Commit trailers: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` at `Claude-Session: <session url>`.

## 2. Standing rules (huwag labagin)
- Walang service-role key sa frontend. Secrets sa Supabase/Netlify settings lang, hindi sa chat/source/logs. Huwag hilingin kay JG na i-paste ang secrets sa chat.
- RLS everywhere. Role/URL param/browser flag/profile tab ay HINDI nagbibigay ng permissions. Staff = sariling data lang.
- Walang auto-send: `online_booking=false`, `test_mode=true`, booking_mode=preview, SMS "Not connected" hanggang pumasa ang acceptance checklist.
- Migrations: non-destructive at re-runnable. Huwag mag-drop/delete ng production data nang walang explicit OK ni JG at backup.
- Huwag gumastos ng external generation credits, huwag mag-send ng test messages sa totoong customers.
- Huwag galawin ang SimplyBooked (lumang site/records/automations). Cleanup nito = JG lang ang magpapatakbo.
- Huwag mag-fabricate ng test results o deployment URLs. Lagyan ng label: VERIFIED / SUPPORTED / HYPOTHESIS.
- Komunikasyon kay JG: Taglish, maikli, direkta, build-first. Final reports sa SISID format. Client-facing copy: natural English.

## 3. Stack at paano mag-build/test
- Supabase Postgres 17: private schema `app` (RLS on, walang table grants); public SECURITY DEFINER functions (`salon_public_*` anon, `salon_dash_*`/`salon_owner_*`/`salon_me`/`salon_claim_invite` authenticated, `salon_internal_*` service_role). Edge function `accept-invite` (v2, verify_jwt false).
- Frontend: vanilla TypeScript + esbuild. `cd web && node build.mjs && npx tsc --noEmit`. CSS: `web/src/styles/{base,site,studio,color}.css` (color.css huling i-import).
- Local tests (Postgres 16 sa /var/tmp/bospg port 55432, madalas tumitigil; restart: `su claude -c "$B/pg_ctl -D /var/tmp/bospg/data -l /var/tmp/bospg/pg.log -o '-p 55432 -k /var/tmp/bospg' start"`, B=/usr/lib/postgresql/*/bin):
  - `bash tests/db/run.sh` (114 checks)
  - `NODE_PATH=/opt/npm-tools/node_modules node tests/e2e/run.cjs` (33 checks; nire-regenerate ang `docs/screenshots/`)
- Workspace limits: egress proxy humaharang sa Netlify, npm, Supabase Auth/Storage hosts, at raw.githubusercontent.com. Gumagana: GitHub push, `git clone` ng github.com, Supabase MCP.

## 4. Ginawa na (VERIFIED sa local tests/screenshots maliban kung nakasaad)
- (SUPERSEDED 2026-10-07: si Shahina ay public professional na ulit, first card; 4 professionals.) Owner-not-bookable model dati. Demo logins (sample lang; emails sa BUILD_STATE, passwords sa JG): shahinaahmed@, sofiamua@, shirinjal@, mihijabbysabiha@ `@sample.com`. Mayroon ding sample bookings/enquiries (phones 07700 9001xx).
- Colourful redesign (landing, sign-in, dashboard), tagline "Your moment. Your signature look.", walang "luxury salon" text.
- **Portfolio media** (static, committed sa `web/public/gallery/<artist-slug>/`, ref sa `app.gallery_items.storage_path` na nagsisimula sa `/`; sinusuportahan ng `publicStorageUrl` ang site-relative paths; videos may `-poster.jpg`):
  - Sofia MUA: 9 items (6 videos, 3 photos) — migrations 20261007001400, 001500
  - Shirin Jal: 8 videos — 001600 (look-8 may FlipaClip watermark + "Photography by Mohamed Gore" credit; look-4 may itim na bar)
  - Mi Hijabby Sabiha: 8 videos — 001700
  - Lahat live na ang rows sa DB (via apply_migration). Kinumpirma ni JG na galing sa Instagram ng mga artists ang media (consent ok).
- **Branding**: tunay na SA monogram (`web/public/brand/sa-monogram.png`) sa header, footer, sidebar, sign-in, hero arch, bridal arch, favicon, apple-touch-icon, og-image. Pangalang "Shahina Ahmed" ay **trinace mula sa mismong logo niya** (`brand/source-logos/shahina-logo-black.png` → `python3 brand/trace_name.py` → `brand/name_path.json` → `python3 brand/build_brand.py <fonts dir>` + `node brand/render.cjs`), kasama ang heart sa i. Wala nang Pinyon font. Hindi cursive: footer "© year", topbar subtitle, document titles.

## 5. Mga susunod na gagawin (priority)
1. **I-verify ang live site** (JG o browser tool): landing, gallery videos nagpe-play, sign-in, dashboard, logo/favicon. Tingnan din kung maayos ang 3-column hero ng artists at mobile.
2. Docs: BUILD_STATE/MISSING_INFO/HANDOFF updated para sa restored Shahina + traced lettering + gallery (README hindi pa).
3. Shahina gallery: 3 videos (isa ay logo reveal, nasa dulo) + 14 photos sa `web/public/gallery/shahina-ahmed/`.
3. **Gallery polish**: ayusin/palitan ang Shirin look-8 (watermark) at look-4 kung gusto ni JG; posibleng i-feature ang gallery sa artist pages (tingnan kung lumalabas, `web/src/public/artist.ts`); isaalang-alang ang autoplay-on-view na muted loop kung hihilingin.
4. **Business info na kulang** (tingnan `docs/MISSING_INFO.md`): address, phone/WhatsApp, hours, service durations/prices, policies.
5. **Pagpapatunay ng pangalan** kay JG: "Sofia MUA" vs "Sofia Musa" (logo lettering), "Mi Hijabby Sabiha" vs "Mi Hijab by Sabiha"; relasyon ng tatlong salons/iisang building?
6. **Bago mag-go-live (kailangan ng explicit OK ni JG)**: tanggalin ang demo accounts at sample data; gumawa ng totoong owner invitation gamit ang email ni Shahina (naka-block ng `owner_exists` hangga't may demo owner).
7. Para kay JG mismo (hindi ko magagawa): Supabase Auth settings — Site URL `https://3salon.netlify.app`, redirect `https://3salon.netlify.app/reset`, i-disable ang signups, SMTP credentials (siya ang maglalagay sa Dashboard); SimplyBooked cleanup.
8. Acceptance checklist (`docs/ACCEPTANCE.md`) bago i-on ang online booking/SMS.

## 6. Mga bagay na dapat tandaan
- Hindi pa nasubukan ang totoong browser login (403 sa auth host mula rito); SQL simulation lang ng JWT claims.
- `accept-invite` password min 10 chars; demo accounts ay ginawa via SQL kaya may 6-char passwords.
- Kapag magdadagdag ng media: i-compress gamit ffmpeg (540px wide, crf 29, `-an`, faststart), gumawa ng `-poster.jpg`, ilagay sa `web/public/gallery/<slug>/`, gumawa ng bagong migration na `insert ... on conflict (storage_path) do nothing`, i-apply sa live via `apply_migration`, push.
- Para sa susunod na media na kailangang Studio → Gallery upload: gumagana ito (bucket `portfolio` at functions live).
