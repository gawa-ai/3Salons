import { h, icon, mount, newIdempotencyKey } from '../lib/dom';
import { button, linkButton, field, textarea, select, spinner, errorBox, notice, setBusy, confirmDialog, toast, statusBadge } from '../lib/ui';
import { rpc } from '../lib/supabase';
import { SALON_SLUG } from '../config';
import { formatDateLong, durationLabel, time12 } from '../lib/format';
import { loadProfile } from './data';
import { publicShell } from './layout';

// ===================================================================== bridal enquiry
export async function bridalPage(app: HTMLElement, query: URLSearchParams) {
  document.title = 'Bridal enquiry · Shahina Ahmed Luxury Salon';
  publicShell(app, null, [spinner()]);
  let profile;
  try { profile = await loadProfile(); } catch (e) {
    publicShell(app, null, [h('div', { class: 'container pad-y' }, errorBox((e as Error).message, () => bridalPage(app, query)))]);
    return;
  }
  const pros = profile.professionals;
  const idem = newIdempotencyKey();
  const pre = query.get('artist');
  const fPro = select({ label: 'Who would you like?', name: 'professional', value: pros.some((p) => p.slug === pre) ? pre! : 'any',
    options: [{ value: 'any', label: 'No preference, the salon will advise' }, ...pros.map((p) => ({ value: p.slug, label: `${p.display_name}${p.specialty ? ', ' + p.specialty : ''}` }))] });
  const fName = field({ label: 'Full name', name: 'name', required: true, autocomplete: 'name', maxlength: 80 });
  const fPhone = field({ label: 'Mobile number', name: 'phone', type: 'tel', required: true, autocomplete: 'tel', inputmode: 'tel' });
  const fEmail = field({ label: 'Email', name: 'email', type: 'email', autocomplete: 'email' });
  const fDate = field({ label: 'Event date', name: 'event_date', type: 'date', min: profile.salon.today, hint: 'If you are not sure yet, leave it blank.' });
  const fLoc = field({ label: 'Where is the event?', name: 'event_location', maxlength: 120, placeholder: 'Town or venue' });
  const fWant = field({ label: 'What would you like?', name: 'services_wanted', maxlength: 200, placeholder: 'For example bridal hair and makeup, hijab styling, family members' });
  const fMsg = textarea({ label: 'Tell us more', name: 'message', rows: 4, maxlength: 1500, placeholder: 'Timings, number of people, the look you have in mind…' });
  const honey = h('div', { class: 'honeypot', attrs: { 'aria-hidden': 'true' } }, h('label', null, 'Company', h('input', { attrs: { type: 'text', name: 'company', tabindex: '-1', autocomplete: 'off' } })));
  const err = h('div', { attrs: { 'aria-live': 'assertive' } });
  const submit = button('Send enquiry', { type: 'submit', size: 'lg' });
  const body = h('div', { class: 'enquiry-body' });
  const form = h('form', { class: 'enquiry-form', attrs: { novalidate: true } },
    fPro.wrap, h('div', { class: 'form-row' }, fName.wrap, fPhone.wrap), h('div', { class: 'form-row' }, fEmail.wrap, fDate.wrap),
    fLoc.wrap, fWant.wrap, fMsg.wrap, honey, err,
    h('p', { class: 'muted small form-note', text: 'We use these details only to reply to your enquiry. See our privacy notice.' }),
    submit);
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    [fName, fPhone, fEmail, fDate].forEach((f) => f.setError(null));
    mount(err);
    let ok = true;
    if (fName.input.value.trim().length < 2) { fName.setError('Please enter your name.'); ok = false; }
    if (fPhone.input.value.replace(/[^0-9]/g, '').length < 10) { fPhone.setError('Please enter a valid mobile number.'); ok = false; }
    if (fEmail.input.value && !/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(fEmail.input.value.trim())) { fEmail.setError('Please check your email address.'); ok = false; }
    if (!ok) { form.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus(); return; }
    setBusy(submit, true, 'Sending…');
    try {
      const r = await rpc<any>('salon_public_enquiry', { p_salon: SALON_SLUG, p_payload: {
        kind: 'bridal', professional: fPro.input.value, name: fName.input.value.trim(), phone: fPhone.input.value.trim(),
        email: fEmail.input.value.trim() || null, event_date: fDate.input.value || null, event_location: fLoc.input.value.trim() || null,
        services_wanted: fWant.input.value.trim() || null, message: fMsg.input.value.trim() || null,
        idempotency_key: idem, company: (honey.querySelector('input') as HTMLInputElement).value,
      } }, { anon: true });
      if (!r.ok) {
        setBusy(submit, false);
        if (r.error === 'phone_required') fPhone.setError(r.message);
        else if (r.error === 'email_invalid') fEmail.setError(r.message);
        else if (r.error === 'date_in_past') fDate.setError(r.message);
        else mount(err, notice('error', r.message));
        return;
      }
      mount(body, h('div', { class: 'done' },
        h('div', { class: 'done-mark', attrs: { 'aria-hidden': 'true' } }, icon('check', 26)),
        h('h2', { class: 'step-title', attrs: { tabindex: '-1' }, text: 'Thank you, your enquiry has been sent' }),
        h('p', { class: 'done-lede', text: r.professional ? `${r.professional} will get back to you about your date.` : 'The salon will get back to you about your date.' }),
        profile.salon.booking_mode === 'preview' ? notice('warn', 'Preview site: this is a test enquiry while the salon gets ready to launch.') : null,
        h('p', { class: 'done-actions' }, linkButton('Back to the salon', '/', { variant: 'ghost' }))));
      body.querySelector<HTMLElement>('h2')?.focus();
    } catch (e2) {
      setBusy(submit, false);
      mount(err, notice('error', (e2 as Error).message));
    }
  });
  mount(body, form);
  publicShell(app, profile, [h('section', { class: 'enquiry' },
    h('div', { class: 'container enquiry-grid' },
      h('div', { class: 'enquiry-intro' },
        h('h1', { class: 'page-title', text: 'Bridal enquiry' }),
        h('p', { class: 'lede', text: 'Tell us about your day. The artist will reply with availability and a quote; nothing is booked until you both agree.' }),
        h('ul', { class: 'tick-list' },
          h('li', null, icon('check', 16), h('span', { text: 'Bridal hair, makeup and hijab styling' })),
          h('li', null, icon('check', 16), h('span', { text: 'Choose an artist or let the salon advise' })),
          h('li', null, icon('check', 16), h('span', { text: 'No payment is taken online' })))),
      body))]);
}

// ===================================================================== manage link
export async function managePage(app: HTMLElement) {
  document.title = 'Your booking · Shahina Ahmed Luxury Salon';
  const token = new URLSearchParams(location.hash.replace(/^#/, '')).get('t') ?? '';
  const profile = await loadProfile().catch(() => null);
  const body = h('div', { class: 'manage' }, spinner('Loading your booking'));
  publicShell(app, profile, [h('section', { class: 'container pad-y narrow' }, h('h1', { class: 'page-title', text: 'Your booking' }), body)]);
  if (!token) { mount(body, notice('error', 'This link is incomplete. Open the full link you saved when you booked.')); return; }

  const load = async () => {
    const r = await rpc<any>('salon_public_manage', { p_token: token }, { anon: true }).catch((e) => ({ ok: false, message: (e as Error).message }));
    if (!r.ok) { mount(body, notice('error', r.message || 'This link is not valid or has expired.'), h('p', { class: 'mt' }, linkButton('Book again', '/book'))); return; }
    const b = r.booking; const s = r.salon;
    const cancelBtn = b.can_cancel ? button('Cancel this booking', { variant: 'secondary', onClick: async () => {
      const c = await confirmDialog({ title: 'Cancel this booking?', message: `${b.service} with ${b.professional} on ${b.when}. The time will be released for other clients.`, confirmLabel: 'Cancel booking', danger: true, reasonLabel: 'Reason (optional)' });
      if (!c.ok) return;
      const res = await rpc<any>('salon_public_manage_cancel', { p_token: token, p_reason: c.reason || null }, { anon: true }).catch((e) => ({ ok: false, message: (e as Error).message }));
      if (!res.ok) { toast(res.message, 'error'); return; }
      toast('Your booking has been cancelled');
      void load();
    } }) : null;
    mount(body,
      h('p', { class: 'lede', text: `Hi ${b.first_name || 'there'}, here are your booking details.` }),
      h('dl', { class: 'review' },
        h('dt', { text: 'Reference' }), h('dd', { class: 'ref', text: b.ref }),
        h('dt', { text: 'Status' }), h('dd', null, statusBadge(b.status)),
        h('dt', { text: 'Artist' }), h('dd', { text: b.professional }),
        h('dt', { text: 'Service' }), h('dd', { text: `${b.service}, about ${durationLabel(b.duration_min)}, ${b.price_label}` }),
        h('dt', { text: 'When' }), h('dd', { text: `${formatDateLong(b.local_date)} at ${time12(b.local_time)} (UK time)` }),
        s.address ? [h('dt', { text: 'Where' }), h('dd', { text: s.address })] : null),
      b.status === 'pending' ? notice('info', `${b.professional_short} has not confirmed this booking yet. The time is held for you in the meantime.`) : null,
      b.status === 'declined' ? notice('warn', `${b.professional_short} could not take this booking${b.status_reason ? ': ' + b.status_reason : ''}. Please choose another time.`) : null,
      s.booking_policy ? h('div', { class: 'policy' }, h('p', { class: 'policy-title', text: 'Booking policy' }), h('p', { class: 'policy-text', text: s.booking_policy })) : null,
      h('div', { class: 'manage-actions' }, cancelBtn, linkButton('Make another booking', '/book', { variant: 'ghost' })),
      (s.phone || s.whatsapp) ? h('p', { class: 'muted small mt', text: `Need to change something else? Contact the salon${s.phone ? ' on ' + s.phone : ''}${s.whatsapp ? ' or WhatsApp ' + s.whatsapp : ''}.` }) : null);
  };
  await load();
}

// ===================================================================== privacy notice
export async function privacyPage(app: HTMLElement) {
  document.title = 'Privacy · Shahina Ahmed Luxury Salon';
  const profile = await loadProfile().catch(() => null);
  const s = profile?.salon;
  const P = (t: string) => h('p', { text: t });
  publicShell(app, profile, [h('section', { class: 'container pad-y prose' },
    h('h1', { class: 'page-title', text: 'Privacy notice' }),
    s?.booking_mode !== 'live' ? notice('warn', 'Draft for the salon to review before launch.') : null,
    h('h2', { text: 'What we collect' }),
    P('When you book or send an enquiry we collect your name, mobile number and, if you give it, your email address and any note you add. We also keep the details of your appointment.'),
    h('h2', { text: 'Why we use it' }),
    P('To arrange and manage your appointment or reply to your enquiry. If you tick the optional box, we may also send you occasional news and offers; you can ask us to stop at any time.'),
    h('h2', { text: 'Who can see it' }),
    P('Only the artist you book and the salon owner. Each artist sees only their own clients. We do not sell your details.'),
    h('h2', { text: 'Where it is stored' }),
    P('Your details are stored securely with our booking system provider (Supabase, hosted in the European Union).'),
    h('h2', { text: 'Your rights' }),
    P('You can ask to see, correct or delete the information we hold about you. Contact the salon and we will help.'),
    h('h2', { text: 'Contact' }),
    P(s?.email ? `Email ${s.email}.` : 'Contact the salon directly.'))]);
}
