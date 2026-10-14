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
