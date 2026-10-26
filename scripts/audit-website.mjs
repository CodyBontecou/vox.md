#!/usr/bin/env node
// Run Lighthouse sequentially so concurrent browsers do not skew performance.
import { spawnSync } from 'node:child_process';
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const base = (process.argv[2] ?? 'https://vox.isolated.tech').replace(/\/$/, '');
const output = resolve(process.argv[3] ?? 'output/lighthouse');
const routes = ['/', '/docs/', '/docs/location/', '/blog/',
  '/blog/best-voice-to-text-keyboard-iphone/', '/privacy', '/terms', '/about', '/contact', '/developers'];
mkdirSync(output, { recursive: true });
const results = [];
let failed = false;
for (const device of ['mobile', 'desktop']) {
  for (const route of routes) {
    const report = resolve(output, `${device}-${route.replaceAll('/', '_')}`);
    const args = ['--yes', 'lighthouse@13.5.0', `${base}${route}`,
      '--chrome-flags=--headless --no-sandbox', '--output=json', '--output=html',
      `--output-path=${report}`, '--only-categories=performance,accessibility,best-practices,seo', '--quiet'];
    if (device === 'desktop') args.push('--preset=desktop');
    const run = spawnSync('npx', args, { encoding: 'utf8', timeout: 120000 });
    if (run.status !== 0) {
      console.error(device, route, run.stderr || run.error || 'Lighthouse failed');
      results.push({ device, route, error: 'Lighthouse failed' });
      failed = true;
    } else {
      const audit = JSON.parse(readFileSync(`${report}.report.json`, 'utf8'));
      const scores = Object.fromEntries(Object.entries(audit.categories)
        .map(([key, category]) => [key, Math.round(category.score * 100)]));
      const metrics = Object.fromEntries(['first-contentful-paint', 'largest-contentful-paint',
        'total-blocking-time', 'cumulative-layout-shift', 'speed-index']
        .map(key => [key, audit.audits[key].numericValue]));
      results.push({ device, route, scores, metrics, report: `${report}.report.html` });
      failed ||= Object.values(scores).some(score => score < 100);
      console.log(device, route, JSON.stringify(scores));
    }
    writeFileSync(resolve(output, 'summary.json'), JSON.stringify({
      lighthouseVersion: '13.5.0', base, auditedAt: new Date().toISOString(), results,
    }, null, 2) + '\n');
  }
}
process.exitCode = failed ? 1 : 0;
