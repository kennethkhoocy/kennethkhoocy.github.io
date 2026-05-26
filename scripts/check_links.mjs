import { readdir, readFile } from 'node:fs/promises';
import { join, relative } from 'node:path';

const DIST = new URL('../dist/', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');

async function walk(dir, files = []) {
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) await walk(p, files);
    else if (entry.name.endsWith('.html')) files.push(p);
  }
  return files;
}

const htmlFiles = await walk(DIST);
const issues = [];
const linkRegex = /href="([^"#?]+)"/g;

for (const f of htmlFiles) {
  const text = await readFile(f, 'utf8');
  let m;
  while ((m = linkRegex.exec(text))) {
    const href = m[1];
    if (href.startsWith('http') || href.startsWith('mailto:') || href.startsWith('//')) continue;
    if (href === '/') continue;
    const target = href.startsWith('/') ? join(DIST, href) : join(f, '..', href);
    const normalized = target.endsWith('/') ? join(target, 'index.html') : target;
    try {
      await readFile(normalized);
    } catch {
      try {
        await readFile(join(target, 'index.html'));
      } catch {
        issues.push({ source: relative(DIST, f), href, expected: relative(DIST, normalized) });
      }
    }
  }
}

if (issues.length) {
  console.error(`Found ${issues.length} broken internal link(s):`);
  for (const i of issues) console.error(`  in ${i.source}: href="${i.href}" -> ${i.expected}`);
  process.exit(1);
} else {
  console.log(`All internal links resolved across ${htmlFiles.length} HTML files.`);
}
