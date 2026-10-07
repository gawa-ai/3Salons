// Tiny DOM helpers. Text is always set via textContent (never innerHTML with data),
// so customer-supplied names/notes cannot inject markup.

type Child = Node | string | number | null | undefined | false | Child[];
type Handler = (ev: any) => void;
export interface Props {
  class?: string | (string | false | null | undefined)[];
  attrs?: Record<string, string | number | boolean | null | undefined>;
  on?: Record<string, Handler>;
  style?: Partial<Record<string, string>>;
  dataset?: Record<string, string>;
  text?: string;
  ref?: (el: HTMLElement) => void;
  [key: string]: unknown;
}

const PROP_KEYS = new Set(['class', 'attrs', 'on', 'style', 'dataset', 'text', 'ref']);

export function h<K extends keyof HTMLElementTagNameMap>(tag: K, props?: Props | null, ...children: Child[]): HTMLElementTagNameMap[K] {
  const el = document.createElement(tag);
  if (props) {
    if (props.class) {
      const c = Array.isArray(props.class) ? props.class.filter(Boolean).join(' ') : props.class;
      if (c) el.className = c;
    }
    if (props.attrs) {
      for (const [k, v] of Object.entries(props.attrs)) {
        if (v === false || v === null || v === undefined) continue;
        el.setAttribute(k, v === true ? '' : String(v));
      }
    }
    for (const [k, v] of Object.entries(props)) {
      if (PROP_KEYS.has(k) || v === undefined) continue;
      (el as any)[k] = v;
    }
    if (props.on) for (const [ev, fn] of Object.entries(props.on)) el.addEventListener(ev, fn);
    if (props.style) for (const [k, v] of Object.entries(props.style)) if (v !== undefined) el.style.setProperty(k, v);
    if (props.dataset) for (const [k, v] of Object.entries(props.dataset)) el.dataset[k] = v;
    if (props.text !== undefined) el.textContent = props.text;
    if (props.ref) props.ref(el);
  }
  append(el, ...children);
  return el;
}

export function append(parent: Node, ...children: Child[]) {
  for (const c of children) {
    if (c === null || c === undefined || c === false) continue;
    if (Array.isArray(c)) append(parent, ...c);
    else if (c instanceof Node) parent.appendChild(c);
    else parent.appendChild(document.createTextNode(String(c)));
  }
}

export function clear(el: Element) {
  while (el.firstChild) el.removeChild(el.firstChild);
}

export function mount(el: Element, ...children: Child[]) {
  clear(el);
  append(el, ...children);
}

// Inline SVG icons (stroke-based, 1.5px). Static strings authored here, never user data.
const ICONS: Record<string, string> = {
  calendar: '<rect x="3.5" y="5" width="17" height="15" rx="2"/><path d="M3.5 9.5h17M8 3v4M16 3v4"/>',
  home: '<path d="M4 10.5 12 4l8 6.5V20a1 1 0 0 1-1 1h-5v-6h-4v6H5a1 1 0 0 1-1-1z"/>',
  list: '<path d="M8 6h12M8 12h12M8 18h12M4 6h.01M4 12h.01M4 18h.01"/>',
  users: '<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.5 3.4-5.5 6.5-5.5s5.7 2 6.5 5.5M16 4.8a3.5 3.5 0 0 1 0 6.4M18.5 14.8c1.6.8 2.7 2.5 3 5.2"/>',
  user: '<circle cx="12" cy="8" r="4"/><path d="M4 20.5c1-4 4.2-6.5 8-6.5s7 2.5 8 6.5"/>',
  scissors: '<circle cx="6" cy="6" r="2.5"/><circle cx="6" cy="18" r="2.5"/><path d="M8 7.5 20 18M8 16.5 20 6"/>',
  clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
  chat: '<path d="M4 5.5h16v10H9l-5 4z"/>',
  chart: '<path d="M4 20V10M10 20V4M16 20v-7M22 20H2"/>',
  settings: '<circle cx="12" cy="12" r="3"/><path d="M12 2.8v2.4M12 18.8v2.4M4.2 6l1.7 1.7M18.1 16.3l1.7 1.7M2.8 12h2.4M18.8 12h2.4M4.2 18l1.7-1.7M18.1 7.7 19.8 6"/>',
  shield: '<path d="M12 3 4.5 6v6c0 4.4 3.2 7.8 7.5 9 4.3-1.2 7.5-4.6 7.5-9V6z"/>',
  image: '<rect x="3.5" y="4.5" width="17" height="15" rx="2"/><circle cx="9" cy="10" r="1.8"/><path d="m4 18 5.5-5 4 3.5 2.5-2 4 3.5"/>',
  mail: '<rect x="3.5" y="5.5" width="17" height="13" rx="2"/><path d="m4 7 8 6 8-6"/>',
  heart: '<path d="M12 20s-7.5-4.6-7.5-10A4.3 4.3 0 0 1 12 7.3 4.3 4.3 0 0 1 19.5 10c0 5.4-7.5 10-7.5 10z"/>',
  logout: '<path d="M14 4h4.5a1.5 1.5 0 0 1 1.5 1.5v13a1.5 1.5 0 0 1-1.5 1.5H14M10 16l-4-4 4-4M6 12h10"/>',
  plus: '<path d="M12 5v14M5 12h14"/>',
  check: '<path d="m5 12.5 4.5 4.5L19 7.5"/>',
  x: '<path d="M6 6l12 12M18 6 6 18"/>',
  chevronLeft: '<path d="m14.5 6-6 6 6 6"/>',
  chevronRight: '<path d="m9.5 6 6 6-6 6"/>',
  chevronDown: '<path d="m6 9.5 6 6 6-6"/>',
  menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
  search: '<circle cx="11" cy="11" r="6.5"/><path d="m16 16 4.5 4.5"/>',
  instagram: '<rect x="3.5" y="3.5" width="17" height="17" rx="5"/><circle cx="12" cy="12" r="4"/><circle cx="17.2" cy="6.8" r=".6" fill="currentColor"/>',
  phone: '<path d="M6.5 3.5h3l1.5 4-2 1.5a11 11 0 0 0 6 6l1.5-2 4 1.5v3a2 2 0 0 1-2 2A16.5 16.5 0 0 1 4.5 5.5a2 2 0 0 1 2-2z"/>',
  pin: '<path d="M12 21s6.5-6.2 6.5-11.5a6.5 6.5 0 0 0-13 0C5.5 14.8 12 21 12 21z"/><circle cx="12" cy="9.5" r="2.2"/>',
  arrowRight: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  sparkle: '<path d="M12 3.5 13.8 10 20.5 12l-6.7 2-1.8 6.5-1.8-6.5L3.5 12l6.7-2z"/>',
  download: '<path d="M12 4v11M7 10.5l5 5 5-5M5 19.5h14"/>',
  upload: '<path d="M12 20V9M7 13.5l5-5 5 5M5 4.5h14"/>',
  trash: '<path d="M5 7h14M10 7V4.5h4V7M7 7l1 13h8l1-13"/>',
  eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
  info: '<circle cx="12" cy="12" r="8.5"/><path d="M12 11v5M12 8h.01"/>',
  alert: '<path d="M12 4 2.8 19.5h18.4z"/><path d="M12 10v4.5M12 17h.01"/>',
  refresh: '<path d="M19.5 12a7.5 7.5 0 1 1-2.2-5.3M19.5 4v4.5H15"/>',
};

export function icon(name: keyof typeof ICONS | string, size = 18, label?: string): SVGSVGElement {
  const ns = 'http://www.w3.org/2000/svg';
  const svg = document.createElementNS(ns, 'svg');
  svg.setAttribute('viewBox', '0 0 24 24');
  svg.setAttribute('width', String(size));
  svg.setAttribute('height', String(size));
  svg.setAttribute('fill', 'none');
  svg.setAttribute('stroke', 'currentColor');
  svg.setAttribute('stroke-width', '1.6');
  svg.setAttribute('stroke-linecap', 'round');
  svg.setAttribute('stroke-linejoin', 'round');
  svg.setAttribute('class', 'icon');
  if (label) { svg.setAttribute('role', 'img'); svg.setAttribute('aria-label', label); }
  else svg.setAttribute('aria-hidden', 'true');
  // ICONS are static, trusted markup defined above.
  svg.innerHTML = ICONS[name] ?? '';
  return svg;
}

export function uid(prefix = 'id'): string {
  return `${prefix}-${Math.random().toString(36).slice(2, 9)}`;
}

export function newIdempotencyKey(): string {
  const a = new Uint8Array(18);
  crypto.getRandomValues(a);
  return Array.from(a, (b) => b.toString(16).padStart(2, '0')).join('');
}
