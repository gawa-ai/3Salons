import { h, icon, mount } from '../lib/dom';
import { linkButton, spinner, errorBox } from '../lib/ui';
import { WEEKDAYS, time12, durationLabel } from '../lib/format';
import { publicStorageUrl } from '../lib/supabase';
import { PORTFOLIO_BUCKET } from '../config';
import { loadProfile, loadGallery, type PublicProfile, type PublicPro } from './data';
import { publicShell, arch, proMark } from './layout';

export async function homePage(app: HTMLElement) {
  document.title = 'Shahina Ahmed · Blackburn';
  publicShell(app, null, [spinner('Loading the studio')]);
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
          ...heroLines(salon.tagline).map((line) => h('span', { class: 'hero-line', text: line }))),
        h('p', { class: 'hero-lede', text: `From flawless makeup and elegant hair to beautifully styled hijabs and sarees, enjoy personalised styling${salon.city ? ' in ' + salon.city : ''}, tailored to you and your occasion.` }),
        h('p', { class: 'hero-lede', text: 'Choose your artist and book your appointment, or get in touch to discuss your dream bridal look.' }),
        h('div', { class: 'hero-actions' },
          linkButton('Book an appointment', '/book', { size: 'lg' }),
          linkButton('Bridal enquiry', '/bridal', { variant: 'secondary', size: 'lg' })),
        h('p', { class: 'hero-note' }, icon('check', 16), h('span', { text: 'Your moment deserves to be unforgettable.' }))),
      h('div', { class: 'hero-visual', attrs: { 'aria-hidden': 'true' } },
        arch(h('div', { class: 'hero-arch-art' },
          h('img', { attrs: { src: '/brand/sa-monogram.png', alt: '', width: 160, height: 210 } })), { size: 'xl', tone: 'blush' }),
        h('div', { class: 'hero-pros' }, pros.filter((p) => p.logo_path).slice(0, 4).map((p) => h('span', { class: 'hero-pro' }, proMark(p, 'sm')))))));

  // ------------------------------------------------------------ professionals
  const prosSection = h('section', { class: 'band band-pearl', attrs: { id: 'professionals', 'aria-labelledby': 'pros-title' } },
    h('div', { class: 'container' },
      h('div', { class: 'band-head' },
        h('h2', { class: 'band-title', attrs: { id: 'pros-title' }, text: 'Our professionals' }),
        h('div', { class: 'band-lede' },
          h('h3', { class: 'band-lede-title', text: 'Book Directly with Your Favourite Artist' }),
          h('p', { text: 'Each artist manages their own diary, so you can choose the person you’d like to book with and select a time that suits you from their available appointments. Simple, convenient, and hassle-free!' }))),
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
      h('div', { class: 'bridal-art', attrs: { 'aria-hidden': 'true' } }, arch(h('span', { class: 'bridal-arch-lines' }, h('img', { class: 'bridal-mark', attrs: { src: '/brand/sa-monogram.png', alt: '', width: 120, height: 158 } })), { size: 'lg', tone: 'night' })),
      h('div', { class: 'bridal-copy' },
        h('h2', { class: 'band-title', attrs: { id: 'bridal-title' }, text: 'Enquire for Bridal bookings' }),
        h('p', { text: 'Every bride deserves a look that feels uniquely hers. Our bridal styling is tailored to you, your vision and your special day.' }),
        h('p', { text: 'Simply share your wedding date/time, your desired look and your preferred artist. They’ll be in touch to discuss availability and provide a personalised quote.' }),
        h('p', { class: 'bridal-closing', text: 'Let’s create your perfect bridal look together!' }),
        h('ul', { class: 'bridal-list' },
          pros.map((p) => h('li', null, h('span', { class: ['pro-dot', `pro-${p.color}`] }), h('span', { text: `${p.display_name}${p.specialty ? ' - ' + p.specialty : ''}` })))),
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
        h('h2', { class: 'band-title', attrs: { id: 'about-title' }, text: 'About the Studio' })),
      h('div', { class: 'about-copy' },
        h('p', { class: 'about-lead', text: `A place for beauty, creativity and individual style in the heart of ${salon.city ?? 'the community'}.` }),
        h('p', { text: 'Shahina Ahmed brings together a talented team of artists with years of experience in hair, makeup, hijab and saree styling. Also offering training to boost the confidence within you.' }),
        h('p', { text: 'Each artist manages their own appointments, giving you the freedom to choose the artist, service and available time that suits you best. When you book online, your appointment is held while your chosen artist confirms the booking.' }),
        h('p', { text: 'For weddings and larger occasions, we offer a personalised bridal enquiry service, allowing your artist to understand your vision, discuss your requirements and plan your styling around your special day.' }),
        h('p', { class: 'about-closing', text: 'Your style, your artist, your moment!' }))));

  const contact = h('section', { class: 'band band-pearl', attrs: { id: 'contact', 'aria-labelledby': 'contact-title' } },
    h('div', { class: 'container' },
      h('div', { class: 'band-head' }, h('h2', { class: 'band-title', attrs: { id: 'contact-title' }, text: 'Visit and contact' })),
      h('div', { class: 'contact-grid' },
        h('div', { class: 'contact-card' },
          h('h3', { class: 'card-title' }, icon('pin', 18), h('span', { text: 'Location' })),
          salon.address
            ? h('p', { class: 'address' }, h('strong', { text: salon.name }), ...salon.address.split(/\s*,\s*|\n/).filter(Boolean).flatMap((line) => [h('br'), line]))
            : h('p', { class: 'muted', text: salon.city ? `${salon.city}. Full address to be announced.` : 'Address to be announced.' })),
        h('div', { class: 'contact-card' },
          h('h3', { class: 'card-title' }, icon('clock', 18), h('span', { text: 'Opening hours' })),
          salon.hours_confirmed && salon.hours?.length ? hoursTable(salon.hours)
            : h('p', { class: 'muted', text: 'Opening hours will be published soon. Online booking always shows the times each artist is free.' }),
          h('p', { class: 'appt-only', text: 'All bookings are strictly by appointment only.' })),
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

const HERO_TITLE = 'Your Beauty. Your Style. Your Special Moment.';
// Earlier staging headlines are replaced by the client's wording; an owner-edited headline is respected.
const OLD_HEROES = ['Your moment. Your signature look.', 'Hair, makeup and hijab styling for the moments that matter.'];
function heroLines(tagline: string | null): string[] {
  const t = tagline && !OLD_HEROES.includes(tagline.trim()) ? tagline : HERO_TITLE;
  return t.split(/(?<=\.)\s+/);
}

function proCard(p: PublicPro) {
  return h('article', { class: ['pro-card', `pro-${p.color}`] },
    h('a', { class: 'pro-card-link', attrs: { href: `/artists/${p.slug}`, 'aria-label': `${p.display_name}, view profile` } },
      arch(proMark(p, 'md'), { size: 'md', tone: 'pro', color: p.color })),
    // The logo already carries the full name and role, so the card shows just the first name (client request).
    h('h3', { class: 'pro-name' }, h('a', { attrs: { href: `/artists/${p.slug}` }, text: p.short_name || p.display_name })),
    h('div', { class: 'pro-actions' },
      p.online_booking && p.services.some((s) => s.bookable_online)
        ? linkButton('Book', `/book?artist=${p.slug}`, { size: 'sm' })
        : h('span', { class: 'muted small', text: 'Booking by enquiry' }),
      linkButton('View profile', `/artists/${p.slug}`, { variant: 'ghost', size: 'sm' })));
}

export function serviceRows(p: PublicPro) {
  return h('ul', { class: 'menu' }, p.services.map((s) => h('li', { class: 'menu-row' },
    h('div', { class: 'menu-main' },
      h('h4', { class: 'menu-name', text: s.name })),
    h('div', { class: 'menu-side' },
      h('p', { class: 'menu-price', text: s.price_label }),
      s.description ? h('p', { class: 'menu-note', text: s.description }) : null,
      s.price_kind !== 'enquire' ? h('p', { class: 'menu-time', text: durationLabel(s.duration_min) }) : null,
      s.bookable_online
        ? linkButton('Book', `/book?artist=${p.slug}&service=${s.id}`, { variant: 'secondary', size: 'sm' })
        : linkButton('Enquire', `/bridal?artist=${p.slug}${s.category === 'bridal' ? '' : `&want=${encodeURIComponent(s.name)}`}`, { variant: 'ghost', size: 'sm' })))));
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
  mount(el, galleryGrid(shahinaFirst(items).slice(0, 12)));
}

export function galleryGrid(items: { storage_path: string; media_type: string; alt_text: string; caption: string | null; professional: string }[]) {
  return h('ul', { class: 'gallery-grid' }, items.map((g) => h('li', { class: 'gallery-item' },
    g.media_type === 'video'
      ? h('video', { attrs: { src: publicStorageUrl(PORTFOLIO_BUCKET, g.storage_path), muted: true, loop: true, playsinline: true, controls: true, preload: 'none', poster: g.storage_path.startsWith('/') ? g.storage_path.replace(/\.mp4$/, '-poster.jpg') : undefined, 'aria-label': g.alt_text || `Video by ${g.professional}` } })
      : zoomable(h('img', { attrs: { src: publicStorageUrl(PORTFOLIO_BUCKET, g.storage_path), alt: g.alt_text || `Look by ${g.professional}`, loading: 'lazy', decoding: 'async' } })),
    h('p', { class: 'gallery-caption', text: g.caption ? (/\bby\b/i.test(g.caption) ? g.caption : `${g.caption}, by ${g.professional}`) : `By ${g.professional}` }))));
}


/** Shahina's own work always leads the gallery; the rest keep their order. */
export function shahinaFirst<T extends { professional_slug?: string }>(items: T[]): T[] {
  return [...items.filter((g) => g.professional_slug === 'shahina-ahmed'), ...items.filter((g) => g.professional_slug !== 'shahina-ahmed')];
}

/** Gallery photos open larger in a native dialog (Esc, the close button or a click outside closes it). */
let lightbox: HTMLDialogElement | null = null;
function zoomable(img: HTMLImageElement) {
  const btn = h('button', { class: 'zoom-btn', attrs: { type: 'button', 'aria-label': `Enlarge photo: ${img.alt}` } }, img);
  btn.addEventListener('click', () => {
    if (!lightbox) {
      lightbox = h('dialog', { class: 'lightbox', attrs: { 'aria-label': 'Photo viewer' } }) as HTMLDialogElement;
      lightbox.addEventListener('click', () => lightbox!.close());
      document.body.appendChild(lightbox);
    }
    const big = h('img', { attrs: { src: img.src, alt: img.alt } });
    const close = h('button', { class: 'lightbox-close', attrs: { type: 'button', 'aria-label': 'Close photo' } }, icon('x', 22));
    mount(lightbox, big, close);
    lightbox.showModal();
  });
  return btn;
}
