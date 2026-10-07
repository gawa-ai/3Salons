// Rasterises the brand SVGs with headless Chromium (transparent PNG exports + a preview sheet).
// Usage: NODE_PATH=/opt/npm-tools/node_modules node brand/render.cjs
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const dir = path.join(__dirname, 'svg');
const out = path.join(__dirname, 'png');
fs.mkdirSync(out, { recursive: true });

const exportsList = [
  ['shahina-ahmed-lockup.svg', 1600], ['shahina-ahmed-lockup-light.svg', 1600],
  ['shahina-ahmed-wordmark.svg', 1200], ['shahina-ahmed-wordmark-light.svg', 1200],
  ['sa-monogram.svg', 1024], ['sa-monogram-light.svg', 1024], ['sa-monogram-filled.svg', 1024],
  ['sa-monogram-filled.svg', 512, 'apple-touch-icon-512.png'], ['sa-monogram-filled.svg', 180, 'apple-touch-icon.png'],
  ['sa-monogram-filled.svg', 32, 'favicon-32.png'],
];

(async () => {
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM || '/opt/pw-browsers/chromium' }).catch(() => chromium.launch());
  const page = await browser.newPage();
  for (const [file, width, name] of exportsList) {
    const svg = fs.readFileSync(path.join(dir, file), 'utf8');
    const m = svg.match(/viewBox="0 0 ([\d.]+) ([\d.]+)"/);
    const h = Math.round(width * Number(m[2]) / Number(m[1]));
    await page.setViewportSize({ width, height: h });
    await page.setContent(`<html><body style="margin:0;background:transparent">${svg.replace(/width="[^"]+" height="[^"]+"/, `width="${width}" height="${h}"`)}</body></html>`);
    await page.screenshot({ path: path.join(out, name || file.replace('.svg', '.png')), omitBackground: true, clip: { x: 0, y: 0, width, height: h } });
  }
  // preview sheet
  const tile = (f, bg, w) => `<div style="background:${bg};padding:40px;display:flex;align-items:center;justify-content:center">${fs.readFileSync(path.join(dir, f), 'utf8').replace(/width="[^"]+" height="[^"]+"/, `width="${w}"`)}</div>`;
  await page.setViewportSize({ width: 1400, height: 1100 });
  await page.setContent(`<html><body style="margin:0;display:grid;grid-template-columns:1fr 1fr;gap:0">
    ${tile('shahina-ahmed-lockup.svg', '#F7F2EA', 560)}${tile('shahina-ahmed-lockup-light.svg', '#1F1B18', 560)}
    ${tile('shahina-ahmed-wordmark.svg', '#FFFFFF', 340)}${tile('shahina-ahmed-wordmark-light.svg', '#2A2420', 340)}
    ${tile('sa-monogram.svg', '#F7F2EA', 200)}${tile('sa-monogram-filled.svg', '#EAE2D7', 200)}
    <div style="background:#fff;padding:20px;display:flex;gap:24px;align-items:center">${['favicon.svg'].map(f => fs.readFileSync(path.join(dir, f), 'utf8').replace(/width="[^"]+" height="[^"]+"/, 'width="32" height="32"')).join('')}
      ${fs.readFileSync(path.join(dir, 'favicon.svg'), 'utf8').replace(/width="[^"]+" height="[^"]+"/, 'width="16" height="16"')}
      ${fs.readFileSync(path.join(dir, 'sa-monogram-filled.svg'), 'utf8').replace(/width="[^"]+" height="[^"]+"/, 'width="64" height="64"')}</div>
  </body></html>`);
  await page.screenshot({ path: path.join(__dirname, 'preview-sheet.png'), fullPage: true });

  // Social share image (1200x630): lockup inside the arch, brand only, no claims.
  const lockup = fs.readFileSync(path.join(dir, 'shahina-ahmed-lockup.svg'), 'utf8').replace(/width="[^"]+" height="[^"]+"/, 'width="470"');
  const mono = fs.readFileSync(path.join(dir, 'sa-monogram.svg'), 'utf8').replace(/width="[^"]+" height="[^"]+"/, 'width="120" height="120"');
  await page.setViewportSize({ width: 1200, height: 630 });
  await page.setContent(`<html><body style="margin:0;width:1200px;height:630px;background:#F7F2EA;display:flex;align-items:center;justify-content:center;position:relative;overflow:hidden">
    <div style="position:absolute;width:640px;height:700px;top:50px;border:1.5px solid #C9A97F;border-radius:320px 320px 0 0"></div>
    <div style="position:absolute;width:608px;height:700px;top:66px;border:1px solid rgba(126,94,63,.35);border-radius:304px 304px 0 0"></div>
    <div style="position:relative;top:30px;display:flex;flex-direction:column;align-items:center;gap:34px">${mono}${lockup}</div>
  </body></html>`);
  await page.screenshot({ path: path.join(out, 'og-image.png'), clip: { x: 0, y: 0, width: 1200, height: 630 } });
  await browser.close();
  console.log('rendered');
})();
