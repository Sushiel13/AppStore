// AppBucket API logic, kept free of Cloudflare imports so it can be tested with a Map.
// `kv` needs only get(key), put(key, value), delete(key) and list({prefix, reverse, limit}).
// It runs inside one Durable Object, which handles one request at a time, so plain
// read-then-write is safe: two downloads at the same moment are both counted.

export const APP_ID = /^[a-z0-9-]{1,60}$/;
export const VID = /^[A-Za-z0-9_-]{16,64}$/;
export const FORMS = {
  review: ["app", "rating", "name", "review"],
  report: ["app", "reason", "details", "contact"],
  subscribe: ["app", "contact"],
};

async function sha(text) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map(b => b.toString(16).padStart(2, "0")).join("").slice(0, 32);
}

// Totals carried over from the old Netlify counter, used the first time only.
export async function seed(kv, startDownloads = {}, startVisitors = 0) {
  if ((await kv.get("counts")) === undefined) await kv.put("counts", { ...startDownloads });
  if ((await kv.get("visitors")) === undefined) await kv.put("visitors", Number(startVisitors) || 0);
}

export async function readCounts(kv) {
  return (await kv.get("counts")) || {};
}

// The same visitor (IP) downloading the same app on the same day counts once.
export async function addDownload(kv, app, ip, now = new Date()) {
  const day = now.toISOString().slice(0, 10);
  const key = `seen/${day}/${await sha(`${ip || "unknown"}|${app}|${day}`)}`;
  if (await kv.get(key)) return { counted: false, counts: await readCounts(kv) };
  await kv.put(key, 1);
  const counts = await readCounts(kv);
  counts[app] = (counts[app] || 0) + 1;
  await kv.put("counts", counts);
  return { counted: true, counts };
}

export async function readVisitors(kv) {
  return (await kv.get("visitors")) || 0;
}

// Each browser is counted once, ever. Only a hash of its random id is kept.
export async function addVisitor(kv, vid) {
  const key = "v/" + (await sha(vid));
  if (await kv.get(key)) return { counted: false, visitors: await readVisitors(kv) };
  await kv.put(key, 1);
  const n = (await readVisitors(kv)) + 1;
  await kv.put("visitors", n);
  return { counted: true, visitors: n };
}

// Reviews, problem reports and update sign-ups (these used to go to Netlify Forms).
// At most 20 messages per IP per day, so one person can't flood the inbox.
export async function addMessage(kv, body, ip, now = new Date()) {
  const fields = FORMS[body && body.form];
  if (!fields) return { error: "unknown form" };
  if (body["bot-field"]) return { ok: true };                 // honeypot: pretend it worked
  const day = now.toISOString().slice(0, 10);
  const rl = `rl/${day}/${await sha(ip || "unknown")}`;
  const used = (await kv.get(rl)) || 0;
  if (used >= 20) return { error: "too many messages today" };
  await kv.put(rl, used + 1);
  const msg = { form: body.form, at: now.toISOString() };
  for (const f of fields) msg[f] = String(body[f] ?? "").slice(0, 2000);
  const id = now.toISOString().replace(/[-:.TZ]/g, "") + "-" + Math.random().toString(36).slice(2, 8);
  await kv.put("msg/" + id, msg);
  return { ok: true, id };
}

export async function listMessages(kv) {
  const m = await kv.list({ prefix: "msg/", reverse: true, limit: 500 });
  return [...m].map(([k, v]) => ({ id: k.slice(4), ...v }));
}

export async function deleteMessage(kv, id) {
  if (!/^[0-9]+-[a-z0-9]+$/.test(id)) return false;
  await kv.delete("msg/" + id);
  return true;
}
