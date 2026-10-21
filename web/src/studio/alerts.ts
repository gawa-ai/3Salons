import { h, mount } from '../lib/dom';
import { button, notice, setBusy, spinner, toast } from '../lib/ui';
import { enablePush, disablePush, sendTestPush, pushState, installedAsApp } from '../lib/pwa';
import type { Ctx } from './shell';

const DISMISS_KEY = 'sa-alerts-banner-dismissed';
const dismissed = () => { try { return localStorage.getItem(DISMISS_KEY) === '1'; } catch { return false; } };
const dismiss = () => { try { localStorage.setItem(DISMISS_KEY, '1'); } catch { /* ignore */ } };

const IOS_STEPS = 'On iPhone, first add the Studio to your Home Screen: tap Share, then Add to Home Screen. Open the Studio from the new icon, sign in, and turn alerts on from this page.';

/** Account page: full control of alerts on this phone. */
export function alertsPanel(ctx: Ctx): HTMLElement {
  const box = h('section', { class: 'panel' });
  const render = async () => {
    mount(box, h('h3', { class: 'panel-title', text: 'Alerts on this phone' }), spinner());
    const st = await pushState(ctx.salonId);
    const intro = h('p', { class: 'muted small', text: ctx.isOwner
      ? 'Get a notification on this phone when a new booking request, a client cancellation or an enquiry comes in for the studio.'
      : 'Get a notification on this phone when a new booking request, a client cancellation or an enquiry comes in for you.' });
    const body: Node[] = [];
    if (st.kind === 'on') {
      const test = button('Send me a test', { variant: 'secondary', onClick: async () => {
        setBusy(test, true, 'Sending…');
        try { await sendTestPush(ctx.salonId); toast('Test sent. It should arrive in a few seconds.'); }
        catch (e) { toast((e as Error).message, 'error'); }
        setBusy(test, false);
      } });
      const off = button('Turn off', { variant: 'ghost', onClick: async () => { setBusy(off, true, 'Turning off…'); await disablePush(); toast('Alerts are off on this phone'); void render(); } });
      body.push(notice('success', 'Alerts are on for this phone.'),
        h('p', { class: 'muted small', text: 'Signing out turns alerts off on this phone. Sign in and turn them on again whenever you like.' }),
        h('div', { class: 'row-end' }, off, test));
    } else if (st.kind === 'off') {
      const on = button('Turn on alerts', { icon: 'chat', onClick: async () => {
        setBusy(on, true, 'Turning on…');
        try { await enablePush(ctx.salonId); toast('Alerts are on'); void render(); }
        catch (e) { toast((e as Error).message, 'error'); setBusy(on, false); }
      } });
      body.push(h('div', { class: 'row-end' }, on));
    } else if (st.kind === 'denied') {
      body.push(notice('warn', 'Alerts are blocked for this site on this phone. Open your phone or browser settings, allow notifications for this site, then come back and turn them on.'));
    } else if (st.kind === 'ios-install') {
      body.push(notice('info', IOS_STEPS));
    } else {
      body.push(notice('info', 'This browser cannot show alerts. On Android, use Chrome. On iPhone (iOS 16.4 or newer), add the Studio to your Home Screen first.'));
    }
    if (!installedAsApp() && st.kind !== 'unsupported') {
      body.push(h('p', { class: 'muted small', text: 'Tip: add the Studio to your Home Screen so it opens like an app. Android: browser menu, then Install app. iPhone: Share, then Add to Home Screen.' }));
    }
    mount(box, h('h3', { class: 'panel-title', text: 'Alerts on this phone' }), intro, ...body);
  };
  void render();
  return box;
}

/** Overview page: a gentle one-time nudge. Returns null when nothing needs saying. */
export async function alertsBanner(ctx: Ctx): Promise<Node | null> {
  if (dismissed()) return null;
  const st = await pushState(ctx.salonId);
  if (st.kind !== 'off' && st.kind !== 'ios-install') return null;
  const wrap = h('div', { class: 'alerts-banner' });
  const hide = button('Not now', { variant: 'ghost', size: 'sm', onClick: () => { dismiss(); wrap.remove(); } });
  const actions = st.kind === 'off'
    ? (() => {
        const on = button('Turn on alerts', { size: 'sm', onClick: async () => {
          setBusy(on, true, 'Turning on…');
          try { await enablePush(ctx.salonId); dismiss(); wrap.remove(); toast('Alerts are on'); }
          catch (e) { toast((e as Error).message, 'error'); setBusy(on, false); }
        } });
        return [on, hide];
      })()
    : [h('a', { class: 'btn btn-secondary btn-sm', attrs: { href: '/studio/account' } }, h('span', { text: 'How to turn on alerts' })), hide];
  mount(wrap, notice('info', h('div', null,
    h('p', { text: 'Get a notification on this phone when a new request or enquiry comes in.' }),
    h('div', { class: 'row-end' }, ...actions))));
  return wrap;
}
