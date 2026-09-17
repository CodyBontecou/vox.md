#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(scriptDir, "../..");
const outputRoot = path.join(
  repoRoot,
  "apps/android/play-console/graphics/vercel-inspired",
);
const screenshotOutput = path.join(outputRoot, "screenshots");
const generatedBackground = path.join(
  outputRoot,
  "source/abstract-voice-background.png",
);
const icon = path.join(
  repoRoot,
  "apps/android/play-console/graphics/app-icon-512.png",
);
const geist = path.join(repoRoot, "Voxboard/Fonts/Geist-SemiBold.ttf");
const geistRegular = path.join(repoRoot, "Voxboard/Fonts/Geist-Regular.ttf");
const geistMono = path.join(repoRoot, "Voxboard/Fonts/GeistMono-Medium.ttf");
const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), "vox-play-store-"));

const slides = [
  {
    file: "01-capture-now.png",
    source: "artifacts/android-parity/goldens/phone/phone-01-quick-capture-dark.png",
    eyebrow: "QUICK CAPTURE",
    headline: "Capture now.\nOrganize later.",
    subhead: "Voice, text, links, files → your Markdown.",
  },
  {
    file: "02-one-tap-right-place.png",
    source: "artifacts/android-parity/goldens/phone/phone-05-capture-presets-dark.png",
    eyebrow: "CAPTURE PRESETS",
    headline: "One tap.\nRight place.",
    subhead: "Pin workflows for inbox, journal, tasks, and meetings.",
  },
  {
    file: "03-private-voice.png",
    source: "artifacts/android-parity/goldens/phone/phone-07-live-recording-dark.png",
    eyebrow: "PRIVATE VOICE",
    headline: "Voice stays\non your device.",
    subhead: "Private transcription with durable local audio.",
  },
  {
    file: "04-plain-markdown.png",
    source: "artifacts/android-parity/goldens/phone/phone-02-history-dark.png",
    eyebrow: "OPEN FILES",
    headline: "Plain Markdown.\nNo lock-in.",
    subhead: "Your notes stay readable in any Markdown app.",
  },
  {
    file: "05-local-models.png",
    source: "artifacts/android-parity/goldens/phone/phone-04-models-dark.png",
    eyebrow: "LOCAL MODELS",
    headline: "Choose your\nvoice stack.",
    subhead: "Whisper, Parakeet, Vosk, or Android speech.",
  },
];

function magick(args) {
  execFileSync("magick", args, { stdio: "inherit" });
}

function textLayer({
  text,
  width,
  height,
  font,
  pointSize,
  color,
  output,
  interline = 0,
}) {
  magick([
    "-background",
    "none",
    "-fill",
    color,
    "-font",
    font,
    "-pointsize",
    String(pointSize),
    "-interline-spacing",
    String(interline),
    "-size",
    `${width}x${height}`,
    "-gravity",
    "northwest",
    `caption:${text}`,
    output,
  ]);
}

function makePortraitBackground(output) {
  const atmosphere = path.join(tempRoot, "portrait-atmosphere.png");
  magick([
    generatedBackground,
    "-resize",
    "1080x540!",
    "-modulate",
    "72,55,100",
    atmosphere,
  ]);

  const gridDraw = [];
  for (let x = 0; x <= 1080; x += 120) {
    gridDraw.push(`line ${x},0 ${x},1920`);
  }
  for (let y = 0; y <= 1920; y += 120) {
    gridDraw.push(`line 0,${y} 1080,${y}`);
  }

  magick([
    "-size",
    "1080x1920",
    "canvas:#050505",
    atmosphere,
    "-gravity",
    "north",
    "-compose",
    "over",
    "-composite",
    "-stroke",
    "rgba(255,255,255,0.045)",
    "-strokewidth",
    "1",
    "-fill",
    "none",
    "-draw",
    gridDraw.join(" "),
    "-fill",
    "rgba(0,0,0,0.22)",
    "-stroke",
    "none",
    "-draw",
    "rectangle 0,470 1080,1920",
    output,
  ]);
}

function makeSlide(slide, index) {
  const background = path.join(tempRoot, `background-${index}.png`);
  const eyebrow = path.join(tempRoot, `eyebrow-${index}.png`);
  const headline = path.join(tempRoot, `headline-${index}.png`);
  const subhead = path.join(tempRoot, `subhead-${index}.png`);
  const number = path.join(tempRoot, `number-${index}.png`);
  const resizedScreenshot = path.join(tempRoot, `screen-${index}.png`);
  const resizedIcon = path.join(tempRoot, "icon-56.png");
  const shadow = path.join(tempRoot, `shadow-${index}.png`);
  const frame = path.join(tempRoot, `frame-${index}.png`);
  const output = path.join(screenshotOutput, slide.file);

  makePortraitBackground(background);
  textLayer({
    text: slide.eyebrow,
    width: 600,
    height: 40,
    font: geistMono,
    pointSize: 25,
    color: "#FF9D2E",
    output: eyebrow,
  });
  textLayer({
    text: slide.headline,
    width: 920,
    height: 240,
    font: geist,
    pointSize: 88,
    color: "#F5F5F5",
    interline: -8,
    output: headline,
  });
  textLayer({
    text: slide.subhead,
    width: 900,
    height: 100,
    font: geistRegular,
    pointSize: 34,
    color: "#A1A1A1",
    interline: 3,
    output: subhead,
  });
  textLayer({
    text: `${String(index + 1).padStart(2, "0")} / ${String(slides.length).padStart(2, "0")}`,
    width: 180,
    height: 40,
    font: geistMono,
    pointSize: 24,
    color: "#666666",
    output: number,
  });

  magick([
    path.join(repoRoot, slide.source),
    "-resize",
    "828x1840!",
    resizedScreenshot,
  ]);
  if (!fs.existsSync(resizedIcon)) {
    magick([icon, "-resize", "56x56!", resizedIcon]);
  }
  magick([
    "-size",
    "1080x1920",
    "canvas:none",
    "-fill",
    "rgba(0,0,0,0.88)",
    "-stroke",
    "none",
    "-draw",
    "roundrectangle 105,594 975,2480 62,62",
    "-blur",
    "0x32",
    shadow,
  ]);
  magick([
    "-size",
    "1080x1920",
    "canvas:none",
    "-fill",
    "#111111",
    "-stroke",
    "#353535",
    "-strokewidth",
    "3",
    "-draw",
    "roundrectangle 110,594 970,2466 58,58",
    frame,
  ]);

  magick([
    background,
    shadow,
    "-compose",
    "over",
    "-composite",
    frame,
    "-composite",
    resizedScreenshot,
    "-geometry",
    "+126+610",
    "-composite",
    resizedIcon,
    "-geometry",
    "+72+54",
    "-composite",
    eyebrow,
    "-geometry",
    "+150+69",
    "-composite",
    number,
    "-geometry",
    "+828+68",
    "-composite",
    headline,
    "-geometry",
    "+72+150",
    "-composite",
    subhead,
    "-geometry",
    "+72+404",
    "-composite",
    "-stroke",
    "#FF9300",
    "-strokewidth",
    "5",
    "-draw",
    "line 72,522 138,522",
    "-alpha",
    "off",
    "-depth",
    "8",
    output,
  ]);
}

function makeFeatureGraphic() {
  const background = path.join(tempRoot, "feature-background.png");
  const wordmark = path.join(tempRoot, "feature-wordmark.png");
  const headline = path.join(tempRoot, "feature-headline.png");
  const subhead = path.join(tempRoot, "feature-subhead.png");
  const output = path.join(outputRoot, "feature-graphic-1024x500.png");

  magick([
    generatedBackground,
    "-resize",
    "1024x500!",
    "-modulate",
    "78,62,100",
    "-fill",
    "rgba(0,0,0,0.14)",
    "-colorize",
    "14%",
    background,
  ]);
  textLayer({
    text: "VOX.MD",
    width: 260,
    height: 45,
    font: geistMono,
    pointSize: 27,
    color: "#F5F5F5",
    output: wordmark,
  });
  textLayer({
    text: "Capture now.\nOrganize later.",
    width: 620,
    height: 180,
    font: geist,
    pointSize: 66,
    color: "#FFFFFF",
    interline: -8,
    output: headline,
  });
  textLayer({
    text: "Local-first voice and text → Markdown.",
    width: 600,
    height: 45,
    font: geistRegular,
    pointSize: 26,
    color: "#B5B5B5",
    output: subhead,
  });
  magick([
    background,
    wordmark,
    "-geometry",
    "+58+63",
    "-composite",
    headline,
    "-geometry",
    "+58+150",
    "-composite",
    subhead,
    "-geometry",
    "+60+393",
    "-composite",
    "-stroke",
    "#FF9300",
    "-strokewidth",
    "4",
    "-draw",
    "line 58,364 116,364",
    "-alpha",
    "off",
    "-depth",
    "8",
    output,
  ]);
}

function makeContactSheet() {
  const files = slides.map((slide) => path.join(screenshotOutput, slide.file));
  const thumbs = files.map((file, index) => {
    const thumb = path.join(tempRoot, `contact-${index}.png`);
    magick([
      file,
      "-resize",
      "270x480!",
      "-bordercolor",
      "#0A0A0A",
      "-border",
      "12x12",
      thumb,
    ]);
    return thumb;
  });
  magick([
    ...thumbs,
    "+append",
    "-alpha",
    "off",
    "-depth",
    "8",
    path.join(outputRoot, "screenshots-contact-sheet.png"),
  ]);
}

for (const required of [generatedBackground, icon, geist, geistRegular, geistMono]) {
  if (!fs.existsSync(required)) {
    throw new Error(`Missing required input: ${required}`);
  }
}

fs.mkdirSync(screenshotOutput, { recursive: true });
slides.forEach(makeSlide);
makeFeatureGraphic();
makeContactSheet();

console.log(`Created ${slides.length + 2} Play Store graphics in ${outputRoot}`);
