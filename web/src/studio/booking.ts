import { h, icon, mount, append, newIdempotencyKey } from '../lib/dom';
import { button, field, textarea, select, checkbox, spinner, errorBox, notice, statusBadge, toast, openDialog, confirmDialog, setBusy, proDot } from '../lib/ui';
import { rpc } from '../lib/supabase';
import { formatDateLong, time12, durationLabel, dateTimeShort, SOURCE_LABEL, todayLocal, relativeTime } from '../lib/format';
import type { Ctx } from './shell';

export interface Booking {
  id: string; ref: string; status: string; source: string; professional_id: string; professional: string; professional_short: string;
  professional_color: string; service_id: string; service: string; starts_at: string; ends_at: string; block_end: string;
  local_date: string; local_time: string; local_end: string; when: string; duration_min: number; buffer_min: number;
  price_pence: number | null; price_kind: string; price_label: string; version: number; created_at: string;
  confirmed_at: string | null; cancelled_at: string | null; status_reason: string | null;
  client_id: string; client_name: string; client_phone: string; client_email: string | null; customer_note: string | null; internal_note: string | null;
}

export function bookingRow(b: Booking, onOpen: () => void, extra?: Node) {
  return h('li', { class: ['brow', `pro-${b.professional_color}`, `st-${b.status}`] },
    h('button', { class: 'brow-main', attrs: { type: 'button', 'aria-label': `${b.client_name}, ${b.service}, ${b.when}. Open booking` }, on: { click: onOpen } },
      h('span', { class: 'brow-time' }, h('span', { class: 'brow-hour', text: time12(b.local_time) }), h('span', { class: 'brow-date', text: formatDateLong(b.local_date).replace(/^(\w+) /, (m) => m.slice(0, 3) + ' ') })),
      h('span', { class: 'brow-body' },
        h('span', { class: 'brow-client', text: b.client_name }),
        h('span', { class: 'brow-svc' }, proDot(b.professional_color), h('span', { text: `${b.service} with ${b.professional_short}` }))),
      h('span', { class: 'brow-side' }, statusBadge(b.status), h('span', { class: 'brow-price', text: b.price_label }))),
    extra ?? null);
}

/** Inline confirm / decline for pending requests. */
export function quickActions(b: Booking, onDone: () => void) {
  if (b.status !== 'pending') return null;
  const confirmBtn = button('Confirm', { size: 'sm', icon: 'check', onClick: async () => {
    setBusy(confirmBtn, true, 'Confirming…');
    try { await rpc('salon_dash_booking_action', { p_booking: b.id, p_action: 'confirm', p_version: b.version }); toast(`Confirmed ${b.client_name}`); onDone(); }
    catch (e) { setBusy(confirmBtn, false); toast((e as Error).message, 'error'); }
  } });
  const declineBtn = button('Decline', { size: 'sm', variant: 'ghost', onClick: async () => {
    const c = await confirmDialog({ title: 'Decline this request?', message: `${b.client_name}, ${b.service} on ${b.when}. The time is released for other clients.`, confirmLabel: 'Decline request', danger: true, reasonLabel: 'Reason for the client (optional)' });
    if (!c.ok) return;
    try { await rpc('salon_dash_booking_action', { p_booking: b.id, p_action: 'decline', p_reason: c.reason || null, p_version: b.version }); toast('Request declined'); onDone(); }
    catch (e) { toast((e as Error).message, 'error'); }
  } });
  return h('div', { class: 'brow-actions' }, confirmBtn, declineBtn);
}

const HISTORY_LABEL: Record<string, string> = {
  'booking.requested': 'Requested on the website', 'booking.created': 'Created in the studio', 'booking.confirmed': 'Confirmed',
  'booking.declined': 'Declined', 'booking.cancelled': 'Cancelled', 'booking.completed': 'Marked completed', 'booking.no_show': 'Marked no-show',
  'booking.rescheduled': 'Moved', 'booking.reassigned': 'Moved to another professional', 'booking.reassigned_away': 'Moved to another professional',
  'booking.note': 'Studio note updated', 'booking.expired': 'Expired (not confirmed in time)',
};
const PURPOSE_LABEL: Record<string, string> = {
  request_received: 'Request received (to client)', new_request: 'New request (to artist)', confirmed: 'Confirmation (to client)',
  declined: 'Declined (to client)', cancelled: 'Cancellation (to client)', cancelled_pro: 'Cancellation (to artist)', rescheduled: 'Moved (to client)', new_enquiry: 'New enquiry (to artist)',
};
export const MSG_STATUS: Record<string, string> = { not_connected: 'Not sent: SMS not connected', queued: 'Queued', sent: 'Sent', failed: 'Failed', skipped: 'Skipped', cancelled: 'Cancelled' };

export function openBooking(ctx: Ctx, id: string, onChange: () => void) {
  const d = openDialog({ title: 'Booking', kind: 'drawer' });
  const load = async () => {
    mount(d.body, spinner());
    mount(d.footer);
    let r: any;
    try { r = await rpc('salon_dash_booking', { p_booking: id }); } catch (e) { mount(d.body, errorBox((e as Error).message, load)); return; }
    const b: Booking = r.booking;
    d.setTitle(b.client_name);
    const act = async (action: string, label: string, opts: { confirm?: string; reason?: boolean; danger?: boolean } = {}) => {
      let reason = '';
      if (opts.confirm) {
        const c = await confirmDialog({ title: `${label}?`, message: opts.confirm, confirmLabel: label, danger: opts.danger, reasonLabel: opts.reason ? 'Reason (optional, shared with the client)' : undefined });
        if (!c.ok) return;
        reason = c.reason;
      }
      try {
        await rpc('salon_dash_booking_action', { p_booking: b.id, p_action: action, p_reason: reason || null, p_version: b.version });
        toast(`${label}: done`);
        onChange(); void load();
      } catch (e) { toast((e as Error).message, 'error'); void load(); }
    };
    const started = new Date(b.starts_at).getTime() <= Date.now();
    const noteField = textarea({ label: 'Studio note', name: 'internal_note', value: b.internal_note ?? '', rows: 3, maxlength: 2000, hint: 'Only visible in the studio.' });
    const saveNote = button('Save note', { variant: 'secondary', size: 'sm', onClick: async () => {
      setBusy(saveNote, true, 'Saving…');
      try { await rpc('salon_dash_booking_note', { p_booking: b.id, p_note: noteField.input.value }); toast('Note saved'); }
      catch (e) { toast((e as Error).message, 'error'); }
      setBusy(saveNote, false);
    } });

    mount(d.body,
      h('div', { class: 'bk-head' }, statusBadge(b.status), h('span', { class: 'bk-ref', text: `Ref ${b.ref}` })),
      b.status === 'pending' ? notice('warn', 'Awaiting confirmation. The client has been told the booking is provisional until it is confirmed.') : null,
      b.status_reason && ['declined', 'cancelled', 'expired'].includes(b.status) ? notice('info', `Reason: ${b.status_reason}`) : null,
      h('dl', { class: 'kv' },
        h('dt', { text: 'When' }), h('dd', { text: `${formatDateLong(b.local_date)}, ${time12(b.local_time)} to ${time12(b.local_end)}` }),
        h('dt', { text: 'Service' }), h('dd', { text: `${b.service}, ${durationLabel(b.duration_min)}${b.buffer_min ? ` + ${b.buffer_min} min buffer` : ''}` }),
        h('dt', { text: 'Professional' }), h('dd', null, proDot(b.professional_color), ' ', b.professional),
        h('dt', { text: 'Listed price' }), h('dd', { text: b.price_label }),
        h('dt', { text: 'Client' }), h('dd', { text: b.client_name }),
        h('dt', { text: 'Mobile' }), h('dd', null, h('a', { attrs: { href: `tel:${b.client_phone}` }, text: b.client_phone })),
        b.client_email ? [h('dt', { text: 'Email' }), h('dd', null, h('a', { attrs: { href: `mailto:${b.client_email}` }, text: b.client_email }))] : null,
        h('dt', { text: 'Booked via' }), h('dd', { text: `${SOURCE_LABEL[b.source] ?? b.source}, ${relativeTime(b.created_at)}` }),
        b.customer_note ? [h('dt', { text: 'Client note' }), h('dd', { class: 'pre', text: b.customer_note })] : null,
        h('dt', { text: 'Visits' }), h('dd', { text: `${r.client_visits} completed with ${b.professional_short}` })),
      noteField.wrap, h('div', { class: 'row-end' }, saveNote),
      h('h3', { class: 'sub-title', text: 'History' }),
      h('ol', { class: 'timeline' }, r.history.map((x: any) => h('li', null,
        h('span', { class: 'tl-when', text: dateTimeShort(x.at) }),
        h('span', { text: `${HISTORY_LABEL[x.action] ?? x.action}${x.detail?.reason ? ': ' + x.detail.reason : ''}${x.detail?.to && x.action.includes('resched') ? ` to ${x.detail.to}` : ''}` }),
        h('span', { class: 'tl-who', text: x.actor })))),
      h('h3', { class: 'sub-title', text: 'Messages' }),
      r.messages.length ? h('ul', { class: 'msg-mini' }, r.messages.map((x: any) => h('li', null,
        h('p', { class: 'msg-mini-head' }, h('span', { text: PURPOSE_LABEL[x.purpose] ?? x.purpose }), h('span', { class: ['msg-status', `ms-${x.status}`], text: MSG_STATUS[x.status] ?? x.status })),
        h('p', { class: 'msg-mini-body', text: x.body })))) : h('p', { class: 'muted small', text: 'No messages.' }));

    const buttons: Node[] = [];
    if (b.status === 'pending') {
      buttons.push(button('Confirm', { icon: 'check', onClick: () => act('confirm', 'Confirm') }));
      buttons.push(button('Decline', { variant: 'secondary', onClick: () => act('decline', 'Decline request', { confirm: 'The time is released and the client is told you cannot take it.', reason: true, danger: true }) }));
    }
    if (['pending', 'confirmed'].includes(b.status)) {
      buttons.push(button('Move', { variant: 'secondary', icon: 'calendar', onClick: () => openReschedule(ctx, b, () => { onChange(); void load(); }) }));
      buttons.push(button('Cancel booking', { variant: 'ghost', onClick: () => act('cancel', 'Cancel booking', { confirm: `${b.service} on ${b.when} will be cancelled and the time released.`, reason: true, danger: true }) }));
    }
    if (started && ['confirmed', 'no_show'].includes(b.status)) buttons.push(button('Mark completed', { variant: 'secondary', onClick: () => act('complete', 'Mark completed') }));
    if (started && ['confirmed', 'completed'].includes(b.status)) buttons.push(button('Mark no-show', { variant: 'ghost', onClick: () => act('no_show', 'Mark no-show', { confirm: 'Record that the client did not attend.' }) }));
    mount(d.footer, buttons);
  };
  void load();
}

// ----------------------------------------------------------------------- reschedule / reassign
function openReschedule(ctx: Ctx, b: Booking, onDone: () => void) {
  const d = openDialog({ title: 'Move booking', subtitle: `${b.client_name}, ${b.service}` });
  const proSel = ctx.isOwner ? select({ label: 'Professional', name: 'pro', value: b.professional_id, options: ctx.pros.map((p) => ({ value: p.id, label: p.display_name })) }) : null;
  const svcWrap = h('div');
  let svcSel: HTMLSelectElement | null = null;
  const fDate = field({ label: 'Date', name: 'date', type: 'date', value: b.local_date, min: todayLocal() });
  const slotsEl = h('div', { class: 'slot-pick' });
  const outside = checkbox({ name: 'outside', label: 'Allow a time outside working hours', hint: 'Overlapping bookings are never allowed.' });
  const fTime = field({ label: 'Time', name: 'time', type: 'time', value: b.local_time, step: '300' });
  fTime.wrap.hidden = true;
  const err = h('div', { attrs: { 'aria-live': 'assertive' } });
  let chosen = '';

  const loadServices = async () => {
    const pro = proSel?.input.value ?? b.professional_id;
    if (pro === b.professional_id) { mount(svcWrap); svcSel = null; return; }
    mount(svcWrap, spinner());
    const r = await rpc<any>('salon_dash_services', { p_salon: ctx.salonId, p_professional: pro });
    const items = r.items.filter((s: any) => s.active);
    const s = select({ label: 'Service with the new professional', name: 'svc', options: items.map((x: any) => ({ value: x.id, label: `${x.name} (${durationLabel(x.duration_min)}, ${x.price_label})` })),
      value: items.find((x: any) => x.name.toLowerCase() === b.service.toLowerCase())?.id });
    svcSel = s.input;
    svcSel.addEventListener('change', () => void loadSlots());
    mount(svcWrap, s.wrap);
  };
  const loadSlots = async () => {
    chosen = '';
    if (outside.input.checked) { mount(slotsEl); fTime.wrap.hidden = false; return; }
    fTime.wrap.hidden = true;
    if (!fDate.input.value) { mount(slotsEl); return; }
    mount(slotsEl, spinner('Loading times'));
    const pro = proSel?.input.value ?? b.professional_id;
    const svc = svcSel?.value ?? b.service_id;
    try {
      const r = await rpc<any>('salon_dash_slots', { p_salon: ctx.salonId, p_professional: pro, p_service: svc, p_date: fDate.input.value, p_exclude_booking: b.id });
      if (!r.slots.length) { mount(slotsEl, h('p', { class: 'muted small', text: 'No free times that day within working hours.' })); return; }
      mount(slotsEl, h('p', { class: 'field-label', text: 'Free times' }), h('div', { class: 'slot-grid' }, r.slots.map((s: any) => {
        const btn = h('button', { class: 'slot', attrs: { type: 'button', 'aria-pressed': 'false' }, text: s.label });
        btn.addEventListener('click', () => {
          chosen = s.time;
          slotsEl.querySelectorAll('.slot').forEach((x) => { x.classList.remove('selected'); x.setAttribute('aria-pressed', 'false'); });
          btn.classList.add('selected'); btn.setAttribute('aria-pressed', 'true');
        });
        return btn;
      })));
    } catch (e) { mount(slotsEl, errorBox((e as Error).message)); }
  };
  proSel?.input.addEventListener('change', async () => { await loadServices(); void loadSlots(); });
  fDate.input.addEventListener('change', () => void loadSlots());
  outside.input.addEventListener('change', () => void loadSlots());

  append(d.body, proSel?.wrap ?? null, svcWrap, fDate.wrap, outside.wrap, slotsEl, fTime.wrap, err,
    ctx.isOwner ? h('p', { class: 'muted small', text: 'Moving a booking to another professional copies only the client’s name and contact details, never notes.' }) : null);
  const save = button('Move booking', { onClick: async () => {
    mount(err);
    const time = outside.input.checked ? fTime.input.value : chosen;
    if (!time) { mount(err, notice('error', 'Choose a time.')); return; }
    setBusy(save, true, 'Saving…');
    try {
      const pro = proSel?.input.value ?? b.professional_id;
      await rpc('salon_dash_booking_reschedule', { p_booking: b.id, p_date: fDate.input.value, p_time: time,
        p_professional: pro !== b.professional_id ? pro : null, p_service: pro !== b.professional_id ? svcSel?.value ?? null : null,
        p_allow_outside_hours: outside.input.checked, p_version: b.version });
      toast('Booking moved');
      d.close(); onDone();
    } catch (e) { setBusy(save, false); mount(err, notice('error', (e as Error).message)); }
  } });
  append(d.footer, button('Cancel', { variant: 'ghost', onClick: () => d.close() }), save);
  void loadSlots();
}

// ----------------------------------------------------------------------- new booking
export function openNewBooking(ctx: Ctx, defaults: { date?: string; time?: string; pro?: string | null }, onDone: () => void) {
  const d = openDialog({ title: 'New booking', subtitle: 'For phone, Instagram or walk-in clients.' });
  const idem = newIdempotencyKey();
  const proSel = ctx.isOwner
    ? select({ label: 'Professional', name: 'pro', value: defaults.pro ?? ctx.scope ?? ctx.pros[0]?.id, options: ctx.pros.map((p) => ({ value: p.id, label: p.display_name })) })
    : null;
  const svcWrap = h('div');
  let svcSel: HTMLSelectElement | null = null;
  const fDate = field({ label: 'Date', name: 'date', type: 'date', value: defaults.date ?? todayLocal() });
  const outside = checkbox({ name: 'outside', label: 'Allow a time outside working hours', hint: 'Overlapping bookings are never allowed.' });
  const slotsEl = h('div', { class: 'slot-pick' });
  const fTime = field({ label: 'Time', name: 'time', type: 'time', value: defaults.time ?? '', step: '300' });
  fTime.wrap.hidden = true;
  const fName = field({ label: 'Client name', name: 'name', required: true, maxlength: 80 });
  const fPhone = field({ label: 'Client mobile', name: 'phone', type: 'tel', required: true, inputmode: 'tel', hint: 'If this number already exists for the professional, the existing client record is used.' });
  const fEmail = field({ label: 'Client email', name: 'email', type: 'email' });
  const fNote = textarea({ label: 'Studio note', name: 'internal_note', rows: 2, maxlength: 2000 });
  const srcSel = select({ label: 'Booked via', name: 'source', value: 'phone', options: [{ value: 'phone', label: 'Phone' }, { value: 'walk_in', label: 'Walk-in' }, { value: 'dashboard', label: 'Instagram or message' }, { value: 'other', label: 'Other' }] });
  const statusSel = select({ label: 'Status', name: 'status', value: 'confirmed', options: [{ value: 'confirmed', label: 'Confirmed' }, { value: 'pending', label: 'Awaiting confirmation' }] });
  const err = h('div', { attrs: { 'aria-live': 'assertive' } });
  let chosen = defaults.time ?? '';

  const proId = () => proSel?.input.value ?? ctx.ownPro?.id ?? '';
  const loadServices = async () => {
    mount(svcWrap, spinner());
    const r = await rpc<any>('salon_dash_services', { p_salon: ctx.salonId, p_professional: proId() });
    const items = r.items.filter((s: any) => s.active);
    if (!items.length) { mount(svcWrap, notice('info', 'This professional has no active services.')); svcSel = null; return; }
    const s = select({ label: 'Service', name: 'svc', options: items.map((x: any) => ({ value: x.id, label: `${x.name} (${durationLabel(x.duration_min)}, ${x.price_label})` })) });
    svcSel = s.input;
    svcSel.addEventListener('change', () => void loadSlots());
    mount(svcWrap, s.wrap);
  };
  const loadSlots = async () => {
    if (outside.input.checked) { mount(slotsEl); fTime.wrap.hidden = false; return; }
    fTime.wrap.hidden = true;
    if (!svcSel || !fDate.input.value) { mount(slotsEl); return; }
    mount(slotsEl, spinner('Loading times'));
    try {
      const r = await rpc<any>('salon_dash_slots', { p_salon: ctx.salonId, p_professional: proId(), p_service: svcSel.value, p_date: fDate.input.value });
      if (!r.slots.length) { mount(slotsEl, h('p', { class: 'muted small', text: 'No free times that day within working hours. Tick the box above to choose another time.' })); chosen = ''; return; }
      if (!r.slots.some((s: any) => s.time === chosen)) chosen = '';
      mount(slotsEl, h('p', { class: 'field-label', text: 'Free times' }), h('div', { class: 'slot-grid' }, r.slots.map((s: any) => {
        const btn = h('button', { class: ['slot', chosen === s.time && 'selected'], attrs: { type: 'button', 'aria-pressed': String(chosen === s.time) }, text: s.label });
        btn.addEventListener('click', () => {
          chosen = s.time;
          slotsEl.querySelectorAll('.slot').forEach((x) => { x.classList.remove('selected'); x.setAttribute('aria-pressed', 'false'); });
          btn.classList.add('selected'); btn.setAttribute('aria-pressed', 'true');
        });
        return btn;
      })));
    } catch (e) { mount(slotsEl, errorBox((e as Error).message)); }
  };
  proSel?.input.addEventListener('change', async () => { await loadServices(); void loadSlots(); });
  fDate.input.addEventListener('change', () => void loadSlots());
  outside.input.addEventListener('change', () => void loadSlots());

  append(d.body, proSel?.wrap ?? null, svcWrap, fDate.wrap, outside.wrap, slotsEl, fTime.wrap,
    h('div', { class: 'form-row' }, fName.wrap, fPhone.wrap), fEmail.wrap, h('div', { class: 'form-row' }, srcSel.wrap, statusSel.wrap), fNote.wrap, err);
  const save = button('Save booking', { onClick: async () => {
    mount(err); fName.setError(null); fPhone.setError(null);
    const time = outside.input.checked ? fTime.input.value : chosen;
    if (!svcSel) { mount(err, notice('error', 'Choose a service.')); return; }
    if (!time) { mount(err, notice('error', 'Choose a time.')); return; }
    if (fName.input.value.trim().length < 2) { fName.setError('Enter the client’s name.'); return; }
    if (fPhone.input.value.replace(/[^0-9]/g, '').length < 10) { fPhone.setError('Enter a valid mobile number.'); return; }
    setBusy(save, true, 'Saving…');
    try {
      await rpc('salon_dash_booking_create', { p_salon: ctx.salonId, p_payload: {
        professional_id: proId(), service_id: svcSel.value, date: fDate.input.value, time, name: fName.input.value.trim(), phone: fPhone.input.value.trim(),
        email: fEmail.input.value.trim() || null, internal_note: fNote.input.value.trim() || null, source: srcSel.input.value, status: statusSel.input.value,
        allow_outside_hours: outside.input.checked, idempotency_key: idem,
      } });
      toast('Booking saved');
      d.close(); onDone();
    } catch (e) { setBusy(save, false); mount(err, notice('error', (e as Error).message)); }
  } });
  append(d.footer, button('Cancel', { variant: 'ghost', onClick: () => d.close() }), save);
  void loadServices().then(loadSlots);
}

export function csvDownload(filename: string, rows: (string | number | null)[][]) {
  const esc = (v: string | number | null) => {
    let s = v === null || v === undefined ? '' : String(v);
    if (/^[=+\-@]/.test(s)) s = `'${s}`; // spreadsheet formula injection guard
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const blob = new Blob(['﻿' + rows.map((r) => r.map(esc).join(',')).join('\r\n')], { type: 'text/csv;charset=utf-8' });
  const a = h('a', { attrs: { href: URL.createObjectURL(blob), download: filename } });
  document.body.appendChild(a); a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
}

export { icon };
