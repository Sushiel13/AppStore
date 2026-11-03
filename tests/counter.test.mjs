import { test } from "node:test";
import assert from "node:assert/strict";
import { addDownload, readCounts } from "../netlify/functions/counter.mjs";

// In-memory stand-in for a Netlify Blobs store, with etags and conditional writes.
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

test("counts downloads per app", async () => {
  const s = fakeStore();
  await addDownload(s, "a", "1.1.1.1");
  await addDownload(s, "a", "2.2.2.2");
  await addDownload(s, "b", "1.1.1.1");
  assert.deepEqual(await readCounts(s), { a: 2, b: 1 });
});

test("same person, same app, same day counts once", async () => {
  const s = fakeStore(), d = new Date("2026-11-03T10:00:00Z");
  assert.equal((await addDownload(s, "a", "9.9.9.9", d)).counted, true);
  assert.equal((await addDownload(s, "a", "9.9.9.9", d)).counted, false);
  assert.equal((await addDownload(s, "a", "9.9.9.9", new Date("2026-11-04T10:00:00Z"))).counted, true);
  assert.deepEqual(await readCounts(s), { a: 2 });
});

test("simultaneous downloads are all counted", async () => {
  const s = fakeStore();
  await Promise.all(Array.from({ length: 25 }, (_, i) => addDownload(s, "a", "10.0.0." + i)));
  assert.equal((await readCounts(s)).a, 25);
});
