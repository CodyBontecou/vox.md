#!/usr/bin/env node
// Renders the Signal-redesign App Store screenshots (exported from the
// "Vox.md — App Store screenshots" Design artifact) for every locale.
//
//   node scripts/localization/store-screenshots/render.mjs --extract
//       Render English and write strings/en.json (every visible string).
//   node scripts/localization/store-screenshots/render.mjs [--locale ja,de-DE] [--only iphone]
//       Render PNGs to artifacts/localization/store-signal/<locale>/<device>/.
//
// Templates are Design Component (.dc.html) files. A tiny in-page runtime
// expands {{holes}}, <sc-for>, <sc-if> and <dc-import>, then every visible
// text node and placeholder is swapped for strings/<locale>.json.

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "../../..");
const templateDir = path.join(here, "templates");
const stringsDir = path.join(here, "strings");
// Frame sets on the Design artifact: "p2" = page "Pass 2 · weirder" (the store design),
// "as" = page "App Store screenshots".
const SETS = { p2: { prefix: "P2_", out: "store-signal" }, as: { prefix: "AS_", out: "store-signal-as" } };
const chrome = process.env.CHROME_PATH || "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome";

// App Store upload sizes. The artifact designs iPhone at 1206×2622 (6.3″); App Store Connect
// requires the 6.9″ set (1320×2868), so iPhone frames render at 1320/1206 device scale.
const OUTPUT_SIZE = { iphone: [1320, 2868] };

export const SHOTS = [
  ["iphone", "01-capture", "iPhone1"],
  ["iphone", "02-private-by-default", "iPhone2"],
  ["iphone", "03-routes", "iPhone3"],
  ["iphone", "04-voice-keyboard", "iPhone4"],
  ["iphone", "05-lock-screen", "iPhone5"],
  ["iphone", "06-library", "iPhone6"],
  ["ipad", "01-capture", "iPad1"],
  ["ipad", "02-library", "iPad2"],
  ["ipad", "03-split-view", "iPad3"],
  ["duo-inner", "01-composer", "DuoInner1"],
  ["duo-inner", "02-library", "DuoInner2"],
  ["duo-inner", "03-split-view", "DuoInner3"],
  ["duo-inner", "04-meetings", "DuoInner4"],
  ["duo-cover", "01-capture", "DuoCover1"],
  ["duo-cover", "02-recording", "DuoCover2"],
  ["mac", "01-workspace", "Mac1"],
  ["mac", "02-quick-capture", "Mac2"],
  ["mac", "03-library", "Mac3"],
  ["mac", "04-activity", "Mac4"],
];

// App Store locale -> BCP 47 tag for <html lang> (drives CJK glyph choice).
export const LOCALES = {
  "en-US": "en", "ar-SA": "ar", "de-DE": "de", "es-ES": "es", "es-MX": "es-MX",
  "fr-FR": "fr", "fr-CA": "fr-CA", hi: "hi", id: "id", it: "it", ja: "ja", ko: "ko",
  "nl-NL": "nl", pl: "pl", "pt-BR": "pt-BR", ru: "ru", th: "th", tr: "tr", uk: "uk",
  vi: "vi", "zh-Hans": "zh-Hans", "zh-Hant": "zh-Hant",
};
const RTL = new Set(["ar-SA"]);

function args() {
  const a = process.argv.slice(2);
  const get = (flag) => { const i = a.indexOf(flag); return i >= 0 ? a[i + 1] : undefined; };
  return {
    extract: a.includes("--extract"),
    mock: a.includes("--mock"),
    set: get("--set") ?? "p2",
    locales: get("--locale")?.split(",") ?? Object.keys(LOCALES),
    only: get("--only")?.split(","),
  };
}

// Real app captures (see capture-runbook in README). Where one exists for a frame's
// screen it replaces the Design mockup; the device bezel is resized to its aspect.
const captureRoot = path.join(repoRoot, "artifacts/localization/store-signal-captures/_ready");
const CAPTURES = {
  iPhone1: { Main: "iphone/main" },
  iPhone2: { LiveRecording: "iphone/live" },
  iPhone3: { Routes: "iphone/routes" },
  iPhone6: { Library: "iphone/library" },
  iPad1: { iPad: "ipad/capture" },
  iPad2: { DuoInnerLibrary: "ipad/library" },
  DuoInner1: { DuoInnerCapture: "duo/inner-capture" },
  DuoInner2: { DuoInnerLibrary: "duo/inner-library" },
  DuoInner4: { DuoTabletop: "duo/tabletop" },
  DuoCover1: { DuoCoverCapture: "duo/cover-capture" },
  DuoCover2: { DuoCoverRecording: "duo/cover-recording" },
  Mac1: { MacWorkspace: "mac/workspace" },
  Mac2: { MacWorkspace: "mac/workspace", MacQuickCapture: "mac/quick-capture" },
  Mac3: { MacLibrary: "mac/library" },
  Mac4: { MacActivity: "mac/activity" },
};

function pngSize(buf) {
  return [buf.readUInt32BE(16), buf.readUInt32BE(20)];
}

function capturesFor(frame, locale) {
  const found = {};
  for (const [importName, rel] of Object.entries(CAPTURES[frame] || {})) {
    const file = path.join(captureRoot, locale, `${rel}.png`);
    if (!fs.existsSync(file)) continue;
    const buf = fs.readFileSync(file);
    const [w, h] = pngSize(buf);
    found[importName] = { src: `data:image/png;base64,${buf.toString("base64")}`, w, h };
  }
  return found;
}

const templates = Object.fromEntries(
  fs.readdirSync(templateDir).filter((f) => f.endsWith(".dc.html"))
    .map((f) => [f.replace(/\.dc\.html$/, ""), fs.readFileSync(path.join(templateDir, f), "utf8")]),
);

const SHELL = `<!doctype html><html><head><meta charset="utf-8">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=Geist+Mono:wght@400;500&display=block">
<style>html,body{margin:0;padding:0;background:transparent}
/* Wrap headlines at phrase boundaries instead of between any two characters. */
:lang(ja) h1, :lang(ja) p { word-break: auto-phrase; line-break: strict }
:lang(zh) h1, :lang(zh) p { line-break: strict }
:lang(ko) h1, :lang(ko) p { word-break: keep-all }
/* Scripts with stacked marks need more leading than the Latin 1.02. */
:lang(th) h1, :lang(hi) h1, :lang(ar) h1 { line-height: 1.28 !important }
:lang(th) p, :lang(hi) p, :lang(ar) p { line-height: 1.45 !important }</style></head><body></body></html>`;

// Runs inside the page.
function pageRuntime() {
  const HOLE = /{{\s*([^}]+?)\s*}}/g;
  const WHOLE = /^{{\s*([^}]+?)\s*}}$/;
  const parsed = {};

  function parse(name) {
    if (parsed[name]) return parsed[name];
    const src = window.__templates[name];
    if (!src) throw new Error("missing template " + name);
    const doc = new DOMParser().parseFromString(src, "text/html");
    const xdc = doc.querySelector("x-dc");
    const helmet = xdc.querySelector("helmet");
    const head = helmet ? helmet.innerHTML : "";
    helmet?.remove();
    const script = doc.querySelector("script[data-dc-script]");
    const DCLogic = class { constructor(props) { this.props = props; this.state = {}; } setState(s) { Object.assign(this.state, s); } };
    const Component = new Function("DCLogic", (script?.textContent || "class Component extends DCLogic { renderVals(){return {}} }") + "\nreturn Component;")(DCLogic);
    return (parsed[name] = { xdc, head, Component });
  }

  function lookup(expr, scope) {
    expr = expr.trim();
    if (expr === "true") return true;
    if (expr === "false") return false;
    if (expr === "null") return null;
    if (/^-?\d+(\.\d+)?$/.test(expr)) return Number(expr);
    if (/^(['"]).*\1$/.test(expr)) return expr.slice(1, -1);
    let v = scope;
    for (const k of expr.split(".")) { if (v == null) return undefined; v = v[k]; }
    return v;
  }
  const interp = (s, scope) => s.replace(HOLE, (_, e) => { const v = lookup(e, scope); return v == null ? "" : String(v); });

  const heads = new Set();
  function renderComponent(name) {
    const { xdc, head, Component } = parse(name);
    heads.add(head);
    const inst = new Component({});
    const vals = inst.renderVals ? inst.renderVals() : {};
    const out = [];
    for (const child of xdc.childNodes) out.push(...walk(child, vals));
    return out;
  }

  function walk(node, scope) {
    if (node.nodeType === Node.TEXT_NODE) return [document.createTextNode(interp(node.data, scope))];
    if (node.nodeType !== Node.ELEMENT_NODE) return [];
    const tag = node.localName;
    if (tag === "sc-for") {
      const list = lookup((node.getAttribute("list").match(WHOLE) || [])[1] || "", scope) || [];
      const as = node.getAttribute("as") || "item";
      const out = [];
      list.forEach((item, i) => { for (const c of node.childNodes) out.push(...walk(c, { ...scope, [as]: item, $index: i })); });
      return out;
    }
    if (tag === "sc-if") {
      const v = lookup((node.getAttribute("value").match(WHOLE) || [])[1] || "false", scope);
      if (!v) return [];
      return [...node.childNodes].flatMap((c) => walk(c, scope));
    }
    if (tag === "dc-import") {
      const importName = node.getAttribute("name");
      const cap = (window.__captures || {})[importName];
      if (cap) {
        const img = document.createElement("img");
        img.src = cap.src;
        img.dataset.capture = importName;
        img.dataset.aspect = String(cap.w / cap.h);
        img.style.cssText = "display:block;width:100%;height:100%";
        return [img];
      }
      return renderComponent(importName);
    }
    const el = document.importNode(node, false);
    for (const attr of [...el.attributes]) {
      const { name, value } = attr;
      if (name.startsWith("hint-")) { el.removeAttribute(name); continue; }
      let target = name;
      if (name.startsWith("sc-camel-")) {
        el.removeAttribute(name);
        target = name.slice(9).replace(/-([a-z])/g, (_, c) => c.toUpperCase());
      }
      const whole = value.match(WHOLE);
      if (whole) {
        const v = lookup(whole[1], scope);
        if (typeof v === "function" || v === false || v == null) { el.removeAttribute(target); continue; }
        el.setAttribute(target, v === true ? "" : String(v));
      } else if (value.includes("{{")) {
        el.setAttribute(target, interp(value, scope));
      } else if (target !== name) {
        el.setAttribute(target, value);
      }
    }
    for (const c of node.childNodes) for (const n of walk(c, scope)) el.appendChild(n);
    return [el];
  }

  window.__render = function (name, lang, dir) {
    document.documentElement.lang = lang;
    const nodes = renderComponent(name);
    for (const h of heads) document.head.insertAdjacentHTML("beforeend", h);
    const root = document.createElement("div");
    root.id = "root";
    root.style.display = "inline-block";
    root.dataset.dir = dir;
    nodes.forEach((n) => root.appendChild(n));
    document.body.appendChild(root);
  };

  // Each mock screen sits in: bezel > screen (overflow hidden, fixed size) > scaler (transform)
  // > component. A capture replaces the component: drop the scaler's transform and give the
  // screen (and bezel) the capture's aspect ratio at the design's screen height.
  window.__fitCaptures = function () {
    document.querySelectorAll("#root img[data-capture]").forEach((img) => {
      const scaler = img.parentElement;
      const screen = scaler.parentElement;
      const bezel = screen.parentElement;
      const aspect = Number(img.dataset.aspect);
      const sw = screen.offsetWidth, sh = screen.offsetHeight;
      scaler.style.transform = "none";
      scaler.style.width = "100%";
      scaler.style.height = "100%";
      const newW = Math.round(sh * aspect);
      screen.style.width = newW + "px";
      // Overlays in a shared screen (Mac quick capture) are absolutely placed: keep them.
      if (bezel && bezel.offsetWidth > sw && getComputedStyle(bezel).position !== "absolute") {
        bezel.style.width = (bezel.offsetWidth - sw + newW) + "px";
      }
    });
  };

  const norm = (s) => s.replace(/\s+/g, " ").trim();
  const hasWords = (s) => /\p{L}/u.test(s);

  window.__extract = function () {
    const found = [];
    const tw = document.createTreeWalker(document.getElementById("root"), NodeFilter.SHOW_TEXT);
    while (tw.nextNode()) {
      const t = norm(tw.currentNode.data);
      const p = tw.currentNode.parentElement;
      if (!t || !hasWords(t) || p.closest("style,script")) continue;
      const raw = tw.currentNode.data.trim().replace(/[ \t]*\n\s*/g, "\n").replace(/[ \t]+/g, " ");
      found.push([t, raw]);
    }
    document.querySelectorAll("#root [placeholder]").forEach((el) => {
      const t = norm(el.getAttribute("placeholder"));
      if (hasWords(t)) found.push([t, t]);
    });
    return found;
  };

  // Text that no longer fits its box: clipped, ellipsized or spilling past a fixed width.
  window.__overflows = function () {
    const out = [];
    document.querySelectorAll("#root *").forEach((el) => {
      if (!el.childNodes.length || ![...el.childNodes].some((c) => c.nodeType === 3 && /\p{L}/u.test(c.data))) return;
      if (el.scrollWidth > el.clientWidth + 2 && el.clientWidth > 0) out.push(norm(el.textContent).slice(0, 60));
    });
    return out;
  };

  window.__translate = function (dict) {
    const missing = [];
    const tw = document.createTreeWalker(document.getElementById("root"), NodeFilter.SHOW_TEXT);
    const nodes = [];
    while (tw.nextNode()) nodes.push(tw.currentNode);
    for (const n of nodes) {
      const t = norm(n.data);
      if (!t || !hasWords(t) || n.parentElement.closest("style,script")) continue;
      if (dict[t] == null) { missing.push(t); continue; }
      const lead = n.data.match(/^\s*/)[0].replace(/\n/g, " ");
      const trail = n.data.match(/\s*$/)[0].replace(/\n/g, " ");
      n.data = lead + dict[t] + trail;
    }
    document.querySelectorAll("#root [placeholder]").forEach((el) => {
      const t = norm(el.getAttribute("placeholder"));
      if (!hasWords(t)) return;
      if (dict[t] == null) missing.push(t); else el.setAttribute("placeholder", dict[t]);
    });
    // RTL: flipping the whole page pushes the scaled app screens out of their device frames
    // (they scale from the top-left). Instead give every text element its own direction so
    // Arabic lines read and align right-to-left inside the unchanged layout.
    if (document.getElementById("root").dataset.dir === "rtl") {
      document.querySelectorAll("#root *").forEach((el) => {
        if ([...el.childNodes].some((c) => c.nodeType === 3 && /\p{L}/u.test(c.data))) el.dir = "auto";
      });
      document.querySelectorAll("#root input[placeholder]").forEach((el) => { el.dir = "auto"; });
    }
    return missing;
  };
}

async function renderOne(browser, shot, locale, dict, useCaptures = false, prefix = "P2_") {
  const frame = shot[2];
  let name = prefix + frame;
  const captures = useCaptures ? capturesFor(frame, locale) : {};
  // A frame can ship a layout variant for real captures (e.g. tabletop is landscape on device).
  if (Object.keys(captures).length && templates[`${name}.capture`]) name = `${name}.capture`;
  const page = await browser.newPage();
  const m = templates[name].match(/"\$preview":\{"width":(\d+),"height":(\d+)\}/);
  const [width, height] = [Number(m[1]), Number(m[2])];
  const out = OUTPUT_SIZE[shot[0]];
  const scale = out ? out[0] / width : 1;
  await page.setViewport({ width, height, deviceScaleFactor: scale });
  await page.setContent(SHELL, { waitUntil: "networkidle0" });
  await page.evaluate((t, c) => { window.__templates = t; window.__captures = c; }, templates, captures);
  await page.evaluate(pageRuntime);
  await page.evaluate((n, lang, dir) => window.__render(n, lang, dir), name, LOCALES[locale], RTL.has(locale) ? "rtl" : "ltr");
  let missing = [];
  if (dict) missing = await page.evaluate((d) => window.__translate(d), dict);
  await page.evaluate(() => document.fonts.ready);
  await page.evaluate(() => Promise.all([...document.images].map((i) => i.decode().catch(() => {}))));
  await page.evaluate(() => window.__fitCaptures());
  // Fonts are the only network traffic; a slow CDN should not abort a whole locale.
  await page.waitForNetworkIdle({ idleTime: 300, timeout: 60000 }).catch(() => {});
  const overflows = await page.evaluate(() => window.__overflows());
  return { page, width, height, scale, out, missing, overflows };
}

async function main() {
  const opts = args();
  const set = SETS[opts.set];
  if (!set) throw new Error(`unknown --set ${opts.set} (p2 | as)`);
  const outRoot = path.join(repoRoot, "artifacts/localization", set.out);
  const browser = await puppeteer.launch({ executablePath: chrome, headless: true });
  const shots = SHOTS.filter(([device]) => !opts.only || opts.only.includes(device));
  try {
    if (opts.extract) {
      // Merge into the existing catalog: both frame sets share one strings file.
      const enFile = path.join(stringsDir, "en.json");
      const strings = fs.existsSync(enFile) ? JSON.parse(fs.readFileSync(enFile, "utf8")) : {};
      for (const shot of shots) {
        const { page } = await renderOne(browser, shot, "en-US", null, false, set.prefix);
        for (const [key, raw] of await page.evaluate(() => window.__extract())) {
          strings[key] ||= { text: raw, boards: [] };
          const board = set.prefix + shot[2];
          strings[key].boards.includes(board) || strings[key].boards.push(board);
        }
        await page.close();
      }
      fs.mkdirSync(stringsDir, { recursive: true });
      fs.writeFileSync(path.join(stringsDir, "en.json"), JSON.stringify(strings, null, 2) + "\n");
      console.log(`extracted ${Object.keys(strings).length} strings -> strings/en.json`);
      return;
    }
    const enOverflowCount = {};
    if (opts.locales[0] !== "en-US" && !opts.locales.includes("en-US")) opts.locales.unshift("en-US");
    const en = JSON.parse(fs.readFileSync(path.join(stringsDir, "en.json"), "utf8"));
    for (const locale of opts.locales) {
      if (!LOCALES[locale]) throw new Error(`unknown locale ${locale}`);
      let dict = null;
      if (locale !== "en-US") {
        const file = path.join(stringsDir, `${locale}.json`);
        if (!fs.existsSync(file)) { console.warn(`skip ${locale}: no strings/${locale}.json`); continue; }
        dict = JSON.parse(fs.readFileSync(file, "utf8"));
      }
      const allMissing = new Set();
      const report = [];
      for (const shot of shots) {
        const [device, slug] = shot;
        const { page, width, height, scale, out, missing, overflows } = await renderOne(browser, shot, locale, dict, !opts.mock, set.prefix);
        missing.forEach((s) => allMissing.add(s));
        if (locale !== "en-US" && overflows.length > (enOverflowCount[shot[2]] ?? 0)) report.push(`${device}/${slug}: ${overflows.length - (enOverflowCount[shot[2]] ?? 0)} more overflowing text boxes than English`);
        if (locale === "en-US") enOverflowCount[shot[2]] = overflows.length;
        const dir = path.join(outRoot, locale, device);
        fs.mkdirSync(dir, { recursive: true });
        const root = await page.$("#root");
        // Clip to the exact target height (6.9″ is a hair taller-ratio than 6.3″: ~2px at the bottom).
        const clipH = out ? out[1] / scale : height;
        await root.screenshot({ path: path.join(dir, `${slug}.png`), clip: { x: 0, y: 0, width, height: clipH } });
        await page.close();
      }
      const unknown = dict ? Object.keys(en).filter((k) => dict[k] == null) : [];
      console.log(`${locale}: ${shots.length} images` + (allMissing.size ? `, ${allMissing.size} untranslated: ${[...allMissing].slice(0, 5).join(" | ")}` : "") + (unknown.length ? `, ${unknown.length} en.json keys missing from strings/${locale}.json` : ""));
      report.forEach((r) => console.log("  ⚠ " + r));
    }
  } finally {
    await browser.close();
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
