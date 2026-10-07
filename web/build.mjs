// Production build: bundles TypeScript + CSS with esbuild, fingerprints assets,
// copies /public and writes dist/index.html. No inline scripts or styles (strict CSP).
import { build } from 'esbuild';
import { cpSync, mkdirSync, rmSync, writeFileSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const env = (k, d) => process.env[k] || d;
const SUPABASE_URL = env('SUPABASE_URL', 'https://vqkrvbtndnnxpcemkuce.supabase.co');
// Publishable (public) key. It can only call what the database grants to `anon`.
const SUPABASE_KEY = env('SUPABASE_PUBLISHABLE_KEY', 'sb_publishable__0EaCw7l1NKRnmOXEKl2Gg_2_g0I1KD');
const SALON = env('SALON_SLUG', 'shahina-ahmed');
if (/service_role|sb_secret_/i.test(SUPABASE_KEY)) throw new Error('Refusing to build with a secret key.');

rmSync('dist', { recursive: true, force: true });
mkdirSync('dist/assets', { recursive: true });
cpSync('public', 'dist', { recursive: true });
const buildId = createHash('sha1').update(String(Date.now())).digest('hex').slice(0, 8);

const result = await build({
  entryPoints: { app: 'src/main.ts' },
  bundle: true, minify: true, sourcemap: false, format: 'esm', target: ['es2021'],
  outdir: 'dist/assets', entryNames: '[name]-[hash]', metafile: true, legalComments: 'none',
  external: ['/fonts/*', '/brand/*'],
  define: {
    __SUPABASE_URL__: JSON.stringify(SUPABASE_URL),
    __SUPABASE_PUBLISHABLE_KEY__: JSON.stringify(SUPABASE_KEY),
    __SALON_SLUG__: JSON.stringify(SALON),
    __BUILD_ID__: JSON.stringify(buildId),
  },
  logLevel: 'warning',
});
const outs = Object.keys(result.metafile.outputs);
const js = outs.find((o) => o.endsWith('.js')).replace('dist', '');
const css = outs.find((o) => o.endsWith('.css')).replace('dist', '');
const html = readFileSync('index.html', 'utf8').replace('%APP_JS%', js).replace('%APP_CSS%', css);
writeFileSync('dist/index.html', html);
console.log('built', js, css);
