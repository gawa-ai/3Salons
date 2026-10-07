// Minimal Supabase client (Auth + RPC + Storage) over fetch.
// Endpoints follow the documented Supabase REST APIs:
//   Auth (GoTrue):   /auth/v1/token, /auth/v1/logout, /auth/v1/recover, /auth/v1/user
//   Data (PostgREST): POST /rest/v1/rpc/<function>
//   Storage:          /storage/v1/object/<bucket>/<path>
import { SUPABASE_URL, SUPABASE_KEY } from '../config';

export interface Session {
  access_token: string;
  refresh_token: string;
  expires_at: number; // epoch seconds
  user: { id: string; email: string };
}

export class ApiError extends Error {
  code: string;
  status: number;
  constructor(code: string, message: string, status = 0) {
    super(message);
    this.code = code;
    this.status = status;
  }
}

const STORAGE_KEY = 'sa-salon-auth-v1';
type Listener = (s: Session | null) => void;
const listeners = new Set<Listener>();
let session: Session | null = load();
let refreshing: Promise<Session | null> | null = null;

function load(): Session | null {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const s = JSON.parse(raw) as Session;
    if (!s.access_token || !s.refresh_token || !s.user?.id) return null;
    return s;
  } catch {
    return null;
  }
}

function save(s: Session | null) {
  session = s;
  try {
    if (s) localStorage.setItem(STORAGE_KEY, JSON.stringify(s));
    else localStorage.removeItem(STORAGE_KEY);
  } catch {
    /* storage unavailable: session lives in memory only */
  }
  listeners.forEach((fn) => fn(s));
}

// Another tab signed in/out: follow it.
window.addEventListener('storage', (e) => {
  if (e.key !== STORAGE_KEY) return;
  const next = load();
  if ((next?.user.id ?? null) !== (session?.user.id ?? null)) {
    session = next;
    listeners.forEach((fn) => fn(next));
  } else {
    session = next;
  }
});

export function onAuthChange(fn: Listener): () => void {
  listeners.add(fn);
  return () => listeners.delete(fn);
}

export function currentSession(): Session | null {
  return session;
}

function toSession(d: any): Session {
  const expiresAt = d.expires_at ?? Math.floor(Date.now() / 1000) + Number(d.expires_in ?? 3600);
  return {
    access_token: d.access_token,
    refresh_token: d.refresh_token,
    expires_at: expiresAt,
    user: { id: d.user?.id, email: d.user?.email },
  };
}

async function authFetch(path: string, init: RequestInit & { token?: string } = {}) {
  const headers: Record<string, string> = { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' };
  if (init.token) headers.Authorization = `Bearer ${init.token}`;
  let res: Response;
  try {
    res = await fetch(`${SUPABASE_URL}/auth/v1${path}`, { ...init, headers });
  } catch {
    throw new ApiError('network', 'We could not reach the server. Check your connection and try again.');
  }
  const text = await res.text();
  let data: any = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = null; }
  if (!res.ok) {
    const code = data?.error_code || data?.code || data?.error || 'auth_error';
    const raw = data?.msg || data?.error_description || data?.message || 'Something went wrong.';
    throw new ApiError(String(code), friendlyAuthMessage(String(code), String(raw)), res.status);
  }
  return data;
}

function friendlyAuthMessage(code: string, raw: string): string {
  const c = code.toLowerCase();
  if (c.includes('invalid_credentials') || c === 'invalid_grant' || /invalid login/i.test(raw)) return 'That email and password do not match.';
  if (c.includes('email_not_confirmed')) return 'Please confirm your email address first.';
  if (c.includes('over_request_rate_limit') || c.includes('over_email_send_rate_limit') || /rate limit/i.test(raw)) return 'Too many attempts. Please wait a few minutes and try again.';
  if (c.includes('weak_password')) return raw;
  if (c.includes('same_password')) return 'Choose a password you have not used before.';
  return raw;
}

export async function signIn(email: string, password: string): Promise<Session> {
  const d = await authFetch('/token?grant_type=password', { method: 'POST', body: JSON.stringify({ email, password }) });
  const s = toSession(d);
  save(s);
  return s;
}

/** Use a session handed over by an auth email link (#access_token=...). */
export function adoptSessionFromHash(hash: string): { session: Session | null; type: string | null; error: string | null } {
  const p = new URLSearchParams(hash.replace(/^#/, ''));
  const error = p.get('error_description') || p.get('error');
  if (error) return { session: null, type: p.get('type'), error };
  const access = p.get('access_token');
  const refresh = p.get('refresh_token');
  if (!access || !refresh) return { session: null, type: p.get('type'), error: null };
  // user id/email are read from the JWT payload; the server re-verifies the token on every call.
  let payload: any = {};
  try { payload = JSON.parse(atob(access.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))); } catch { /* ignore */ }
  const s: Session = {
    access_token: access,
    refresh_token: refresh,
    expires_at: Number(p.get('expires_at')) || Math.floor(Date.now() / 1000) + Number(p.get('expires_in') || 3600),
    user: { id: payload.sub, email: payload.email },
  };
  save(s);
  return { session: s, type: p.get('type'), error: null };
}

async function refresh(): Promise<Session | null> {
  if (!session) return null;
  if (!refreshing) {
    const rt = session.refresh_token;
    refreshing = authFetch('/token?grant_type=refresh_token', { method: 'POST', body: JSON.stringify({ refresh_token: rt }) })
      .then((d) => { const s = toSession(d); save(s); return s; })
      .catch((e: ApiError) => {
        // Only a definitive rejection ends the session; network blips keep it.
        if (e.status >= 400 && e.status < 500) save(null);
        return null;
      })
      .finally(() => { refreshing = null; });
  }
  return refreshing;
}

export async function accessToken(): Promise<string | null> {
  if (!session) return null;
  if (session.expires_at - 60 < Date.now() / 1000) {
    const s = await refresh();
    return s?.access_token ?? null;
  }
  return session.access_token;
}

export async function signOut(): Promise<void> {
  const token = session?.access_token;
  save(null);
  if (token) {
    try { await authFetch('/logout?scope=local', { method: 'POST', token }); } catch { /* already signed out locally */ }
  }
}

export async function requestPasswordReset(email: string, redirectTo: string): Promise<void> {
  await authFetch(`/recover?redirect_to=${encodeURIComponent(redirectTo)}`, { method: 'POST', body: JSON.stringify({ email }) });
}

export async function updatePassword(password: string): Promise<void> {
  const token = await accessToken();
  if (!token) throw new ApiError('not_signed_in', 'Your reset link has expired. Please request a new one.');
  await authFetch('/user', { method: 'PUT', token, body: JSON.stringify({ password }) });
}

// Keep the session fresh while a tab is open.
setInterval(() => { if (session && session.expires_at - 300 < Date.now() / 1000) void refresh(); }, 60_000);

/** Call a Postgres function through PostgREST. Dashboard functions raise on business errors. */
export async function rpc<T = any>(fn: string, args: Record<string, unknown> = {}, opts: { anon?: boolean } = {}): Promise<T> {
  const doCall = async (token: string | null) => {
    const headers: Record<string, string> = { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' };
    if (token) headers.Authorization = `Bearer ${token}`;
    return fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, { method: 'POST', headers, body: JSON.stringify(args) });
  };
  let token = opts.anon ? null : await accessToken();
  let res: Response;
  try {
    res = await doCall(token);
    if (res.status === 401 && token) {
      const s = await refresh();
      token = s?.access_token ?? null;
      res = await doCall(token);
    }
  } catch {
    throw new ApiError('network', 'We could not reach the server. Check your connection and try again.');
  }
  const text = await res.text();
  let data: any = null;
  try { data = text ? JSON.parse(text) : null; } catch { data = null; }
  if (!res.ok) {
    // P0001 business errors: message = code, details = human-readable text
    if (data?.code === 'P0001') throw new ApiError(String(data.message), String(data.details || data.message), res.status);
    if (res.status === 401 || data?.code === '42501' || data?.code === 'PGRST301') {
      throw new ApiError('not_signed_in', 'Your session has ended. Please sign in again.', res.status);
    }
    throw new ApiError(String(data?.code ?? 'server_error'), 'Something went wrong on our side. Please try again.', res.status);
  }
  return data as T;
}

export async function callFunction<T = any>(name: string, body: unknown): Promise<{ status: number; data: T }> {
  let res: Response;
  try {
    res = await fetch(`${SUPABASE_URL}/functions/v1/${name}`, {
      method: 'POST',
      headers: { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
  } catch {
    throw new ApiError('network', 'We could not reach the server. Check your connection and try again.');
  }
  let data: any = null;
  try { data = await res.json(); } catch { data = null; }
  return { status: res.status, data };
}

export function publicStorageUrl(bucket: string, path: string): string {
  // Site-relative static media (committed under web/public), e.g. /gallery/sofia-mua/look-1.mp4
  if (path.startsWith('/')) return path;
  return `${SUPABASE_URL}/storage/v1/object/public/${bucket}/${path.split('/').map(encodeURIComponent).join('/')}`;
}

export async function uploadFile(bucket: string, path: string, file: File): Promise<void> {
  const token = await accessToken();
  if (!token) throw new ApiError('not_signed_in', 'Please sign in again.');
  let res: Response;
  try {
    res = await fetch(`${SUPABASE_URL}/storage/v1/object/${bucket}/${path}`, {
      method: 'POST',
      headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${token}`, 'Content-Type': file.type || 'application/octet-stream', 'x-upsert': 'false', 'cache-control': '31536000' },
      body: file,
    });
  } catch {
    throw new ApiError('network', 'Upload failed. Check your connection and try again.');
  }
  if (!res.ok) {
    let d: any = null;
    try { d = await res.json(); } catch { /* */ }
    const msg = String(d?.message || d?.error || 'Upload failed.');
    throw new ApiError('upload_failed', /size/i.test(msg) ? 'That file is too large (max 50 MB).' : /mime|type/i.test(msg) ? 'Use a JPG, PNG, WebP or MP4 file.' : msg, res.status);
  }
}

export async function removeFile(bucket: string, path: string): Promise<void> {
  const token = await accessToken();
  if (!token) return;
  try {
    await fetch(`${SUPABASE_URL}/storage/v1/object/${bucket}`, {
      method: 'DELETE',
      headers: { apikey: SUPABASE_KEY, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefixes: [path] }),
    });
  } catch { /* the DB row is already gone; orphaned file is harmless */ }
}
