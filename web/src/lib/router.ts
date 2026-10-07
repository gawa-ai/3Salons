// History-API router. Routes are matched in order; ":param" segments capture values.
export interface RouteMatch { params: Record<string, string>; query: URLSearchParams; path: string }
export type RouteHandler = (m: RouteMatch) => void | Promise<void>;
interface Route { pattern: RegExp; keys: string[]; handler: RouteHandler }

const routes: Route[] = [];
let notFound: RouteHandler = () => {};
const beforeEach: ((path: string) => void)[] = [];

export function route(path: string, handler: RouteHandler) {
  const keys: string[] = [];
  const pattern = new RegExp('^' + path.replace(/\/:([a-z_]+)/gi, (_m, k) => { keys.push(k); return '/([^/]+)'; }).replace(/\/\*$/, '(?:/.*)?') + '/?$');
  routes.push({ pattern, keys, handler });
}

export function setNotFound(h: RouteHandler) { notFound = h; }
export function onNavigate(fn: (path: string) => void) { beforeEach.push(fn); }

export function navigate(to: string, opts: { replace?: boolean } = {}) {
  if (to === location.pathname + location.search + location.hash) { void resolve(); return; }
  if (opts.replace) history.replaceState(null, '', to);
  else history.pushState(null, '', to);
  void resolve();
}

export async function resolve() {
  const path = location.pathname;
  beforeEach.forEach((fn) => fn(path));
  for (const r of routes) {
    const m = path.match(r.pattern);
    if (m) {
      const params: Record<string, string> = {};
      r.keys.forEach((k, i) => { params[k] = decodeURIComponent(m[i + 1]); });
      await r.handler({ params, query: new URLSearchParams(location.search), path });
      return;
    }
  }
  await notFound({ params: {}, query: new URLSearchParams(location.search), path });
}

export function startRouter() {
  window.addEventListener('popstate', () => void resolve());
  document.addEventListener('click', (e) => {
    const a = (e.target as Element)?.closest?.('a');
    if (!a || e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    const href = a.getAttribute('href');
    if (!href || a.target === '_blank' || a.hasAttribute('download') || !href.startsWith('/') || href.startsWith('//')) return;
    if (a.dataset.native !== undefined) return;
    const url = new URL(href, location.origin);
    if (url.pathname === location.pathname && url.hash && !url.search) {
      e.preventDefault();
      history.pushState(null, '', href);
      document.getElementById(url.hash.slice(1))?.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
      return;
    }
    e.preventDefault();
    navigate(href);
  });
  void resolve();
}
