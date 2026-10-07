import { TIMEZONE } from '../config';

export const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
export const WEEKDAYS_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

export function pounds(pence: number | null | undefined): string {
  if (pence === null || pence === undefined) return '—';
  const v = pence / 100;
  return new Intl.NumberFormat('en-GB', { style: 'currency', currency: 'GBP', minimumFractionDigits: v % 1 ? 2 : 0 }).format(v);
}

/** Today's date (YYYY-MM-DD) in the salon timezone. */
export function todayLocal(tz = TIMEZONE): string {
  return isoDateInTz(new Date(), tz);
}

export function isoDateInTz(d: Date, tz = TIMEZONE): string {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(d);
  const g = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
  return `${g('year')}-${g('month')}-${g('day')}`;
}

/** Pure calendar arithmetic on YYYY-MM-DD strings (no timezone involved). */
export function addDays(iso: string, n: number): string {
  const [y, m, d] = iso.split('-').map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d + n));
  return dt.toISOString().slice(0, 10);
}

export function weekdayOf(iso: string): number {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d)).getUTCDay();
}

export function startOfWeek(iso: string): string {
  const wd = weekdayOf(iso); // Monday-based week
  return addDays(iso, -((wd + 6) % 7));
}

export function formatDateLong(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  return new Intl.DateTimeFormat('en-GB', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'UTC' }).format(new Date(Date.UTC(y, m - 1, d)));
}

export function formatDateShort(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number);
  return new Intl.DateTimeFormat('en-GB', { weekday: 'short', day: 'numeric', month: 'short', timeZone: 'UTC' }).format(new Date(Date.UTC(y, m - 1, d)));
}

export function formatMonthYear(iso: string): string {
  const [y, m] = iso.split('-').map(Number);
  return new Intl.DateTimeFormat('en-GB', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(new Date(Date.UTC(y, m - 1, 1)));
}

export function time12(hhmm: string): string {
  const [h, m] = hhmm.split(':').map(Number);
  const suffix = h >= 12 ? 'pm' : 'am';
  const hh = h % 12 === 0 ? 12 : h % 12;
  return `${hh}${m ? ':' + String(m).padStart(2, '0') : ''}${suffix}`;
}

export function minutesOf(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

export function durationLabel(min: number): string {
  if (min < 60) return `${min} min`;
  const h = Math.floor(min / 60);
  const m = min % 60;
  return m ? `${h} hr ${m} min` : `${h} hr${h > 1 ? 's' : ''}`;
}

/** UTC instant for a local wall-clock date+time in the salon timezone (DST-safe). */
export function zonedToUtc(dateIso: string, hhmm: string, tz = TIMEZONE): Date {
  const [y, mo, d] = dateIso.split('-').map(Number);
  const [h, mi] = hhmm.split(':').map(Number);
  let guess = Date.UTC(y, mo - 1, d, h, mi);
  for (let i = 0; i < 3; i++) {
    const parts = new Intl.DateTimeFormat('en-GB', { timeZone: tz, hourCycle: 'h23', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }).formatToParts(new Date(guess));
    const g = (t: string) => Number(parts.find((p) => p.type === t)?.value);
    const asUtc = Date.UTC(g('year'), g('month') - 1, g('day'), g('hour'), g('minute'));
    const diff = asUtc - Date.UTC(y, mo - 1, d, h, mi);
    if (diff === 0) break;
    guess -= diff;
  }
  return new Date(guess);
}

export function relativeTime(iso: string): string {
  const diff = (Date.now() - new Date(iso).getTime()) / 1000;
  if (diff < 60) return 'just now';
  if (diff < 3600) return `${Math.floor(diff / 60)} min ago`;
  if (diff < 86400) return `${Math.floor(diff / 3600)} hr ago`;
  if (diff < 86400 * 7) return `${Math.floor(diff / 86400)} day${diff >= 172800 ? 's' : ''} ago`;
  return new Intl.DateTimeFormat('en-GB', { day: 'numeric', month: 'short', timeZone: TIMEZONE }).format(new Date(iso));
}

export function dateTimeShort(iso: string): string {
  return new Intl.DateTimeFormat('en-GB', { weekday: 'short', day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit', hour12: true, timeZone: TIMEZONE })
    .format(new Date(iso)).replace(' am', 'am').replace(' pm', 'pm');
}

export const STATUS_LABEL: Record<string, string> = {
  pending: 'Awaiting confirmation',
  confirmed: 'Confirmed',
  declined: 'Declined',
  cancelled: 'Cancelled',
  completed: 'Completed',
  no_show: 'No-show',
  expired: 'Expired',
};

export const SOURCE_LABEL: Record<string, string> = {
  website: 'Website',
  dashboard: 'Studio',
  phone: 'Phone',
  walk_in: 'Walk-in',
  other: 'Other',
};

export function initials(name: string): string {
  return name.split(/\s+/).filter(Boolean).slice(0, 2).map((p) => p[0]?.toUpperCase() ?? '').join('');
}
