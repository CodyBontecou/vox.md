// Vox.md 3.0.4 Play production rollout: phone code 10 and Wear code 1000010 at a staged fraction.
//
//   node play-production-rollout.mjs <service-account.json>            # validate only, edit deleted
//   node play-production-rollout.mjs <service-account.json> --commit   # validate, then commit
//
// One edit replaces the production track's releases (dropping the stale 3.0.0 / code 7 draft,
// keeping the completed 1.1.2 / code 5 release that serves until the rollout completes) and sets
// wear:production. Both codes must already be on internal / wear:internal (android/v3.0.4 tag run).
// Env: FRACTION (default 0.2), PACKAGE (default md.vox.android), NOTES (default the en-US Play notes).
import fs from "node:fs"; import crypto from "node:crypto"; import path from "node:path";

const [keyPath, flag] = process.argv.slice(2);
const commit = flag === "--commit";
const pkg = process.env.PACKAGE ?? "md.vox.android";
const fraction = Number(process.env.FRACTION ?? "0.2");
const here = path.dirname(new URL(import.meta.url).pathname);
const notesPath = process.env.NOTES ?? path.join(here, "../../../apps/android/play-console/listing/en-US/release-notes/en-US/default.txt");
const notes = fs.readFileSync(notesPath, "utf8").trim();
if (!(fraction > 0 && fraction < 1)) throw new Error(`FRACTION must be between 0 and 1: ${fraction}`);
if (notes.length > 500) throw new Error(`release notes are ${notes.length} chars (max 500)`);

const key = JSON.parse(fs.readFileSync(keyPath, "utf8"));
const b64 = o => Buffer.from(JSON.stringify(o)).toString("base64url");
const iat = Math.floor(Date.now() / 1000);
const unsigned = `${b64({ alg: "RS256", typ: "JWT" })}.${b64({ iss: key.client_email, scope: "https://www.googleapis.com/auth/androidpublisher", aud: key.token_uri, iat, exp: iat + 3600 })}`;
const sig = crypto.sign("RSA-SHA256", Buffer.from(unsigned), key.private_key).toString("base64url");
const token = (await (await fetch(key.token_uri, { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
  body: `grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer&assertion=${unsigned}.${sig}` })).json()).access_token;
const H = { authorization: `Bearer ${token}`, "content-type": "application/json" };
const base = `https://androidpublisher.googleapis.com/androidpublisher/v3/applications/${pkg}`;
async function call(method, url, body) {
  const res = await fetch(url, { method, headers: H, body: body ? JSON.stringify(body) : undefined });
  const text = await res.text();
  if (!res.ok) throw new Error(`${method} ${url.replace(base, "")} -> ${res.status} ${text.slice(0, 600)}`);
  return text ? JSON.parse(text) : {};
}

const edit = await call("POST", `${base}/edits`, {});
let committed = false;
try {
  const tracks = await call("GET", `${base}/edits/${edit.id}/tracks`);
  const track = name => (tracks.tracks ?? []).find(t => t.track === name);
  for (const [name, code] of [["internal", "10"], ["wear:internal", "1000010"]]) {
    if (!(track(name)?.releases ?? []).some(r => (r.versionCodes ?? []).includes(code))) throw new Error(`${code} is not on ${name}`);
  }
  if (!track("wear:production")) throw new Error("wear:production is missing: enable the Wear OS form factor first");
  const completed = (track("production")?.releases ?? []).filter(r => r.status === "completed");
  const release = code => ({ name: "3.0.4", versionCodes: [code], status: "inProgress", userFraction: fraction,
    releaseNotes: [{ language: "en-US", text: notes }] });

  const phone = await call("PUT", `${base}/edits/${edit.id}/tracks/production`, { track: "production", releases: [release("10"), ...completed] });
  const wear = await call("PUT", `${base}/edits/${edit.id}/tracks/${encodeURIComponent("wear:production")}`, { track: "wear:production", releases: [release("1000010")] });
  console.log("production:", JSON.stringify(phone.releases));
  console.log("wear:production:", JSON.stringify(wear.releases));
  await call("POST", `${base}/edits/${edit.id}:validate`);
  console.log("validated");
  if (commit) {
    await call("POST", `${base}/edits/${edit.id}:commit?changesNotSentForReview=false&changesInReviewBehavior=ERROR_IF_IN_REVIEW`);
    committed = true;
    console.log("committed: both releases go to Google review, then roll out at", fraction);
  }
} finally {
  if (!committed) { await fetch(`${base}/edits/${edit.id}`, { method: "DELETE", headers: H }); console.log("edit deleted (nothing committed)"); }
}
