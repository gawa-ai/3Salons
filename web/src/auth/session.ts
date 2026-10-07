import { rpc, currentSession, onAuthChange } from '../lib/supabase';

export interface ProRef { id: string; slug: string; display_name: string; short_name: string; specialty: string | null; color: string; logo_path: string | null; active: boolean }
export interface Membership {
  membership_id: string; role: 'owner' | 'professional'; display_name: string | null;
  salon: { id: string; slug: string; name: string; timezone: string; booking_mode: string; sms_connected: boolean };
  professional_id: string | null;
  professionals: ProRef[];
}
export interface Me { user: { id: string; email: string }; memberships: Membership[] }

let me: Promise<Me | null> | null = null;
let meFor: string | null = null;
const clearHooks = new Set<() => void>();

/** Register private caches that must be wiped on sign-out / account switch. */
export function onPrivateClear(fn: () => void) { clearHooks.add(fn); }

onAuthChange((s) => {
  if ((s?.user.id ?? null) !== meFor) {
    me = null; meFor = null;
    clearHooks.forEach((fn) => fn());
  }
});

/** The signed-in user's memberships, straight from the database (never from local flags). */
export function loadMe(force = false): Promise<Me | null> {
  const s = currentSession();
  if (!s) return Promise.resolve(null);
  if (!me || force || meFor !== s.user.id) {
    meFor = s.user.id;
    me = rpc<any>('salon_me').then((r) => (r?.ok ? (r as Me) : null)).catch((e) => { me = null; throw e; });
  }
  return me;
}

export function primaryMembership(m: Me | null): Membership | null {
  if (!m || !m.memberships.length) return null;
  return m.memberships.find((x) => x.role === 'owner') ?? m.memberships[0];
}
