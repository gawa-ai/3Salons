// Local stand-in for the Supabase HTTP APIs, backed by the REAL schema/functions in a
// throwaway local Postgres. Lets the real frontend run end-to-end offline:
//   POST /rest/v1/rpc/<fn>          -> executes public.<fn>(...) as anon/authenticated/service_role
//   POST /auth/v1/token             -> password + refresh grants (test users only)
//   POST /auth/v1/logout, /recover, PUT /auth/v1/user
//   POST /functions/v1/accept-invite -> same steps as the Edge Function
//   storage upload/delete/public read (policy checked with app.storage_can_write)
// TEST ONLY. Tokens are unsigned; never expose this server.
import http from 'node:http';
import { execFileSync } from 'node:child_process';
import { mkdirSync, writeFileSync, readFileSync, existsSync, rmSync } from 'node:fs';
import path from 'node:path';

const PORT = Number(process.env.MOCK_PORT || 54321);
const DB = process.env.PGDATABASE || 'salontest';
const PSQL = ['-h', process.env.PGHOST || '/var/tmp/bospg', '-p', process.env.PGPORT || '55432', '-U', 'postgres', '-d', DB, '-X', '-q', '-At', '-v', 'VERBOSITY=verbose', '-v', 'ON_ERROR_STOP=1'];
const STORE = path.resolve(process.env.MOCK_STORE || '/tmp/mock-storage');
const passwords = new Map(); // email -> password (test accounts)
rmSync(STORE, { recursive: true, force: true }); mkdirSync(STORE, { recursive: true });

const q = (s) => `'${String(s).replace(/'/g, "''")}'`;
function psql(sql) {
  try {
    return { out: execFileSync('psql', PSQL, { input: sql, stdio: ['pipe', 'pipe', 'pipe'] }).toString() };
  } catch (e) {
    return { err: e.stderr.toString() };
  }
}

// function signatures: name -> [{name, type}]
const sigs = {};
for (const line of psql(`select proname || '|' || coalesce(array_to_string(proargnames, ','), '') || '|' || coalesce(array_to_string(proargtypes::regtype[]::text[], ','), '') from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and proname like 'salon\\_%';`).out.trim().split('\n')) {
  const [name, names, types] = line.split('|');
  const ns = names ? names.split(',') : []; const ts = types ? types.split(',') : [];
  sigs[name] = ns.map((n, i) => ({ name: n, type: ts[i] }));
}

function b64url(o) { return Buffer.from(JSON.stringify(o)).toString('base64url'); }
function makeToken(user) {
  const exp = Math.floor(Date.now() / 1000) + 3600;
  return { access_token: `${b64url({ alg: 'none' })}.${b64url({ sub: user.id, email: user.email, role: 'authenticated', exp })}.x`, refresh_token: `r.${user.id}`, expires_in: 3600, expires_at: exp, token_type: 'bearer', user: { id: user.id, email: user.email } };
}
function userFromAuth(req) {
  const h = req.headers.authorization || '';
  const t = h.replace(/^Bearer /, '');
  if (!t || t.startsWith('sb_publishable')) return null;
  try { const p = JSON.parse(Buffer.from(t.split('.')[1], 'base64url').toString()); return p.exp > Date.now() / 1000 ? p : 'expired'; } catch { return null; }
}

function callRpc(fn, args, role, sub) {
  const sig = sigs[fn];
  if (!sig) return { status: 404, body: { code: 'PGRST202', message: `function ${fn} not found` } };
  const parts = [];
  for (const a of sig) {
    if (!(a.name in args)) continue;
    const v = args[a.name];
    if (v === null) { parts.push(`${a.name} => null::${a.type}`); continue; }
    if (a.type === 'jsonb') parts.push(`${a.name} => ${q(JSON.stringify(v))}::jsonb`);
    else if (a.type.endsWith('[]')) parts.push(`${a.name} => array(select jsonb_array_elements_text(${q(JSON.stringify(v))}::jsonb))::${a.type}`);
    else parts.push(`${a.name} => ${q(v)}::${a.type}`);
  }
  const claims = sub ? `select set_config('request.jwt.claims', ${q(JSON.stringify({ sub, role }))}, false);` : `select set_config('request.jwt.claims', '', false);`;
  const sql = `\\o /dev/null\nset role ${role};\n${claims}\nselect set_config('request.headers', '{"x-forwarded-for":"127.0.0.1"}', false);\n\\o\nselect public.${fn}(${parts.join(', ')})::text;\n`;
  const r = psql(sql);
  if (r.err) {
    const m = r.err.match(/ERROR:\s+([0-9A-Z]{5}): (.*)/);
    const d = r.err.match(/DETAIL:\s+(.*)/);
    if (m) return { status: m[1] === '42501' ? 401 : 400, body: { code: m[1], message: m[2].trim(), details: d ? d[1].trim() : null } };
    return { status: 500, body: { code: 'XX000', message: r.err } };
  }
  const out = r.out.trim();
  return { status: 200, body: out ? JSON.parse(out) : null };
}

function send(res, status, body, headers = {}) {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': '*', ...headers });
  res.end(body === undefined ? '' : JSON.stringify(body));
}

const server = http.createServer(async (req, res) => {
  if (req.method === 'OPTIONS') return send(res, 204);
  const url = new URL(req.url, `http://localhost:${PORT}`);
  const chunks = []; for await (const c of req) chunks.push(c);
  const raw = Buffer.concat(chunks);
  const json = () => { try { return JSON.parse(raw.toString() || '{}'); } catch { return {}; } };
  const p = url.pathname;

  if (p.startsWith('/rest/v1/rpc/')) {
    const u = userFromAuth(req);
    if (u === 'expired') return send(res, 401, { code: 'PGRST301', message: 'JWT expired' });
    const r = callRpc(p.slice('/rest/v1/rpc/'.length), json(), u ? 'authenticated' : 'anon', u?.sub);
    return send(res, r.status, r.body);
  }
  if (p === '/auth/v1/token') {
    const b = json();
    if (url.searchParams.get('grant_type') === 'password') {
      const email = String(b.email || '').toLowerCase();
      if (!passwords.has(email) || passwords.get(email) !== b.password) return send(res, 400, { code: 'invalid_credentials', msg: 'Invalid login credentials' });
      const id = psql(`select id from auth.users where lower(email) = ${q(email)};`).out.trim();
      psql(`update auth.users set last_sign_in_at = now() where id = ${q(id)};`);
      return send(res, 200, makeToken({ id, email }));
    }
    if (url.searchParams.get('grant_type') === 'refresh_token') {
      const id = String(b.refresh_token || '').replace(/^r\./, '');
      const email = psql(`select email from auth.users where id::text = ${q(id)};`).out.trim();
      if (!email) return send(res, 400, { code: 'refresh_token_not_found', msg: 'Invalid Refresh Token' });
      return send(res, 200, makeToken({ id, email }));
    }
  }
  if (p === '/auth/v1/logout') return send(res, 204);
  if (p === '/auth/v1/recover') return send(res, 200, {});
  if (p === '/auth/v1/user' && req.method === 'PUT') {
    const u = userFromAuth(req); if (!u || u === 'expired') return send(res, 401, { msg: 'not signed in' });
    passwords.set(u.email, json().password); return send(res, 200, { id: u.sub, email: u.email });
  }
  if (p === '/functions/v1/accept-invite') {
    const b = json();
    const email = String(b.email || '').trim().toLowerCase();
    if (String(b.password || '').length < 10) return send(res, 400, { ok: false, error: 'weak_password', message: 'Use a password of at least 10 characters.' });
    const chk = callRpc('salon_internal_invite_check', { p_code: b.code, p_email: email }, 'service_role');
    if (!chk.body?.ok) return send(res, 400, chk.body);
    if (psql(`select 1 from auth.users where lower(email) = ${q(email)};`).out.trim()) return send(res, 409, { ok: false, error: 'account_exists', message: 'An account with this email already exists. Sign in, then enter your invitation code.' });
    const id = psql(`insert into auth.users (email) values (${q(email)}) returning id;`).out.trim();
    const acc = callRpc('salon_internal_invite_accept', { p_code: b.code, p_user: id, p_email: email, p_name: b.name || '' }, 'service_role');
    if (!acc.body?.ok) { psql(`delete from auth.users where id = ${q(id)};`); return send(res, 400, acc.body); }
    passwords.set(email, b.password);
    return send(res, 200, { ok: true, role: acc.body.role });
  }
  if (p.startsWith('/storage/v1/object/public/')) {
    const f = path.join(STORE, decodeURIComponent(p.slice('/storage/v1/object/public/'.length)));
    if (!f.startsWith(STORE) || !existsSync(f)) return send(res, 404, { message: 'not found' });
    res.writeHead(200, { 'Content-Type': f.endsWith('.mp4') ? 'video/mp4' : 'image/' + (f.split('.').pop() === 'jpg' ? 'jpeg' : f.split('.').pop()), 'Access-Control-Allow-Origin': '*' });
    return res.end(readFileSync(f));
  }
  if (p.startsWith('/storage/v1/object/')) {
    const u = userFromAuth(req); if (!u || u === 'expired') return send(res, 401, { message: 'unauthorised' });
    const rest = decodeURIComponent(p.slice('/storage/v1/object/'.length));
    if (req.method === 'POST') {
      const [bucket, ...k] = rest.split('/'); const key = k.join('/');
      const allowed = psql(`set role authenticated; select set_config('request.jwt.claims', ${q(JSON.stringify({ sub: u.sub }))}, false); select app.storage_can_write(${q(key)});`).out.trim().split('\n').pop();
      if (allowed !== 't') return send(res, 403, { message: 'new row violates row-level security policy' });
      const f = path.join(STORE, bucket, key); mkdirSync(path.dirname(f), { recursive: true }); writeFileSync(f, raw);
      return send(res, 200, { Key: `${bucket}/${key}` });
    }
    if (req.method === 'DELETE') return send(res, 200, []);
  }
  send(res, 404, { message: 'mock: unknown route ' + p });
});

// expose test-account registration for the test runner
server.on('request', () => {});
export function addPassword(email, pw) { passwords.set(email.toLowerCase(), pw); }
server.listen(PORT, () => console.log(`mock supabase on :${PORT}`));
process.on('message', (m) => { if (m?.type === 'password') passwords.set(m.email.toLowerCase(), m.password); });
