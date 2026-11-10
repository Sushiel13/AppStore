// Unique visitors to appbucket.in.
// GET  /api/visitors                  -> { "visitors": 123 }
// POST /api/visitors {"vid":"<random>"} -> counts this browser once, ever; returns the total
// Each browser keeps a random visitor id; only a hash of it is stored.
import { getStore } from "@netlify/blobs";
import { addVisitor, readVisitors, VID } from "./visitor-counter.mjs";

const HEADERS = { "Content-Type": "application/json", "Cache-Control": "no-store" };
const json = (body, status = 200) => new Response(JSON.stringify(body), { status, headers: HEADERS });

export default async req => {
  const store = getStore({ name: "visitors", consistency: "strong" });
  if (req.method === "GET") return json({ visitors: await readVisitors(store) });
  if (req.method === "POST") {
    let vid = "";
    try { vid = String((await req.json()).vid || ""); } catch (e) {}
    if (!VID.test(vid)) return json({ error: "bad id" }, 400);
    try { return json(await addVisitor(store, vid)); }
    catch (e) { return json({ error: "try again" }, 503); }
  }
  return json({ error: "method not allowed" }, 405);
};

export const config = { path: "/api/visitors" };
