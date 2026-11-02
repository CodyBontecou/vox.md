import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const root = new URL('../../', import.meta.url);
const html = await readFile(new URL('website/index.html', root), 'utf8');
const css = await readFile(new URL('website/geist.css', root), 'utf8');
const fixture = JSON.parse(await readFile(new URL('fixtures/app-store-reviews.json', import.meta.url), 'utf8'));
const section = html.match(/<section class="reviews-section[\s\S]*?<\/section>/)?.[0] ?? '';
const cards = [...section.matchAll(/<figure class="review-card[^"]*" data-review-id="([^"]+)">([\s\S]*?)<\/figure>/g)];
const normalize = value => value.replace(/\s+/g, ' ').trim();

test('three distinct App Store reviewers keep exact titles, quotes, attribution, dates and ratings', () => {
  assert.equal(cards.length, 3);
  assert.equal(new Set(cards.map(([, id]) => id)).size, 3);
  for (const [, id, card] of cards) {
    const source = fixture.reviews.find(review => review.id === id);
    assert.ok(source, id);
    const quoteHtml = card.match(/<blockquote>([\s\S]*?)<\/blockquote>/)?.[1] ?? '';
    const quote = normalize(quoteHtml.replace(/<[^>]+>/g, '')).replace(/^“|”$/g, '');
    assert.ok(quote && normalize(source.body).includes(quote), id);
    assert.ok(card.includes(`<h3>${source.title}</h3>`));
    assert.ok(card.includes(`<span class="review-author">${source.author}</span>`));
    assert.ok(card.includes(`datetime="${source.date}"`));
    assert.equal(source.rating, 5);
    assert.ok(card.includes('role="img" aria-label="5 out of 5 stars"'));
  }
  assert.ok(section.includes('Eric’s quote is an excerpt'));
  assert.ok(section.includes(`id${fixture.appId}?see-all=reviews`));
  assert.ok(html.indexOf(section) < html.indexOf('<section class="cta-section'));
  assert.doesNotMatch(section, /aggregateRating|<img|@/);
});

test('static review layout supports mobile and the shared light/dark Signal theme', () => {
  assert.ok(html.includes('href="geist.css"') || html.includes('href="/geist.css"'));
  assert.doesNotMatch(html, /href="\/?reviews\.css"/);
  const reviewRules = [...css.matchAll(/^\.review[^{]*\{[^}]*\}/gm)].map(([rule]) => rule).join('\n');
  assert.match(reviewRules, /\.review-grid \{[^}]*grid-template-columns: repeat\(auto-fit, minmax\(min\(100%, 300px\), 1fr\)\)/);
  assert.match(reviewRules, /var\(--/);
  assert.doesNotMatch(reviewRules, /animation:|transform:|#[0-9a-fA-F]{3,8}\b/);
  assert.match(css, /@media \(prefers-color-scheme: dark\)/);
});
