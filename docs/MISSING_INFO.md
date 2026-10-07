# Missing information (for JG to ask the client)

Wala sa site ang anumang hindi kinumpirma ng client. Kapag wala ang value, sinasabi ng site na "will be published soon" at walang ini-imbento.

## 1. Photos and videos (oo, kailangan)

Wala pang totoong portfolio photo sa site. Ang gallery at artist pages ay nagpapakita lang ng logo hanggang may ma-upload. Bawat artist ay puwedeng mag-upload mismo sa **Studio → Gallery** (kapag na-run na ang `supabase/manual/01_pending_functions_and_storage.sql`), o ipadala kay JG.

| Para kanino | Ano | Format |
|---|---|---|
| Bawat artist (Sofia, Shirin, Sabiha) | 6–12 portfolio photos ng sariling trabaho (party hair, makeup, hijab, saree, bridal) | JPG/PNG/WebP, portrait 4:5, mga 1600 px ang haba ng gilid o mas malaki |
| Bawat artist, optional | 1–3 maikling video (before/after, styling process) | MP4/MOV, 9:16, hanggang 50 MB, 15–60 segundo |
| Bawat artist, optional | Isang portrait/headshot para sa profile | JPG, square o 4:5 |
| Salon | 3–6 photos ng loob ng salon (chair, mirror, lighting) para sa About section | JPG, landscape 3:2 |
| Lahat | **Pahintulot ng client** na makikita sa photo/video na mailagay ito sa website | yes/no bawat larawan |

Hindi gagamit ng stock o AI-generated photos bilang "trabaho" ng artists.

## 2. Names and labels (kumpirmahin)

| Brief (ginamit sa site) | Iba ang nakasulat sa | Tanong |
|---|---|---|
| **Sofia MUA** | Logo at Instagram: "sofia musa" / @sofimusamua; price list: "Sofi" | "Sofia MUA" o "Sofia Musa" ang gusto niyang pangalan sa site? |
| **Mi Hijabby Sabiha** | Logo: "Mi hijab BY SABIHA"; Instagram @mi.hijabbysabiha | "Mi Hijabby Sabiha" o "Mi Hijab by Sabiha"? |
| **Shirin Jal** | Pareho sa logo | — |
| **Shahina Ahmed** | Owner at public professional (ibinalik ni JG 2026-10-07) | Kumpirmahin ang services/prices/oras niya (placeholder pa) |

Ang pagpapalit ng pangalan ay isang update lang sa Studio → Professionals. Walang code change.

## 3. Business details (hindi pa naka-publish)

- **Address** ng salon (city lang ang alam: Blackburn, mula sa Instagram bios).
- **Phone / WhatsApp** para sa enquiries.
- **Opening hours** ng salon at **working hours** ng bawat artist. Staging ngayon: 10:00–18:00 araw-araw, at hindi ito ipinapakita sa publiko (`hours_confirmed = false`).
- **Duration** ng bawat service. Staging ngayon: Party Hair 60, Makeup 60, Hair & Makeup 120, Hijab 30, Saree 30 (+15 min buffer). Hindi pa kumpirmado (`details_confirmed = false`).
- **Deposit / cancellation / lateness policy.** Wala sa site hanggang ibigay.
- **Studio lang ba o may home visit/travel** para sa bridal?
- **Ano ang eksaktong relasyon ng tatlong salon kay Shahina** (isang building ba, o magkakahiwalay?) para sa About text. Ang site ay nagsasabi lang na "owned by Shahina Ahmed".
- **Login emails** ni Shahina at ng tatlong artist (para sa invitation codes).

## 4. Technical decisions para kay JG

- **Region.** Nasa **eu-west-1 (Ireland)** ang "3 Salons". Ang handoff ay nagmungkahi ng London (eu-west-2). Gumagana ito nang maayos para sa UK. Kung kailangang London para sa data residency, gagawa ng bagong project at ire-run ang migrations (mga 10 minuto; wala pang totoong data).
- **SMS/WhatsApp notifications.** Naka-"Not connected". Walang naipapadala. Kailangan ng provider at go-signal bago buksan.
- **Custom domain** (kung meron) para sa Netlify at Supabase Auth redirect URLs.
