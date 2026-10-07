import { h, mount } from '../lib/dom';
import { button, spinner, emptyState } from '../lib/ui';
import { rpc } from '../lib/supabase';
import { addDays, todayLocal, formatDateLong, formatDateShort, startOfWeek, zonedToUtc, minutesOf, time12, WEEKDAYS_SHORT, weekdayOf } from '../lib/format';
import type { Ctx } from './shell';
import { openBooking, openNewBooking, type Booking } from './booking';
import { onPrivateClear } from '../auth/session';

let state = { date: todayLocal(), view: 'day' as 'day' | 'week' };
onPrivateClear(() => { state = { date: todayLocal(), view: 'day' }; });
const PX = 1.15; // pixels per minute

export async function calendarPage(ctx: Ctx) {
  const toolbar = h('div', { class: 'cal-toolbar' });
  const body = h('div', { class: 'cal-body' });
  mount(ctx.content, toolbar, body);
  ctx.setActions([button('New booking', { icon: 'plus', size: 'sm', onClick: () => openNewBooking(ctx, { date: state.date }, () => void load()) })]);

  const narrow = () => window.matchMedia('(max-width: 760px)').matches;

  const load = async () => {
    const days = state.view === 'day' ? [state.date] : Array.from({ length: 7 }, (_, i) => addDays(startOfWeek(state.date), i));
    renderToolbar(days);
    mount(body, spinner());
    const from = zonedToUtc(days[0], '00:00').toISOString();
    const to = zonedToUtc(addDays(days[days.length - 1], 1), '00:00').toISOString();
    const [bk, sch] = await Promise.all([
      rpc<any>('salon_dash_bookings', { p_salon: ctx.salonId, p_professional: ctx.scope, p_from: from, p_to: to, p_statuses: ['pending', 'confirmed', 'completed', 'no_show'] }),
      rpc<any>('salon_dash_schedule', { p_salon: ctx.salonId, p_professional: ctx.scope }),
    ]);
    const items: Booking[] = bk.items;
    if (narrow()) { renderAgenda(days, items); return; }
    renderGrid(days, items, sch);
  };

  function renderToolbar(days: string[]) {
    const label = state.view === 'day' ? formatDateLong(state.date) : `${formatDateShort(days[0])} – ${formatDateShort(days[6])}`;
    mount(toolbar,
      h('div', { class: 'cal-nav' },
        button('', { variant: 'ghost', size: 'sm', icon: 'chevronLeft', ariaLabel: state.view === 'day' ? 'Previous day' : 'Previous week', onClick: () => { state.date = addDays(state.date, state.view === 'day' ? -1 : -7); void load(); } }),
        button('Today', { variant: 'secondary', size: 'sm', onClick: () => { state.date = todayLocal(); void load(); } }),
        button('', { variant: 'ghost', size: 'sm', icon: 'chevronRight', ariaLabel: state.view === 'day' ? 'Next day' : 'Next week', onClick: () => { state.date = addDays(state.date, state.view === 'day' ? 1 : 7); void load(); } }),
        h('h2', { class: 'cal-label', attrs: { 'aria-live': 'polite' }, text: label })),
      h('div', { class: 'seg', attrs: { role: 'group', 'aria-label': 'Calendar view' } },
        ...(['day', 'week'] as const).map((v) => h('button', { class: ['seg-btn', state.view === v && 'active'], attrs: { type: 'button', 'aria-pressed': String(state.view === v) }, text: v === 'day' ? 'Day' : 'Week', on: { click: () => { state.view = v; void load(); } } }))),
      h('input', { class: 'input input-sm cal-date', attrs: { type: 'date', 'aria-label': 'Go to date', value: state.date }, on: { change: (e: Event) => { const v = (e.target as HTMLInputElement).value; if (v) { state.date = v; void load(); } } } }));
  }

  function bounds(items: Booking[], sch: any): [number, number] {
    let lo = 9 * 60; let hi = 19 * 60;
    for (const p of sch.professionals) for (const w of p.working_hours) { lo = Math.min(lo, minutesOf(w.opens)); hi = Math.max(hi, minutesOf(w.closes)); }
    for (const b of items) { lo = Math.min(lo, minutesOf(b.local_time)); hi = Math.max(hi, minutesOf(b.local_end) + b.buffer_min); }
    return [Math.floor(lo / 60) * 60, Math.min(24 * 60, Math.ceil(hi / 60) * 60)];
  }

  function renderGrid(days: string[], items: Booking[], sch: any) {
    const [lo, hi] = bounds(items, sch);
    const height = (hi - lo) * PX;
    // columns: day view = one per professional in scope; week view = one per day
    const cols = state.view === 'day'
      ? (ctx.scope ? ctx.pros.filter((p) => p.id === ctx.scope) : ctx.pros).map((p) => ({ key: p.id, title: p.display_name, color: p.color, date: state.date, pro: p.id as string | null }))
      : days.map((d) => ({ key: d, title: `${WEEKDAYS_SHORT[weekdayOf(d)]} ${Number(d.slice(8))}`, color: '', date: d, pro: ctx.scope }));
    const hours: number[] = [];
    for (let m = lo; m < hi; m += 60) hours.push(m);
    const today = todayLocal();
    const working = (proId: string | null, date: string) => {
      if (!proId) return [];
      const p = sch.professionals.find((x: any) => x.id === proId);
      return (p?.working_hours ?? []).filter((w: any) => w.weekday === weekdayOf(date));
    };

    const grid = h('div', { class: ['cgrid', `cgrid-${state.view}`], style: { '--cols': String(cols.length) } },
      h('div', { class: 'cgrid-corner' }),
      cols.map((c) => h('div', { class: ['cgrid-head', c.color && `pro-${c.color}`, c.date === today && state.view === 'week' && 'is-today'] },
        c.color ? h('span', { class: ['pro-dot', `pro-${c.color}`] }) : null,
        h('span', { text: c.title }),
        h('span', { class: 'cgrid-count', text: String(items.filter((b) => b.local_date === c.date && (!c.pro || b.professional_id === c.pro)).length) }))),
      h('div', { class: 'cgrid-axis', style: { height: `${height}px` } }, hours.map((m) => h('span', { class: 'cgrid-hour', style: { top: `${(m - lo) * PX}px` }, text: time12(`${String(m / 60).padStart(2, '0')}:00`) }))),
      cols.map((c) => {
        const col = h('div', { class: 'cgrid-col', style: { height: `${height}px` }, attrs: { 'aria-label': `${c.title}, ${formatDateLong(c.date)}` } });
        // off-hours shading for a single professional's column
        const wh = working(c.pro, c.date);
        if (c.pro) {
          const open = wh.map((w: any) => [minutesOf(w.opens), minutesOf(w.closes)] as [number, number]).sort((a: number[], b: number[]) => a[0] - b[0]);
          let cur = lo;
          for (const [o, cl] of open) { if (o > cur) col.appendChild(h('div', { class: 'cgrid-off', style: { top: `${(cur - lo) * PX}px`, height: `${(o - cur) * PX}px` } })); cur = Math.max(cur, cl); }
          if (cur < hi) col.appendChild(h('div', { class: 'cgrid-off', style: { top: `${(cur - lo) * PX}px`, height: `${(hi - cur) * PX}px` } }));
        }
        hours.forEach((m) => col.appendChild(h('div', { class: 'cgrid-line', style: { top: `${(m - lo) * PX}px` } })));
        // click empty space to add a booking at that time
        col.addEventListener('click', (e) => {
          if ((e.target as Element).closest('.event')) return;
          const rect = col.getBoundingClientRect();
          const mins = lo + Math.floor(((e as MouseEvent).clientY - rect.top) / PX / 15) * 15;
          const time = `${String(Math.floor(mins / 60)).padStart(2, '0')}:${String(mins % 60).padStart(2, '0')}`;
          openNewBooking(ctx, { date: c.date, time, pro: c.pro }, () => void load());
        });
        const evs = items.filter((b) => b.local_date === c.date && (!c.pro || b.professional_id === c.pro));
        layoutOverlaps(evs).forEach(({ b, lane, lanes }) => {
          const top = (minutesOf(b.local_time) - lo) * PX;
          const hgt = Math.max(28, b.duration_min * PX);
          const ev = h('button', {
            class: ['event', `pro-${b.professional_color}`, `st-${b.status}`],
            attrs: { type: 'button', 'aria-label': `${time12(b.local_time)} ${b.client_name}, ${b.service}, ${b.professional}, ${b.status}` },
            style: { top: `${top}px`, height: `${hgt}px`, left: `calc(${(lane / lanes) * 100}% + 3px)`, width: `calc(${100 / lanes}% - 6px)` },
            on: { click: () => openBooking(ctx, b.id, () => void load()) },
          },
            h('span', { class: 'ev-svc', text: b.service }),
            h('span', { class: 'ev-client', text: b.client_name }),
            hgt > 44 ? h('span', { class: 'ev-time', text: `${time12(b.local_time)} – ${time12(b.local_end)}${state.view === 'week' && !ctx.scope ? ', ' + b.professional_short : ''}` }) : null,
            b.status === 'pending' ? h('span', { class: 'ev-flag', text: 'Awaiting confirmation' }) : null);
          if (b.buffer_min) col.appendChild(h('div', { class: 'ev-buffer', attrs: { 'aria-hidden': 'true' }, style: { top: `${top + b.duration_min * PX}px`, height: `${b.buffer_min * PX}px`, left: `calc(${(lane / lanes) * 100}% + 3px)`, width: `calc(${100 / lanes}% - 6px)` } }));
          col.appendChild(ev);
        });
        // now line
        if (c.date === today) {
          const nowParts = new Intl.DateTimeFormat('en-GB', { timeZone: 'Europe/London', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' }).format(new Date());
          const nm = minutesOf(nowParts);
          if (nm >= lo && nm <= hi) col.appendChild(h('div', { class: 'now-line', style: { top: `${(nm - lo) * PX}px` }, attrs: { 'aria-hidden': 'true' } }));
        }
        return col;
      }));
    mount(body, h('div', { class: 'cgrid-scroll' }, grid),
      h('div', { class: 'cal-legend' },
        h('span', null, h('span', { class: 'legend-swatch legend-pending' }), 'Awaiting confirmation'),
        h('span', null, h('span', { class: 'legend-swatch legend-confirmed' }), 'Confirmed'),
        h('span', null, h('span', { class: 'legend-swatch legend-off' }), 'Outside working hours'),
        h('span', { class: 'muted', text: 'Click an empty slot to add a booking.' })));
  }

  function renderAgenda(days: string[], items: Booking[]) {
    if (!items.length) { mount(body, emptyState(state.view === 'day' ? 'No appointments this day' : 'No appointments this week', 'Use New booking to add one.')); return; }
    mount(body, h('div', { class: 'agenda-days' }, days.map((d) => {
      const list = items.filter((b) => b.local_date === d);
      if (!list.length && state.view === 'week') return null;
      return h('section', { class: 'agenda-day' },
        h('h3', { class: 'agenda-day-title', text: formatDateLong(d) }),
        list.length ? h('ol', { class: 'agenda' }, list.map((b) => h('li', { class: ['agenda-item', `pro-${b.professional_color}`, `st-${b.status}`] },
          h('button', { class: 'agenda-btn', attrs: { type: 'button' }, on: { click: () => openBooking(ctx, b.id, () => void load()) } },
            h('span', { class: 'agenda-time', text: `${time12(b.local_time)}–${time12(b.local_end)}` }),
            h('span', { class: 'agenda-body' }, h('span', { class: 'agenda-client', text: b.client_name }), h('span', { class: 'agenda-svc', text: `${b.service}${ctx.isOwner ? ', ' + b.professional_short : ''}` })),
            b.status === 'pending' ? h('span', { class: 'badge badge-pending', text: 'Awaiting' }) : null)))) : h('p', { class: 'muted small', text: 'No appointments.' }));
    })));
  }

  let lastNarrow = narrow();
  const onResize = () => { if (narrow() !== lastNarrow) { lastNarrow = narrow(); void load(); } };
  window.addEventListener('resize', onResize);
  const obs = new MutationObserver(() => { if (!document.body.contains(body)) { window.removeEventListener('resize', onResize); obs.disconnect(); } });
  obs.observe(document.body, { childList: true, subtree: true });
  await load();
}

/** Side-by-side lanes for overlapping events in one column (week view, all professionals). */
function layoutOverlaps(evs: Booking[]) {
  const sorted = [...evs].sort((a, b) => a.starts_at.localeCompare(b.starts_at));
  const out: { b: Booking; lane: number; lanes: number }[] = [];
  let cluster: { b: Booking; lane: number }[] = [];
  let clusterEnd = 0;
  const flush = () => { const lanes = Math.max(1, ...cluster.map((c) => c.lane + 1)); cluster.forEach((c) => out.push({ ...c, lanes })); cluster = []; };
  for (const b of sorted) {
    const s = new Date(b.starts_at).getTime(); const e = new Date(b.block_end).getTime();
    if (cluster.length && s >= clusterEnd) flush();
    const used = new Set(cluster.filter((c) => new Date(c.b.block_end).getTime() > s).map((c) => c.lane));
    let lane = 0; while (used.has(lane)) lane++;
    cluster.push({ b, lane });
    clusterEnd = Math.max(clusterEnd, e);
  }
  if (cluster.length) flush();
  return out;
}
