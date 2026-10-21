// Studio-only "app" behaviour: installable app + phone alerts (web push).
// The public website (landing page, booking, bridal enquiry) is NOT installable: the manifest link and the
// service worker are only added on the Studio and staff sign-in pages. The worker caches nothing.
import { rpc, ApiError, callFunction, onBeforeSignOut } from './supabase';
import { VAPID_PUBLIC_KEY } from '../config';

const APP_PATHS = /^\/(studio|signin|join|forgot|reset)(\/|$)/;
let swRequested = false;

function metaTag(name: string, content: string | null) {
  let m = document.head.querySelector<HTMLMetaElement>(`meta[name="${name}"]`);
  if (content === null) { m?.remove(); return; }
  if (!m) { m = document.createElement('meta'); m.name = name; document.head.appendChild(m); }
  m.content = content;
}

/** Call on every navigation: adds the app manifest only on Studio pages, and removes it on the public site. */
export function syncAppMode(path: string) {
  const on = APP_PATHS.test(path);
  const link = document.head.querySelector<HTMLLinkElement>('link[rel="manifest"]');
  if (on && !link) {
    const l = document.createElement('link'); l.rel = 'manifest'; l.href = '/manifest.webmanifest';
    document.head.appendChild(l);
  } else if (!on && link) link.remove();
  metaTag('apple-mobile-web-app-capable', on ? 'yes' : null);
  metaTag('apple-mobile-web-app-title', on ? 'Studio' : null);
  metaTag('apple-mobile-web-app-status-bar-style', on ? 'black' : null);
  if (on && !swRequested && 'serviceWorker' in navigator) {
    swRequested = true;
    navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(() => { swRequested = false; });
  }
}

const isIos = () => /iPad|iPhone|iPod/.test(navigator.userAgent) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
const isStandalone = () => matchMedia('(display-mode: standalone)').matches || (navigator as any).standalone === true;
const capable = () => 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;

export type PushState =
  | { kind: 'unsupported' } | { kind: 'ios-install' } | { kind: 'denied' } | { kind: 'off' } | { kind: 'on'; devices: number };

export function installedAsApp(): boolean { return isStandalone(); }

export async function pushState(salonId: string): Promise<PushState> {
  if (!capable()) return isIos() && !isStandalone() ? { kind: 'ios-install' } : { kind: 'unsupported' };
  if (Notification.permission === 'denied') return { kind: 'denied' };
  try {
    const reg = await navigator.serviceWorker.getRegistration('/');
    const sub = await reg?.pushManager.getSubscription();
    if (!sub) return { kind: 'off' };
    const r = await rpc<any>('push_status', { p_salon: salonId, p_endpoint: sub.endpoint });
    return r.ok && r.this_device ? { kind: 'on', devices: Number(r.devices) || 1 } : { kind: 'off' };
  } catch { return { kind: 'off' }; }
}

function keyBytes(b64url: string): Uint8Array<ArrayBuffer> {
  const pad = '='.repeat((4 - (b64url.length % 4)) % 4);
  const raw = atob((b64url + pad).replace(/-/g, '+').replace(/_/g, '/'));
  const out = new Uint8Array(new ArrayBuffer(raw.length));
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
  return out;
}

/** Must be called straight from a tap: the permission question is only allowed after a user action. */
export async function enablePush(salonId: string): Promise<void> {
  if (!capable()) throw new ApiError('unsupported', 'This browser cannot show alerts.');
  const perm = await Notification.requestPermission();
  if (perm !== 'granted') {
    throw new ApiError('permission', perm === 'denied'
      ? 'Alerts are blocked for this site. Allow notifications in your phone settings, then try again.'
      : 'Alerts were not turned on.');
  }
  await navigator.serviceWorker.register('/sw.js', { scope: '/' });
  const reg = await navigator.serviceWorker.ready;
  const opts = { userVisibleOnly: true, applicationServerKey: keyBytes(VAPID_PUBLIC_KEY) };
  let sub: PushSubscription;
  try { sub = await reg.pushManager.subscribe(opts); }
  catch {
    // an old subscription made with a different key blocks a new one: remove it and try once more
    try { await (await reg.pushManager.getSubscription())?.unsubscribe(); sub = await reg.pushManager.subscribe(opts); }
    catch { throw new ApiError('subscribe_failed', 'This phone could not turn alerts on. Check your connection and try again.'); }
  }
  const j = sub.toJSON();
  const r = await rpc<any>('push_subscribe', { p_salon: salonId, p_sub: { endpoint: j.endpoint, keys: j.keys }, p_user_agent: navigator.userAgent.slice(0, 300) });
  if (!r.ok) { await sub.unsubscribe().catch(() => {}); throw new ApiError(r.error, r.message); }
}

export async function disablePush(): Promise<void> {
  const reg = await navigator.serviceWorker.getRegistration('/');
  const sub = await reg?.pushManager.getSubscription();
  if (!sub) return;
  await rpc('push_unsubscribe', { p_endpoint: sub.endpoint }).catch(() => {});
  await sub.unsubscribe().catch(() => {});
}

export async function sendTestPush(salonId: string): Promise<void> {
  const r = await rpc<any>('push_test', { p_salon: salonId });
  if (!r.ok) throw new ApiError(r.error, r.message);
  void callFunction('send-notifications', {}).catch(() => {});   // send now instead of waiting up to a minute
}

// Signing out switches alerts off on this phone, so the next person using it does not get your alerts.
onBeforeSignOut(async () => { if (capable()) await disablePush(); });
