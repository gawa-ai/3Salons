import { h, icon, mount } from '../lib/dom';
import { linkButton } from '../lib/ui';
import type { PublicProfile } from './data';

const NAV = [
  { href: '/#services', label: 'Services' },
  { href: '/#professionals', label: 'Our professionals' },
  { href: '/#gallery', label: 'Gallery' },
  { href: '/#about', label: 'About' },
  { href: '/#contact', label: 'Contact' },
];

export function publicShell(app: HTMLElement, profile: PublicProfile | null, content: Node[]) {
  document.body.className = 'site';
  const menuId = 'site-menu';
  const toggle = h('button', { class: 'nav-toggle', attrs: { type: 'button', 'aria-expanded': 'false', 'aria-controls': menuId, 'aria-label': 'Open menu' } }, icon('menu', 22));
  const nav = h('nav', { class: 'site-nav', attrs: { id: menuId, 'aria-label': 'Main' } },
    h('ul', null, NAV.map((n) => h('li', null, h('a', { attrs: { href: n.href }, text: n.label })))),
    h('div', { class: 'site-nav-cta' },
      linkButton('Book appointment', '/book', { size: 'sm' })));
  toggle.addEventListener('click', () => {
    const open = toggle.getAttribute('aria-expanded') !== 'true';
    toggle.setAttribute('aria-expanded', String(open));
    toggle.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
    nav.classList.toggle('open', open);
    mount(toggle, icon(open ? 'x' : 'menu', 22));
  });
  nav.addEventListener('click', (e) => {
    if ((e.target as Element).closest('a')) { nav.classList.remove('open'); toggle.setAttribute('aria-expanded', 'false'); mount(toggle, icon('menu', 22)); }
  });

  const preview = profile?.salon.booking_mode === 'preview'
    ? h('div', { class: 'preview-bar', attrs: { role: 'note' } },
        h('p', null, h('strong', { text: 'Preview site. ' }), 'The salon is getting ready to launch, so bookings made here are test bookings for now.'))
    : null;

  const header = h('header', { class: 'site-header' },
    h('div', { class: 'site-header-inner' },
      h('a', { class: 'site-logo', attrs: { href: '/', 'aria-label': 'Shahina Ahmed, home' } },
        h('img', { class: 'logo-mark', attrs: { src: '/brand/sa-monogram.png', alt: '', width: 34, height: 44 } }),
        h('img', { class: 'logo-word', attrs: { src: '/brand/shahina-ahmed-wordmark.svg', alt: '', width: 252, height: 23 } })),
      nav,
      h('a', { class: 'staff-link', attrs: { href: '/signin' } }, icon('user', 16), h('span', { text: 'Staff sign in' })),
      toggle));

  const year = new Date().getFullYear();
  const footer = h('footer', { class: 'site-footer' },
    h('div', { class: 'site-footer-inner' },
      h('div', { class: 'footer-brand' },
        h('img', { class: 'logo-mark', attrs: { src: '/brand/sa-monogram.png', alt: '', width: 40, height: 52 } }),
        h('img', { attrs: { src: '/brand/shahina-ahmed-lockup-light.svg', alt: 'Shahina Ahmed', width: 260, height: 38 } }),
        profile?.salon.city ? h('p', { class: 'footer-city', text: profile.salon.city }) : null),
      h('div', { class: 'footer-cols' },
        h('div', null, h('p', { class: 'footer-head', text: 'Visit' }),
          h('ul', null,
            h('li', null, h('a', { attrs: { href: '/book' }, text: 'Book appointment' })),
            h('li', null, h('a', { attrs: { href: '/bridal' }, text: 'Bridal enquiry' })),
            h('li', null, h('a', { attrs: { href: '/#contact' }, text: 'Contact' })))),
        h('div', null, h('p', { class: 'footer-head', text: 'Artists' }),
          h('ul', null, (profile?.professionals ?? []).map((p) => h('li', null, h('a', { attrs: { href: `/artists/${p.slug}` }, text: p.display_name }))))),
        h('div', null, h('p', { class: 'footer-head', text: 'Salon' }),
          h('ul', null,
            h('li', null, h('a', { attrs: { href: '/privacy' }, text: 'Privacy' })),
            h('li', null, h('a', { attrs: { href: '/signin' }, text: 'Staff sign in' })))))),
    h('p', { class: 'footer-legal', text: `© ${year} Shahina Ahmed` }));

  mount(app,
    h('a', { class: 'skip-link', attrs: { href: '#main' }, text: 'Skip to content' }),
    preview, header,
    h('main', { attrs: { id: 'main', tabindex: '-1' } }, content),
    footer);
}

/** The arch frame: the site's signature shape. */
export function arch(content: Node, opts: { size?: 'sm' | 'md' | 'lg' | 'xl'; tone?: 'blush' | 'stone' | 'night' | 'pro'; color?: string } = {}) {
  return h('div', { class: ['arch', `arch-${opts.size ?? 'md'}`, `arch-${opts.tone ?? 'blush'}`, opts.color ? `pro-${opts.color}` : null] },
    h('div', { class: 'arch-inner' }, content));
}

export function proMark(p: { logo_path: string | null; display_name: string }, size: 'sm' | 'md' | 'lg' = 'md') {
  if (p.logo_path) {
    return h('img', { class: ['pro-logo', `pro-logo-${size}`], attrs: { src: p.logo_path, alt: `${p.display_name} logo`, loading: 'lazy', decoding: 'async', width: 240, height: 240 } });
  }
  return h('span', { class: ['pro-logo', 'pro-logo-text', `pro-logo-${size}`], text: p.display_name });
}
