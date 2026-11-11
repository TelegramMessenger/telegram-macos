import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { runWidget } from '../../../third-party/widget-sandbox/packages/core/scripts/sandbox-node.ts';

const html = fs.readFileSync(fileURLToPath(new URL('./fixtures/review.html', import.meta.url)), 'utf8');
for (const theme of ['light', 'dark'] as const) {
  const result = await runWidget(html, {
    theme,
    storage: { local: { 'review-count': '41' } },
    data: { chatData: 'initial', publicData: 'shared' },
    script: [
      { probe: "(document.getElementById('count').click(), n)" },
      { probe: "(document.getElementById('add').click(), document.getElementById('add').click(), rows.children.length)" },
      { probe: "(document.getElementById('remove').click(), rows.children.length)" },
      { probe: "(document.getElementById('anchor').click(), edge)" },
      { probe: "(document.getElementById('copy').click(), 'synthetic')" },
      { data: { chatData: 'updated', publicData: 'new-shared' } },
      { probe: "document.getElementById('status').textContent" },
      { theme: theme === 'light' ? 'dark' : 'light' },
      { probe: "document.getElementById('status').textContent" },
    ],
  });
  assert.deepEqual(result.probes.slice(0, 5), ['42', '2', '1', 'bottom', 'synthetic']);
  assert.match(result.probes[5], /chat updated \/ public new-shared/);
  assert.ok(result.probes[6].includes(theme === 'light' ? 'dark' : 'light'));
  assert.equal(result.resizeAnchor, 'bottom');
  assert.deepEqual(result.copiedTexts, []);
  assert.equal(result.logs.filter(log => log.level === 'error').length, 0, JSON.stringify(result.logs));
  assert.ok(result.storageCommits.some(commit => commit.local?.['review-count'] === '42'));
  const reset = await runWidget(html, {
    storage: { local: { 'review-count': '42' } },
    script: [{ probe: "(document.getElementById('reset').click(), localStorage.getItem('review-count'))" }],
  });
  assert.deepEqual(reset.probes, ['0']);
  console.log(`PASS ${theme}: counter, storage preload/commit/reset, resize anchor, rows, data/theme updates, denied synthetic clipboard`);
}
