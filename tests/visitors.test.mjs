import { test } from "node:test";
import assert from "node:assert/strict";
import { addVisitor, readVisitors } from "../netlify/functions/visitor-counter.mjs";

function fakeStore() {
  const m = new Map(); let n = 0;
  const put = (k, v, o = {}) => {
    const cur = m.get(k);
    if (o.onlyIfNew && cur) return { modified: false };
    if (o.onlyIfMatch && (!cur || cur.etag !== o.onlyIfMatch)) return { modified: false };
    const etag = String(++n); m.set(k, { v, etag }); return { modified: true, etag };
  };
  return {
    async get(k) { const c = m.get(k); return c ? JSON.parse(JSON.stringify(c.v)) : null; },
    async getWithMetadata(k) { const c = m.get(k); return c ? { data: JSON.parse(JSON.stringify(c.v)), etag: c.etag } : null; },
    async set(k, v, o) { return put(k, v, o); },
    async setJSON(k, v, o) { return put(k, JSON.parse(JSON.stringify(v)), o); },
  };
}

test("each browser counts once", async () => {
  const s = fakeStore();
  assert.equal((await addVisitor(s, "aaaaaaaaaaaaaaaaaaaa")).visitors, 1);
  assert.equal((await addVisitor(s, "aaaaaaaaaaaaaaaaaaaa")).counted, false);
  assert.equal((await addVisitor(s, "bbbbbbbbbbbbbbbbbbbb")).visitors, 2);
  assert.equal(await readVisitors(s), 2);
});

test("simultaneous new visitors are all counted", async () => {
  const s = fakeStore();
  await Promise.all(Array.from({ length: 30 }, (_, i) => addVisitor(s, "visitor-number-" + String(i).padStart(4, "0"))));
  assert.equal(await readVisitors(s), 30);
});
