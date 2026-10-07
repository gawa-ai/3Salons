import { h, icon, mount, append } from '../lib/dom';
import { button, spinner, emptyState, field, textarea, select, checkbox, toast, openDialog, setBusy, proDot, notice } from '../lib/ui';
import { rpc } from '../lib/supabase';
import { addDays, todayLocal, zonedToUtc, formatDateLong, relativeTime, dateTimeShort, time12, SOURCE_LABEL, STATUS_LABEL } from '../lib/format';
import type { Ctx } from './shell';
import { bookingRow, quickActions, openBooking, openNewBooking, csvDownload, type Booking } from './booking';

// ===================================================================== bookings
const VIEWS: { key: string; label: string }[] = [
  { key: 'upcoming', label: 'Upcoming' },
  { key: 'pending', label: 'Awaiting confirmation' },
  { key: 'outcome', label: 'Needs outcome' },
  { key: 'past', label: 'Past' },
  { key: 'closed', label: 'Cancelled and declined' },
  { key: 'all', label: 'All' },
];

export async function bookingsPage(ctx: Ctx) {
  const params = new URLSearchParams(location.search);
  let view = VIEWS.some((v) => v.key === params.get('view')) ? params.get('view')! : 'upcoming';
  let q = '';
  const tabs = h('div', { class: 'chips', attrs: { role: 'tablist', 'aria-label': 'Filter bookings' } });
  const search = h('input', { class: 'input input-sm', attrs: { type: 'search', placeholder: 'Search name, phone, service or ref', 'aria-label': 'Search bookings' } });
  const list = h('div');
  let current: Booking[] = [];
  let timer = 0;
  search.addEventListener('input', () => { clearTimeout(timer); timer = window.setTimeout(() => { q = search.value.trim(); void load(); }, 300); });

  const load = async () => {
    mount(tabs, VIEWS.map((v) => h('button', { class: ['chip', view === v.key && 'active'], attrs: { type: 'button', role: 'tab', 'aria-selected': String(view === v.key) }, text: v.label,
      on: { click: () => { view = v.key; history.replaceState(null, '', `/studio/bookings?view=${v.key}`); void load(); } } })));
    mount(list, spinner());
    const now = new Date().toISOString();
    const args: Record<string, unknown> = { p_salon: ctx.salonId, p_professional: ctx.scope, p_search: q || null, p_limit: 1000 };
    if (view === 'upcoming') { args.p_from = now; args.p_statuses = ['pending', 'confirmed']; }
    if (view === 'pending') { args.p_from = now; args.p_statuses = ['pending']; }
    if (view === 'outcome') { args.p_to = now; args.p_statuses = ['confirmed']; }
    if (view === 'past') { args.p_to = now; args.p_from = zonedToUtc(addDays(todayLocal(), -365), '00:00').toISOString(); args.p_statuses = ['completed', 'no_show', 'confirmed', 'expired']; }
    if (view === 'closed') { args.p_statuses = ['cancelled', 'declined', 'expired']; }
    const r = await rpc<any>('salon_dash_bookings', args);
    current = r.items;
    if (view === 'past' || view === 'closed' || view === 'outcome') current = [...current].reverse();
    if (!current.length) { mount(list, emptyState(q ? 'No matches' : 'Nothing here yet', q ? 'Try a different name, number or reference.' : 'Bookings will appear here as they come in.')); return; }
    const groups = new Map<string, Booking[]>();
    current.forEach((b) => groups.set(b.local_date, [...(groups.get(b.local_date) ?? []), b]));
    mount(list, Array.from(groups.entries()).map(([d, items]) => h('section', { class: 'bgroup' },
      h('h3', { class: 'bgroup-title', text: formatDateLong(d) }),
      h('ul', { class: 'blist' }, items.map((b) => bookingRow(b, () => openBooking(ctx, b.id, () => void load()), quickActions(b, () => void load()) ?? undefined))))));
  };

  ctx.setActions([
    button('Export CSV', { variant: 'ghost', size: 'sm', icon: 'download', onClick: () => csvDownload(`bookings-${todayLocal()}.csv`, [
      ['Ref', 'Date', 'Time', 'Professional', 'Service', 'Client', 'Mobile', 'Email', 'Status', 'Listed price (GBP)', 'Source'],
      ...current.map((b) => [b.ref, b.local_date, b.local_time, b.professional, b.service, b.client_name, b.client_phone, b.client_email, STATUS_LABEL[b.status], b.price_pence === null ? '' : (b.price_pence / 100).toFixed(2), SOURCE_LABEL[b.source]])]) }),
    button('New booking', { icon: 'plus', size: 'sm', onClick: () => openNewBooking(ctx, {}, () => void load()) }),
  ]);
  mount(ctx.content, h('div', { class: 'list-tools' }, tabs, search), list);
  await load();
}

// ===================================================================== clients
export async function clientsPage(ctx: Ctx) {
  const search = h('input', { class: 'input input-sm', attrs: { type: 'search', placeholder: 'Search name, phone or email', 'aria-label': 'Search clients' } });
  const list = h('div');
  let timer = 0; let items: any[] = [];
  search.addEventListener('input', () => { clearTimeout(timer); timer = window.setTimeout(() => void load(), 300); });
  const load = async () => {
    mount(list, spinner());
    const r = await rpc<any>('salon_dash_clients', { p_salon: ctx.salonId, p_professional: ctx.scope, p_search: search.value.trim() || null });
    items = r.items;
    if (!items.length) { mount(list, emptyState(search.value ? 'No matches' : 'No clients yet', 'Clients are added automatically when someone books.')); return; }
    mount(list, h('div', { class: 'table-wrap' }, h('table', { class: 'table table-click' },
      h('thead', null, h('tr', null, ['Client', 'Mobile', ctx.isOwner && !ctx.scope ? 'Professional' : null, 'Completed', 'Upcoming', 'Last visit'].filter(Boolean).map((t) => h('th', { attrs: { scope: 'col' }, class: ['Completed', 'Upcoming'].includes(t!) ? 'num' : '', text: t! })))),
      h('tbody', null, items.map((c) => {
        const tr = h('tr', { attrs: { tabindex: '0', 'aria-label': `Open ${c.name}` } },
          h('th', { attrs: { scope: 'row' }, text: c.name }),
          h('td', { text: c.phone }),
          ctx.isOwner && !ctx.scope ? h('td', null, h('span', { class: 'cell-pro' }, proDot(c.professional_color), c.professional)) : null,
          h('td', { class: 'num', text: String(c.completed) }), h('td', { class: 'num', text: String(c.upcoming) }),
          h('td', { text: c.last_visit ? relativeTime(c.last_visit) : '—' }));
        const open = () => openClient(ctx, c.id, () => void load());
        tr.addEventListener('click', open);
        tr.addEventListener('keydown', (e) => { if (e.key === 'Enter') open(); });
        return tr;
      })))),
      ctx.isOwner && !ctx.scope ? h('p', { class: 'muted small mt', text: 'Each professional keeps a separate record for the same person, so notes stay private to that professional.' }) : null);
  };
  ctx.setActions([button('Export CSV', { variant: 'ghost', size: 'sm', icon: 'download', onClick: () => csvDownload(`clients-${todayLocal()}.csv`, [
    ['Name', 'Mobile', 'Email', 'Professional', 'Completed', 'Upcoming', 'Marketing consent'],
    ...items.map((c) => [c.name, c.phone, c.email, c.professional, c.completed, c.upcoming, c.marketing_consent ? 'yes' : 'no'])]) })]);
  mount(ctx.content, h('div', { class: 'list-tools' }, search), list);
  await load();
}

function openClient(ctx: Ctx, id: string, onChange: () => void) {
  const d = openDialog({ title: 'Client', kind: 'drawer' });
  const load = async () => {
    mount(d.body, spinner()); mount(d.footer);
    const r = await rpc<any>('salon_dash_client', { p_client: id });
    const c = r.client;
    d.setTitle(c.name);
    const fName = field({ label: 'Name', name: 'name', value: c.name, maxlength: 80 });
    const fEmail = field({ label: 'Email', name: 'email', type: 'email', value: c.email ?? '' });
    const fNotes = textarea({ label: 'Notes', name: 'notes', value: c.notes ?? '', rows: 4, maxlength: 4000, hint: `Private to ${c.professional}${ctx.isOwner ? ' and you' : ' and the salon owner'}.` });
    const mk = checkbox({ name: 'mk', checked: c.marketing_consent, label: 'Agreed to receive news and offers', hint: c.marketing_consent_at ? `Since ${dateTimeShort(c.marketing_consent_at)}` : undefined });
    mount(d.body,
      h('dl', { class: 'kv' }, h('dt', { text: 'Mobile' }), h('dd', null, h('a', { attrs: { href: `tel:${c.phone}` }, text: c.phone })),
        h('dt', { text: 'Professional' }), h('dd', { text: c.professional }), h('dt', { text: 'Client since' }), h('dd', { text: dateTimeShort(c.created_at) })),
      fName.wrap, fEmail.wrap, fNotes.wrap, mk.wrap,
      h('h3', { class: 'sub-title', text: 'Appointments' }),
      r.bookings.length ? h('ul', { class: 'blist' }, r.bookings.map((b: Booking) => bookingRow(b, () => openBooking(ctx, b.id, () => { onChange(); void load(); })))) : h('p', { class: 'muted small', text: 'No appointments.' }));
    const save = button('Save client', { onClick: async () => {
      setBusy(save, true, 'Saving…');
      try {
        await rpc('salon_dash_client_save', { p_client: id, p_payload: { name: fName.input.value, email: fEmail.input.value, notes: fNotes.input.value, marketing_consent: mk.input.checked } });
        toast('Client saved'); onChange(); void load();
      } catch (e) { setBusy(save, false); toast((e as Error).message, 'error'); }
    } });
    mount(d.footer, save);
  };
  void load();
}

// ===================================================================== enquiries
const ENQ_STATUS: Record<string, string> = { new: 'New', contacted: 'Contacted', booked: 'Booked', closed: 'Closed' };
export async function enquiriesPage(ctx: Ctx) {
  let filter = 'open';
  const chips = h('div', { class: 'chips', attrs: { role: 'tablist', 'aria-label': 'Filter enquiries' } });
  const list = h('div');
  const load = async () => {
    mount(chips, [['open', 'Open'], ['new', 'New'], ['contacted', 'Contacted'], ['booked', 'Booked'], ['closed', 'Closed'], ['all', 'All']].map(([k, l]) =>
      h('button', { class: ['chip', filter === k && 'active'], attrs: { type: 'button', role: 'tab', 'aria-selected': String(filter === k) }, text: l, on: { click: () => { filter = k; void load(); } } })));
    mount(list, spinner());
    const r = await rpc<any>('salon_dash_enquiries', { p_salon: ctx.salonId, p_professional: ctx.scope, p_status: ['new', 'contacted', 'booked', 'closed'].includes(filter) ? filter : null });
    let items = r.items as any[];
    if (filter === 'open') items = items.filter((e) => e.status === 'new' || e.status === 'contacted');
    if (!items.length) { mount(list, emptyState('No enquiries', 'Bridal and general enquiries from the website appear here.')); return; }
    mount(list, h('ul', { class: 'enq-list' }, items.map((e) => h('li', { class: 'enq' },
      h('div', { class: 'enq-head' },
        h('div', null, h('p', { class: 'enq-name', text: e.name }), h('p', { class: 'muted small', text: `${e.kind === 'bridal' ? 'Bridal' : 'General'} enquiry, ${relativeTime(e.created_at)}` })),
        h('span', { class: ['badge', e.status === 'new' ? 'badge-pending' : e.status === 'booked' ? 'badge-confirmed' : 'badge-neutral'], text: ENQ_STATUS[e.status] })),
      h('dl', { class: 'kv kv-compact' },
        h('dt', { text: 'For' }), h('dd', null, e.professional ? [proDot(e.professional_color), ' ', e.professional] : 'No preference'),
        e.event_date ? [h('dt', { text: 'Date' }), h('dd', { text: formatDateLong(e.event_date) })] : null,
        e.event_location ? [h('dt', { text: 'Where' }), h('dd', { text: e.event_location })] : null,
        e.services_wanted ? [h('dt', { text: 'Wants' }), h('dd', { text: e.services_wanted })] : null,
        h('dt', { text: 'Mobile' }), h('dd', null, h('a', { attrs: { href: `tel:${e.phone}` }, text: e.phone })),
        e.email ? [h('dt', { text: 'Email' }), h('dd', null, h('a', { attrs: { href: `mailto:${e.email}` }, text: e.email }))] : null),
      e.message ? h('p', { class: 'enq-msg pre', text: e.message }) : null,
      h('div', { class: 'enq-actions' }, button('Update', { size: 'sm', variant: 'secondary', onClick: () => editEnquiry(ctx, e, () => void load()) }))))));
  };
  mount(ctx.content, h('div', { class: 'list-tools' }, chips), list);
  await load();
}

function editEnquiry(ctx: Ctx, e: any, onDone: () => void) {
  const d = openDialog({ title: 'Update enquiry', subtitle: e.name, size: 'sm' });
  const st = select({ label: 'Status', name: 'status', value: e.status, options: Object.entries(ENQ_STATUS).map(([value, label]) => ({ value, label })) });
  const pro = ctx.isOwner ? select({ label: 'Assigned to', name: 'pro', value: e.professional_id ?? '', options: [{ value: '', label: 'No preference (owner only)' }, ...ctx.pros.map((p) => ({ value: p.id, label: p.display_name }))] }) : null;
  const note = textarea({ label: 'Studio note', name: 'note', value: e.internal_note ?? '', rows: 3, maxlength: 2000 });
  append(d.body, st.wrap, pro?.wrap ?? null, note.wrap);
  const save = button('Save', { onClick: async () => {
    setBusy(save, true, 'Saving…');
    try {
      const payload: Record<string, unknown> = { status: st.input.value, internal_note: note.input.value };
      if (pro && pro.input.value !== (e.professional_id ?? '')) payload.professional_id = pro.input.value;
      await rpc('salon_dash_enquiry_update', { p_enquiry: e.id, p_payload: payload });
      toast('Enquiry updated'); d.close(); onDone();
    } catch (err) { setBusy(save, false); toast((err as Error).message, 'error'); }
  } });
  append(d.footer, button('Cancel', { variant: 'ghost', onClick: () => d.close() }), save);
}

// ===================================================================== messages (outbox) + calls
const PURPOSE: Record<string, string> = {
  request_received: 'Request received', new_request: 'New request', confirmed: 'Confirmed', declined: 'Declined', cancelled: 'Cancelled',
  cancelled_pro: 'Client cancelled', rescheduled: 'Moved', new_enquiry: 'New enquiry',
};
export async function messagesPage(ctx: Ctx) {
  mount(ctx.content, spinner());
  const r = await rpc<any>('salon_dash_messages', { p_salon: ctx.salonId, p_professional: ctx.scope });
  mount(ctx.content,
    h('div', { class: 'ov-grid' },
      h('section', { class: 'panel' },
        h('div', { class: 'panel-head' }, h('h3', { class: 'panel-title', text: 'Calls' }), h('span', { class: 'badge badge-neutral', text: 'Not connected' })),
        h('p', { class: 'muted', text: 'Phone answering is not connected for this salon. When it is, call summaries for your bookings will appear here.' })),
      h('section', { class: 'panel' },
        h('div', { class: 'panel-head' }, h('h3', { class: 'panel-title', text: 'Text messages' }), h('span', { class: ['badge', r.sms_connected ? 'badge-confirmed' : 'badge-neutral'], text: r.sms_connected ? 'Connected' : 'Not connected' })),
        h('p', { class: 'muted', text: r.sms_connected ? 'Messages are sent automatically.' : 'Every message the system would send is recorded below, but nothing is sent until text messaging is connected. Contact clients yourself in the meantime.' }))),
    h('section', { class: 'panel' },
      h('div', { class: 'panel-head' }, h('h3', { class: 'panel-title', text: 'Message log' })),
      r.items.length ? h('ul', { class: 'msg-list' }, r.items.map((m: any) => h('li', { class: 'msg' },
        h('div', { class: 'msg-head' },
          h('span', { class: 'msg-purpose', text: `${PURPOSE[m.purpose] ?? m.purpose}, to ${m.audience === 'customer' ? 'client' : 'artist'}` }),
          h('span', { class: ['msg-status', `ms-${m.status}`], text: m.status === 'not_connected' ? 'Not sent' : m.status }),
          h('span', { class: 'muted small', text: relativeTime(m.at) })),
        h('p', { class: 'msg-body', text: m.body }),
        h('p', { class: 'muted small' }, ctx.isOwner && m.professional ? [proDot(m.professional_color), ` ${m.professional}`] : null, m.booking_ref ? ` Ref ${m.booking_ref}` : '')))) : emptyState('No messages yet', 'Messages are logged here when bookings are made or changed.')));
}

export { icon, time12, notice };
