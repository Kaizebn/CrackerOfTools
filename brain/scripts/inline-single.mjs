// Post-process the single-file build: inline favicon, apple-touch icon and the
// web app manifest (with its icons) as data URIs, then delete the sidecar files
// so dist-single/ holds ONE fully self-contained index.html.
import fs from 'node:fs';

const dir = 'dist-single';
let html = fs.readFileSync(`${dir}/index.html`, 'utf8');
const b64 = (f) => fs.readFileSync(`${dir}/${f}`).toString('base64');

const favSvg = `data:image/svg+xml;base64,${b64('favicon.svg')}`;
const apple = `data:image/png;base64,${b64('apple-touch-icon.png')}`;

const man = JSON.parse(fs.readFileSync(`${dir}/manifest.webmanifest`, 'utf8'));
man.icons = man.icons.map((ic) => ({ ...ic, src: `data:image/png;base64,${b64(ic.src)}` }));
const manData = `data:application/manifest+json;base64,${Buffer.from(JSON.stringify(man)).toString('base64')}`;

html = html
  .replace('href="favicon.svg"', `href="${favSvg}"`)
  .replace('href="apple-touch-icon.png"', `href="${apple}"`)
  .replace('href="manifest.webmanifest"', `href="${manData}"`);

fs.writeFileSync(`${dir}/index.html`, html);

for (const f of ['favicon.svg', 'apple-touch-icon.png', 'icon-192.png', 'icon-512.png', 'icon-512-maskable.png', 'manifest.webmanifest', 'sw.js']) {
  try { fs.unlinkSync(`${dir}/${f}`); } catch { /* ignore */ }
}
console.log(`Single file ready: ${dir}/index.html (${(fs.statSync(`${dir}/index.html`).size / 1024 / 1024).toFixed(2)} MB)`);
