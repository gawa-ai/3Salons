import { h, icon, mount, append } from '../lib/dom';
import { button, spinner, emptyState, field, textarea, select, checkbox, toast, openDialog, setBusy, proDot, notice, confirmDialog, errorBox } from '../lib/ui';
import { rpc, uploadFile, removeFile, publicStorageUrl, updatePassword, signOut } from '../lib/supabase';
import { WEEKDAYS, addDays, todayLocal, pounds, durationLabel, dateTimeShort, zonedToUtc, time12 } from '../lib/format';
import { PORTFOLIO_BUCKET } from '../config';
import { navigate } from '../lib/router';
import { loadMe } from '../auth/session';
import type { Ctx } from './shell';
import { csvDownload } from './booking';

// ===================================================================== services
export async function servicesPage(ctx: Ctx) {
  const load = async () => {
    mount(ctx.content, spinner());
    const r = await rpc<any>('salon_dash_services', { p_salon: ctx.salonId, p_professional: ctx.scope });
    const byPro = new Map<string, any[]>();
    r.items.forEach((s: any) => byPro.set(s.professional_id, [...(byPro.get(s.professional_id) ?? []), s]));
    const unconfirmed = r.items.filter((s: any) => !s.details_confirmed && s.price_kind !== 'enquire').length;
    mount(ctx.content,
      unconfirmed ? notice('warn', `${unconfirmed} service time${unconfirmed === 1 ? '' : 's'} are placeholders and still need confirming. Check each duration and buffer, then ${ctx.isOwner ? 'mark them confirmed' : 'ask the owner to mark them confirmed'}.`) : null,
      !ctx.isOwner ? h('p', { class: 'muted small', text: 'You can change the description, duration, preparation buffer and whether a service can be booked online. Prices and names are managed by the owner.' }) : null,
      Array.from(byPro.entries()).map(([proId, items]) => {
        const p = ctx.proById(proId);
        return h('section', { class: 'panel' },
          h('div', { class: 'panel-head' }, h('h3', { class: 'panel-title' }, p ? proDot(p.color) : null, ' ', p?.display_name ?? 'Services')),
          h('div', { class: 'table-wrap' }, h('table', { class: 'table' },
            h('thead', null, h('tr', null, ['Service', 'Price', 'Duration', 'Online', 'Status', ''].map((t) => h('th', { attrs: { scope: 'col' }, text: t })))),
            h('tbody', null, items.map((s) => h('tr', { class: !s.active ? 'row-muted' : '' },
              h('th', { attrs: { scope: 'row' } }, h('span', { class: 'cell-strong', text: s.name }), s.description ? h('span', { class: 'cell-sub', text: s.description }) : null),
              h('td', { text: s.price_label }),
              h('td', null, s.price_kind === 'enquire' ? '—' : `${durationLabel(s.duration_min)}${s.buffer_min ? ` + ${s.buffer_min} min` : ''}`,
                s.price_kind !== 'enquire' && !s.details_confirmed ? h('span', { class: 'badge badge-pending tiny', text: 'To confirm' }) : null),
              h('td', { text: s.price_kind === 'enquire' ? 'Enquiry' : s.bookable_online ? 'Yes' : 'No' }),
              h('td', { text: s.active ? 'Active' : 'Hidden' }),
              h('td', { class: 'cell-actions' }, button('Edit', { size: 'sm', variant: 'ghost', onClick: () => editService(ctx, s, load) }))))))));
      }),
      !r.items.length ? emptyState('No services yet', ctx.isOwner ? 'Add the first service for a professional.' : 'The owner has not added services for you yet.') : null);
  };
  if (ctx.isOwner) ctx.setActions([button('Add service', { icon: 'plus', size: 'sm', onClick: () => editService(ctx, null, load) })]);
  await load();
}

function editService(ctx: Ctx, s: any | null, onDone: () => void) {
  const owner = ctx.isOwner;
  const d = openDialog({ title: s ? `Edit ${s.name}` : 'Add service', subtitle: s ? ctx.proById(s.professional_id)?.display_name : undefined });
  const pro = !s && owner ? select({ label: 'Professional', name: 'pro', value: ctx.scope ?? ctx.pros[0]?.id, options: ctx.pros.map((p) => ({ value: p.id, label: p.display_name })) }) : null;
  const fName = field({ label: 'Name', name: 'name', value: s?.name ?? '', maxlength: 80 });
  fName.input.disabled = !owner;
  const fDesc = textarea({ label: 'Description', name: 'desc', value: s?.description ?? '', rows: 2, maxlength: 500 });
  const kind = select({ label: 'Price type', name: 'kind', value: s?.price_kind ?? 'fixed', options: [{ value: 'fixed', label: 'Fixed price' }, { value: 'from', label: '"From" price' }, { value: 'enquire', label: 'Please enquire (not bookable online)' }] });
  kind.input.disabled = !owner;
  const fPrice = field({ label: 'Price (£)', name: 'price', type: 'number', min: '0', step: '0.01', value: s?.price_pence != null ? (s.price_pence / 100).toFixed(2).replace(/\.00$/, '') : '', inputmode: 'decimal' });
  fPrice.input.disabled = !owner;
  const cat = select({ label: 'Category', name: 'cat', value: s?.category ?? 'other', options: [['hair', 'Hair'], ['makeup', 'Makeup'], ['hair_makeup', 'Hair and makeup'], ['hijab', 'Hijab'], ['saree', 'Saree'], ['bridal', 'Bridal'], ['other', 'Other']].map(([value, label]) => ({ value, label })) });
  cat.input.disabled = !owner;
  const fDur = field({ label: 'Duration (minutes)', name: 'dur', type: 'number', min: '5', max: '720', step: '5', value: String(s?.duration_min ?? 60) });
  const fBuf = field({ label: 'Buffer after (minutes)', name: 'buf', type: 'number', min: '0', max: '240', step: '5', value: String(s?.buffer_min ?? 0), hint: 'Clean-up or preparation time kept free after the appointment.' });
  const online = checkbox({ name: 'online', checked: s?.bookable_online ?? true, label: 'Clients can book this online' });
  const active = checkbox({ name: 'active', checked: s?.active ?? true, label: 'Show this service' });
  const confirmed = owner ? checkbox({ name: 'confirmed', checked: s?.details_confirmed ?? false, label: 'Duration and buffer are confirmed' }) : null;
  const err = h('div', { attrs: { 'aria-live': 'assertive' } });
  const syncKind = () => { const enq = kind.input.value === 'enquire'; fPrice.wrap.hidden = enq; online.wrap.hidden = enq; };
  kind.input.addEventListener('change', syncKind); syncKind();
  append(d.body, pro?.wrap ?? null, fName.wrap, fDesc.wrap, h('div', { class: 'form-row' }, kind.wrap, fPrice.wrap), cat.wrap, h('div', { class: 'form-row' }, fDur.wrap, fBuf.wrap), online.wrap, active.wrap, confirmed?.wrap ?? null, err);
  const save = button('Save service', { onClick: async () => {
    mount(err);
    const payload: Record<string, unknown> = {
      description: fDesc.input.value, duration_min: Number(fDur.input.value), buffer_min: Number(fBuf.input.value),
      bookable_online: online.input.checked, active: active.input.checked,
    };
    if (owner) {
      Object.assign(payload, { name: fName.input.value, price_kind: kind.input.value, category: cat.input.value, details_confirmed: confirmed!.input.checked,
        price_pence: kind.input.value === 'enquire' ? null : Math.round(Number(fPrice.input.value) * 100) });
      if (kind.input.value !== 'enquire' && (fPrice.input.value === '' || Number.isNaN(Number(fPrice.input.value)))) { mount(err, notice('error', 'Enter a price.')); return; }
    }
    if (s) payload.id = s.id; else payload.professional_id = pro?.input.value;
    setBusy(save, true, 'Saving…');
    try { await rpc('salon_dash_service_save', { p_salon: ctx.salonId, p_payload: payload }); toast('Service saved'); d.close(); onDone(); }
    catch (e) { setBusy(save, false); mount(err, notice('error', (e as Error).message)); }
  } });
  append(d.footer, button('Cancel', { variant: 'ghost', onClick: () => d.close() }), save);
}

// ===================================================================== availability
export async function availabilityPage(ctx: Ctx) {
  const load = async () => {
    mount(ctx.content, spinner());
    const r = await rpc<any>('salon_dash_schedule', { p_salon: ctx.salonId, p_professional: ctx.scope });
    mount(ctx.content,
      ctx.isOwner ? salonHoursPanel(ctx, r, load) : null,
      r.professionals.map((p: any) => proSchedulePanel(ctx, p, load)),
      h('section', { class: 'panel' },
        h('div', { class: 'panel-head' }, h('h3', { class: 'panel-title', text: 'Salon closures' }),
          ctx.isOwner ? button('Close the salon', { size: 'sm', variant: 'secondary', icon: 'plus', onClick: () => addTimeOff(ctx, null, load) }) : null),
        r.salon_time_off.length ? timeOffList(ctx, r.salon_time_off, ctx.isOwner, load) : h('p', { class: 'muted small', text: 'No upcoming closures.' })));
  };
  await load();
}

function hoursEditor(rows: { weekday: number; opens: string; closes: string }[]) {
  const order = [1, 2, 3, 4, 5, 6, 0];
  const lines = order.map((wd) => {
    const r = rows.find((x) => x.weekday === wd);
    const open = checkbox({ name: `d${wd}`, checked: !!r, label: WEEKDAYS[wd] });
    const o = h('input', { class: 'input input-sm', attrs: { type: 'time', step: '900', 'aria-label': `${WEEKDAYS[wd]} start`, value: r?.opens ?? '10:00' } });
    const c = h('input', { class: 'input input-sm', attrs: { type: 'time', step: '900', 'aria-label': `${WEEKDAYS[wd]} end`, value: r?.closes ?? '18:00' } });
    const sync = () => { o.disabled = !open.input.checked; c.disabled = !open.input.checked; };
    open.input.addEventListener('change', sync); sync();
    return { wd, el: h('div', { class: 'hours-line' }, open.wrap, h('div', { class: 'hours-times' }, o, h('span', { class: 'muted', text: 'to' }), c)), open, o, c };
  });
  return {
    el: h('div', { class: 'hours-edit' }, lines.map((l) => l.el)),
    value: () => lines.filter((l) => l.open.input.checked).map((l) => ({ weekday: l.wd, opens: l.o.value, closes: l.c.value })),
  };
}

function salonHoursPanel(ctx: Ctx, r: any, reload: () => void) {
  const ed = hoursEditor(r.salon_hours);
  const confirmed = checkbox({ name: 'confirmed', checked: r.hours_confirmed, label: 'These are the confirmed opening hours (show them on the website)' });
  const save = button('Save salon hours', { size: 'sm', onClick: async () => {
    setBusy(save, true, 'Saving…');
    try {
      await rpc('salon_owner_salon_hours_save', { p_salon: ctx.salonId, p_rows: ed.value() });
      await rpc('salon_owner_settings_save', { p_salon: ctx.salonId, p_payload: { hours_confirmed: confirmed.input.checked } });
      toast('Salon hours saved'); reload();
    } catch (e) { setBusy(save, false); toast((e as Error).message, 'error'); }
  } });
  return h('section', { class: 'panel' },
    h('div', { class: 'panel-head' }, h('h3', { class: 'panel-title', text: 'Salon opening hours' })),
    h('p', { class: 'muted small', text: 'No one can be booked online outside these hours.' }),
    !r.hours_confirmed ? notice('warn', 'These hours are placeholders and are not shown on the website until you confirm them.') : null,
    ed.el, confirmed.wrap, h('div', { class: 'row-end' }, save));
}

function proSchedulePanel(ctx: Ctx, p: any, reload: () => void) {
  const ed = hoursEditor(p.working_hours);
  const save = button('Save working hours', { size: 'sm', onClick: async () => {
    setBusy(save, true, 'Saving…');
    try {
      const r = await rpc<any>('salon_dash_hours_save', { p_salon: ctx.salonId, p_professional: p.id, p_rows: ed.value() });
      toast(r.bookings_outside_hours ? `Saved. ${r.bookings_outside_hours} upcoming booking(s) now fall outside these hours and were kept.` : 'Working hours saved', r.bookings_outside_hours ? 'info' : 'success');
      reload();
    } catch (e) { setBusy(save, false); toast((e as Error).message, 'error'); }
  } });
  return h('section', { class: ['panel', `pro-${p.color}`] },
    h('div', { class: 'panel-head' }, h('h3', { class: 'panel-title' }, proDot(p.color), ` ${p.name}`)),
    h('div', { class: 'two-col' },
      h('div', null, h('p', { class: 'sub-title', text: 'Working hours' }), ed.el, h('div', { class: 'row-end' }, save)),
      h('div', null, h('div', { class: 'row-between' }, h('p', { class: 'sub-title', text: 'Time off' }), button('Add time off', { size: 'sm', variant: 'secondary', icon: 'plus', onClick: () => addTimeOff(ctx, p.id, reload) })),
        p.time_off.length ? timeOffList(ctx, p.time_off, true, reload) : h('p', { class: 'muted small', text: 'No upcoming time off.' }))));
}

function timeOffList(_ctx: Ctx, items: any[], canDelete: boolean, reload: () => void) {
  return h('ul', { class: 'tol' }, items.map((t) => h('li', null,
    h('div', null, h('p', { class: 'cell-strong', text: `${dateTimeShort(t.starts_at)} to ${dateTimeShort(t.ends_at)}` }), t.reason ? h('p', { class: 'muted small', text: t.reason }) : null),
    canDelete ? button('Remove', { size: 'sm', variant: 'ghost', onClick: async () => {
      const c = await confirmDialog({ title: 'Remove time off?', message: 'Those times will become bookable again.', confirmLabel: 'Remove' });
      if (!c.ok) return;
      try { await rpc('salon_dash_time_off_delete', { p_id: t.id }); toast('Time off removed'); reload(); } catch (e) { toast((e as Error).message, 'error'); }
    } }) : null)));
}

function addTimeOff(ctx: Ctx, proId: string | null, reload: () => void) {
  const d = openDialog({ title: proId ? 'Add time off' : 'Close the salon', size: 'sm' });
  const fFrom = field({ label: 'From date', name: 'from', type: 'date', value: todayLocal(), min: todayLocal() });
  const fFromT = field({ label: 'From time', name: 'fromt', type: 'time', value: '00:00' });
  const fTo = field({ label: 'Until date', name: 'to', type: 'date', value: todayLocal(), min: todayLocal() });
  const fToT = field({ label: 'Until time', name: 'tot', type: 'time', value: '23:59' });
  const fReason = field({ label: 'Reason', name: 'reason', maxlength: 200, hint: 'Only visible in the studio.' });
  append(d.body, h('div', { class: 'form-row' }, fFrom.wrap, fFromT.wrap), h('div', { class: 'form-row' }, fTo.wrap, fToT.wrap), fReason.wrap);
  const save = button('Save', { onClick: async () => {
    const s = zonedToUtc(fFrom.input.value, fFromT.input.value || '00:00');
    const e = zonedToUtc(fTo.input.value, fToT.input.value || '23:59');
    setBusy(save, true, 'Saving…');
    try {
      const r = await rpc<any>('salon_dash_time_off_add', { p_salon: ctx.salonId, p_professional: proId, p_starts: s.toISOString(), p_ends: e.toISOString(), p_reason: fReason.input.value || null });
      toast(r.overlapping_bookings ? `Saved. ${r.overlapping_bookings} existing booking(s) fall in this time and were kept; move or cancel them if needed.` : 'Saved', r.overlapping_bookings ? 'info' : 'success');
      d.close(); reload();
    } catch (err) { setBusy(save, false); toast((err as Error).message, 'error'); }
  } });
  append(d.footer, button('Cancel', { variant: 'ghost', onClick: () => d.close() }), save);
}

// ===================================================================== gallery
export async function galleryPage(ctx: Ctx) {
  const load = async () => {
    mount(ctx.content, spinner());
    const r = await rpc<any>('salon_dash_gallery', { p_salon: ctx.salonId, p_professional: ctx.scope });
    const target = ctx.isOwner ? (ctx.scope ?? null) : ctx.ownPro?.id ?? null;
    const input = h('input', { class: 'sr-only', attrs: { type: 'file', accept: 'image/jpeg,image/png,image/webp,video/mp4', multiple: true, id: 'gallery-file' } });
    const status = h('div', { attrs: { 'aria-live': 'polite' } });
    input.addEventListener('change', async () => {
      const files = Array.from(input.files ?? []);
      if (!target) { toast('Choose a professional at the top first.', 'error'); return; }
      for (const f of files) {
        if (f.size > 50 * 1024 * 1024) { toast(`${f.name} is larger than 50 MB.`, 'error'); continue; }
        mount(status, notice('info', `Uploading ${f.name}…`));
        const ext = (f.name.split('.').pop() ?? 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '').slice(0, 5) || 'jpg';
        const path = `${ctx.salonId}/${target}/${crypto.randomUUID()}.${ext}`;
        try {
          await uploadFile(PORTFOLIO_BUCKET, path, f);
          await rpc('salon_dash_gallery_add', { p_salon: ctx.salonId, p_professional: target, p_path: path, p_media_type: f.type.startsWith('video') ? 'video' : 'image', p_alt: '' });
        } catch (e) { toast((e as Error).message, 'error'); }
      }
      mount(status); void load();
    });
    mount(ctx.content,
      h('div', { class: 'panel upload-panel' },
        h('div', null, h('h3', { class: 'panel-title', text: 'Add photos or videos' }),
          h('p', { class: 'muted small', text: 'JPG, PNG, WebP or MP4 up to 50 MB. Only share photos the client has agreed to. Add a short description for screen-reader users.' })),
        target ? h('label', { class: 'btn btn-primary btn-sm', attrs: { for: 'gallery-file' } }, icon('upload', 17), h('span', { text: 'Choose files' })) : h('p', { class: 'muted small', text: 'Choose a professional at the top to upload to their portfolio.' }),
        input, status),
      r.items.length ? h('ul', { class: 'gal-admin' }, r.items.map((g: any) => {
        const alt = h('input', { class: 'input input-sm', attrs: { value: g.alt_text ?? '', maxlength: 200, placeholder: 'Describe the look', 'aria-label': 'Description' } });
        const pub = checkbox({ name: `p${g.id}`, checked: g.published, label: 'Show on website' });
        return h('li', { class: 'gal-card' },
          g.media_type === 'video' ? h('video', { attrs: { src: publicStorageUrl(PORTFOLIO_BUCKET, g.storage_path), muted: true, controls: true, preload: 'metadata' } })
            : h('img', { attrs: { src: publicStorageUrl(PORTFOLIO_BUCKET, g.storage_path), alt: g.alt_text || '', loading: 'lazy' } }),
          ctx.isOwner && !ctx.scope ? h('p', { class: 'muted small', text: g.professional }) : null,
          alt, pub.wrap,
          h('div', { class: 'row-between' },
            button('Save', { size: 'sm', variant: 'secondary', onClick: async () => { try { await rpc('salon_dash_gallery_update', { p_item: g.id, p_payload: { alt_text: alt.value, published: pub.input.checked } }); toast('Saved'); } catch (e) { toast((e as Error).message, 'error'); } } }),
            button('Delete', { size: 'sm', variant: 'ghost', icon: 'trash', onClick: async () => {
              const c = await confirmDialog({ title: 'Delete this item?', message: 'It will be removed from the website and storage.', confirmLabel: 'Delete', danger: true });
              if (!c.ok) return;
              try { const res = await rpc<any>('salon_dash_gallery_delete', { p_item: g.id }); await removeFile(PORTFOLIO_BUCKET, res.storage_path); toast('Deleted'); void load(); } catch (e) { toast((e as Error).message, 'error'); }
            } })));
      })) : emptyState('No portfolio items yet', 'Uploaded photos appear on the public website once published.'));
  };
  await load();
}

// ===================================================================== reports
export async function reportsPage(ctx: Ctx) {
  const fFrom = h('input', { class: 'input input-sm', attrs: { type: 'date', 'aria-label': 'From', value: addDays(todayLocal(), -29) } });
  const fTo = h('input', { class: 'input input-sm', attrs: { type: 'date', 'aria-label': 'To', value: todayLocal() } });
  const out = h('div');
  let last: any = null;
  const load = async () => {
    mount(out, spinner());
    try {
      last = await rpc<any>('salon_dash_report', { p_salon: ctx.salonId, p_professional: ctx.scope, p_from: fFrom.value, p_to: fTo.value });
    } catch (e) { mount(out, errorBox((e as Error).message)); return; }
    const t = last.totals ?? {};
    const cols: [string, string][] = [['total', 'Bookings'], ['completed', 'Completed'], ['confirmed', 'Confirmed'], ['pending', 'Awaiting'], ['cancelled', 'Cancelled'], ['declined', 'Declined'], ['no_show', 'No-shows'], ['expired', 'Expired']];
    mount(out,
      h('div', { class: 'tiles' },
        h('div', { class: 'tile' }, h('p', { class: 'tile-label', text: 'Bookings in range' }), h('p', { class: 'tile-value', text: String(t.total ?? 0) }), h('p', { class: 'tile-sub', text: `${t.website ?? 0} from the website` })),
        h('div', { class: 'tile' }, h('p', { class: 'tile-label', text: 'Completed appointment value' }), h('p', { class: 'tile-value', text: pounds(Number(t.completed_value_pence ?? 0)) }), h('p', { class: 'tile-sub', text: 'At listed prices. Not payments received.' })),
        h('div', { class: 'tile' }, h('p', { class: 'tile-label', text: 'Booked value' }), h('p', { class: 'tile-value', text: pounds(Number(t.booked_value_pence ?? 0)) }), h('p', { class: 'tile-sub', text: 'Confirmed and completed, at listed prices.' }))),
      h('div', { class: 'table-wrap' }, h('table', { class: 'table' },
        h('thead', null, h('tr', null, h('th', { attrs: { scope: 'col' }, text: 'Professional' }), cols.map(([, l]) => h('th', { attrs: { scope: 'col' }, class: 'num', text: l })), h('th', { attrs: { scope: 'col' }, class: 'num', text: 'Completed value' }))),
        h('tbody', null, last.rows.map((r: any) => h('tr', null,
          h('th', { attrs: { scope: 'row' } }, h('span', { class: 'cell-pro' }, proDot(r.color), r.professional)),
          cols.map(([k]) => h('td', { class: 'num', text: String(r[k]) })), h('td', { class: 'num', text: pounds(r.completed_value_pence) })))),
        last.rows.length > 1 ? h('tfoot', null, h('tr', null, h('th', { attrs: { scope: 'row' }, text: 'Total' }), cols.map(([k]) => h('td', { class: 'num', text: String(t[k] ?? 0) })), h('td', { class: 'num', text: pounds(Number(t.completed_value_pence ?? 0)) }))) : null)),
      h('p', { class: 'muted small mt', text: 'Bookings are counted by appointment date (UK time). The total row is the sum of the rows above. Payments are not recorded in this system.' }));
  };
  ctx.setActions([button('Export CSV', { variant: 'ghost', size: 'sm', icon: 'download', onClick: () => last && csvDownload(`report-${last.from}-to-${last.to}.csv`, [
    ['Professional', 'Bookings', 'Completed', 'Confirmed', 'Awaiting', 'Cancelled', 'Declined', 'No-shows', 'Expired', 'Completed value (GBP, listed prices)', 'Booked value (GBP, listed prices)'],
    ...last.rows.map((r: any) => [r.professional, r.total, r.completed, r.confirmed, r.pending, r.cancelled, r.declined, r.no_show, r.expired, (r.completed_value_pence / 100).toFixed(2), (r.booked_value_pence / 100).toFixed(2)])]) })]);
  const apply = button('Show', { size: 'sm', variant: 'secondary', onClick: () => void load() });
  mount(ctx.content, h('div', { class: 'list-tools' }, h('div', { class: 'range' }, h('label', { class: 'muted small', text: 'From' }), fFrom, h('label', { class: 'muted small', text: 'to' }), fTo, apply)), out);
  await load();
}

// ===================================================================== team (owner)
export async function teamPage(ctx: Ctx) {
  const load = async () => {
    mount(ctx.content, spinner());
    const r = await rpc<any>('salon_owner_team', { p_salon: ctx.salonId });
    mount(ctx.content,
      h('p', { class: 'muted small', text: 'Each professional signs in with their own account and only sees their own bookings and clients. You see everyone.' }),
      h('ul', { class: 'team' }, r.professionals.map((p: any) => {
        const member = p.members.find((m: any) => m.role === 'professional' && m.status === 'active') ?? p.members.find((m: any) => m.role === 'professional');
        const ownerHere = p.members.find((m: any) => m.role === 'owner');
        const inv = p.invitations[0];
        return h('li', { class: ['team-card', `pro-${p.color}`] },
          h('div', { class: 'team-head' },
            p.logo_path ? h('img', { class: 'team-logo', attrs: { src: p.logo_path, alt: '', width: 56, height: 56 } }) : h('span', { class: 'team-logo team-logo-text', text: p.short_name[0] }),
            h('div', null, h('p', { class: 'team-name', text: p.display_name }), h('p', { class: 'muted small', text: p.specialty ?? '' })),
            h('div', { class: 'team-flags' },
              h('span', { class: ['badge', p.is_public ? 'badge-confirmed' : 'badge-neutral'], text: p.is_public ? 'On website' : 'Hidden' }),
              h('span', { class: ['badge', p.online_booking ? 'badge-confirmed' : 'badge-neutral'], text: p.online_booking ? 'Online booking on' : 'Online booking off' }))),
          h('div', { class: 'team-login' },
            ownerHere ? h('p', { class: 'small', text: `Your own profile (${ownerHere.email}).` })
              : member ? h('p', { class: 'small' }, h('span', { class: ['badge', member.status === 'active' ? 'badge-confirmed' : 'badge-cancelled'], text: member.status === 'active' ? 'Login active' : 'Login disabled' }), ` ${member.email}${member.last_sign_in_at ? ', last sign-in ' + dateTimeShort(member.last_sign_in_at) : ''}`)
              : inv ? h('p', { class: 'small' }, h('span', { class: 'badge badge-pending', text: 'Invited' }), ` ${inv.email}, code expires ${dateTimeShort(inv.expires_at)}`)
              : h('p', { class: 'small muted', text: 'No login yet.' })),
          h('div', { class: 'team-actions' },
            button('Edit profile', { size: 'sm', variant: 'secondary', onClick: () => editProfile(ctx, p, load) }),
            !ownerHere && (!member || member.status !== 'active') ? button(inv ? 'New invitation' : 'Invite', { size: 'sm', onClick: () => invite(ctx, p, load) }) : null,
            inv && !member ? button('Revoke invitation', { size: 'sm', variant: 'ghost', onClick: async () => { await rpc('salon_owner_invite_revoke', { p_invite: inv.id }); toast('Invitation revoked'); void load(); } }) : null,
            member && member.status === 'active' ? button('Disable login', { size: 'sm', variant: 'ghost', onClick: async () => {
              const c = await confirmDialog({ title: `Disable ${p.short_name}'s login?`, message: 'They will immediately lose access to the studio. Their bookings and clients are kept.', confirmLabel: 'Disable login', danger: true });
              if (!c.ok) return;
              try { await rpc('salon_owner_member_status', { p_membership: member.membership_id, p_status: 'disabled' }); toast('Login disabled'); void load(); } catch (e) { toast((e as Error).message, 'error'); }
            } }) : null,
            member && member.status === 'disabled' ? button('Enable login', { size: 'sm', variant: 'ghost', onClick: async () => {
              try { await rpc('salon_owner_member_status', { p_membership: member.membership_id, p_status: 'active' }); toast('Login enabled'); void load(); } catch (e) { toast((e as Error).message, 'error'); }
            } }) : null));
      })));
  };
  await load();
}

function invite(ctx: Ctx, p: any, reload: () => void) {
  const d = openDialog({ title: `Invite ${p.short_name}`, size: 'sm' });
  const fEmail = field({ label: 'Their email address', name: 'email', type: 'email', required: true });
  append(d.body, h('p', { class: 'muted small', text: 'You will get a one-time code to give them in person or by private message. It works once, for this email, for 7 days. We never show it again.' }), fEmail.wrap);
  const go = button('Create invitation', { onClick: async () => {
    setBusy(go, true, 'Creating…');
    try {
      const r = await rpc<any>('salon_owner_invite', { p_salon: ctx.salonId, p_professional: p.id, p_email: fEmail.input.value.trim() });
      const link = `${location.origin}/join`;
      mount(d.body,
        notice('success', `Invitation created for ${r.email}.`),
        h('p', { class: 'field-label mt', text: 'Invitation code' }),
        h('p', { class: 'code-box', text: r.code }),
        h('p', { class: 'muted small', text: `Ask ${p.short_name} to open ${link}, enter this code and create a password with ${r.email}. Copy the code now; it will not be shown again.` }));
      mount(d.footer,
        button('Copy code and link', { variant: 'secondary', onClick: async () => { try { await navigator.clipboard.writeText(`${r.code}\n${link}`); toast('Copied'); } catch { toast('Copy failed, please copy it manually.', 'error'); } } }),
        button('Done', { onClick: () => { d.close(); reload(); } }));
    } catch (e) { setBusy(go, false); fEmail.setError((e as Error).message); }
  } });
  append(d.footer, button('Cancel', { variant: 'ghost', onClick: () => d.close() }), go);
}

function editProfile(ctx: Ctx, p: any, reload: () => void) {
  const d = openDialog({ title: `Edit ${p.display_name}` });
  const fName = field({ label: 'Display name', name: 'name', value: p.display_name, maxlength: 80 });
  const fShort = field({ label: 'Short name', name: 'short', value: p.short_name, maxlength: 40, hint: 'Used in messages, for example "Sofia has confirmed…"' });
  const fSpec = field({ label: 'Specialty', name: 'spec', value: p.specialty ?? '', maxlength: 120 });
  const fBio = textarea({ label: 'Short bio', name: 'bio', value: p.bio ?? '', rows: 3, maxlength: 1200 });
  const fIg = field({ label: 'Instagram link', name: 'ig', value: p.instagram_url ?? '', placeholder: 'https://www.instagram.com/…' });
  const pub = checkbox({ name: 'pub', checked: p.is_public, label: 'Show on the website' });
  const ob = checkbox({ name: 'ob', checked: p.online_booking, label: 'Allow online booking' });
  const err = h('div');
  append(d.body, h('div', { class: 'form-row' }, fName.wrap, fShort.wrap), fSpec.wrap, fBio.wrap, fIg.wrap, pub.wrap, ob.wrap, err);
  const save = button('Save profile', { onClick: async () => {
    setBusy(save, true, 'Saving…');
    try {
      await rpc('salon_owner_professional_save', { p_salon: ctx.salonId, p_payload: { id: p.id, display_name: fName.input.value, short_name: fShort.input.value, specialty: fSpec.input.value, bio: fBio.input.value, instagram_url: fIg.input.value, is_public: pub.input.checked, online_booking: ob.input.checked } });
      toast('Profile saved'); d.close(); await loadMe(true); reload();
    } catch (e) { setBusy(save, false); mount(err, notice('error', (e as Error).message)); }
  } });
  append(d.footer, button('Cancel', { variant: 'ghost', onClick: () => d.close() }), save);
}

// ===================================================================== settings (owner)
export async function settingsPage(ctx: Ctx) {
  mount(ctx.content, spinner());
  const r = await rpc<any>('salon_owner_settings', { p_salon: ctx.salonId });
  const s = r.settings;
  const f = (label: string, key: string, o: Partial<Parameters<typeof field>[0]> = {}) => { const x = field({ label, name: key, value: s[key] ?? '', ...o }); return [key, x] as const; };
  const fields = [f('Salon name', 'name'), f('Tagline', 'tagline', { maxlength: 200 }), f('Town or city', 'city'), f('Full address', 'address', { hint: 'Leave blank until confirmed. Shown on the website.' }),
    f('Phone', 'phone', { type: 'tel' }), f('WhatsApp number', 'whatsapp', { type: 'tel' }), f('Email', 'email', { type: 'email' }), f('Salon Instagram link', 'instagram_url')];
  const policy = textarea({ label: 'Booking policy (deposits, cancellations, lateness)', name: 'policy', value: s.booking_policy ?? '', rows: 4, maxlength: 2000, hint: 'Leave blank if you have no policy yet. When filled in, clients must accept it before booking.' });
  const mode = select({ label: 'Online booking', name: 'mode', value: s.booking_mode, options: [{ value: 'preview', label: 'Preview: bookings work, website shows a test notice' }, { value: 'live', label: 'Live: open to clients' }, { value: 'closed', label: 'Closed: no online bookings' }] });
  const notice1 = field({ label: 'Minimum notice (hours)', name: 'notice', type: 'number', min: '0', max: '336', value: String(s.min_notice_min / 60) });
  const ahead = field({ label: 'Book up to (days ahead)', name: 'ahead', type: 'number', min: '1', max: '365', value: String(s.max_days_ahead) });
  const grid = select({ label: 'Start times every', name: 'grid', value: String(s.slot_interval_min), options: [10, 15, 20, 30, 60].map((n) => ({ value: String(n), label: `${n} minutes` })) });
  const err = h('div');
  const save = button('Save settings', { onClick: async () => {
    mount(err);
    if (mode.input.value === 'live' && s.booking_mode !== 'live') {
      const c = await confirmDialog({ title: 'Open booking to the public?', message: 'The test notice will disappear and new bookings are treated as real. Make sure services, prices, hours and logins are confirmed first.', confirmLabel: 'Go live' });
      if (!c.ok) return;
    }
    const payload: Record<string, unknown> = Object.fromEntries(fields.map(([k, x]) => [k, x.input.value]));
    Object.assign(payload, { booking_policy: policy.input.value, booking_mode: mode.input.value, min_notice_min: Math.round(Number(notice1.input.value) * 60), max_days_ahead: Number(ahead.input.value), slot_interval_min: Number(grid.input.value) });
    setBusy(save, true, 'Saving…');
    try { await rpc('salon_owner_settings_save', { p_salon: ctx.salonId, p_payload: payload }); toast('Settings saved'); await loadMe(true); navigate('/studio/settings', { replace: true }); }
    catch (e) { setBusy(save, false); mount(err, notice('error', (e as Error).message)); }
  } });
  mount(ctx.content,
    h('section', { class: 'panel' }, h('h3', { class: 'panel-title', text: 'Salon details' }), h('div', { class: 'form-grid' }, fields.map(([, x]) => x.wrap))),
    h('section', { class: 'panel' }, h('h3', { class: 'panel-title', text: 'Online booking' }), mode.wrap, h('div', { class: 'form-grid' }, notice1.wrap, ahead.wrap, grid.wrap), policy.wrap),
    h('section', { class: 'panel' }, h('h3', { class: 'panel-title', text: 'Integrations' }),
      h('dl', { class: 'kv' }, h('dt', { text: 'Text messages' }), h('dd', { text: s.sms_connected ? 'Connected' : 'Not connected' }),
        h('dt', { text: 'Phone answering' }), h('dd', { text: 'Not connected' }), h('dt', { text: 'Payments and deposits' }), h('dd', { text: 'Not connected. No money is taken online.' }))),
    err, h('div', { class: 'row-end' }, save));
}

// ===================================================================== audit (owner)
const ACTION_LABEL: Record<string, string> = {
  'booking.requested': 'Website booking request', 'booking.created': 'Booking created', 'booking.confirmed': 'Booking confirmed', 'booking.declined': 'Booking declined',
  'booking.cancelled': 'Booking cancelled', 'booking.completed': 'Marked completed', 'booking.no_show': 'Marked no-show', 'booking.rescheduled': 'Booking moved',
  'booking.reassigned': 'Booking moved to another professional', 'booking.reassigned_away': 'Booking moved away', 'booking.note': 'Booking note', 'booking.expired': 'Request expired',
  'client.updated': 'Client updated', 'enquiry.created': 'Enquiry received', 'enquiry.updated': 'Enquiry updated', 'service.created': 'Service added', 'service.updated': 'Service changed',
  'hours.updated': 'Working hours changed', 'salon_hours.updated': 'Salon hours changed', 'time_off.added': 'Time off added', 'time_off.removed': 'Time off removed',
  'invitation.created': 'Invitation created', 'invitation.accepted': 'Invitation accepted', 'invitation.revoked': 'Invitation revoked', 'membership.disabled': 'Login disabled',
  'membership.active': 'Login enabled', 'professional.created': 'Profile added', 'professional.updated': 'Profile changed', 'settings.updated': 'Settings changed',
  'gallery.added': 'Portfolio item added', 'gallery.updated': 'Portfolio item changed', 'gallery.removed': 'Portfolio item removed',
};
export async function auditPage(ctx: Ctx) {
  mount(ctx.content, spinner());
  const r = await rpc<any>('salon_owner_audit', { p_salon: ctx.salonId, p_professional: ctx.scope, p_limit: 300 });
  mount(ctx.content, r.items.length ? h('div', { class: 'table-wrap' }, h('table', { class: 'table' },
    h('thead', null, h('tr', null, ['When', 'What', 'Professional', 'By'].map((t) => h('th', { attrs: { scope: 'col' }, text: t })))),
    h('tbody', null, r.items.map((a: any) => h('tr', null,
      h('td', { text: dateTimeShort(a.at) }),
      h('td', null, h('span', { class: 'cell-strong', text: ACTION_LABEL[a.action] ?? a.action }), a.detail?.ref ? h('span', { class: 'cell-sub', text: `Ref ${a.detail.ref}${a.detail.reason ? ', ' + a.detail.reason : ''}` }) : null),
      h('td', { text: a.professional ?? '—' }),
      h('td', { text: a.actor_email ?? (a.actor === 'customer' ? 'Client (website)' : a.actor === 'system' ? 'System' : a.actor) })))))) : emptyState('No activity yet'));
}

// ===================================================================== account
export async function accountPage(ctx: Ctx) {
  const f1 = field({ label: 'New password', name: 'p1', type: 'password', autocomplete: 'new-password', hint: 'At least 10 characters.' });
  const f2 = field({ label: 'Repeat new password', name: 'p2', type: 'password', autocomplete: 'new-password' });
  const save = button('Change password', { onClick: async () => {
    f1.setError(null); f2.setError(null);
    if (f1.input.value.length < 10) { f1.setError('Use at least 10 characters.'); return; }
    if (f1.input.value !== f2.input.value) { f2.setError('The passwords do not match.'); return; }
    setBusy(save, true, 'Saving…');
    try { await updatePassword(f1.input.value); toast('Password changed'); f1.input.value = ''; f2.input.value = ''; }
    catch (e) { f1.setError((e as Error).message); }
    setBusy(save, false);
  } });
  mount(ctx.content,
    h('section', { class: 'panel' }, h('h3', { class: 'panel-title', text: 'Your account' }),
      h('dl', { class: 'kv' }, h('dt', { text: 'Email' }), h('dd', { text: ctx.me.user.email }),
        h('dt', { text: 'Access' }), h('dd', { text: ctx.isOwner ? 'Owner: all professionals' : `${ctx.ownPro?.display_name ?? 'Professional'}: own bookings and clients only` }))),
    h('section', { class: 'panel' }, h('h3', { class: 'panel-title', text: 'Change password' }), f1.wrap, f2.wrap, h('div', { class: 'row-end' }, save)),
    h('section', { class: 'panel' }, h('h3', { class: 'panel-title', text: 'Sign out' }),
      h('p', { class: 'muted small', text: 'Signing out clears your studio data from this browser.' }),
      h('div', { class: 'row-end' }, button('Sign out', { variant: 'secondary', icon: 'logout', onClick: async () => { await signOut(); navigate('/signin', { replace: true }); } }))));
}

export { time12 };
