# HANDOFF — Shahina Ahmed salon site (para sa next tab)

Huling update: 2026-10-14. Basahin muna ito, tapos `docs/BUILD_STATE.md` ("Round 4: deposit flow").

## Sino / ano
- JG = principal contact (Taglish, build-first, Philippines). Mohsin = client-side contact na nagre-relay ng requests ni Shahina.
- Repo `gawa-ai/3Salons` → `/home/claude/3salons`. Supabase project `vqkrvbtndnnxpcemkuce`. Netlify site `shahinaahmed` (deploys from GitHub main). Domain `shahinaahmed.co.uk` / `www.shahinaahmed.co.uk`.
- Hiwalay ito sa SimplyBooked / Booking OS. Huwag galawin ang SimplyBooked.

## Standing rules (huwag labagin)
- Huwag hilingin kay JG na mag-paste ng secrets sa chat. Walang service-role key sa frontend.
- Bank details at private phone: NEVER sa repo, code, chat o memory. Ilalagay lang ni JG/Shahina sa Studio > Settings.
- Walang auto-send ng messages. Walang test messages sa totoong customers.
- Walang delete nang walang explicit OK ni JG at backup. Walang external spend.
- SMS/email provider accounts (Twilio, email) = tayo (JG + Claude) ang gagawa, hindi ginagabay ang client. Client lang ang magbibigay ng business details, card (sila mismo maglalagay), DNS access, sender choice.

## Estado ngayon
**Built + tested LOCAL, hindi pa live:**
- Deposit flow: booking → artist accepts ("Accept and ask for deposit") → deposit request message → salon pinipindot ang "Deposit received" → confirmed + message. Bank transfer, walang Stripe.
- Deposits: £10 hair/hijab, £20 hair+makeup (backfill sa migration). Makeup-only/saree/bridal = 0 pa (owner ang magse-set sa Studio).
- Slot hold `deposit_hours` (default 24); pag lumipas → status `expired` + `deposit_expired` message. pg_cron job `app-expire-stale` tuwing 10 min.
- Payment details lang makikita ng customer sa manage-link page habang may deposit due. `salons.private_phone` (hiwalay sa public `phone`) lumalabas lang sa `confirmed`/`deposit_received` texts at sa manage page pag confirmed na.
- Fix na rin: `salon_owner_settings_save` audit ay hindi na nagla-log ng bank details/private phone.
- Tests: DB 112/112 (`tests/db/run.sh`), e2e 38 (`tests/e2e/run.cjs`), typecheck + build OK.
- Git: local commits `d990206` at `b88b661` sa main, **HINDI pa pushed**.
- Migration file: `supabase/migrations/20261014120000_deposit_flow.sql`.

**Live DB ngayon:** walang deposit columns, walang cron job `app-expire-stale`; `app.opening_hours` = weekday 0–6 bawat isa 10:00–18:00 (ito ang backup values). pg_cron extension installed na (1.6.4). Live migrations nagtatapos sa `client_feedback_round3c_email`.

## BLOCKER
`mcp__Supabase__apply_migration` (name `deposit_flow`) ay nag-return ng `{"status":"cancelled"}` DALAWANG BESES — malamang hindi na-approve ang prompt. Huwag mag-loop. Sabihan si JG na i-approve ang prompt; kung ayaw pa rin, ibang paraan (hal. si JG magpa-paste ng SQL sa Supabase SQL editor mula sa migration file — walang secrets doon).

## Susunod na gagawin (sunod-sunod)
1. Ma-apply ang `20261014120000_deposit_flow.sql` sa live. I-verify: bagong columns (`salons.private_phone/deposit_instructions/deposit_hours`, `services.deposit_pence`, `bookings.deposit_*`), `cron.job` `app-expire-stale`, functions (`salon_owner_deposits`, `salon_owner_deposits_save`, updated `salon_dash_booking_action`, `salon_public_manage`, `salon_owner_settings_save`, `expire_stale`, `expire_all`), grants (anon walang access sa owner functions).
2. Studio hours: `update app.opening_hours set opens='06:30', closes='17:00'` para sa lahat ng 7 araw (update lang). Huwag galawin ang per-artist hours maliban kung sabihin ni JG.
3. Push main (`git -c safe.directory=/home/claude/3salons push origin main`) — saka lang pagkatapos ng #1, para ma-deploy sa Netlify.
4. Sabihan si JG: ilagay sa Studio > Settings ang bank details (Deposits panel) + private phone ni Shahina; i-set ang deposit ng makeup-only/saree/bridal kapag nakumpirma ang amounts.

## Natitira pagkatapos
- **Domain (JG):** i-set ang www bilang primary sa Netlify, confirm HTTPS, Make public; Supabase Auth Site URL `https://www.shahinaahmed.co.uk` at Redirect `https://www.shahinaahmed.co.uk/reset`; incognito test. Tapos i-update ang docs (BUILD_STATE, README, HANDOFF, ACCEPTANCE) sa final domain.
- SMS (Twilio) at email provider: tayo ang gagawa ng accounts; wire real sending (keys sa secure settings lang). Email provider hindi pa napipili/napre-presyo. Reference (USD, pwedeng magbago): Twilio UK SMS ~$0.056/segment, UK number ~$1.15/mo (mobile ~$2.50/mo), alphanumeric sender libre pero walang replies.
- Remove demo `@sample.com` accounts + sample data (kailangan explicit OK + backup). Alisin ang "Preview site" banner sa go-live.
- Optional phase 2: receipt/screenshot upload (HINDI pa built). Gallery original hi-res photos mula kay Mohsin. Optional rename "Bridal enquiry" → "Enquiry".
- Open tanong kay Mohsin/Shahina: deposit para sa makeup-only, saree, bridal; artists' own hours ba ay 6:30–17:00 din; original gallery photos; sender choice para sa SMS/email.

## Environment notes
- Walang npm registry: gamitin `/opt/npm-tools/node_modules` (symlink bilang `web/node_modules` at root `node_modules`, gitignored). Typecheck: `/opt/npm-tools/node_modules/.bin/tsc`; build: `node build.mjs` (sa `web/`).
- Local Postgres: `su claude -c "/usr/lib/postgresql/16/bin/pg_ctl -D /var/tmp/bospg/data -l /var/tmp/bospg/pg.log -o '-k /var/tmp/bospg -p 55432' start"`. Patakbuhin ang tests bilang user `claude`: `tests/db/run.sh`, `tests/e2e/run.cjs`.
- Git: gamitin `-c safe.directory=/home/claude/3salons`. Commit trailer: `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>` at `Claude-Session: https://claude.ai/code/session_01UVmTphvybHdkERYGa7aadL`.
- Reply style kay JG: Taglish, maikli, direkta, build-first.
