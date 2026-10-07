import { h, icon, mount, newIdempotencyKey } from '../lib/dom';
import { button, linkButton, field, textarea, checkbox, spinner, errorBox, notice, setBusy, toast } from '../lib/ui';
import { rpc, ApiError } from '../lib/supabase';
import { SALON_SLUG } from '../config';
import { addDays, formatDateLong, formatMonthYear, weekdayOf, durationLabel, minutesOf } from '../lib/format';
import { loadProfile, type PublicProfile, type PublicPro, type PublicService } from './data';
import { publicShell, proMark } from './layout';

interface State {
  pro: PublicPro | null;
  service: PublicService | null;
  date: string | null;
  time: string | null;
  timeLabel: string | null;
  name: string; phone: string; email: string; note: string; marketing: boolean; policy: boolean;
  idem: string;
  step: 1 | 2 | 3 | 4 | 5;
  month: string; // YYYY-MM-01 shown in the calendar
  flash: string | null;
}

const STEPS = ['Artist', 'Service', 'Date and time', 'Your details', 'Review'];

export async function bookPage(app: HTMLElement, query: URLSearchParams) {
  document.title = 'Book an appointment · Shahina Ahmed';
  publicShell(app, null, [spinner('Loading')]);
  let profile: PublicProfile;
  try { profile = await loadProfile(); } catch (e) {
    publicShell(app, null, [h('div', { class: 'container pad-y' }, errorBox((e as Error).message, () => bookPage(app, query)))]);
    return;
  }
  const salon = profile.salon;
  const bookable = profile.professionals.filter((p) => p.online_booking && p.services.some((s) => s.bookable_online));
  const today = salon.today;

  const st: State = {
    pro: null, service: null, date: null, time: null, timeLabel: null,
    name: '', phone: '', email: '', note: '', marketing: false, policy: false,
    idem: newIdempotencyKey(), step: 1, month: today.slice(0, 8) + '01', flash: null,
  };
  const qp = query.get('artist');
  if (qp) st.pro = bookable.find((p) => p.slug === qp) ?? null;
  if (st.pro) {
    st.step = 2;
    const qs = query.get('service');
    const svc = qs ? st.pro.services.find((s) => s.id === qs && s.bookable_online) : null;
    if (svc) { st.service = svc; st.step = 3; }
    else if (st.pro.services.filter((s) => s.bookable_online).length === 1) { st.service = st.pro.services.find((s) => s.bookable_online)!; st.step = 3; }
  }

  const stage = h('div', { class: 'book-stage' });
  const summary = h('aside', { class: 'book-summary', attrs: { 'aria-label': 'Your booking so far' } });
  const progress = h('ol', { class: 'steps', attrs: { 'aria-label': 'Booking progress' } });

  publicShell(app, profile, [h('section', { class: 'book' },
    h('div', { class: 'container book-head' },
      h('h1', { class: 'page-title', text: 'Book an appointment' }),
      h('p', { class: 'muted', text: 'Choose your artist, service and a free time. Your booking is held for you while the artist confirms it.' }),
      progress),
    h('div', { class: 'container book-grid' }, stage, summary))]);

  const syncUrl = () => {
    const q = new URLSearchParams();
    if (st.pro) q.set('artist', st.pro.slug);
    if (st.service) q.set('service', st.service.id);
    history.replaceState(null, '', `/book${q.toString() ? '?' + q : ''}`);
  };

  const go = (step: State['step']) => {
    st.step = step;
    render();
    stage.querySelector<HTMLElement>('h2')?.focus();
    if (window.innerWidth < 900) stage.scrollIntoView({ block: 'start' });
  };

  function renderProgress() {
    mount(progress, STEPS.map((label, i) => {
      const n = (i + 1) as State['step'];
      const done = n < st.step;
      return h('li', { class: ['step', done && 'is-done', n === st.step && 'is-current'], attrs: { 'aria-current': n === st.step ? 'step' : undefined } },
        h('span', { class: 'step-num', text: done ? '' : String(n) }, done ? icon('check', 14) : null),
        h('span', { class: 'step-label', text: label }));
    }));
  }

  function renderSummary() {
    const rows: Node[] = [];
    if (st.pro) rows.push(h('div', { class: 'sum-pro' }, proMark(st.pro, 'sm'), h('div', null, h('p', { class: 'sum-strong', text: st.pro.display_name }), st.pro.specialty ? h('p', { class: 'muted small', text: st.pro.specialty }) : null)));
    if (st.service) rows.push(h('div', { class: 'sum-row' }, h('span', { text: st.service.name }), h('span', { class: 'sum-strong', text: st.service.price_label })),
      h('p', { class: 'muted small', text: `About ${durationLabel(st.service.duration_min)}` }));
    if (st.date && st.time) rows.push(h('div', { class: 'sum-when' }, icon('calendar', 17), h('span', { text: `${formatDateLong(st.date)}, ${st.timeLabel}` })));
    mount(summary, h('div', { class: 'sum-card' },
      h('p', { class: 'sum-title', text: 'Your booking' }),
      rows.length ? rows : h('p', { class: 'muted small', text: 'Your choices will appear here.' }),
      h('p', { class: 'sum-foot' }, icon('info', 15), h('span', { text: 'UK time (Europe/London). Nothing is charged online.' }))));
  }

  // -------------------------------------------------------------- step 1
  function stepArtist() {
    return [h('h2', { class: 'step-title', attrs: { tabindex: '-1' }, text: 'Who would you like to book?' }),
      bookable.length ? h('ul', { class: 'choice-grid' }, bookable.map((p) => h('li', null,
        h('button', { class: ['choice', 'choice-pro', `pro-${p.color}`, st.pro?.id === p.id && 'selected'], attrs: { type: 'button', 'aria-pressed': String(st.pro?.id === p.id) },
          on: { click: () => { if (st.pro?.id !== p.id) { st.pro = p; st.service = null; st.date = null; st.time = null; st.idem = newIdempotencyKey(); } syncUrl(); go(2); } } },
          proMark(p, 'sm'),
          h('span', { class: 'choice-body' }, h('span', { class: 'choice-title', text: p.display_name }), p.specialty ? h('span', { class: 'choice-sub', text: p.specialty }) : null),
          icon('chevronRight', 18)))))
        : notice('info', 'Online booking is not available right now. Please send an enquiry and the salon will get back to you.'),
      h('p', { class: 'book-alt' }, 'Planning a wedding? ', h('a', { attrs: { href: '/bridal' }, text: 'Send a bridal enquiry' }), ' instead.')];
  }

  // -------------------------------------------------------------- step 2
  function stepService() {
    const p = st.pro!;
    const online = p.services.filter((s) => s.bookable_online);
    const enquire = p.services.filter((s) => !s.bookable_online);
    return [h('h2', { class: 'step-title', attrs: { tabindex: '-1' }, text: `Choose a service with ${p.short_name}` }),
      h('ul', { class: 'choice-list' }, online.map((s) => h('li', null,
        h('button', { class: ['choice', 'choice-service', st.service?.id === s.id && 'selected'], attrs: { type: 'button', 'aria-pressed': String(st.service?.id === s.id) },
          on: { click: () => { if (st.service?.id !== s.id) { st.service = s; st.date = null; st.time = null; st.idem = newIdempotencyKey(); } syncUrl(); go(3); } } },
          h('span', { class: 'choice-body' }, h('span', { class: 'choice-title', text: s.name }), h('span', { class: 'choice-sub', text: `About ${durationLabel(s.duration_min)}${s.description ? '. ' + s.description : ''}` })),
          h('span', { class: 'choice-price', text: s.price_label }))))),
      enquire.length ? h('div', { class: 'enquire-box' }, icon('heart', 18), h('p', null, `${enquire.map((s) => s.name).join(', ')} ${enquire.length > 1 ? 'are' : 'is'} by enquiry. `, h('a', { attrs: { href: `/bridal?artist=${p.slug}` }, text: 'Send an enquiry' }))) : null,
      h('div', { class: 'step-nav' }, button('Back', { variant: 'ghost', icon: 'chevronLeft', onClick: () => go(1) }))];
  }

  // -------------------------------------------------------------- step 3
  const slotsCache = new Map<string, { time: string; label: string }[]>();
  function stepWhen() {
    const cal = h('div', { class: 'cal' });
    const slotsEl = h('div', { class: 'slots', attrs: { 'aria-live': 'polite' } });
    const wrap = [h('h2', { class: 'step-title', attrs: { tabindex: '-1' }, text: 'Pick a date and time' }),
      st.flash ? notice('warn', st.flash) : null,
      h('div', { class: 'when-grid' }, cal, slotsEl),
      h('div', { class: 'step-nav' }, button('Back', { variant: 'ghost', icon: 'chevronLeft', onClick: () => go(2) }))];
    st.flash = null;
    void renderCalendar(cal, slotsEl);
    if (st.date) void renderSlots(slotsEl, st.date);
    else mount(slotsEl, h('p', { class: 'muted slots-hint', text: 'Choose a highlighted day to see free times.' }));
    return wrap;
  }

  async function renderCalendar(cal: HTMLElement, slotsEl: HTMLElement) {
    const first = st.month;
    const lastAllowed = addDays(today, salon.max_days_ahead);
    const minMonth = today.slice(0, 8) + '01';
    const nextMonth = addDays(first, 32).slice(0, 8) + '01';
    const prevMonth = addDays(first, -1).slice(0, 8) + '01';
    const head = h('div', { class: 'cal-head' },
      button('', { variant: 'ghost', size: 'sm', icon: 'chevronLeft', ariaLabel: 'Previous month', disabled: first <= minMonth, onClick: () => { st.month = prevMonth; void renderCalendar(cal, slotsEl); } }),
      h('p', { class: 'cal-month', attrs: { 'aria-live': 'polite' }, text: formatMonthYear(first) }),
      button('', { variant: 'ghost', size: 'sm', icon: 'chevronRight', ariaLabel: 'Next month', disabled: nextMonth > lastAllowed, onClick: () => { st.month = nextMonth; void renderCalendar(cal, slotsEl); } }));
    mount(cal, head, spinner('Checking availability'));
    let days: { date: string; slots: number }[] = [];
    try {
      const from = first < today ? today : first;
      const r = await rpc<any>('salon_public_days', { p_salon: SALON_SLUG, p_professional: st.pro!.slug, p_service: st.service!.id, p_from: from, p_days: 42 }, { anon: true });
      if (!r.ok) throw new ApiError(r.error, r.message);
      days = r.days;
    } catch (e) {
      mount(cal, head, errorBox((e as Error).message, () => renderCalendar(cal, slotsEl)));
      return;
    }
    if (st.month !== first) return; // user navigated meanwhile
    const open = new Map(days.map((d) => [d.date, d.slots]));
    const grid = h('div', { class: 'cal-grid', attrs: { role: 'grid', 'aria-label': formatMonthYear(first) } });
    ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].forEach((d) => grid.appendChild(h('span', { class: 'cal-dow', attrs: { 'aria-hidden': 'true' }, text: d })));
    const offset = (weekdayOf(first) + 6) % 7;
    for (let i = 0; i < offset; i++) grid.appendChild(h('span', { class: 'cal-pad' }));
    let d = first;
    while (d.slice(0, 7) === first.slice(0, 7)) {
      const iso = d;
      const n = open.get(iso) ?? 0;
      const btn = h('button', {
        class: ['cal-day', n > 0 && 'has-slots', st.date === iso && 'selected', iso === today && 'today'],
        attrs: { type: 'button', disabled: n === 0, 'aria-pressed': String(st.date === iso), 'aria-label': `${formatDateLong(iso)}${n ? `, ${n} free time${n === 1 ? '' : 's'}` : ', no free times'}` },
        on: { click: () => { st.date = iso; st.time = null; st.idem = newIdempotencyKey(); renderSummary(); void renderCalendar(cal, slotsEl); void renderSlots(slotsEl, iso); } },
      }, h('span', { text: String(Number(iso.slice(8))) }));
      grid.appendChild(btn);
      d = addDays(d, 1);
    }
    mount(cal, head, grid, days.length === 0 ? h('p', { class: 'muted small cal-none', text: 'No free times this month. Try the next month.' }) : null);
  }

  async function renderSlots(el: HTMLElement, date: string, force = false) {
    mount(el, h('p', { class: 'slots-date', text: formatDateLong(date) }), spinner('Loading times'));
    let slots = force ? undefined : slotsCache.get(date);
    if (!slots) {
      try {
        const r = await rpc<any>('salon_public_slots', { p_salon: SALON_SLUG, p_professional: st.pro!.slug, p_service: st.service!.id, p_date: date }, { anon: true });
        if (!r.ok) throw new ApiError(r.error, r.message);
        slots = r.slots as { time: string; label: string }[];
        slotsCache.set(date, slots);
      } catch (e) {
        mount(el, errorBox((e as Error).message, () => renderSlots(el, date, true)));
        return;
      }
    }
    if (st.date !== date) return;
    if (!slots.length) { mount(el, h('p', { class: 'slots-date', text: formatDateLong(date) }), h('p', { class: 'muted', text: 'That day has just filled up. Please choose another day.' })); return; }
    const groups: [string, typeof slots][] = [
      ['Morning', slots.filter((s) => minutesOf(s.time) < 12 * 60)],
      ['Afternoon', slots.filter((s) => minutesOf(s.time) >= 12 * 60 && minutesOf(s.time) < 17 * 60)],
      ['Evening', slots.filter((s) => minutesOf(s.time) >= 17 * 60)],
    ];
    mount(el, h('p', { class: 'slots-date', text: formatDateLong(date) }),
      groups.filter(([, g]) => g.length).map(([label, g]) => h('div', { class: 'slot-group' },
        h('p', { class: 'slot-group-label', text: label }),
        h('div', { class: 'slot-grid' }, g.map((s) => h('button', {
          class: ['slot', st.time === s.time && 'selected'], attrs: { type: 'button', 'aria-pressed': String(st.time === s.time) },
          on: { click: () => { st.time = s.time; st.timeLabel = s.label; st.idem = newIdempotencyKey(); go(4); } },
          text: s.label,
        }))))));
  }

  // -------------------------------------------------------------- step 4
  function stepDetails() {
    const fName = field({ label: 'Full name', name: 'name', required: true, autocomplete: 'name', value: st.name, maxlength: 80 });
    const fPhone = field({ label: 'Mobile number', name: 'phone', type: 'tel', required: true, autocomplete: 'tel', inputmode: 'tel', value: st.phone, hint: 'Used only for this booking, for example to confirm or change it.' });
    const fEmail = field({ label: 'Email', name: 'email', type: 'email', autocomplete: 'email', value: st.email, maxlength: 254 });
    const fNote = textarea({ label: 'Anything the artist should know?', name: 'note', value: st.note, maxlength: 500, rows: 3, placeholder: 'For example the occasion, the look you have in mind, or hair length.' });
    const cMarketing = checkbox({ name: 'marketing', checked: st.marketing, label: 'Send me occasional news and offers from the salon.', hint: 'Optional. This does not affect your booking.' });
    const honey = h('div', { class: 'honeypot', attrs: { 'aria-hidden': 'true' } }, h('label', null, 'Company', h('input', { attrs: { type: 'text', name: 'company', tabindex: '-1', autocomplete: 'off' } })));
    const form = h('form', { class: 'details-form', attrs: { novalidate: true } }, fName.wrap, fPhone.wrap, fEmail.wrap, fNote.wrap, cMarketing.wrap, honey,
      h('div', { class: 'step-nav' }, button('Back', { variant: 'ghost', icon: 'chevronLeft', onClick: () => { save(); go(3); } }), button('Review booking', { type: 'submit', iconRight: 'arrowRight' })));
    const save = () => {
      st.name = fName.input.value.trim(); st.phone = fPhone.input.value.trim(); st.email = fEmail.input.value.trim();
      st.note = fNote.input.value.trim(); st.marketing = cMarketing.input.checked;
      (st as any).company = (honey.querySelector('input') as HTMLInputElement).value;
    };
    form.addEventListener('submit', (e) => {
      e.preventDefault();
      save();
      let ok = true;
      fName.setError(null); fPhone.setError(null); fEmail.setError(null);
      if (st.name.length < 2) { fName.setError('Please enter your name.'); ok = false; }
      if (st.phone.replace(/[^0-9]/g, '').length < 10) { fPhone.setError('Please enter a valid mobile number.'); ok = false; }
      if (st.email && !/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/i.test(st.email)) { fEmail.setError('Please check your email address.'); ok = false; }
      if (!ok) { form.querySelector<HTMLElement>('[aria-invalid="true"]')?.focus(); return; }
      go(5);
    });
    return [h('h2', { class: 'step-title', attrs: { tabindex: '-1' }, text: 'Your details' }), form];
  }

  // -------------------------------------------------------------- step 5
  function stepReview() {
    const p = st.pro!; const s = st.service!;
    const err = h('div', { attrs: { 'aria-live': 'assertive' } });
    const policy = salon.booking_policy ? checkbox({ name: 'policy', checked: st.policy, label: 'I have read and accept the booking policy above.' }) : null;
    const submit = button('Send booking request', { size: 'lg', full: true, onClick: () => void send() });
    const send = async () => {
      mount(err);
      if (policy && !policy.input.checked) { mount(err, notice('error', 'Please accept the booking policy to continue.')); return; }
      st.policy = !!policy?.input.checked;
      setBusy(submit, true, 'Sending…');
      try {
        const r = await rpc<any>('salon_public_book', { p_salon: SALON_SLUG, p_payload: {
          professional: p.slug, service: s.id, date: st.date, time: st.time, name: st.name, phone: st.phone, email: st.email || null,
          note: st.note || null, marketing_consent: st.marketing, policy_accepted: st.policy, idempotency_key: st.idem, company: (st as any).company || '',
        } }, { anon: true });
        if (!r.ok) {
          setBusy(submit, false);
          if (r.error === 'slot_taken' || r.error === 'slot_unavailable') {
            slotsCache.delete(st.date!); st.time = null; st.idem = newIdempotencyKey();
            st.flash = r.message; go(3); return;
          }
          if (['name_required', 'phone_required', 'email_invalid'].includes(r.error)) { go(4); toast(r.message, 'error'); return; }
          if (r.error === 'in_progress') { mount(err, notice('info', r.message)); return; }
          mount(err, notice('error', r.message));
          return;
        }
        renderDone(r);
      } catch (e) {
        setBusy(submit, false);
        mount(err, notice('error', `${(e as Error).message} Your request was not confirmed yet; pressing the button again is safe and will not double book.`));
      }
    };
    return [h('h2', { class: 'step-title', attrs: { tabindex: '-1' }, text: 'Check and send' }),
      h('dl', { class: 'review' },
        h('dt', { text: 'Artist' }), h('dd', { text: p.display_name }),
        h('dt', { text: 'Service' }), h('dd', { text: `${s.name}, about ${durationLabel(s.duration_min)}` }),
        h('dt', { text: 'When' }), h('dd', { text: `${formatDateLong(st.date!)} at ${st.timeLabel} (UK time)` }),
        h('dt', { text: 'Price' }), h('dd', { text: s.price_label }),
        h('dt', { text: 'Name' }), h('dd', { text: st.name }),
        h('dt', { text: 'Mobile' }), h('dd', { text: st.phone }),
        st.email ? [h('dt', { text: 'Email' }), h('dd', { text: st.email })] : null,
        st.note ? [h('dt', { text: 'Note' }), h('dd', { text: st.note })] : null),
      h('p', { class: 'review-edit' }, button('Change details', { variant: 'link', onClick: () => go(4) }), button('Change time', { variant: 'link', onClick: () => go(3) })),
      notice('info', `This is a booking request. The time is held for you, and it becomes confirmed once ${p.short_name} accepts it.`),
      salon.booking_policy ? h('div', { class: 'policy' }, h('p', { class: 'policy-title', text: 'Booking policy' }), h('p', { class: 'policy-text', text: salon.booking_policy }), policy!.wrap) : null,
      err,
      h('div', { class: 'submit-row' }, submit),
      h('div', { class: 'step-nav' }, button('Back', { variant: 'ghost', icon: 'chevronLeft', onClick: () => go(4) }))];
  }

  function renderDone(r: any) {
    const link = `${location.origin}/manage#t=${encodeURIComponent(r.manage_token)}`;
    mount(progress);
    mount(summary);
    summary.hidden = true;
    mount(stage, h('div', { class: 'done' },
      h('div', { class: 'done-mark', attrs: { 'aria-hidden': 'true' } }, icon('check', 26)),
      h('h2', { class: 'step-title', attrs: { tabindex: '-1' }, text: 'Your request has been sent' }),
      h('p', { class: 'done-lede', text: `${r.professional_short} will confirm your appointment. Until then it is held for you and shows as awaiting confirmation.` }),
      h('dl', { class: 'review' },
        h('dt', { text: 'Reference' }), h('dd', { class: 'ref', text: r.ref }),
        h('dt', { text: 'Status' }), h('dd', null, h('span', { class: 'badge badge-pending', text: 'Awaiting confirmation' })),
        h('dt', { text: 'Artist' }), h('dd', { text: r.professional }),
        h('dt', { text: 'Service' }), h('dd', { text: `${r.service}, ${r.price_label}` }),
        h('dt', { text: 'When' }), h('dd', { text: `${formatDateLong(r.date)} at ${st.timeLabel} (UK time)` })),
      h('div', { class: 'manage-box' },
        h('p', { class: 'sum-strong', text: 'Keep this private link' }),
        h('p', { class: 'muted small', text: 'Use it to check the status of your booking or cancel it. Anyone with the link can see this booking, so do not share it.' }),
        h('div', { class: 'manage-actions' },
          button('Copy link', { variant: 'secondary', size: 'sm', icon: 'check', onClick: async () => { try { await navigator.clipboard.writeText(link); toast('Link copied'); } catch { toast('Copy failed. Use "Open my booking" and bookmark the page.', 'error'); } } }),
          linkButton('Open my booking', `/manage#t=${encodeURIComponent(r.manage_token)}`, { variant: 'ghost', size: 'sm' }))),
      r.preview ? notice('warn', 'Preview site: this is a test booking while the salon gets ready to launch.') : null,
      h('p', { class: 'done-actions' }, linkButton('Back to the salon', '/', { variant: 'ghost' }))));
    stage.querySelector<HTMLElement>('h2')?.focus();
    window.scrollTo({ top: 0 });
  }

  function render() {
    renderProgress();
    renderSummary();
    const views: Record<number, () => (Node | null)[]> = { 1: stepArtist, 2: stepService, 3: stepWhen, 4: stepDetails, 5: stepReview };
    if (st.step >= 2 && !st.pro) st.step = 1;
    if (st.step >= 3 && !st.service) st.step = 2;
    if (st.step >= 4 && (!st.date || !st.time)) st.step = 3;
    mount(stage, views[st.step]());
  }

  if (salon.booking_mode === 'closed') {
    mount(stage, notice('info', 'Online booking is not open yet. Please contact the salon, or send an enquiry.'), h('p', { class: 'mt' }, linkButton('Send an enquiry', '/bridal')));
    renderSummary();
    return;
  }
  render();
}
