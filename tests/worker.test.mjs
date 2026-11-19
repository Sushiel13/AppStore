import { test } from "node:test";
import assert from "node:assert/strict";
import * as L from "../worker/src/logic.js";

// In-memory stand-in for Durable Object storage.
function fakeKV() {
  const m = new Map();
  return {
    async get(k) { return m.has(k) ? structuredClone(m.get(k)) : undefined; },
    async put(k, v) { m.set(k, structuredClone(v)); },
    async delete(k) { return m.delete(k); },
    async list({ prefix = "", reverse = false, limit = 1000 } = {}) {
      let keys = [...m.keys()].filter(k => k.startsWith(prefix)).sort();
      if (reverse) keys.reverse();
      return new Map(keys.slice(0, limit).map(k => [k, structuredClone(m.get(k))]));
    },
  };
}

test("seeds old totals once", async () => {
  const kv = fakeKV();
  await L.seed(kv, { a: 8 }, "297");
  await L.addDownload(kv, "a", "1.1.1.1");
  await L.seed(kv, { a: 8 }, "297");
  assert.deepEqual(await L.readCounts(kv), { a: 9 });
  assert.equal(await L.readVisitors(kv), 297);
});

test("same person, same app, same day counts once", async () => {
  const kv = fakeKV(), d = new Date("2026-11-03T10:00:00Z");
  assert.equal((await L.addDownload(kv, "a", "9.9.9.9", d)).counted, true);
  assert.equal((await L.addDownload(kv, "a", "9.9.9.9", d)).counted, false);
  assert.equal((await L.addDownload(kv, "a", "9.9.9.9", new Date("2026-11-04T10:00:00Z"))).counted, true);
  assert.equal((await L.addDownload(kv, "b", "9.9.9.9", d)).counted, true);
  assert.deepEqual(await L.readCounts(kv), { a: 2, b: 1 });
});

test("each browser counts once as a visitor", async () => {
  const kv = fakeKV();
  await L.seed(kv, {}, 10);
  assert.equal((await L.addVisitor(kv, "abcdefghijklmnop1")).visitors, 11);
  assert.equal((await L.addVisitor(kv, "abcdefghijklmnop1")).counted, false);
  assert.equal((await L.addVisitor(kv, "abcdefghijklmnop2")).visitors, 12);
});

test("forms are saved, listed newest first, and deletable", async () => {
  const kv = fakeKV();
  const r1 = await L.addMessage(kv, { form: "review", app: "a", rating: "5", name: "Priya", review: "Nice" }, "1.1.1.1", new Date("2026-11-19T10:00:00Z"));
  const r2 = await L.addMessage(kv, { form: "subscribe", app: "a", contact: "x@y.in" }, "1.1.1.1", new Date("2026-11-19T11:00:00Z"));
  assert.ok(r1.ok && r2.ok);
  const list = await L.listMessages(kv);
  assert.equal(list.length, 2);
  assert.equal(list[0].form, "subscribe");
  assert.equal(list[1].name, "Priya");
  assert.equal(await L.deleteMessage(kv, r1.id), true);
  assert.equal((await L.listMessages(kv)).length, 1);
});

test("rejects unknown forms, ignores bots, limits floods", async () => {
  const kv = fakeKV();
  assert.ok((await L.addMessage(kv, { form: "hack" }, "1")).error);
  assert.deepEqual(await L.addMessage(kv, { form: "report", "bot-field": "x" }, "1"), { ok: true });
  assert.equal((await L.listMessages(kv)).length, 0);
  for (let i = 0; i < 20; i++) assert.ok((await L.addMessage(kv, { form: "report", app: "a" }, "2")).ok);
  assert.ok((await L.addMessage(kv, { form: "report", app: "a" }, "2")).error);
});
