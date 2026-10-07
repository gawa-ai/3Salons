import { h, icon, mount } from '../lib/dom';
import { linkButton, spinner, errorBox } from '../lib/ui';
import { loadProfile, loadGallery } from './data';
import { publicShell, arch, proMark } from './layout';
import { serviceRows, galleryGrid } from './home';

export async function artistPage(app: HTMLElement, slug: string) {
  publicShell(app, null, [spinner()]);
  let profile;
  try { profile = await loadProfile(); } catch (e) {
    publicShell(app, null, [h('div', { class: 'container pad-y' }, errorBox((e as Error).message, () => artistPage(app, slug)))]);
    return;
  }
  const p = profile.professionals.find((x) => x.slug === slug);
  if (!p) {
    document.title = 'Artist not found · Shahina Ahmed';
    publicShell(app, profile, [h('section', { class: 'container pad-y narrow' },
      h('h1', { class: 'page-title', text: 'We could not find that artist' }),
      h('p', { class: 'muted', text: 'The link may be out of date. See everyone who works at the salon on the home page.' }),
      h('p', { class: 'mt' }, linkButton('See our professionals', '/#professionals')))]);
    return;
  }
  document.title = `${p.display_name} · Shahina Ahmed`;
  const galleryEl = h('div', null, spinner('Loading portfolio'));
  const canBook = p.online_booking && p.services.some((s) => s.bookable_online);

  publicShell(app, profile, [
    h('section', { class: ['artist-hero', `pro-${p.color}`] },
      h('div', { class: 'container artist-hero-grid' },
        arch(proMark(p, 'lg'), { size: 'lg', tone: 'pro', color: p.color }),
        h('div', { class: 'artist-intro' },
          h('p', { class: 'crumb' }, h('a', { attrs: { href: '/#professionals' }, text: 'Our professionals' })),
          h('h1', { class: 'page-title', text: p.display_name }),
          p.specialty ? h('p', { class: 'artist-specialty', text: p.specialty }) : null,
          p.bio ? h('p', { class: 'artist-bio', text: p.bio }) : null,
          h('div', { class: 'hero-actions' },
            canBook ? linkButton(`Book with ${p.short_name}`, `/book?artist=${p.slug}`, { size: 'lg' }) : null,
            p.services.some((s) => s.category === 'bridal') ? linkButton('Bridal enquiry', `/bridal?artist=${p.slug}`, { variant: 'secondary', size: 'lg' }) : null),
          p.instagram_url ? h('p', { class: 'artist-ig' }, h('a', { attrs: { href: p.instagram_url, target: '_blank', rel: 'noopener noreferrer' } }, icon('instagram', 17), h('span', { text: 'See recent work on Instagram' }))) : null))),
    h('section', { class: 'band band-stone', attrs: { 'aria-labelledby': 'artist-services' } },
      h('div', { class: 'container narrow-wide' },
        h('div', { class: 'band-head' }, h('h2', { class: 'band-title', attrs: { id: 'artist-services' }, text: 'Services' }),
          h('p', { class: 'band-lede', text: 'Times shown are approximate.' })),
        serviceRows(p))),
    h('section', { class: 'band band-pearl', attrs: { 'aria-labelledby': 'artist-portfolio' } },
      h('div', { class: 'container' },
        h('div', { class: 'band-head' }, h('h2', { class: 'band-title', attrs: { id: 'artist-portfolio' }, text: 'Portfolio' })),
        galleryEl)),
  ]);

  const items = await loadGallery(p.slug).catch(() => []);
  mount(galleryEl, items.length ? galleryGrid(items) : h('div', { class: 'gallery-empty' },
    h('p', { class: 'gallery-empty-title', text: `${p.short_name}’s portfolio is coming soon.` }),
    p.instagram_url ? h('p', null, h('a', { class: 'ig-link', attrs: { href: p.instagram_url, target: '_blank', rel: 'noopener noreferrer' } }, icon('instagram', 18), h('span', { text: 'Latest work on Instagram' }))) : null));
}
