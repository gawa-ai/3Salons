// Serves web/dist like Netlify: SPA fallback + the same security headers (CSP adjusted
// only to point connect-src at the local mock API).
import http from 'node:http';
import { readFileSync, existsSync, statSync } from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.argv[2] || 'web/dist');
const PORT = Number(process.argv[3] || 4173);
const API = process.argv[4] || 'http://localhost:54321';
const TYPES = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.webp': 'image/webp', '.woff': 'font/woff', '.txt': 'text/plain', '.json': 'application/json' };
const CSP = `default-src 'self'; script-src 'self'; style-src 'self'; img-src 'self' data: blob: ${API}; media-src 'self' blob: ${API}; font-src 'self'; connect-src 'self' ${API}; frame-ancestors 'none'; base-uri 'self'; form-action 'self'; object-src 'none'`;

http.createServer((req, res) => {
  const u = new URL(req.url, 'http://x');
  let f = path.join(ROOT, decodeURIComponent(u.pathname));
  if (!f.startsWith(ROOT) || !existsSync(f) || statSync(f).isDirectory()) f = path.join(ROOT, 'index.html');
  res.writeHead(200, { 'Content-Type': TYPES[path.extname(f)] || 'application/octet-stream', 'Content-Security-Policy': CSP, 'X-Content-Type-Options': 'nosniff' });
  res.end(readFileSync(f));
}).listen(PORT, () => console.log(`static on :${PORT}`));
