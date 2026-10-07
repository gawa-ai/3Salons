// End-to-end UI test: real frontend build + real SQL (local Postgres) behind a mock HTTP layer.
// Usage: node tests/e2e/run.cjs   (expects local Postgres from tests/db/run.sh)
const { chromium } = require('playwright');
const { spawn, execFileSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const ROOT = path.resolve(__dirname, '../..');
const SHOTS = path.join(ROOT, 'docs/screenshots');
const PSQLA = ['-h', '/var/tmp/bospg', '-p', '55432', '-U', 'postgres', '-X', '-q', '-At'];
const BASE = 'http://localhost:4173';
fs.mkdirSync(SHOTS, { recursive: true });

let passed = 0; const results = [];
function check(ok, name, info) {
  results.push(`${ok ? 'PASS' : 'FAIL'}  ${name}${ok || info === undefined ? '' : ' :: ' + String(info).slice(0, 300)}`);
  console.log(results[results.length - 1]);
  if (!ok) throw new Error('E2E failure: ' + name);
  passed++;
}
const sql = (s, db = 'e2edb') => execFileSync('psql', [...PSQLA, '-d', db], { input: s }).toString().trim();

async function main() {
  // fresh database with migrations only (like production, no fixtures)
  execFileSync('psql', [...PSQLA, '-d', 'postgres'], { input: 'drop database if exists e2edb; create database e2edb;' });
  execFileSync('psql', [...PSQLA, '-d', 'e2edb', '-f', path.join(ROOT, 'tests/db/00_supabase_shim.sql')]);
  for (const f of fs.readdirSync(path.join(ROOT, 'supabase/migrations')).sort()) execFileSync('psql', [...PSQLA, '-d', 'e2edb', '-v', 'ON_ERROR_STOP=1', '-f', path.join(ROOT, 'supabase/migrations', f)]);

  execFileSync('node', ['build.mjs'], { cwd: path.join(ROOT, 'web'), env: { ...process.env, SUPABASE_URL: 'http://localhost:54321', SUPABASE_PUBLISHABLE_KEY: 'sb_publishable_localtest' } });
  const mock = spawn('node', [path.join(__dirname, 'mock-supabase.mjs')], { env: { ...process.env, PGDATABASE: 'e2edb' }, stdio: 'inherit' });
  const stat = spawn('node', [path.join(__dirname, 'static-server.mjs'), path.join(ROOT, 'web/dist'), '4173'], { stdio: 'inherit' });
  await new Promise((r) => setTimeout(r, 1200));

  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' }).catch(() => chromium.launch());
  const problems = [];
  const newPage = async (vp = { width: 1440, height: 900 }) => {
    const ctx = await browser.newContext({ viewport: vp, deviceScaleFactor: 1, reducedMotion: 'reduce' });
    const page = await ctx.newPage();
    page.on('console', (m) => { if (m.type() === 'error') problems.push(`[console] ${m.text()}`); });
    page.on('pageerror', (e) => problems.push(`[pageerror] ${e.message}`));
    await page.addInitScript(() => document.addEventListener('securitypolicyviolation', (e) => console.error(`CSP violation: ${e.violatedDirective} ${e.blockedURI}`)));
    return { ctx, page };
  };
  const shot = (page, name, full = true) => page.screenshot({ path: path.join(SHOTS, `${name}.png`), fullPage: full });

  try {
    // ------------------------------------------------------------------ public site
    let { ctx, page } = await newPage();
    await page.goto(BASE + '/');
    await page.waitForSelector('.pro-card');
    check((await page.locator('.pro-card').count()) === 4, 'P1 home lists 4 professionals (Shahina first)');
    check(await page.locator('text=Preview site.').isVisible(), 'P2 preview notice shown while booking_mode = preview');
    check(await page.locator('text=Opening hours will be published soon').isVisible(), 'P3 unconfirmed hours are not published as fact');
    await page.waitForTimeout(400);
    await shot(page, 'desktop-home');
    await page.click('#tab-shirin-jal');
    check(await page.locator('.menu-name', { hasText: 'Party Hijab' }).isVisible(), 'P4 service tabs switch artist');
    await page.goto(BASE + '/artists/mi-hijabby-sabiha');
    await page.waitForSelector('h1:has-text("Mi Hijabby Sabiha")');
    await shot(page, 'desktop-artist-sabiha');

    // booking flow
    await page.goto(BASE + '/book');
    await page.waitForSelector('.choice-pro');
    await shot(page, 'desktop-book-1-artist', false);
    await page.click('.choice-pro:has-text("Sofia MUA")');
    await page.waitForSelector('.choice-service');
    await shot(page, 'desktop-book-2-service', false);
    await page.click('.choice-service:has-text("Party Makeup")');
    await page.waitForSelector('.cal-day.has-slots');
    // pick the 4th open day (beyond minimum notice)
    await page.locator('.cal-day.has-slots').nth(3).click();
    await page.waitForSelector('.slot');
    await shot(page, 'desktop-book-3-time', false);
    const slotLabel = (await page.locator('.slot').first().textContent()).trim();
    await page.locator('.slot').first().click();
    await page.waitForSelector('input[name=name]');
    await page.fill('input[name=name]', 'Amira Khan');
    await page.fill('input[name=phone]', '07700 900111');
    await page.fill('input[name=email]', 'amira@example.com');
    await page.fill('textarea[name=note]', 'Soft glam for a mehndi');
    await shot(page, 'desktop-book-4-details', false);
    await page.click('button:has-text("Review booking")');
    await page.waitForSelector('text=Check and send');
    await shot(page, 'desktop-book-5-review', false);
    await page.click('button:has-text("Send booking request")');
    await page.waitForSelector('text=Your request has been sent');
    const ref = (await page.locator('.review .ref').textContent()).trim();
    check(/^[A-Z2-9]{6}$/.test(ref), 'P5 booking request accepted with a reference', ref);
    check(await page.locator('.badge-pending').isVisible(), 'P6 confirmation shows "Awaiting confirmation" (provisional)');
    await shot(page, 'desktop-book-6-done', false);
    const manageHref = await page.locator('a:has-text("Open my booking")').getAttribute('href');
    check(sql(`select status from app.bookings where ref = '${ref}'`) === 'pending', 'P7 booking persisted as pending in the database');

    // a second customer tries the same slot via the API directly -> refused
    const sofiaSvc = sql(`select v.id from app.services v join app.professionals p on p.id=v.professional_id where p.slug='sofia-mua' and v.name='Party Makeup'`);
    const bookedDate = sql(`select to_char(starts_at at time zone 'Europe/London','YYYY-MM-DD')||'|'||to_char(starts_at at time zone 'Europe/London','HH24:MI') from app.bookings where ref='${ref}'`);
    const [bd, bt] = bookedDate.split('|');
    const clash = await page.evaluate(async ([svc, d, t]) => {
      const r = await fetch('http://localhost:54321/rest/v1/rpc/salon_public_book', { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: 'x' },
        body: JSON.stringify({ p_salon: 'shahina-ahmed', p_payload: { professional: 'sofia-mua', service: svc, date: d, time: t, name: 'Second Person', phone: '07700900222', idempotency_key: 'e2e-clash-000000000001' } }) });
      return r.json();
    }, [sofiaSvc, bd, bt]);
    check(clash.error === 'slot_taken', 'P8 same slot cannot be booked twice', JSON.stringify(clash));

    // Shirin booking (should never be visible to Sofia)
    const shirinSvc = sql(`select v.id from app.services v join app.professionals p on p.id=v.professional_id where p.slug='shirin-jal' and v.name='Party Hair'`);
    const shirinBk = await page.evaluate(async ([svc, d]) => {
      const r = await fetch('http://localhost:54321/rest/v1/rpc/salon_public_book', { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: 'x' },
        body: JSON.stringify({ p_salon: 'shahina-ahmed', p_payload: { professional: 'shirin-jal', service: svc, date: d, time: '15:00', name: 'Zainab Shirin-Client', phone: '07700900333', idempotency_key: 'e2e-shirin-0000000001' } }) });
      return r.json();
    }, [shirinSvc, bd]);
    check(shirinBk.ok === true, 'P9 booking for Shirin created', JSON.stringify(shirinBk));

    await page.goto(BASE + manageHref);
    await page.waitForSelector(`text=${ref}`);
    check(await page.locator('text=has not confirmed this booking yet').isVisible(), 'P10 private manage link shows provisional status');
    await shot(page, 'desktop-manage', false);

    await page.goto(BASE + '/bridal?artist=shirin-jal');
    await page.waitForSelector('form.enquiry-form');
    await page.fill('input[name=name]', 'Hana Bride');
    await page.fill('input[name=phone]', '07700 900666');
    await page.fill('input[name=services_wanted]', 'Bridal hair, makeup and hijab');
    await shot(page, 'desktop-bridal', false);
    await page.click('button:has-text("Send enquiry")');
    await page.waitForSelector('text=Thank you, your enquiry has been sent');
    check(true, 'P11 bridal enquiry sent');
    await ctx.close();

    // ------------------------------------------------------------------ owner provisioning + master dashboard
    const ownerCode = sql(`select app.create_owner_invitation('shahina-ahmed', 'owner@salon.test')`).match(/([A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4})/)[1];
    ({ ctx, page } = await newPage());
    await page.goto(BASE + '/studio');
    await page.waitForURL('**/signin');
    check(true, 'O1 signed-out visitor is redirected away from the studio');
    await shot(page, 'desktop-signin', false);
    await page.goto(BASE + '/join');
    await page.fill('input[name=code]', ownerCode);
    await page.fill('input[name=name]', 'Shahina Ahmed');
    await page.fill('input[name=email]', 'owner@salon.test');
    await page.fill('input[name=password]', 'Owner-password-123');
    await page.click('button:has-text("Create my account")');
    await page.waitForURL('**/studio');
    await page.waitForSelector('.tiles');
    check(await page.locator('.scope-btn', { hasText: 'All professionals' }).isVisible(), 'O2 owner sees the All professionals selector');
    check((await page.locator('.blist .brow').count()) === 2, 'O3 owner "Needs confirming" shows both pending requests');
    await page.waitForTimeout(300);
    await shot(page, 'desktop-owner-overview');
    await page.goto(BASE + '/studio/calendar');
    await page.waitForSelector('.cgrid');
    await page.fill('input.cal-date', bd); await page.dispatchEvent('input.cal-date', 'change');
    await page.waitForSelector('.event');
    check((await page.locator('.cgrid-head').count()) === 4, 'O4 owner day calendar has one column per professional');
    await shot(page, 'desktop-owner-calendar-day', false);
    await page.click('.seg-btn:has-text("Week")');
    await page.waitForSelector('.cgrid-week');
    await shot(page, 'desktop-owner-calendar-week', false);
    await page.goto(BASE + '/studio/bookings');
    await page.waitForSelector('.brow');
    await shot(page, 'desktop-owner-bookings', false);
    await page.goto(BASE + '/studio/services');
    await page.waitForSelector('.table');
    await shot(page, 'desktop-owner-services');
    await page.goto(BASE + '/studio/availability');
    await page.waitForSelector('.hours-edit');
    await shot(page, 'desktop-owner-availability');
    await page.goto(BASE + '/studio/enquiries');
    await page.waitForSelector('.enq');
    await shot(page, 'desktop-owner-enquiries', false);
    await page.goto(BASE + '/studio/messages');
    await page.waitForSelector('.msg');
    check(await page.locator('text=Not connected').first().isVisible(), 'O5 messages page is honest: SMS not connected');
    await shot(page, 'desktop-owner-messages', false);
    await page.goto(BASE + '/studio/reports');
    await page.waitForSelector('.table');
    await shot(page, 'desktop-owner-reports', false);

    // invite Sofia
    await page.goto(BASE + '/studio/team');
    await page.waitForSelector('.team-card');
    await shot(page, 'desktop-owner-team', false);
    await page.locator('.team-card:has-text("Sofia MUA") button:has-text("Invite")').click();
    await page.fill('input[name=email]', 'sofia@salon.test');
    await page.click('button:has-text("Create invitation")');
    await page.waitForSelector('.code-box');
    const sofiaCode = (await page.locator('.code-box').textContent()).trim();
    check(/^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$/.test(sofiaCode), 'O6 owner creates a one-time staff invitation code', sofiaCode);
    check(sql(`select count(*) from app.invitations where code_hash like '%${sofiaCode.replace(/-/g, '')}%'`) === '0', 'O7 code is not stored in plain text');
    await page.click('button:has-text("Done")');
    await page.goto(BASE + '/studio/settings');
    await page.waitForSelector('select[name=mode]');
    await shot(page, 'desktop-owner-settings');
    await page.goto(BASE + '/studio/audit');
    await page.waitForSelector('.table');
    await shot(page, 'desktop-owner-audit', false);
    // sign out clears session
    await page.goto(BASE + '/studio/account');
    await page.click('.studio-content button:has-text("Sign out")');
    await page.waitForURL('**/signin');
    const leftover = await page.evaluate(() => localStorage.getItem('sa-salon-auth-v1'));
    check(leftover === null, 'O8 sign-out removes the stored session');
    await ctx.close();

    // ------------------------------------------------------------------ Sofia: scoped staff dashboard
    ({ ctx, page } = await newPage());
    await page.goto(BASE + '/join');
    await page.fill('input[name=code]', sofiaCode);
    await page.fill('input[name=name]', 'Sofia MUA');
    await page.fill('input[name=email]', 'sofia@salon.test');
    await page.fill('input[name=password]', 'Sofia-password-123');
    await page.click('button:has-text("Create my account")');
    await page.waitForURL('**/studio');
    await page.waitForSelector('.tiles');
    check(!(await page.locator('.scope-btn', { hasText: 'All professionals' }).count()), 'S1 staff has no All professionals selector');
    check(!(await page.locator('a.side-link[href="/studio/team"]').count()), 'S2 staff has no owner administration links');
    const body = await page.locator('main').innerText();
    check(body.includes('Amira Khan') && !body.includes('Zainab Shirin-Client'), 'S3 Sofia sees her client, never Shirin\'s');
    await shot(page, 'desktop-staff-overview');
    await page.locator('.brow:has-text("Amira Khan") .brow-actions button:has-text("Confirm")').click();
    await page.waitForSelector('text=Confirmed Amira Khan');
    check(sql(`select status from app.bookings where ref = '${ref}'`) === 'confirmed', 'S4 Sofia confirms her request (persisted)');
    await page.goto(BASE + '/studio/bookings?view=all');
    await page.waitForSelector('.brow');
    const list = await page.locator('main').innerText();
    check(!list.includes('Zainab'), 'S5 Sofia\'s bookings list contains no other profile\'s bookings');
    await page.goto(BASE + '/studio/team');
    await page.waitForURL('**/studio');
    check(true, 'S6 staff opening an owner page is sent back to their overview');
    // direct API probe with Sofia's token for Shirin's data (expected 400s are not app errors)
    const beforeProbe = problems.length;
    const probe = await page.evaluate(async (shirinPro) => {
      const s = JSON.parse(localStorage.getItem('sa-salon-auth-v1'));
      const call = (fn, args) => fetch(`http://localhost:54321/rest/v1/rpc/${fn}`, { method: 'POST', headers: { 'Content-Type': 'application/json', apikey: 'x', Authorization: `Bearer ${s.access_token}` }, body: JSON.stringify(args) }).then((r) => r.json());
      const me = await call('salon_me', {});
      const salon = me.memberships[0].salon.id;
      return { widen: await call('salon_dash_bookings', { p_salon: salon, p_professional: shirinPro }), owner: await call('salon_owner_team', { p_salon: salon }) };
    }, sql(`select id from app.professionals where slug='shirin-jal'`));
    await page.waitForTimeout(300); problems.splice(beforeProbe);
    check(probe.widen.message === 'forbidden' && probe.owner.message === 'forbidden', 'S7 Sofia\'s token cannot widen scope or call owner functions', JSON.stringify(probe));
    await page.goto(BASE + '/studio/calendar');
    await page.waitForSelector('.cgrid');
    await shot(page, 'desktop-staff-calendar', false);
    await ctx.close();

    // ------------------------------------------------------------------ responsive screenshots
    for (const [w, hgt, tag] of [[390, 844, 'mobile'], [768, 1024, 'tablet']]) {
      ({ ctx, page } = await newPage({ width: w, height: hgt }));
      await page.goto(BASE + '/'); await page.waitForSelector('.pro-card'); await page.waitForTimeout(300);
      await shot(page, `${tag}-home`);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
      check(overflow <= 0, `R ${tag}: home has no horizontal overflow`, overflow);
      if (tag === 'mobile') { await page.click('.nav-toggle'); await shot(page, 'mobile-menu', false); }
      await page.goto(BASE + '/book?artist=shirin-jal'); await page.waitForSelector('.choice-service');
      await page.click('.choice-service:has-text("Party Hijab")'); await page.waitForSelector('.cal-day.has-slots');
      await page.locator('.cal-day.has-slots').nth(2).click(); await page.waitForSelector('.slot');
      await shot(page, `${tag}-book-time`);
      const o2 = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
      check(o2 <= 0, `R ${tag}: booking has no horizontal overflow`, o2);
      await page.goto(BASE + '/signin'); await page.fill('input[name=email]', 'owner@salon.test'); await page.fill('input[name=password]', 'Owner-password-123');
      await page.click('button[type=submit]'); await page.waitForSelector('.tiles');
      await shot(page, `${tag}-owner-overview`);
      const o3 = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth);
      check(o3 <= 0, `R ${tag}: studio has no horizontal overflow`, o3);
      await page.goto(BASE + '/studio/calendar'); await page.waitForSelector(tag === 'mobile' ? '.agenda-days, .empty' : '.cgrid');
      await shot(page, `${tag}-owner-calendar`);
      await ctx.close();
    }
    const real = problems.filter((p) => !/favicon/.test(p));
    check(real.length === 0, 'Z no console errors, page errors or CSP violations', real.join('\n'));
  } finally {
    await browser.close();
    mock.kill(); stat.kill();
    fs.writeFileSync(path.join(ROOT, 'docs/e2e-results.txt'), results.join('\n') + `\n\n${passed} checks passed\n`);
  }
  console.log(`\nE2E: ${passed} checks passed`);
}
main().catch((e) => { console.error(e); process.exit(1); });
