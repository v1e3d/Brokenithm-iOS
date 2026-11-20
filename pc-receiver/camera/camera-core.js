// Camera AIR judging core, shared by camera.html and the offline benchmark (tools/airbench).
// Pure functions and small classes only: no DOM, no canvas.
// Coordinates are normalized 0..1, y grows downward; beams[i] is the height of beam i+1 (index 0 = lowest).

export const BEAMS = 6;

// ---------- AI mode ----------

/** Vertical span of one hand's landmarks inside the ROI (x range), or null when the hand is outside. */
export function handSpan(pts, left, right) {
  const xMin = Math.min(left, right), xMax = Math.max(left, right);
  let minY = Infinity, maxY = -Infinity, inside = 0, cx = 0, cy = 0;
  for (const p of pts) {
    cx += p.x; cy += p.y;
    if (p.x < xMin || p.x > xMax) continue;
    inside++;
    if (p.y < minY) minY = p.y;
    if (p.y > maxY) maxY = p.y;
  }
  if (inside < 5) return null;
  return { minY, maxY, cx: cx / pts.length, cy: cy / pts.length };
}

/**
 * Points along the forearm below a hand (from the wrist, away from the knuckles), so the span covers the arm
 * like the cabinet's IR beams do: a raised hand keeps the lower beams blocked by the forearm.
 * lengthFactor is in hand lengths (wrist to middle fingertip ~ 1.9 x wrist-to-middle-knuckle).
 */
export function armPoints(pts, lengthFactor) {
  if (!lengthFactor || pts.length < 10) return [];
  const w = pts[0], k = pts[9];
  const dx = w.x - k.x, dy = w.y - k.y, d = Math.hypot(dx, dy);
  if (d < 1e-4) return [];
  const len = d * 1.9 * lengthFactor, ux = dx / d, uy = dy / d, out = [];
  for (let i = 1; i <= 4; i++) out.push({ x: w.x + ux * len * i / 4, y: w.y + uy * len * i / 4 });
  return out;
}

/**
 * Tracks up to N hands across camera frames by nearest centre, and produces the spans used for judging.
 *  - sweep: a fast hand can jump past a beam between two frames; like a real IR curtain, every beam the
 *    hand passed through since the previous frame counts as broken for this frame.
 *  - coast: when a tracked hand disappears (motion blur, detector miss) keep it alive at its predicted
 *    position for a few frames instead of dropping the AIR instantly.
 */
export class HandTracker {
  constructor(options) {
    // verticalWeight < 1: AIR motion is mostly vertical and fast (a flick can move 30% of the frame per camera
    // frame), while two hands are separated sideways, so vertical distance counts less when matching.
    this.options = Object.assign({ matchDistance: 0.25, verticalWeight: 0.3, sweep: true, coastFrames: 2, maxGapMs: 250 }, options || {});
    this.tracks = [];
    this.nextId = 1;
    this.frameInterval = 1000 / 60;
    this.lastT = 0;
    this.seen = [];
  }

  update(spans, t) {
    if (this.lastT) this.frameInterval = this.frameInterval * 0.8 + Math.min(200, t - this.lastT) * 0.2;
    this.lastT = t;
    const o = this.options, pairs = [];
    spans.forEach((sm, si) => this.tracks.forEach((tr, ti) => {
      // compare with where the hand should be now, not where it was
      const predictedCy = tr.last.cy + (tr.vy || 0) * Math.max(0, t - tr.last.t);
      const d = Math.hypot(sm.cx - tr.last.cx, (sm.cy - predictedCy) * o.verticalWeight);
      const reach = o.matchDistance;
      if (d < reach && t - tr.last.t < o.maxGapMs) pairs.push([d, si, ti]);
    }));
    pairs.sort((a, b) => a[0] - b[0]);
    const usedS = new Set(), usedT = new Set(), next = [];
    for (const [, si, ti] of pairs) {
      if (usedS.has(si) || usedT.has(ti)) continue;
      usedS.add(si); usedT.add(ti);
      const tr = this.tracks[ti], sm = Object.assign({ t }, spans[si]);
      const dt = Math.max(1, t - tr.last.t);
      next.push({ id: tr.id, prev: tr.last, last: sm, missed: 0, vy: ((sm.minY + sm.maxY) - (tr.last.minY + tr.last.maxY)) / 2 / dt });
    }
    spans.forEach((sm, si) => { if (!usedS.has(si)) next.push({ id: this.nextId++, prev: null, last: Object.assign({ t }, sm), missed: 0, vy: 0 }); });
    for (const sm of spans) this.seen.push({ t, cx: sm.cx, minY: sm.minY, maxY: sm.maxY });
    this.seen = this.seen.filter((h) => t - h.t <= 1000).slice(-16);
    // coast unmatched tracks at their predicted position
    this.tracks.forEach((tr, ti) => {
      if (usedT.has(ti) || tr.missed >= o.coastFrames) return;
      const dt = t - tr.last.t, shift = (tr.vy || 0) * dt;
      const ghost = { t, minY: tr.last.minY + shift, maxY: tr.last.maxY + shift, cx: tr.last.cx, cy: tr.last.cy + shift };
      next.push({ id: tr.id, prev: tr.last, last: ghost, missed: tr.missed + 1, vy: tr.vy });
    });
    this.tracks = next;
  }

  clear() { this.tracks = []; this.seen = []; }

  /** Horizontal windows around hands seen (by the AI) within holdMs, for motion assist. */
  motionWindows(now, holdMs, halfWidth) {
    const out = [];
    for (const h of this.seen) if (now - h.t <= holdMs) out.push([h.cx - halfWidth, h.cx + halfWidth]);
    return out;
  }

  /** Spans to judge at time `now`. interp: "off" | "smooth" | "predict". */
  spansAt(now, interp) {
    const out = [];
    for (const tr of this.tracks) {
      const { prev, last } = tr;
      let span;
      if (interp === "off" || !prev || interp === undefined) span = { minY: last.minY, maxY: last.maxY };
      else {
        const dt = Math.max(1, last.t - prev.t);
        let k;
        if (interp === "smooth") k = Math.min(1, Math.max(0, (now - this.frameInterval - prev.t) / dt));
        else k = 1 + Math.min(Math.max(0, now - last.t), dt, this.frameInterval) / dt;
        span = { minY: prev.minY + (last.minY - prev.minY) * k, maxY: prev.maxY + (last.maxY - prev.maxY) * k };
      }
      if (this.options.sweep && prev && last.t - prev.t <= this.frameInterval * 2.5) {
        // union with the previous frame's span: beams crossed between frames are not skipped
        span = { minY: Math.min(span.minY, prev.minY), maxY: Math.max(span.maxY, prev.maxY) };
      }
      out.push(span);
    }
    return out;
  }
}

/** Beams whose height lies inside any span (with padding). */
export function beamsFromSpans(spans, beams, pad) {
  const raw = new Array(beams.length).fill(false);
  for (const sp of spans) {
    const minY = sp.minY - pad, maxY = sp.maxY + pad;
    for (let i = 0; i < beams.length; i++) if (beams[i] >= minY && beams[i] <= maxY) raw[i] = true;
  }
  return raw;
}

/** Requires a change to persist `hold` evaluations before it is applied. */
export class BeamDebouncer {
  constructor(count) { this.state = new Array(count).fill(false); this.pending = new Array(count).fill(0); }
  apply(raw, hold) {
    for (let i = 0; i < raw.length; i++) {
      if (raw[i] === this.state[i]) { this.pending[i] = 0; continue; }
      if (++this.pending[i] >= hold) { this.state[i] = raw[i]; this.pending[i] = 0; }
    }
    return this.state;
  }
}

// ---------- low light ----------

/** Mean luminance of an RGBA buffer, sampled every `step` pixels. */
export function meanLuminance(rgba, step) {
  let sum = 0, n = 0;
  for (let k = 0; k < rgba.length; k += 4 * step) { sum += rgba[k] * 0.299 + rgba[k + 1] * 0.587 + rgba[k + 2] * 0.114; n++; }
  return n ? sum / n : 0;
}

/**
 * Brightening LUT for dark frames: gain to bring the mean up to ~105, then a mild gamma.
 * Returns null when the frame is bright enough. Mirrors tools/airbench/generate.py low_light_lut().
 */
export function lowLightLut(mean) {
  const gain = Math.min(6, Math.max(1, 105 / Math.max(mean, 1)));
  if (gain <= 1.05) return null;
  const lut = new Uint8ClampedArray(256);
  for (let v = 0; v < 256; v++) lut[v] = Math.round(255 * Math.pow(Math.min(1, (v / 255) * gain), 0.85));
  return { lut, gain };
}

/**
 * 3x3 box blur, applied twice (close to a Gaussian with sigma ~1.15), on RGBA in place.
 * In very dark frames the AI sees only sensor noise; half resolution + this blur + the LUT
 * brought hand detection in the "dark" benchmark from 0% to 100% of frames.
 * Mirrors tools/airbench/generate.py low_light_input() (cv2.blur 3x3 twice).
 */
export function boxBlur3(rgba, w, h) {
  // integer row sums, then one rounding per pass (like OpenCV's 2-D box filter); borders reflect-101
  const rowSum = new Uint16Array(w * h * 3);
  const refl = (i, n) => (i < 0 ? (n > 1 ? 1 : 0) : i >= n ? (n > 1 ? n - 2 : 0) : i);
  for (let pass = 0; pass < 2; pass++) {
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const k = (y * w + x) * 4, kl = (y * w + refl(x - 1, w)) * 4, kr = (y * w + refl(x + 1, w)) * 4, o = (y * w + x) * 3;
      for (let ch = 0; ch < 3; ch++) rowSum[o + ch] = rgba[kl + ch] + rgba[k + ch] + rgba[kr + ch];
    }
    for (let y = 0; y < h; y++) {
      const yu = refl(y - 1, h), yd = refl(y + 1, h);
      for (let x = 0; x < w; x++) {
        const k = (y * w + x) * 4, o = (y * w + x) * 3, ou = (yu * w + x) * 3, od = (yd * w + x) * 3;
        for (let ch = 0; ch < 3; ch++) rgba[k + ch] = Math.round((rowSum[ou + ch] + rowSum[o + ch] + rowSum[od + ch]) / 9);
      }
    }
  }
}

export function applyLut(rgba, lut) {
  for (let k = 0; k < rgba.length; k += 4) { rgba[k] = lut[rgba[k]]; rgba[k + 1] = lut[rgba[k + 1]]; rgba[k + 2] = lut[rgba[k + 2]]; }
}

/** In-place box filter over columns (radius r). A blurred hand is wide; sensor noise is not. */
export function smoothColumns(values, r) {
  if (!r) return values;
  const n = values.length, out = new Float32Array(n);
  let acc = 0;
  for (let c = 0; c < Math.min(n, r); c++) acc += values[c];
  for (let c = 0; c < n; c++) {
    if (c + r < n) acc += values[c + r];
    if (c - r - 1 >= 0) acc -= values[c - r - 1];
    out[c] = acc / (Math.min(n - 1, c + r) - Math.max(0, c - r) + 1);
  }
  return out;
}

// ---------- fast mode (background difference) ----------

/** Running background model: per-pixel mean and standard deviation of luminance. */
export class BackgroundModel {
  constructor(size) { this.size = size; this.reset(); }
  reset() { this.n = 0; this.sum = new Float64Array(this.size); this.sq = new Float64Array(this.size); this.mean = null; this.std = null; }
  add(lum) {
    for (let j = 0; j < this.size; j++) { const v = lum[j]; this.sum[j] += v; this.sq[j] += v * v; }
    this.n++;
  }
  finish() {
    this.mean = new Float32Array(this.size); this.std = new Float32Array(this.size);
    for (let j = 0; j < this.size; j++) {
      const m = this.sum[j] / this.n;
      this.mean[j] = m;
      this.std[j] = Math.sqrt(Math.max(0, this.sq[j] / this.n - m * m));
    }
    this.sum = null; this.sq = null;
  }
  get ready() { return this.mean !== null; }
}

/**
 * Judges one beam from a band of luminance pixels (rows x width) against the background band.
 *  - Rows are averaged per column (cuts noise by ~sqrt(rows)).
 *  - The median signed difference across the ROI is subtracted (camera auto-exposure / lighting drift).
 *  - A column changes when |diff| exceeds max(thresh, noiseK x background noise).
 *  - The beam is blocked when the longest run of changed columns (1-column gaps allowed) covers `sens` of the ROI.
 *
 * band, bgMean, bgStd: arrays of rows*stride values; columns x0..x1 (exclusive) are judged.
 * Returns { blocked, changed (Uint8Array over x0..x1) }.
 */
export function judgeBand(band, bgMean, bgStd, rows, stride, x0, x1, params) {
  const w = Math.max(1, x1 - x0);
  const diff = new Float32Array(w), noise = new Float32Array(w);
  for (let c = 0; c < w; c++) {
    let d = 0, s = 0;
    for (let r = 0; r < rows; r++) { const j = r * stride + x0 + c; d += band[j] - bgMean[j]; s += bgStd[j]; }
    diff[c] = d / rows;
    noise[c] = s / rows / Math.sqrt(rows);
  }
  if (params.smooth) {
    const sm = smoothColumns(diff, params.smooth), sn = smoothColumns(noise, params.smooth);
    const scale = 1 / Math.sqrt(2 * params.smooth + 1);
    for (let c = 0; c < w; c++) { diff[c] = sm[c]; noise[c] = sn[c] * scale; }
  }
  let offset = 0;
  if (params.driftCompensation !== false) {
    // Global lighting/exposure drift = median signed difference over the WHOLE band width (not just the ROI),
    // capped: when hands and arms cover most of a narrow ROI, the ROI median is the hand, not the lighting.
    const all = new Float32Array(stride);
    for (let c = 0; c < stride; c++) {
      let d = 0;
      for (let r = 0; r < rows; r++) { const j = r * stride + c; d += band[j] - bgMean[j]; }
      all[c] = d / rows;
    }
    all.sort();
    const cap = params.maxDrift ?? 12;
    offset = Math.max(-cap, Math.min(cap, all[stride >> 1]));
  }
  const changed = new Uint8Array(w);
  for (let c = 0; c < w; c++) {
    const thr = Math.max(params.thresh, (params.noiseK ?? 4) * noise[c]);
    if (Math.abs(diff[c] - offset) > thr) changed[c] = 1;
  }
  let best = 0, run = 0, gap = 0;
  for (let c = 0; c < w; c++) {
    if (changed[c]) { run += 1 + gap; gap = 0; if (run > best) best = run; }
    else if (run > 0 && gap === 0) gap = 1;
    else { run = 0; gap = 0; }
  }
  return { blocked: best / w >= params.sens, changed };
}

/** Lets clear beams slowly follow lighting changes (mean and noise). */
export function adaptBand(band, bgMean, bgStd, rows, stride, x0, x1, rate) {
  for (let r = 0; r < rows; r++) for (let c = x0; c < x1; c++) {
    const j = r * stride + c, d = band[j] - bgMean[j];
    bgMean[j] += d * rate;
    bgStd[j] += (Math.abs(d) - bgStd[j]) * rate * 0.5;
  }
}

/** The original fast-mode rule (any row differs by more than thresh; fraction of changed columns). Kept for comparison. */
export function judgeBandLegacy(band, bgMean, rows, stride, x0, x1, params) {
  const w = Math.max(1, x1 - x0), changed = new Uint8Array(w);
  for (let r = 0; r < rows; r++) for (let c = 0; c < w; c++) {
    const j = r * stride + x0 + c;
    if (Math.abs(band[j] - bgMean[j]) > params.thresh) changed[c] = 1;
  }
  let count = 0; for (let c = 0; c < w; c++) count += changed[c];
  return { blocked: count / w >= params.sens, changed };
}

// ---------- motion assist (AI mode) ----------

/**
 * Frame-difference check along one beam band, used when the AI loses a hand that was just there
 * (motion blur in low light). Only columns inside the given windows (around the last seen hands) count.
 * cur/prev: rows*stride luminance; windows: [[x0, x1], ...] in pixel columns.
 * The threshold adapts to the band's own noise (median absolute frame difference).
 */
export function motionBand(cur, prev, rows, stride, windows, params) {
  const diff = new Float32Array(stride);
  for (let c = 0; c < stride; c++) {
    let d = 0;
    for (let r = 0; r < rows; r++) { const j = r * stride + c; d += Math.abs(cur[j] - prev[j]); }
    diff[c] = d / rows;
  }
  const d2 = params.smooth ? smoothColumns(diff, params.smooth) : diff;
  for (let c = 0; c < stride; c++) diff[c] = d2[c];
  const sorted = Array.from(diff).sort((a, b) => a - b);
  const noise = sorted[stride >> 1];
  const thr = Math.max(params.thresh, (params.noiseK ?? 5) * noise);
  const minRun = Math.max(2, Math.round(params.minRun * stride));
  const changed = new Uint8Array(stride);
  let blocked = false;
  for (const [a, b] of windows) {
    const x0 = Math.max(0, Math.floor(a)), x1 = Math.min(stride, Math.ceil(b));
    let run = 0, gap = 0;
    for (let c = x0; c < x1; c++) {
      if (diff[c] > thr) { changed[c] = 1; run += 1 + gap; gap = 0; if (run >= minRun) blocked = true; }
      else if (run > 0 && gap === 0) gap = 1;
      else { run = 0; gap = 0; }
    }
  }
  return { blocked, changed };
}
