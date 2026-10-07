import { h, icon, mount } from '../lib/dom';
import { linkButton, spinner, errorBox } from '../lib/ui';
import { WEEKDAYS, time12, durationLabel } from '../lib/format';
import { publicStorageUrl } from '../lib/supabase';
import { PORTFOLIO_BUCKET } from '../config';
import { loadProfile, loadGallery, fromPrice, type PublicProfile, type PublicPro } from './data';
import { publicShell, arch, proMark } from './layout';

export async function homePage(app: HTMLElement) {
  document.title = 'Shahina Ahmed · Blackburn';
  publicShell(app, null, [spinner('Loading the salon')]);
  let profile: PublicProfile;
  try {
    profile = await loadProfile();
  } catch (e) {
    publicShell(app, null, [h('div', { class: 'container pad-y' }, errorBox((e as Error).message, () => homePage(app)))]);
    return;
  }
  const { salon, professionals: pros } = profile;

  // ------------------------------------------------------------ hero
  const hero = h('section', { class: 'hero', attrs: { 'aria-labelledby': 'hero-title' } },
    h('div', { class: 'container hero-grid' },
      h('div', { class: 'hero-copy' },
        h('h1', { class: 'hero-title', attrs: { id: 'hero-title' } },
          ...(salon.tagline ?? 'Your moment. Your signature look.').split(/(?<=\.)\s+/).map((line) => h('span', { class: 'hero-line', text: line }))),
        h('p', { class: 'hero-lede', text: `Hair, makeup, hijab and saree styling${salon.city ? ' in ' + salon.city : ''}, tailored to you and your occasion. Choose your artist and book your appointment, or get in touch for bridal styling.` }),
        h('div', { class: 'hero-actions' },
          linkButton('Book an appointment', '/book', { size: 'lg' }),
          linkButton('Bridal enquiry', '/bridal', { variant: 'secondary', size: 'lg' })),
        h('p', { class: 'hero-note' }, icon('check', 16), h('span', { text: 'Choose your artist and a free time. Your artist confirms the booking personally.' }))),
      h('div', { class: 'hero-visual', attrs: { 'aria-hidden': 'true' } },
        arch(h('div', { class: 'hero-arch-art' },
          h('img', { attrs: { src: '/brand/sa-monogram.svg', alt: '', width: 220, height: 220 } })), { size: 'xl', tone: 'blush' }),
        h('div', { class: 'hero-pros' }, pros.filter((p) => p.logo_path).slice(0, 4).map((p) => h('span', { class: 'hero-pro' }, proMark(p, 'sm')))))));

  // ------------------------------------------------------------ professionals
  const prosSection = h('section', { class: 'band band-pearl', attrs: { id: 'professionals', 'aria-labelledby': 'pros-title' } },
    h('div', { class: 'container' },
      h('div', { class: 'band-head' },
        h('h2', { class: 'band-title', attrs: { id: 'pros-title' }, text: 'Our professionals' }),
        h('p', { class: 'band-lede', text: 'Each artist keeps their own diary. Pick the person you want and book straight into their free times.' })),
      h('ul', { class: 'pro-grid' }, pros.map((p) => h('li', null, proCard(p))))));

  // ------------------------------------------------------------ services (tabs per artist)
  const servicesSection = h('section', { class: 'band band-stone', attrs: { id: 'services', 'aria-labelledby': 'services-title' } },
    h('div', { class: 'container' },
      h('div', { class: 'band-head' },
        h('h2', { class: 'band-title', attrs: { id: 'services-title' }, text: 'Services and prices' }),
        h('p', { class: 'band-lede', text: 'Prices are set by each artist. Times shown are approximate.' })),
      serviceTabs(pros)));

  // ------------------------------------------------------------ bridal
  const bridal = h('section', { class: 'band band-night', attrs: { id: 'bridal', 'aria-labelledby': 'bridal-title' } },
    h('div', { class: 'container bridal-grid' },
      h('div', { class: 'bridal-art', attrs: { 'aria-hidden': 'true' } }, arch(h('span', { class: 'bridal-arch-lines' }), { size: 'lg', tone: 'night' })),
      h('div', { class: 'bridal-copy' },
        h('h2', { class: 'band-title', attrs: { id: 'bridal-title' }, text: 'Bridal, by enquiry' }),
        h('p', { text: 'Every bride is planned individually. Tell us your date, the look you have in mind and who you would like, and the artist will come back to you with availability and a quote.' }),
        h('ul', { class: 'bridal-list' },
          pros.filter((p) => p.services.some((s) => s.category === 'bridal')).map((p) => h('li', null, h('span', { class: ['pro-dot', `pro-${p.color}`] }), h('span', { text: `${p.display_name}${p.specialty ? ', ' + p.specialty.toLowerCase() : ''}` })))),
        linkButton('Send a bridal enquiry', '/bridal', { variant: 'secondary', size: 'lg', class: 'btn-on-dark' }))));

  // ------------------------------------------------------------ gallery
  const galleryBody = h('div', { class: 'gallery-body' }, spinner('Loading gallery'));
  const gallery = h('section', { class: 'band band-pearl', attrs: { id: 'gallery', 'aria-labelledby': 'gallery-title' } },
    h('div', { class: 'container' },
      h('div', { class: 'band-head' },
        h('h2', { class: 'band-title', attrs: { id: 'gallery-title' }, text: 'Gallery' }),
        h('p', { class: 'band-lede', text: 'Recent work by our artists.' })),
      galleryBody));
  void renderGallery(galleryBody, pros);

  // ------------------------------------------------------------ about + contact
  const about = h('section', { class: 'band band-stone', attrs: { id: 'about', 'aria-labelledby': 'about-title' } },
    h('div', { class: 'container about-grid' },
      h('div', null,
        h('h2', { class: 'band-title', attrs: { id: 'about-title' }, text: 'About the salon' })),
      h('div', { class: 'about-copy' },
        h('p', { text: 'Each artist runs their own appointments. When you book online you choose the artist, the service and a free time, and your booking is held for you while the artist confirms it.' }),
        h('p', { text: 'For weddings and larger occasions, send a bridal enquiry so the artist can plan the day with you.' }))));

  const contact = h('section', { class: 'band band-pearl', attrs: { id: 'contact', 'aria-labelledby': 'contact-title' } },
    h('div', { class: 'container' },
      h('div', { class: 'band-head' }, h('h2', { class: 'band-title', attrs: { id: 'contact-title' }, text: 'Visit and contact' })),
      h('div', { class: 'contact-grid' },
        h('div', { class: 'contact-card' },
          h('h3', { class: 'card-title' }, icon('pin', 18), h('span', { text: 'Location' })),
          salon.address ? h('p', { text: salon.address }) : h('p', { class: 'muted', text: salon.city ? `${salon.city}. Full address to be announced.` : 'Address to be announced.' })),
        h('div', { class: 'contact-card' },
          h('h3', { class: 'card-title' }, icon('clock', 18), h('span', { text: 'Opening hours' })),
          salon.hours_confirmed && salon.hours?.length ? hoursTable(salon.hours)
            : h('p', { class: 'muted', text: 'Opening hours will be published soon. Online booking always shows the times each artist is free.' })),
        h('div', { class: 'contact-card' },
          h('h3', { class: 'card-title' }, icon('chat', 18), h('span', { text: 'Get in touch' })),
          h('ul', { class: 'contact-list' },
            salon.phone ? h('li', null, icon('phone', 16), h('a', { attrs: { href: `tel:${salon.phone.replace(/\s/g, '')}` }, text: salon.phone })) : null,
            salon.whatsapp ? h('li', null, icon('chat', 16), h('a', { attrs: { href: `https://wa.me/${salon.whatsapp.replace(/[^0-9]/g, '')}`, target: '_blank', rel: 'noopener noreferrer' }, text: `WhatsApp ${salon.whatsapp}` })) : null,
            salon.email ? h('li', null, icon('mail', 16), h('a', { attrs: { href: `mailto:${salon.email}` }, text: salon.email })) : null,
            ...pros.filter((p) => p.instagram_url).map((p) => h('li', null, icon('instagram', 16), h('a', { attrs: { href: p.instagram_url!, target: '_blank', rel: 'noopener noreferrer' }, text: `${p.display_name} on Instagram` }))))))));

  publicShell(app, profile, [hero, prosSection, servicesSection, bridal, gallery, about, contact]);
  if (location.hash) requestAnimationFrame(() => document.getElementById(location.hash.slice(1))?.scrollIntoView());
}

function proCard(p: PublicPro) {
  const from = fromPrice(p);
  return h('article', { class: ['pro-card', `pro-${p.color}`] },
    h('a', { class: 'pro-card-link', attrs: { href: `/artists/${p.slug}`, 'aria-label': `${p.display_name}, view profile` } },
      arch(proMark(p, 'md'), { size: 'md', tone: 'pro', color: p.color })),
    h('h3', { class: 'pro-name' }, h('a', { attrs: { href: `/artists/${p.slug}` }, text: p.display_name })),
    p.specialty ? h('p', { class: 'pro-specialty', text: p.specialty }) : null,
    h('p', { class: 'pro-meta', text: [`${p.services.length} service${p.services.length === 1 ? '' : 's'}`, from].filter(Boolean).join(', ') }),
    h('div', { class: 'pro-actions' },
      p.online_booking && p.services.some((s) => s.bookable_online)
        ? linkButton('Book', `/book?artist=${p.slug}`, { size: 'sm' })
        : h('span', { class: 'muted small', text: 'Booking by enquiry' }),
      linkButton('View profile', `/artists/${p.slug}`, { variant: 'ghost', size: 'sm' })));
}

export function serviceRows(p: PublicPro) {
  return h('ul', { class: 'menu' }, p.services.map((s) => h('li', { class: 'menu-row' },
    h('div', { class: 'menu-main' },
      h('h4', { class: 'menu-name', text: s.name }),
      s.description ? h('p', { class: 'menu-desc', text: s.description }) : null),
    h('div', { class: 'menu-side' },
      h('p', { class: 'menu-price', text: s.price_label }),
      s.price_kind !== 'enquire' ? h('p', { class: 'menu-time', text: `about ${durationLabel(s.duration_min)}` }) : null,
      s.bookable_online
        ? linkButton('Book', `/book?artist=${p.slug}&service=${s.id}`, { variant: 'secondary', size: 'sm' })
        : linkButton('Enquire', `/bridal?artist=${p.slug}`, { variant: 'ghost', size: 'sm' })))));
}

function serviceTabs(pros: PublicPro[]) {
  const tabs = h('div', { class: 'tabs', attrs: { role: 'tablist', 'aria-label': 'Choose an artist' } });
  const panel = h('div', { class: 'tab-panel', attrs: { role: 'tabpanel', tabindex: '0' } });
  const buttons: HTMLButtonElement[] = [];
  const select = (i: number, focus = false) => {
    buttons.forEach((b, j) => {
      b.setAttribute('aria-selected', String(i === j));
      b.tabIndex = i === j ? 0 : -1;
    });
    panel.setAttribute('aria-labelledby', buttons[i].id);
    mount(panel, serviceRows(pros[i]));
    if (focus) buttons[i].focus();
  };
  pros.forEach((p, i) => {
    const b = h('button', { class: ['tab', `pro-${p.color}`], attrs: { role: 'tab', type: 'button', id: `tab-${p.slug}` } },
      h('span', { class: ['pro-dot', `pro-${p.color}`] }), h('span', { text: p.display_name }));
    b.addEventListener('click', () => select(i));
    b.addEventListener('keydown', (e) => {
      if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
        e.preventDefault();
        select((i + (e.key === 'ArrowRight' ? 1 : pros.length - 1)) % pros.length, true);
      }
    });
    buttons.push(b);
    tabs.appendChild(b);
  });
  if (pros.length) select(0);
  return h('div', { class: 'services-tabs' }, tabs, panel);
}

function hoursTable(hours: { weekday: number; opens: string; closes: string }[]) {
  const byDay = new Map<number, string[]>();
  hours.forEach((r) => byDay.set(r.weekday, [...(byDay.get(r.weekday) ?? []), `${time12(r.opens)} – ${time12(r.closes)}`]));
  const order = [1, 2, 3, 4, 5, 6, 0];
  return h('dl', { class: 'hours' }, order.map((d) => [h('dt', { text: WEEKDAYS[d] }), h('dd', { text: byDay.get(d)?.join(', ') ?? 'Closed' })]));
}

async function renderGallery(el: HTMLElement, pros: PublicPro[]) {
  const items = await loadGallery().catch(() => []);
  if (!items.length) {
    mount(el, h('div', { class: 'gallery-empty' },
      h('p', { class: 'gallery-empty-title', text: 'New photos are on their way.' }),
      h('p', { class: 'muted', text: 'Until then, see each artist’s latest looks on Instagram.' }),
      h('ul', { class: 'ig-links' }, pros.filter((p) => p.instagram_url).map((p) =>
        h('li', null, h('a', { class: 'ig-link', attrs: { href: p.instagram_url!, target: '_blank', rel: 'noopener noreferrer' } },
          icon('instagram', 18), h('span', { text: p.display_name })))))));
    return;
  }
  mount(el, galleryGrid(items.slice(0, 12)));
}

export function galleryGrid(items: { storage_path: string; media_type: string; alt_text: string; caption: string | null; professional: string }[]) {
  return h('ul', { class: 'gallery-grid' }, items.map((g) => h('li', { class: 'gallery-item' },
    g.media_type === 'video'
      ? h('video', { attrs: { src: publicStorageUrl(PORTFOLIO_BUCKET, g.storage_path), muted: true, loop: true, playsinline: true, controls: true, preload: 'none', poster: g.storage_path.startsWith('/') ? g.storage_path.replace(/\.mp4$/, '-poster.jpg') : undefined, 'aria-label': g.alt_text || `Video by ${g.professional}` } })
      : h('img', { attrs: { src: publicStorageUrl(PORTFOLIO_BUCKET, g.storage_path), alt: g.alt_text || `Look by ${g.professional}`, loading: 'lazy', decoding: 'async' } }),
    h('p', { class: 'gallery-caption', text: g.caption ? `${g.caption}, by ${g.professional}` : `By ${g.professional}` }))));
}

