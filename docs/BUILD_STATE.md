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

| Shahina = owner lang, hindi artist | **VERIFIED** live + local | Migration `owner_not_bookable`: 3 public professionals, profile niya ay inactive/hidden (walang binura), `/artists/shahina-ahmed` → not found, owner invite walang professional |

## Ano ang hindi ginalaw
- SimplyBooked repo, Supabase project at Netlify site: walang binago.
- Ang mga orihinal na logo ng artists (`brand/source-logos/`) ay hindi binago. Ang mga `web/public/brand/pros/*.webp|png` ay resized copies lang para sa web.
