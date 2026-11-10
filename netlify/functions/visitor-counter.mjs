// Unique-visitor counting, kept free of Netlify imports so it can be tested with a fake store.
import { createHash } from "node:crypto";

export const VID = /^[A-Za-z0-9_-]{16,64}$/;
const TOTAL = "total";

export async function readVisitors(store) {
  const t = await store.get(TOTAL, { type: "json" });
  return (t && t.n) || 0;
}

export async function addVisitor(store, vid) {
  const key = "v/" + createHash("sha256").update(vid).digest("hex").slice(0, 32);
  const seen = await store.set(key, "1", { onlyIfNew: true });
  if (seen && seen.modified === false) return { counted: false, visitors: await readVisitors(store) };
  for (let i = 0; i < 8; i++) {                       // compare-and-swap so simultaneous visits all count
    const cur = await store.getWithMetadata(TOTAL, { type: "json" });
    const n = ((cur && cur.data && cur.data.n) || 0) + 1;
    const res = cur
      ? await store.setJSON(TOTAL, { n }, { onlyIfMatch: cur.etag })
      : await store.setJSON(TOTAL, { n }, { onlyIfNew: true });
    if (!res || res.modified !== false) return { counted: true, visitors: n };
    await new Promise(r => setTimeout(r, 40 + Math.random() * 120));
  }
  throw new Error("busy");
}
