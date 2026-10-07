# Go-live acceptance checklist

Hanggang hindi pa naka-tsek lahat ng nasa ibaba, nananatiling `booking_mode = 'preview'` (may "Preview site" banner, at test booking lang ang bawat booking) at walang SMS na naipapadala.

## A. Setup (JG)
- [ ] **Bago mag-live:** i-disable/burahin ang 4 demo accounts (`@sample.com`, mahina ang password) at saka gawin ang totoong owner invitation.
- [x] Na-run ang `supabase/manual/01_pending_functions_and_storage.sql` sa "3 Salons" (verified live 2026-10-07).
- [ ] Naka-link ang Netlify site `3salon` (`https://3salon.netlify.app`) sa `gawa-ai/3Salons` (main), at successful ang deploy.
- [ ] Supabase Auth: Site URL `https://3salon.netlify.app` + `/reset` redirect, naka-off ang public sign-ups, custom SMTP.
- [ ] Owner invitation (`02_owner_invitation.sql`), at naka-sign in si Shahina sa `/join`.

## B. Owner (Shahina, sa totoong site)
- [ ] Studio → Professionals: kumpirmado ang pangalan, specialty at Instagram ng bawat artist (tingnan ang `MISSING_INFO.md` §2).
- [ ] Studio → Settings: address, phone/WhatsApp, booking policy.
- [ ] Studio → Availability → Salon hours: tamang oras. I-tick ang "These are the confirmed opening hours" (kailangan muna ang step A1).
- [ ] Studio → Services: tamang duration bawat service. I-tick ang "details confirmed".
- [ ] Studio → Professionals → Invite: tig-isang code para kay Sofia, Shirin at Sabiha.

## C. Staff (bawat artist, sa sarili niyang phone)
- [ ] Nakapag-sign in gamit ang sariling code.
- [ ] Availability: tamang working hours at time off.
- [ ] Gallery: naka-upload ang mga photo (may pahintulot ng client).

## D. Live test (preview mode)
- [ ] Mag-book bilang customer kay Sofia → "Awaiting confirmation" ang lumalabas, at nasa "Needs confirming" ni Sofia.
- [ ] Naka-sign in bilang Shirin → **hindi** makikita ang booking ni Sofia (wala sa calendar, bookings at clients).
- [ ] Ang booking ni Sofia ay nakikita ni Shahina sa "All professionals" at sa filter na Sofia.
- [ ] Sofia → Confirm. Ang status sa private link ng customer ay naging confirmed.
- [ ] Parehong oras, ibang customer → tinanggihan (slot taken).
- [ ] Customer → Cancel gamit ang private link. Bakante na ulit ang oras.
- [ ] Bridal enquiry → lumabas sa Enquiries ng tamang artist at ng owner.
- [ ] Mobile (390 px) at tablet: walang sira ang layout.
- [ ] Studio → Activity log: nakatala ang mga ginawa sa itaas.
- [ ] Linisin ang test bookings: i-decline o i-cancel. Walang delete na kailangan.

## E. Go-live (Shahina o JG, kapag pumasa lahat)
- [ ] Studio → Settings → Booking mode: **Live**.
- [ ] (Hiwalay na desisyon) SMS/WhatsApp provider. Naka-"Not connected" hanggang may go-signal.
