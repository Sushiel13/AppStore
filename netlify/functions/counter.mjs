// Download counter logic, kept free of Netlify imports so it can be tested with a fake store.
import { createHash } from "node:crypto";

export const APP_ID = /^[a-z0-9-]{1,60}$/;
const COUNTS = "counts";

export async function readCounts(store) {
  return (await store.get(COUNTS, { type: "json" })) || {};
}

// Counts one download of `app`. The same visitor (IP) downloading the same app
// on the same day counts once, so repeated taps don't inflate the total.
export async function addDownload(store, app, ip, now = new Date()) {
  const day = now.toISOString().slice(0, 10);
  const who = createHash("sha256").update(`${ip || "unknown"}|${app}|${day}`).digest("hex").slice(0, 32);
  const seen = await store.set(`seen/${day}/${who}`, "1", { onlyIfNew: true });
  if (seen && seen.modified === false) return { counted: false, counts: await readCounts(store) };

  // Compare-and-swap so two downloads at the same moment are both counted.
  for (let i = 0; i < 8; i++) {
    const cur = await store.getWithMetadata(COUNTS, { type: "json" });
    const counts = (cur && cur.data) || {};
    counts[app] = (counts[app] || 0) + 1;
    const res = cur
      ? await store.setJSON(COUNTS, counts, { onlyIfMatch: cur.etag })
      : await store.setJSON(COUNTS, counts, { onlyIfNew: true });
    if (!res || res.modified !== false) return { counted: true, counts };
    await new Promise(r => setTimeout(r, 40 + Math.random() * 120));
  }
  throw new Error("busy");
}
