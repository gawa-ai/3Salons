# Build state (2026-10-07)

Labels: **VERIFIED** = tested, at may resulta sa ibaba. **SUPPORTED** = sinusuportahan ng ebidensya pero hindi pa na-test sa live site. **HYPOTHESIS** = hindi pa napapatunayan.

| Bahagi | Status | Ebidensya |
|---|---|---|
| Database logic: booking engine, provisional flow, separation, invites, audit, DST, concurrency | **VERIFIED** (local PG16) | `tests/db/run.sh` 114/114, paulit-ulit |
| Frontend flow laban sa totoong SQL (public booking, owner, staff, responsive, CSP) | **VERIFIED** (local) | `tests/e2e/run.cjs` 33/33; `docs/e2e-results.txt`; 34 screenshots |
| Schema, functions, grants at seed sa live "3 Salons" | **VERIFIED** | Ang md5 ng 88 functions ay tugma sa local; mga live query (tingnan ang `PERMISSIONS.md`) |
| Live separation (visitor, Sofia vs Shirin, direct table access) | **VERIFIED** live | Rolled-back transaction, 2026-10-07; walang naiwang data |
| Profile labels ayon sa brief + specialties ayon sa logo/price list | **VERIFIED** live | Migration `profile_labels`; query ng professionals/services |
| FK indexes (performance advisor) | **VERIFIED** live | Migration `fk_indexes` |
| 4 dashboard functions na may DELETE + portfolio storage bucket | **VERIFIED** live (2026-10-07) | Na-run ni JG ang `supabase/manual/01_pending_functions_and_storage.sql`; kumpirmado ng query: 4 functions (SECURITY DEFINER, empty search_path, anon walang access, authenticated meron), bucket `portfolio`, 4 storage policies |
| Edge function `accept-invite` | Deployed (v2, CORS para sa 3salon.netlify.app). **SUPPORTED** | Na-test ang logic sa mock (E2E O6/S-flows). Hindi pa natatawag mula sa live browser |
| Netlify deploy | Live sa `https://3salon.netlify.app` (si JG ang nag-link). Hindi ko ma-verify mula sa workspace | Naka-block ang Netlify API |
| Password reset emails | **HYPOTHESIS** | Kailangan ang Site URL/redirect + custom SMTP sa Supabase Auth |
| SMS / WhatsApp / calls | **Not connected** (sinadya) | Outbox lang; ang site at dashboard ay tapat na "Not connected" |
| SimplyBooked cleanup | **Inihanda + VERIFIED local** (7/7), **HINDI pinatakbo** | `supabase/manual/simplybooked_cleanup.sql`, `tests/db/30_simplybooked_cleanup.sh` |
| Portfolio photos/videos | **Wala pa** | Tingnan ang `MISSING_INFO.md` §1 |

| Shahina = owner AT public professional (ibinalik 2026-10-07 sa utos ni JG) | **VERIFIED** live (migration) + local (115 DB, 33 e2e) | Migration `shahina_professional_gallery`: 4 public professionals, siya ang first card (circular logo, IG shahinaahmedmua), 4 services reactivated (placeholder prices, unconfirmed), 17 gallery items. Owner membership/invite ay walang professional (owner view pa rin ng lahat). Pinapalitan nito ang epekto ng `owner_not_bookable` |
| Demo logins (live, 2026-10-07) | **VERIFIED** sa DB | 4 sample accounts: `shahinaahmed@sample.com` (owner), `sofiamua@`, `shirinjal@`, `mihijabbysabiha@` (`@sample.com`). Password hash ay tugma; owner nakakakita ng Team at All professionals; bawat staff ay naka-scope sa sariling artist at `forbidden` sa Team at sa ibang artist. Totoong browser login ay hindi na-test mula sa workspace (naka-block ang Supabase Auth host) |

## Ano ang hindi ginalaw
- SimplyBooked repo, Supabase project at Netlify site: walang binago.
- Ang mga orihinal na logo ng artists (`brand/source-logos/`) ay hindi binago. Ang mga `web/public/brand/pros/*.webp|png` ay resized copies lang para sa web.

## Sample data sa live (2026-10-07)
7 bookings (3 confirmed, 4 awaiting confirmation) at 2 bridal enquiries, lahat gawa-gawa lang. Mga numero ay nasa reserved fictional range `+44 7700 9001xx` (07700 900101 hanggang 900113). Walang naipadala: lahat ng 13 notifications ay `not_connected`. Tatanggalin bago mag-live, kasama ang demo accounts; hihingi muna ng OK ni JG bago magbura (hindi ito automated na script).

## BAGO MAG-LIVE: tanggalin ang demo accounts
Mahina ang password ng demo accounts (hiningi ni JG para sa preview). Bago ang totoong owner invitation at bago i-on ang Live mode: i-disable o burahin ang apat na `@sample.com` users (Studio -> Team -> Disable login, o sa Supabase Auth). Hanggang may aktibong demo owner, tatanggihan ng `02_owner_invitation.sql` ang totoong owner (`owner_exists`).

## Round 1 client feedback (2026-10-13) — DONE
- Hero headline/copy, bridal + About copy, address 199 Preston New Road BB2 6BN, "Studio" wording, black/gold/cream palette (no pink/purple), artist cards show first names, "Sofia Musa", booking-page words removed.
- Gallery: only the 4 photos Shahina sent are published; 42 others hidden (published=false), not deleted.
- Migration `20261013194500_client_feedback_round1.sql` applied live (verified by SQL). DB tests green (incl. 16c-16g), e2e 33 checks pass.
- Still open: opening hours, phone, prices; confirm "Mi Hijabby Sabiha"; demo accounts/sample data removal before go-live (needs explicit OK).

## Round 2 client feedback (2026-10-14) — DONE
- 7 amendments from the PDF: bridal names/roles, gallery captions (Shahina first), logos with one white circular border, neutral cards, no service descriptions (pricing notes kept), "Sabiha Patel", "Book Directly with Your Favourite Artist" intro, Training (enquire-only) for Shahina.
- Migration `20261014050000_client_feedback_round2.sql` applied live and verified. Commit `011661b`.
- Gallery blur: sources are low-res (~464x662); needs original photos from Shahina (as Document).

## Round 3a client feedback (2026-10-14) — DONE
- "15 min buffer" text removed from Studio booking details; "All bookings are strictly by appointment only." under opening hours; gallery images open in a lightbox (click/Esc to close).
- Customer texts now include the studio address (`app.message_body`); migration `20261014090000_client_feedback_round3a.sql` applied live and verified. Commit `4cd8ace`.
- DB suite green (incl. 16k), e2e 36 checks pass.
- WAITING (round 3b): Shahina's contact number for confirmation text; opening hours 6:30am-5pm (which days); deposit flow (bank transfer vs Stripe, makeup-only amount, 24h expiry). Bank details must NEVER go in git/code; owner-editable setting only.

## Round 3b/3c (2026-10-14)
- 3b: confirmation text adds "Questions? Call <salon phone>." only when the salon phone is set (Studio > Settings > Phone). Migration `20261014100000_client_feedback_round3b_contact.sql`, applied live.
- 3c: client decided messages go out by SMS AND email. Every customer message is also recorded as an email row when the client left an email (`salons.email_connected` default false, so nothing is sent yet). Studio message log labels Text/Email. Migration `20261014110000_client_feedback_round3c_email.sql`.
- Both channels need the client's own provider accounts (SMS and email sending), paid by the client; keys go in secure settings, never in git or chat.
- STILL OPEN: deposit flow (bank transfer vs Stripe, makeup-only amount, 24h expiry), 6:30am-5pm days, Shahina phone number, original photos. AI voice: client said not now.

## Lumipat ng Netlify (2026-10-14)
- Bagong site: `https://shahinaahmed.netlify.app` (project `shahinaahmed`, deploy mula sa GitHub main). Lahat ng build settings at public keys ay nasa `netlify.toml`, kaya walang env vars na kailangan.
- Edge function `accept-invite` (v3, live): tinatanggap na ang bagong origin. Ang lumang `3salon` origin ay nakalista pa rin.
- Ang bagong site ay "Private" (Netlify team login) hanggang pindutin ang "Make public". Hindi pa ito mabubuksan ng client.
- JG pa ang gagawa: Supabase Auth > URL Configuration: Site URL `https://shahinaahmed.netlify.app`, Redirect `https://shahinaahmed.netlify.app/reset`. I-unlink o i-pause ang lumang `3salon` site para hindi doble ang build.

## Domain (2026-10-14)
- Mohsin bought `shahinaahmed.co.uk`. Edge function `accept-invite` v4 (live) already accepts it and `www`.
- Pending: add the domain in Netlify (Domain management), set DNS at the registrar (the values Netlify shows), then Supabase Auth Site URL `https://shahinaahmed.co.uk` + redirect `https://shahinaahmed.co.uk/reset`.
- Later, the same domain can send email (needs the email provider's SPF/DKIM DNS records).

## Round 4: deposit flow (2026-10-14) — BUILT + TESTED LOCAL, NOT YET LIVE
- Flow (Shahina's wording): customer books online (pending) -> artist accepts -> if the service has a deposit, the booking stays pending, the slot is held for 24h (`salons.deposit_hours`) and the customer gets the deposit request (amount, "non refundable", "deducted on the day", payment details, reference) -> the studio checks its own bank and presses "Deposit received" -> confirmed + "deposit received" message -> no deposit in time = expired, slot released, customer told.
- Bank transfer only. No money moves on the website. Payment details are typed by the owner in Studio > Settings > Deposits (`salons.deposit_instructions`); they are NEVER in git, code or the audit log.
- Migration `20261014120000_deposit_flow.sql`: deposit columns (services, salons, bookings), snapshot trigger, new message texts (`deposit_request`, `deposit_received`, `deposit_expired`), `salon_dash_booking_action` (confirm -> request deposit; `deposit_received`), `expire_stale`/`expire_all`, `salon_public_manage` (shows payment details while a deposit is due), `salon_owner_deposits` / `salon_owner_deposits_save`. Default deposits: hair 10, hijab 10, hair+makeup 20 (client's words). Makeup only, saree, bridal: NOT set (unconfirmed), owner sets in Settings.
- Auto-release of unpaid deposits runs every 10 minutes only if pg_cron is enabled in Supabase; otherwise it happens when Studio is opened.
- Messages still go nowhere until SMS/email providers are connected: Studio has a "Copy deposit message" button to send it by WhatsApp meanwhile; the customer's booking link page also shows the payment details.
- Not built: receipt/screenshot upload (optional phase 2; the studio confirms from its own bank).
- Tests: DB 112 incl. D1-D16 + concurrency; e2e 38 (O9, O10); typecheck + build OK.
- DO NOT push to main before the migration is applied live (the Studio Settings page calls the new functions).

## Round 5 (2026-10-15): client wording for the deposit message, opening hours
- Deposit request text now follows Shahina's own wording line by line (migration `20261015010000_deposit_message_format.sql`, applied live): "{pro} is available for {service} on {when}", studio note, deposit sentence, her payment details (typed in Studio), "Please leave your ref ... as the payment reference", then signature block (salon name, "Makeup Artist", address lines, private number). Line breaks are kept; the Studio drawer shows them (`white-space: pre-wrap`) and "Copy deposit message" copies them as-is. Test D21 + updated D17.
- Opening hours: studio and all four artists 06:30-17:00 every day (live data), `hours_confirmed = true`, so the website shows the hours. The "will be published soon" placeholder text is removed from the site.
- Applied live via SQL (apply_migration prompt kept being cancelled): deposit_flow (by JG in the SQL editor), message format (execute_sql).

## Round 6 (2026-10-15): each artist can be paid into their own bank account
- Client question: can artists be paid into their own banks? Yes. Studio > Settings > Deposits now has an optional own-account box per artist. Blank = the studio details are used. The deposit request text and the client's booking page use the artist's account when set.
- Stored in `app.professional_payment_details` (own table, RLS on, no API access, never in git, never in the audit log). Migration `20261015030000_artist_payment_details.sql`, applied live with execute_sql and verified (table, RLS, grants, function bodies). Tests D22-D28 (DB 112 + concurrency OK), e2e O11a/O11b (40 checks).
- Only the owner can set artist accounts (artists cannot read or change them).
- Email: Mohsin offered bookings@shahinaahmed.co.uk for notification emails. Needs DNS access (SPF/DKIM) when we set up the email provider.

## Round 8 (2026-10-20): texts (SMS) built and proven, site gated "Coming soon"
- SMS provider: The SMS Works (UK). Account verified by their support, 50 free credits added. Live test text received on Mohsin's UK mobile from sender "Shahina" (job: test row, `sent:1`). Auth must use the `JWT <token>` scheme (raw token gives 401). Sender "Shahina": seen by Mohsin, explicit OK still to be asked.
- Outbox (migration `20261016100000_sms_outbox.sql`, applied live): `app.notifications` gains attempts/next_attempt_at/locked_at/sent_at/provider_message_id; `public.sms_claim` (FOR UPDATE SKIP LOCKED, only connected salons or `sms_test`, stale lock >5 min -> failed `unknown_send_state`, never auto-resent) and `public.sms_complete` (sent/failed/retry/skipped, retry capped at 3 attempts with back-off). service_role only.
- Edge Function `send-notifications` (v6 live, `verify_jwt=false`, source in `supabase/functions/send-notifications/index.ts`). Secrets `SMSWORKS_JWT`, `SMS_SENDER` live in Supabase, never in git. Single send attempt, no auto-resend on network error. Rejects non-UK-mobile numbers.
- pg_cron job `app-send-sms` (every minute, applied live via `20261020120000_sms_cron.sql`, guarded so local tests skip it). Verified: runs succeed, function answers 200 `claimed:0`.
- Studio > Settings > "Which texts are sent to clients": per-type switches (request_received, deposit_request, deposit_received, confirmed, deposit_expired, rescheduled, cancelled). Migration `20261020130000_sms_purpose_toggles.sql` (RPC `salon_owner_sms_save`, owner only, audited). Defaults: on = confirmed, deposit_request, deposit_received, rescheduled, cancelled; off = request_received, deposit_expired. FIX: `deposit_received` was missing from the earlier default, so a client who paid the deposit would have got no confirmation text.
- Reminder texts DO NOT EXIST yet (nothing in the system creates a "reminder" notification). Only built if the client asks.
- `salons.sms_connected` is still FALSE. Set it to true only after: sender name OK from Mohsin, toggles migration applied live, final test. While false, nothing goes to customers.
- Tests: DB suite S1-S15 (toggle permissions, claim/lock/retry/stale/connected), all pass with D1-D35 and concurrency; e2e 46 pass.
- Site gate: `netlify.toml` has a temporary "COMING SOON GATE" block (forced rewrites to `web/public/coming-soon.html`). Delete that block to go live.
- Go-live data cleanup: `supabase/ops/go_live_cleanup.sql` (backs up to schema `backup_golive`, then clears test bookings, clients, enquiries, notifications, audit log; tested locally including restore). NOT run. Live counts at 2026-10-20: 19 bookings (2 upcoming active), 16 clients, 2 enquiries. Needs JG's explicit OK; check the 2 upcoming bookings are not real first.
- Customer manage page: can cancel, cannot reschedule (the client contacts the studio, who moves it in Studio). Payments stay bank transfer; Stripe only if the client asks (phase 2).

## Round 9 (2026-10-20)
- Live: site opened (gate removed), SMS live, test data cleaned (backup in `backup_golive`).
- Email field removed from booking and enquiry forms. Artist boxes equal size.
- Multi-artist same-time booking: migration `20261020140000_multi_artist_booking.sql` (`salon_public_book_multi`, `bookings.group_id`), 2-3 artists, all-or-nothing, one private link each. UI: "Add another artist at the same time" on the Review step; done page shows one card per booking. DB tests M1-M6, e2e M-UI1..3 (50 e2e checks pass).
- Migration must be applied live (paste in Supabase SQL editor).
- Not built: reminders, SEO (needs address/phone), PWA, owner delete booking, Stripe/Apple Pay.
- Owner-only Delete booking (`20261020150000_owner_delete_booking.sql`, `salon_owner_booking_delete`): only for cancelled/declined/expired/completed/no-show; active ones must be cancelled first; audit keeps a snapshot. Button "Delete" in the booking dialog (owner only).
- Round 9b (2026-10-21): multi-artist items may have their own time (`items[].time`); deposit snapshot = service deposit x party_size; dashboard "Next 7 days" = confirmed only (+ "plus N awaiting"); add-artist button now primary (was invisible on iPhone). Migration `20261021100000_multi_time_deposit_party.sql` (apply live).
