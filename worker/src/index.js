// AppBucket API on Cloudflare Workers (free plan). Replaces the old Netlify Functions and Netlify Forms.
//
// GET    /api/downloads                 -> { "house-help-tracker": 12, ... }
// POST   /api/downloads {"app":"id"}     -> counts one download, returns the new totals
// GET    /api/visitors                  -> { "visitors": 123 }
// POST   /api/visitors {"vid":"..."}     -> counts this browser once, ever
// POST   /api/forms {"form":"review",...} -> saves a review / report / update sign-up
// GET    /api/messages      (owner key) -> saved messages, newest first
// DELETE /api/messages/<id> (owner key) -> removes one message
import { DurableObject } from "cloudflare:workers";
import catalog from "../../apps.json";
import * as L from "./logic.js";

// Only apps listed in apps.json are counted or shown. The Worker redeploys when apps.json changes.
const KNOWN = new Set((catalog.apps || []).map(a => a.id));
const onlyKnown = c => Object.fromEntries(Object.entries(c).filter(([k]) => KNOWN.has(k)));

function cors(req, env) {
  const allowed = String(env.ALLOWED_ORIGINS || "").split(",").map(s => s.trim()).filter(Boolean);
  const origin = req.headers.get("Origin") || "";
  return {
    "Access-Control-Allow-Origin": allowed.includes(origin) ? origin : allowed[0] || "*",
    "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Vary": "Origin",
  };
}

export class Store extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    let start = {};
    try { start = JSON.parse(env.START_DOWNLOADS || "{}"); } catch (e) {}
    ctx.blockConcurrencyWhile(() => L.seed(ctx.storage, start, env.START_VISITORS));
  }

  async fetch(req) {
    const url = new URL(req.url), path = url.pathname, kv = this.ctx.storage, env = this.env;
    const ip = req.headers.get("CF-Connecting-IP") || "";
    const out = (body, status = 200) => new Response(JSON.stringify(body), {
      status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...cors(req, env) },
    });
    const body = async () => { try { return await req.json(); } catch (e) { return {}; } };

    if (path === "/api/downloads") {
      if (req.method === "GET") return out(onlyKnown(await L.readCounts(kv)));
      if (req.method === "POST") {
        const app = String((await body()).app || "");
        if (!L.APP_ID.test(app) || !KNOWN.has(app)) return out({ error: "unknown app" }, 400);
        const { counted, counts } = await L.addDownload(kv, app, ip);
        return out({ counted, counts: onlyKnown(counts) });
      }
    }

    if (path === "/api/visitors") {
      if (req.method === "GET") return out({ visitors: await L.readVisitors(kv) });
      if (req.method === "POST") {
        const vid = String((await body()).vid || "");
        if (!L.VID.test(vid)) return out({ error: "bad id" }, 400);
        return out(await L.addVisitor(kv, vid));
      }
    }

    if (path === "/api/forms" && req.method === "POST") {
      const r = await L.addMessage(kv, await body(), ip);
      return out(r, r.error ? 400 : 200);
    }

    if (path.startsWith("/api/messages")) {
      const key = env.OWNER_KEY || "";
      if (!key || req.headers.get("Authorization") !== "Bearer " + key) return out({ error: "not allowed" }, 401);
      if (req.method === "GET" && path === "/api/messages") return out(await L.listMessages(kv));
      if (req.method === "DELETE") return out({ ok: await L.deleteMessage(kv, path.split("/").pop()) });
    }

    return out({ error: "not found" }, 404);
  }
}

export default {
  async fetch(req, env) {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(req, env) });
    // Everything lives in one small Durable Object, so counts are exact and never race.
    return env.STORE.get(env.STORE.idFromName("appbucket")).fetch(req);
  },
};
