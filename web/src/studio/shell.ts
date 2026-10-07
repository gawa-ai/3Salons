import { h, icon, mount } from '../lib/dom';
import { spinner, errorBox, button } from '../lib/ui';
import { currentSession, signOut } from '../lib/supabase';
import { navigate } from '../lib/router';
import { loadMe, primaryMembership, onPrivateClear, type Membership, type Me, type ProRef } from '../auth/session';

export interface Ctx {
  m: Membership;
  me: Me;
  isOwner: boolean;
  salonId: string;
  pros: ProRef[];               // profiles visible to this login (owner: all, staff: own)
  scope: string | null;          // owner: null = all professionals; staff: always their own id
  ownPro: ProRef | null;
  content: HTMLElement;
  setActions: (nodes: Node[]) => void;
  proById: (id: string | null | undefined) => ProRef | undefined;
}

interface NavItem { path: string; label: string; icon: string; owner?: boolean }
const NAV: NavItem[] = [
  { path: '/studio', label: 'Overview', icon: 'home' },
  { path: '/studio/calendar', label: 'Calendar', icon: 'calendar' },
  { path: '/studio/bookings', label: 'Bookings', icon: 'list' },
  { path: '/studio/clients', label: 'Clients', icon: 'users' },
  { path: '/studio/enquiries', label: 'Enquiries', icon: 'heart' },
  { path: '/studio/services', label: 'Services', icon: 'scissors' },
  { path: '/studio/availability', label: 'Availability', icon: 'clock' },
  { path: '/studio/gallery', label: 'Gallery', icon: 'image' },
  { path: '/studio/messages', label: 'Calls & messages', icon: 'chat' },
  { path: '/studio/reports', label: 'Reports', icon: 'chart' },
  { path: '/studio/team', label: 'Professionals', icon: 'user', owner: true },
  { path: '/studio/settings', label: 'Settings', icon: 'settings', owner: true },
  { path: '/studio/audit', label: 'Activity log', icon: 'shield', owner: true },
];
const STAFF_LABELS: Record<string, string> = {
  '/studio/calendar': 'My calendar', '/studio/bookings': 'My bookings', '/studio/clients': 'My clients',
  '/studio/enquiries': 'My enquiries', '/studio/services': 'My services', '/studio/gallery': 'My portfolio',
};

let scopeOwner: string | null = null;  // remembered owner filter for this tab
onPrivateClear(() => { scopeOwner = null; });

export type StudioPage = (ctx: Ctx) => Promise<void> | void;

export async function studio(app: HTMLElement, path: string, page: StudioPage, opts: { ownerOnly?: boolean; title: string; scoped?: boolean }) {
  document.body.className = 'studio-body';
  if (!currentSession()) { navigate(`/signin`, { replace: true }); return; }
  mount(app, h('div', { class: 'studio-loading' }, spinner('Opening the studio')));
  let me: Me | null;
  try { me = await loadMe(); } catch (e) {
    mount(app, h('div', { class: 'studio-loading' }, errorBox((e as Error).message, () => studio(app, path, page, opts))));
    return;
  }
  if (!currentSession()) { navigate('/signin', { replace: true }); return; }
  const m = primaryMembership(me);
  if (!me || !m) {
    mount(app, h('div', { class: 'studio-loading' }, h('div', { class: 'denied' },
      h('h1', { class: 'page-title', text: 'No studio access' }),
      h('p', { class: 'muted', text: 'This account is not linked to the salon, or its access has been switched off by the owner.' }),
      h('div', { class: 'denied-actions' }, button('Sign out', { variant: 'secondary', onClick: async () => { await signOut(); navigate('/signin'); } }),
        h('a', { attrs: { href: '/join' }, text: 'Use an invitation code' })))));
    return;
  }
  const isOwner = m.role === 'owner';
  if (opts.ownerOnly && !isOwner) { navigate('/studio', { replace: true }); return; }
  const ownPro = m.professionals.find((p) => p.id === m.professional_id) ?? null;
  const pros = m.professionals.filter((p) => p.active);
  const scope = isOwner ? (scopeOwner && pros.some((p) => p.id === scopeOwner) ? scopeOwner : null) : m.professional_id;

  const content = h('main', { class: 'studio-content', attrs: { id: 'main', tabindex: '-1' } });
  const actions = h('div', { class: 'top-actions' });
  const title = !isOwner && STAFF_LABELS[path] ? STAFF_LABELS[path] : opts.title;
  document.title = `${title} · Studio · Shahina Ahmed`;

  const navList = h('ul', { class: 'side-nav' }, NAV.filter((n) => !n.owner || isOwner).map((n) =>
    h('li', null, h('a', { class: ['side-link', path === n.path && 'active'], attrs: { href: n.path, 'aria-current': path === n.path ? 'page' : undefined } },
      icon(n.icon, 18), h('span', { text: !isOwner && STAFF_LABELS[n.path] ? STAFF_LABELS[n.path] : n.label })))));

  const who = isOwner ? 'Owner' : (ownPro?.specialty ?? 'Professional');
  const identity = h('div', { class: 'side-identity' },
    ownPro?.logo_path ? h('img', { class: 'side-avatar', attrs: { src: ownPro.logo_path, alt: '', width: 40, height: 40 } }) : h('span', { class: 'side-avatar side-avatar-text', text: (me.user.email[0] ?? '?').toUpperCase() }),
    h('div', { class: 'side-id-text' },
      h('p', { class: 'side-name', text: isOwner ? 'Shahina Ahmed' : (ownPro?.display_name ?? m.display_name ?? me.user.email) }),
      h('p', { class: 'side-role', text: who })));

  const sidebar = h('aside', { class: 'sidebar', attrs: { id: 'studio-nav', 'aria-label': 'Studio' } },
    h('a', { class: 'side-brand', attrs: { href: '/studio', 'aria-label': 'Studio overview' } },
      h('img', { attrs: { src: '/brand/shahina-ahmed-wordmark.svg', alt: 'Shahina Ahmed Luxury Salon', width: 190, height: 44 } })),
    h('nav', { attrs: { 'aria-label': 'Studio sections' } }, navList),
    h('div', { class: 'side-foot' }, identity,
      h('div', { class: 'side-foot-links' },
        h('a', { attrs: { href: '/studio/account' }, text: 'Account' }),
        h('a', { attrs: { href: '/', target: '_blank', rel: 'noopener' }, text: 'View website' }),
        button('Sign out', { variant: 'ghost', size: 'sm', icon: 'logout', onClick: async () => { await signOut(); navigate('/signin', { replace: true }); } }))));

  const menuBtn = h('button', { class: 'menu-btn', attrs: { type: 'button', 'aria-controls': 'studio-nav', 'aria-expanded': 'false', 'aria-label': 'Open studio menu' } }, icon('menu', 22));
  menuBtn.addEventListener('click', () => {
    const open = !sidebar.classList.contains('open');
    sidebar.classList.toggle('open', open);
    menuBtn.setAttribute('aria-expanded', String(open));
  });
  sidebar.addEventListener('click', (e) => { if ((e.target as Element).closest('a')) sidebar.classList.remove('open'); });

  // Owner-only professional selector. It changes WHAT the owner asks for; the database
  // decides what anyone may see, so this is never a security control.
  let scopeBar: HTMLElement | null = null;
  if (isOwner && opts.scoped !== false) {
    scopeBar = h('div', { class: 'scope', attrs: { role: 'radiogroup', 'aria-label': 'Show bookings for' } },
      [{ id: null as string | null, label: 'All professionals', color: '' }, ...pros.map((p) => ({ id: p.id as string | null, label: p.display_name, color: p.color }))].map((o) =>
        h('button', { class: ['scope-btn', scope === o.id && 'active'], attrs: { type: 'button', role: 'radio', 'aria-checked': String(scope === o.id) },
          on: { click: () => { scopeOwner = o.id; void studio(app, path, page, opts); } } },
          o.color ? h('span', { class: ['pro-dot', `pro-${o.color}`] }) : null, h('span', { text: o.label }))));
  } else if (!isOwner && ownPro && opts.scoped !== false) {
    scopeBar = h('div', { class: 'scope scope-fixed' }, h('span', { class: ['pro-dot', `pro-${ownPro.color}`] }), h('span', { text: `${ownPro.display_name} only` }));
  }

  const preview = m.salon.booking_mode !== 'live'
    ? h('div', { class: 'studio-banner', attrs: { role: 'note' } }, icon('info', 16),
        h('span', { text: m.salon.booking_mode === 'preview' ? 'Preview mode: the public site shows a test-booking notice. Text messages are not connected yet, so nothing is sent to clients.' : 'Online booking is closed. Clients cannot book on the website.' }))
    : null;

  mount(app,
    h('a', { class: 'skip-link', attrs: { href: '#main' }, text: 'Skip to content' }),
    h('div', { class: 'studio' }, sidebar,
      h('div', { class: 'studio-main' },
        h('header', { class: 'topbar' }, menuBtn,
          h('div', { class: 'topbar-titles' }, h('h1', { class: 'top-title', text: title }), h('p', { class: 'top-sub', text: m.salon.name })),
          actions),
        preview, scopeBar, content)));

  const ctx: Ctx = {
    m, me, isOwner, salonId: m.salon.id, pros, scope, ownPro, content,
    setActions: (nodes) => mount(actions, nodes),
    proById: (id) => m.professionals.find((p) => p.id === id),
  };
  try {
    await page(ctx);
  } catch (e) {
    const err = e as Error & { code?: string };
    if (err.code === 'not_signed_in') { await signOut(); navigate('/signin', { replace: true }); return; }
    if (err.code === 'forbidden') { scopeOwner = null; }
    mount(content, errorBox(err.message, () => studio(app, path, page, opts)));
  }
}
