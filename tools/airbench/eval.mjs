// Replays the airbench dataset through camera/camera-core.js and reports beam accuracy.
// Usage: node tools/airbench/eval.mjs <data dir> [--json out.json]
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const core = await import(path.join(here, "..", "..", "camera", "camera-core.js"));
const { HandTracker, handSpan, beamsFromSpans, BeamDebouncer, BackgroundModel, judgeBand, judgeBandLegacy, adaptBand, motionBand } = core;

const dataDir = process.argv[2];
// meta.json is written when generation finishes; while it runs, evaluate whatever scenarios exist.
const meta = fs.existsSync(path.join(dataDir, "meta.json")) ? JSON.parse(fs.readFileSync(path.join(dataDir, "meta.json"), "utf8")) : {
  beams: Array.from({ length: 6 }, (_, i) => 0.85 + (0.25 - 0.85) * i / 5),
  scenarios: fs.readdirSync(dataDir).filter((f) => /^[a-z]+-[a-z0-9_]+\.json$/.test(f) && fs.existsSync(path.join(dataDir, f.replace(".json", ".bands.npy"))))
    .map((f) => { const key = f.replace(".json", ""); const [light, ...rest] = key.split("-"); return { key, light, scenario: rest.join("-") }; }),
};

function readNpy(file) {
  const buf = fs.readFileSync(file);
  const headerLen = buf.readUInt16LE(8);
  const header = buf.toString("latin1", 10, 10 + headerLen);
  const shape = header.match(/'shape': \(([^)]*)\)/)[1].split(",").map((s) => s.trim()).filter(Boolean).map(Number);
  if (!/'descr': '\|u1'/.test(header)) throw new Error("expected uint8 npy");
  return { shape, data: new Uint8Array(buf.buffer, buf.byteOffset + 10 + headerLen) };
}

// ---------- metrics ----------
// Ground truth is "the beam was crossed during this frame interval". Detection may lag by one frame.
function metrics(pred, gt) {
  let tp = 0, fn = 0, fp = 0, tn = 0, events = 0, eventHits = 0, latency = 0;
  const n = gt.length, beams = gt[0].length;
  for (let b = 0; b < beams; b++) {
    for (let f = 0; f < n; f++) {
      const g = gt[f][b], p = pred[f][b];
      const gNear = g || (f > 0 && gt[f - 1][b]);
      const pNear = p || (f + 1 < n && pred[f + 1][b]);
      if (g) { if (pNear) tp++; else fn++; }
      if (p && !gNear) fp++;
      if (!p && !g) tn++;
    }
    // events: contiguous runs of ground-truth "on"
    for (let f = 0; f < n; f++) {
      if (!gt[f][b] || (f > 0 && gt[f - 1][b])) continue;
      let end = f; while (end + 1 < n && gt[end + 1][b]) end++;
      events++;
      for (let k = f; k <= Math.min(n - 1, end + 1); k++) if (pred[k][b]) { eventHits++; latency += k - f; break; }
    }
  }
  return { recall: tp / Math.max(1, tp + fn), fpRate: fp / Math.max(1, fp + tn), events, eventRecall: events ? eventHits / events : 1, latency: eventHits ? latency / eventHits : 0, fp };
}

// ---------- AI pipeline ----------
function runAi(frames, variant, bands) {
  const tracker = new HandTracker({ sweep: variant.sweep, coastFrames: variant.coast });
  const deb = new BeamDebouncer(meta.beams.length);
  const [, beams, rows, width] = bands.shape, per = beams * rows * width, bandSize = rows * width;
  return frames.map((fr, f) => {
    const hands = fr[variant.input];
    const spans = [];
    for (const h of hands) { const sp = handSpan(h.map(([x, y]) => ({ x, y })), 0, 1); if (sp) spans.push(sp); }
    tracker.update(spans, fr.t);
    const raw = beamsFromSpans(tracker.spansAt(fr.t, "off"), meta.beams, variant.pad);
    if (variant.motion && f > 0) {
      const windows = tracker.motionWindows(fr.t, variant.motion.holdMs, variant.motion.halfWidth).map(([a, b]) => [a * width, b * width]);
      if (windows.length) {
        const cur = bands.data.subarray(f * per, (f + 1) * per), prev = bands.data.subarray((f - 1) * per, f * per);
        for (let b = 0; b < beams; b++) {
          if (raw[b]) continue;
          if (motionBand(cur.subarray(b * bandSize, (b + 1) * bandSize), prev.subarray(b * bandSize, (b + 1) * bandSize), rows, width, windows, variant.motion).blocked) raw[b] = true;
        }
      }
    }
    return deb.apply(raw, 1).slice();
  });
}

// ---------- fast pipeline ----------
function runFast(bandsNpy, bgNpy, variant) {
  const [n, beams, rows, width] = bandsNpy.shape;
  const per = beams * rows * width;
  const model = new BackgroundModel(per);
  for (let i = 0; i < bgNpy.shape[0]; i++) model.add(bgNpy.data.subarray(i * per, (i + 1) * per));
  model.finish();
  const out = [];
  const stride = width, bandSize = rows * width;
  for (let f = 0; f < n; f++) {
    const frame = bandsNpy.data.subarray(f * per, (f + 1) * per);
    const raw = [];
    for (let b = 0; b < beams; b++) {
      const band = frame.subarray(b * bandSize, (b + 1) * bandSize);
      const mean = model.mean.subarray(b * bandSize, (b + 1) * bandSize);
      const std = model.std.subarray(b * bandSize, (b + 1) * bandSize);
      const res = variant.legacy
        ? judgeBandLegacy(band, mean, rows, stride, 0, width, variant)
        : judgeBand(band, mean, std, rows, stride, 0, width, variant);
      raw.push(res.blocked);
      if (!res.blocked && variant.adapt) adaptBand(band, mean, std, rows, stride, 0, width, variant.adapt);
    }
    out.push(raw);
  }
  return out;
}

const MOTION = { holdMs: 400, halfWidth: 0.12, thresh: 5, noiseK: 2.5, smooth: 4, minRun: 0.03 }; // same as camera.html
const AI_VARIANTS = {
  "AI 기존": { input: "raw", sweep: false, coast: 0, pad: 0.02 },
  "AI +저조도보정": { input: "fixed", sweep: false, coast: 0, pad: 0.02 },
  "AI +보정+스윕+유지": { input: "fixed", sweep: true, coast: 2, pad: 0.02 },
  "AI 최종(+모션보조)": { input: "fixed", sweep: true, coast: 2, pad: 0.02, motion: MOTION },
};
const FAST_VARIANTS = {
  "빠른 기존": { legacy: true, thresh: 30, sens: 0.03, adapt: 0.01 },
  "빠른 최종": { thresh: 4, noiseK: 2.5, smooth: 0, sens: 0.02, adapt: 0.01 }, // same as camera.html defaults
};

const results = [];
for (const sc of meta.scenarios) {
  const frames = JSON.parse(fs.readFileSync(path.join(dataDir, sc.key + ".json"), "utf8"));
  const gtHand = frames.map((f) => f.gtHand), gtMask = frames.map((f) => f.gtMask);
  const bands = readNpy(path.join(dataDir, sc.key + ".bands.npy"));
  const bg = readNpy(path.join(dataDir, sc.light + ".bg.npy"));
  for (const [name, v] of Object.entries(AI_VARIANTS)) results.push({ scenario: sc.scenario, light: sc.light, variant: name, ...metrics(runAi(frames, v, bands), gtHand) });
  for (const [name, v] of Object.entries(FAST_VARIANTS)) results.push({ scenario: sc.scenario, light: sc.light, variant: name, ...metrics(runFast(bands, bg, v), gtMask) });
}

// ---------- report ----------
const pct = (v) => (v * 100).toFixed(0).padStart(4) + "%";
const variants = [...Object.keys(AI_VARIANTS), ...Object.keys(FAST_VARIANTS)];
const lights = [...new Set(meta.scenarios.map((s) => s.light))];
const motion = (r) => !["empty", "idle_mid"].includes(r.scenario);
console.log("Per light (motion scenarios: slow, flick6/4/3/2, two_hands). eventRecall = beam crossings caught; recall = frames; FP = false-positive frame rate incl. empty/idle");
for (const light of lights) {
  console.log(`\n[${light}]`);
  console.log("variant".padEnd(26) + "eventRecall  frameRecall  latency(f)  FPrate");
  for (const v of variants) {
    const rs = results.filter((r) => r.light === light && r.variant === v);
    const mv = rs.filter(motion);
    const ev = mv.reduce((a, r) => a + r.eventRecall * r.events, 0) / Math.max(1, mv.reduce((a, r) => a + r.events, 0));
    const rec = mv.reduce((a, r) => a + r.recall, 0) / mv.length;
    const lat = mv.reduce((a, r) => a + r.latency, 0) / mv.length;
    const fpr = rs.reduce((a, r) => a + r.fpRate, 0) / rs.length;
    console.log(v.padEnd(26) + pct(ev).padEnd(13) + pct(rec).padEnd(13) + lat.toFixed(2).padEnd(12) + pct(fpr));
  }
}
console.log("\nPer scenario eventRecall (bright / dim / dark):");
for (const scen of [...new Set(meta.scenarios.map((s) => s.scenario))]) {
  const row = variants.map((v) => lights.map((l) => { const r = results.find((x) => x.scenario === scen && x.light === l && x.variant === v); return r ? (scen === "empty" ? "fp" + r.fp : Math.round(r.eventRecall * 100)) : "-"; }).join("/"));
  console.log(scen.padEnd(10) + row.map((s, i) => (variants[i].split(" ")[0] + ":" + s).padEnd(18)).join(""));
}
const jsonOut = process.argv.indexOf("--json");
if (jsonOut > 0) fs.writeFileSync(process.argv[jsonOut + 1], JSON.stringify(results, null, 1));
