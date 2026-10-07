import { h, icon, mount } from '../lib/dom';
import { button, linkButton, emptyState, notice, spinner } from '../lib/ui';
import { rpc } from '../lib/supabase';
import { pounds, formatDateLong, time12 } from '../lib/format';
import type { Ctx } from './shell';
import { bookingRow, quickActions, openBooking, openNewBooking, type Booking } from './booking';

export async function overviewPage(ctx: Ctx) {
  const render = async () => {
    mount(ctx.content, spinner());
    const r = await rpc<any>('salon_dash_overview', { p_salon: ctx.salonId, p_professional: ctx.scope });
    const c = r.counts;
    const today: Booking[] = r.today_items;
    const pending: Booking[] = r.needs_confirming;
    const reload = () => void render();

    const tile = (label: string, value: string, sub: string, href?: string, tone = '') =>
      h(href ? 'a' : 'div', { class: ['tile', tone], attrs: href ? { href } : {} },
        h('p', { class: 'tile-label', text: label }), h('p', { class: 'tile-value', text: value }), h('p', { class: 'tile-sub', text: sub }));

    mount(ctx.content,
      h('div', { class: 'greeting' },
        h('p', { class: 'greet-date', text: formatDateLong(r.today) }),
        h('h2', { class: 'greet-title', text: ctx.isOwner ? (ctx.scope ? `${ctx.proById(ctx.scope)?.display_name}’s day` : 'The salon today') : 'Your day' })),
      h('div', { class: 'tiles' },
        tile('Today', String(today.length), today.length === 1 ? 'appointment' : 'appointments', '/studio/calendar'),
        tile('Awaiting confirmation', String(c.pending), c.pending ? 'requests need your answer' : 'nothing waiting', '/studio/bookings?view=pending', c.pending ? 'tile-attention' : ''),
        tile('Next 7 days', String(c.upcoming_7d), 'pending and confirmed', '/studio/bookings'),
        tile('Completed, last 30 days', pounds(c.completed_value_30d_pence), `${c.completed_30d} appointments at listed prices. Not payments received.`, '/studio/reports')),
      c.awaiting_outcome ? notice('info', h('p', null, `${c.awaiting_outcome} past appointment${c.awaiting_outcome === 1 ? '' : 's'} still need an outcome (completed or no-show). `, h('a', { attrs: { href: '/studio/bookings?view=outcome' }, text: 'Review them' }))) : null,
      h('div', { class: 'ov-grid' },
        h('section', { class: 'panel', attrs: { 'aria-labelledby': 'nc-title' } },
          h('div', { class: 'panel-head' }, h('h3', { class: 'panel-title', attrs: { id: 'nc-title' }, text: 'Needs confirming' }),
            pending.length ? h('span', { class: 'count-pill', text: String(pending.length) }) : null),
          pending.length
            ? h('ul', { class: 'blist' }, pending.map((b) => bookingRow(b, () => openBooking(ctx, b.id, reload), quickActions(b, reload) ?? undefined)))
            : emptyState('All caught up', 'New website requests will appear here for you to confirm or decline.')),
        h('section', { class: 'panel', attrs: { 'aria-labelledby': 'today-title' } },
          h('div', { class: 'panel-head' }, h('h3', { class: 'panel-title', attrs: { id: 'today-title' }, text: 'Today' }),
            button('New booking', { size: 'sm', variant: 'secondary', icon: 'plus', onClick: () => openNewBooking(ctx, {}, reload) })),
          today.length
            ? h('ol', { class: 'agenda' }, today.map((b) => h('li', { class: ['agenda-item', `pro-${b.professional_color}`, `st-${b.status}`] },
                h('button', { class: 'agenda-btn', attrs: { type: 'button' }, on: { click: () => openBooking(ctx, b.id, reload) } },
                  h('span', { class: 'agenda-time', text: `${time12(b.local_time)}–${time12(b.local_end)}` }),
                  h('span', { class: 'agenda-body' }, h('span', { class: 'agenda-client', text: b.client_name }), h('span', { class: 'agenda-svc', text: `${b.service}${ctx.isOwner ? ', ' + b.professional_short : ''}` })),
                  b.status === 'pending' ? h('span', { class: 'badge badge-pending', text: 'Awaiting' }) : null))))
            : emptyState('No appointments today', 'Enjoy the quiet, or add a booking for a phone or walk-in client.'))),
      r.by_professional ? h('section', { class: 'panel', attrs: { 'aria-labelledby': 'bp-title' } },
        h('div', { class: 'panel-head' }, h('h3', { class: 'panel-title', attrs: { id: 'bp-title' }, text: 'By professional' })),
        h('div', { class: 'table-wrap' }, h('table', { class: 'table' },
          h('thead', null, h('tr', null, h('th', { attrs: { scope: 'col' }, text: 'Professional' }), h('th', { attrs: { scope: 'col' }, class: 'num', text: 'Today' }), h('th', { attrs: { scope: 'col' }, class: 'num', text: 'Awaiting' }), h('th', { attrs: { scope: 'col' }, class: 'num', text: 'Next 7 days' }))),
          h('tbody', null, r.by_professional.map((p: any) => h('tr', null,
            h('th', { attrs: { scope: 'row' } }, h('span', { class: 'cell-pro' }, h('span', { class: ['pro-dot', `pro-${p.color}`] }), p.name)),
            h('td', { class: 'num', text: String(p.today) }), h('td', { class: ['num', p.pending && 'attn'], text: String(p.pending) }), h('td', { class: 'num', text: String(p.upcoming_7d) }))))))) : null,
      r.new_enquiries ? h('p', { class: 'ov-foot' }, icon('heart', 16), h('span', { text: `${r.new_enquiries} new enquir${r.new_enquiries === 1 ? 'y' : 'ies'}. ` }), linkButton('Open enquiries', '/studio/enquiries', { variant: 'link' })) : null);
  };
  ctx.setActions([button('New booking', { icon: 'plus', size: 'sm', onClick: () => openNewBooking(ctx, {}, () => void render()) })]);
  await render();
}
