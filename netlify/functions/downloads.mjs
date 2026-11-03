// GET  /api/downloads              -> { "house-help-tracker": 12, ... }
// POST /api/downloads {"app":"id"}  -> counts one download, returns the new totals
import { getStore } from "@netlify/blobs";
import { APP_ID, readCounts, addDownload } from "./counter.mjs";

const HEADERS = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: HEADERS });

async function knownApps(origin) {
  try {
    const r = await fetch(`${origin}/apps.json`, { headers: { "Cache-Control": "no-cache" } });
    const d = await r.json();
    return new Set((d.apps || []).map(a => a.id));
  } catch (e) { return null; }
}

export default async (req, context) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: HEADERS });
  const store = getStore({ name: "downloads", consistency: "strong" });

  if (req.method === "GET") return json(await readCounts(store));

  if (req.method === "POST") {
    let app = "";
    try { app = String((await req.json()).app || ""); } catch (e) {}
    if (!APP_ID.test(app)) return json({ error: "unknown app" }, 400);
    const apps = await knownApps(new URL(req.url).origin);
    if (apps && !apps.has(app)) return json({ error: "unknown app" }, 400);
    try {
      const { counted, counts } = await addDownload(store, app, context.ip);
      return json({ counted, counts });
    } catch (e) {
      return json({ error: "try again" }, 503);
    }
  }
  return json({ error: "method not allowed" }, 405);
};

export const config = { path: "/api/downloads" };
