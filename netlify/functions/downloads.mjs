// GET  /api/downloads              -> { "house-help-tracker": 12, ... }
// POST /api/downloads {"app":"id"}  -> counts one download, returns the new totals
import { getStore } from "@netlify/blobs";
import { APP_ID, readCounts, addDownload } from "./counter.mjs";
import catalog from "../../apps.json" with { type: "json" };

const HEADERS = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: HEADERS });

// The list of real apps is bundled in at deploy time, so only their downloads are counted or shown.
const KNOWN = new Set((catalog.apps || []).map(a => a.id));
const onlyKnown = counts => Object.fromEntries(Object.entries(counts).filter(([k]) => KNOWN.has(k)));

export default async (req, context) => {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: HEADERS });
  const store = getStore({ name: "downloads", consistency: "strong" });

  if (req.method === "GET") return json(onlyKnown(await readCounts(store)));

  if (req.method === "POST") {
    let app = "";
    try { app = String((await req.json()).app || ""); } catch (e) {}
    if (!APP_ID.test(app) || !KNOWN.has(app)) return json({ error: "unknown app" }, 400);
    try {
      const { counted, counts } = await addDownload(store, app, context.ip);
      return json({ counted, counts: onlyKnown(counts) });
    } catch (e) {
      return json({ error: "try again" }, 503);
    }
  }
  return json({ error: "method not allowed" }, 405);
};

export const config = { path: "/api/downloads" };
