"""
Synthetic 60 fps benchmark for camera AIR.

Builds hand cut-outs from MediaPipe sample photos, moves them across a scene with known
trajectories (slow, fast flicks, two hands, idle, empty), renders motion blur, low light,
sensor noise and webcam JPEG compression, then for every frame:
  * runs MediaPipe HandLandmarker (VIDEO mode) on the raw frame and on the low-light
    corrected frame (same LUT as camera-core.js),
  * stores the luminance bands around each beam line for the fast (background) mode,
  * stores ground truth per beam: was the beam crossed by the hand during the frame interval.

Usage: python generate.py <hand_landmarker.task> <assets dir> <out dir>
"""
import json, math, os, sys
import numpy as np
import cv2
import mediapipe as mp
from mediapipe.tasks.python import vision, BaseOptions

W, H, FPS = 640, 480, 60
FAST_W = 320
BEAMS = [0.85 + (0.25 - 0.85) * i / 5 for i in range(6)]  # beam 1 (lowest) .. beam 6
BAND = 1
SUB = 8  # sub-frames per frame for motion blur and swept ground truth
rng = np.random.default_rng(1234)

LIGHTING = {
    # gain, sensor noise sigma, exposure fraction of the frame interval, jpeg quality
    "bright": dict(gain=1.0, noise=2.0, exposure=0.3, jpeg=85),
    "dim": dict(gain=0.33, noise=5.0, exposure=0.7, jpeg=75),
    "dark": dict(gain=0.14, noise=8.0, exposure=1.0, jpeg=70),
}


def landmarker(model, mode, hands=2):
    opts = vision.HandLandmarkerOptions(base_options=BaseOptions(model_asset_path=model), num_hands=hands,
                                        running_mode=mode, min_hand_detection_confidence=0.5,
                                        min_hand_presence_confidence=0.5, min_tracking_confidence=0.5)
    return vision.HandLandmarker.create_from_options(opts)


def make_cutouts(model, assets):
    """Return list of (rgba hand image, landmarks in cut-out pixel coords)."""
    det = landmarker(model, vision.RunningMode.IMAGE, 4)
    cuts = []
    for name in sorted(os.listdir(assets)):
        img = cv2.imread(os.path.join(assets, name))
        if img is None:
            continue
        rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
        res = det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb))
        for lms in res.hand_landmarks:
            pts = np.array([[p.x * img.shape[1], p.y * img.shape[0]] for p in lms], np.float32)
            size = max(np.ptp(pts[:, 0]), np.ptp(pts[:, 1]))
            hull = cv2.convexHull(pts.astype(np.int32))
            mask = np.zeros(img.shape[:2], np.uint8)
            cv2.fillConvexPoly(mask, hull, 255)
            for a, b in [(0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8), (9, 10), (10, 11), (11, 12),
                         (13, 14), (14, 15), (15, 16), (0, 17), (17, 18), (18, 19), (19, 20)]:
                cv2.line(mask, tuple(map(int, pts[a])), tuple(map(int, pts[b])), 255, max(3, int(size * 0.09)))
            mask = cv2.dilate(mask, np.ones((3, 3), np.uint8), iterations=max(1, int(size * 0.03)))
            # keep skin-coloured pixels inside the dilated hull (drops most of the photo background)
            ycc = cv2.cvtColor(img, cv2.COLOR_BGR2YCrCb)
            skin = cv2.inRange(ycc, (0, 133, 77), (255, 180, 135))
            skin = cv2.morphologyEx(skin, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))
            core = np.zeros_like(mask)
            cv2.fillConvexPoly(core, hull, 255)
            alpha = cv2.bitwise_and(mask, cv2.bitwise_or(skin, cv2.erode(core, np.ones((5, 5), np.uint8), iterations=2)))
            alpha = cv2.GaussianBlur(alpha, (5, 5), 0)
            ys, xs = np.nonzero(alpha > 20)
            if len(xs) < 100:
                continue
            x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
            rgba = np.dstack([rgb[y0:y1, x0:x1], alpha[y0:y1, x0:x1]])
            cuts.append((rgba, pts - [x0, y0]))
    det.close()
    return cuts


def background():
    """A room-like scene with an iPad slider at the bottom."""
    y = np.linspace(0, 1, H)[:, None]
    base = (110 + 60 * y) * np.ones((1, W))
    img = np.dstack([base * 0.95, base, base * 1.05])
    tex = cv2.GaussianBlur(rng.normal(0, 18, (H, W)), (0, 0), 3)
    img += tex[..., None]
    cv2.rectangle(img, (30, 40), (190, 260), (70, 80, 95), -1)       # shelf
    cv2.rectangle(img, (470, 60), (610, 200), (160, 150, 120), -1)   # poster
    cv2.rectangle(img, (0, int(H * 0.9)), (W, H), (25, 25, 30), -1)  # iPad slider
    for i in range(16):
        x = int(i * W / 16)
        cv2.line(img, (x, int(H * 0.9)), (x, H), (60, 60, 80), 1)
    return np.clip(img, 0, 255).astype(np.float32)


# ---------- trajectories: list of hands, each returns (cx, cy, scale) at time t or None ----------
def flick(t, period, rise_frames, x=0.5, phase=0.0, low=1.02, high=0.08):
    """Hand rests low, flicks up through all beams in `rise_frames`, holds, comes back down."""
    rise = rise_frames / FPS
    u = (t + phase) % period
    hold = 0.18
    if u < 0.3:
        y = low
    elif u < 0.3 + rise:
        y = low + (high - low) * (u - 0.3) / rise
    elif u < 0.3 + rise + hold:
        y = high
    elif u < 0.3 + 2 * rise + hold:
        y = high + (low - high) * (u - 0.3 - rise - hold) / rise
    else:
        y = low
    return (x, y)


SCENARIOS = {
    "slow": dict(seconds=6, hands=[lambda t: (0.5 + 0.1 * math.sin(t * 1.3), 0.55 + 0.42 * math.sin(2 * math.pi * t / 2.0))]),
    "flick6": dict(seconds=6, hands=[lambda t: flick(t, 1.0, 6)]),
    "flick4": dict(seconds=6, hands=[lambda t: flick(t, 0.9, 4)]),
    "flick3": dict(seconds=6, hands=[lambda t: flick(t, 0.8, 3)]),
    "flick2": dict(seconds=6, hands=[lambda t: flick(t, 0.8, 2)]),
    "two_hands": dict(seconds=6, hands=[lambda t: flick(t, 1.0, 4, x=0.3), lambda t: flick(t, 1.0, 4, x=0.7, phase=0.5)]),
    "idle_mid": dict(seconds=4, hands=[lambda t: (0.5 + 0.01 * math.sin(t * 7), 0.6 + 0.01 * math.sin(t * 5))]),
    "empty": dict(seconds=4, hands=[]),
}
HAND_PX = 150  # rendered hand height in pixels


def place(cut, cx, cy):
    rgba, pts = cut
    s = HAND_PX / rgba.shape[0]
    img = cv2.resize(rgba, None, fx=s, fy=s, interpolation=cv2.INTER_AREA)
    x0 = int(round(cx * W - img.shape[1] / 2))
    y0 = int(round(cy * H - img.shape[0] / 2))
    return img, x0, y0, pts * s + [x0, y0]


def composite(frame, img, x0, y0, mask_acc):
    h, w = img.shape[:2]
    fx0, fy0, fx1, fy1 = max(0, x0), max(0, y0), min(W, x0 + w), min(H, y0 + h)
    if fx0 >= fx1 or fy0 >= fy1:
        return
    sub = img[fy0 - y0:fy1 - y0, fx0 - x0:fx1 - x0].astype(np.float32)
    a = sub[..., 3:4] / 255.0
    frame[fy0:fy1, fx0:fx1] = frame[fy0:fy1, fx0:fx1] * (1 - a) + sub[..., :3] * a
    mask_acc[fy0:fy1, fx0:fx1] = np.maximum(mask_acc[fy0:fy1, fx0:fx1], (a[..., 0] > 0.5))


def low_light_input(rgb):
    """What camera-core.js feeds the AI in the dark: half resolution, 3x3 box blur twice, then the LUT."""
    lum = 0.299 * rgb[::8, ::8, 0] + 0.587 * rgb[::8, ::8, 1] + 0.114 * rgb[::8, ::8, 2]
    gain = min(6.0, max(1.0, 105.0 / max(float(lum.mean()), 1.0)))
    if gain <= 1.05:
        return rgb, 1.0
    small = cv2.resize(rgb, (rgb.shape[1] // 2, rgb.shape[0] // 2), interpolation=cv2.INTER_AREA)
    small = cv2.blur(cv2.blur(small, (3, 3)), (3, 3))
    v = np.arange(256) / 255.0
    lut = np.clip(np.round(255.0 * np.power(np.minimum(1.0, v * gain), 0.85)), 0, 255).astype(np.uint8)
    return lut[small], gain


def low_light_lut(rgb):
    """Same correction as camera-core.js lowLightLut(): gain to a target mean, then gamma."""
    lum = 0.299 * rgb[::8, ::8, 0] + 0.587 * rgb[::8, ::8, 1] + 0.114 * rgb[::8, ::8, 2]
    mean = float(lum.mean())
    gain = min(6.0, max(1.0, 105.0 / max(mean, 1.0)))
    if gain <= 1.05:
        return rgb, 1.0
    v = np.arange(256) / 255.0
    lut = np.clip(255.0 * np.power(np.minimum(1.0, v * gain), 0.85), 0, 255).astype(np.uint8)
    return lut[rgb], gain


def main():
    model, assets, out = sys.argv[1:4]
    os.makedirs(out, exist_ok=True)
    cuts = make_cutouts(model, assets)
    print("hand cut-outs:", len(cuts))
    bg = background()
    fast_h = round(FAST_W * H / W)
    meta = dict(fps=FPS, width=W, height=H, fastWidth=FAST_W, fastHeight=fast_h, band=BAND, beams=BEAMS, scenarios=[])
    for light_name, light in LIGHTING.items():
        # Background-only frames (same light, noise and compression) for the fast mode's "save background".
        bg_bands = []
        for _ in range(15):
            img = np.clip(bg * light["gain"] + rng.normal(0, light["noise"], bg.shape), 0, 255).astype(np.uint8)
            ok, enc = cv2.imencode(".jpg", cv2.cvtColor(img, cv2.COLOR_RGB2BGR), [cv2.IMWRITE_JPEG_QUALITY, light["jpeg"]])
            img = cv2.cvtColor(cv2.imdecode(enc, cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
            small = cv2.resize(img, (FAST_W, fast_h), interpolation=cv2.INTER_AREA).astype(np.float32)
            lum = small[..., 0] * 0.299 + small[..., 1] * 0.587 + small[..., 2] * 0.114
            bg_bands.append(np.stack([lum[max(0, round(yb * (fast_h - 1)) - BAND):min(fast_h, round(yb * (fast_h - 1)) + BAND + 1)].round().astype(np.uint8) for yb in BEAMS]))
        np.save(os.path.join(out, light_name + ".bg.npy"), np.stack(bg_bands))
        for scen_name, scen in SCENARIOS.items():
            n = int(scen["seconds"] * FPS)
            hand_cuts = [cuts[(i * 2 + len(scen_name)) % len(cuts)] for i in range(len(scen["hands"]))]
            det_raw = landmarker(model, vision.RunningMode.VIDEO)
            det_fix = landmarker(model, vision.RunningMode.VIDEO)
            frames_out, bands = [], []
            for f in range(n):
                t = f / FPS
                acc = np.zeros((H, W, 3), np.float32)
                gt_lm = [False] * 6
                gt_mask = [False] * 6
                exp_subs = max(1, int(round(SUB * light["exposure"])))
                for s in range(SUB):
                    ts = t - (SUB - 1 - s) / SUB / FPS  # sub-frame times across the frame interval
                    frame = bg.copy()
                    mask = np.zeros((H, W), np.float32)
                    for traj, cut in zip(scen["hands"], hand_cuts):
                        cx, cy = traj(ts)
                        img, x0, y0, lm = place(cut, cx, cy)
                        composite(frame, img, x0, y0, mask)
                        lo, hi = lm[:, 1].min() / H, lm[:, 1].max() / H
                        for b, yb in enumerate(BEAMS):
                            if lo <= yb <= hi:
                                gt_lm[b] = True
                    rows = mask.any(axis=1)
                    for b, yb in enumerate(BEAMS):
                        if rows[int(yb * (H - 1))]:
                            gt_mask[b] = True
                    if s >= SUB - exp_subs:
                        acc += frame
                img = acc / exp_subs
                img = img * light["gain"] + rng.normal(0, light["noise"], img.shape)
                img = np.clip(img, 0, 255).astype(np.uint8)
                ok, enc = cv2.imencode(".jpg", cv2.cvtColor(img, cv2.COLOR_RGB2BGR), [cv2.IMWRITE_JPEG_QUALITY, light["jpeg"]])
                img = cv2.cvtColor(cv2.imdecode(enc, cv2.IMREAD_COLOR), cv2.COLOR_BGR2RGB)
                ts_ms = int(f * 1000 / FPS)
                res_raw = det_raw.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=img), ts_ms)
                fixed, gain = low_light_input(img)
                res_fix = det_fix.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=np.ascontiguousarray(fixed)), ts_ms)
                small = cv2.resize(img, (FAST_W, fast_h), interpolation=cv2.INTER_AREA).astype(np.float32)
                lum = small[..., 0] * 0.299 + small[..., 1] * 0.587 + small[..., 2] * 0.114
                band = []
                for yb in BEAMS:
                    yc = round(yb * (fast_h - 1))
                    band.append(lum[max(0, yc - BAND):min(fast_h, yc + BAND + 1)].round().astype(np.uint8))
                bands.append(np.stack(band))
                frames_out.append(dict(
                    t=ts_ms, gtHand=gt_lm, gtMask=gt_mask, gain=round(gain, 2),
                    raw=[[[round(p.x, 4), round(p.y, 4)] for p in h] for h in res_raw.hand_landmarks],
                    fixed=[[[round(p.x, 4), round(p.y, 4)] for p in h] for h in res_fix.hand_landmarks],
                ))
                if f in (0, n // 3) and scen_name in ("flick3", "two_hands", "empty"):
                    cv2.imwrite(os.path.join(out, f"{light_name}-{scen_name}-{f}.jpg"), cv2.cvtColor(img, cv2.COLOR_RGB2BGR))
            det_raw.close()
            det_fix.close()
            key = f"{light_name}-{scen_name}"
            np.save(os.path.join(out, key + ".bands.npy"), np.stack(bands))
            with open(os.path.join(out, key + ".json"), "w") as fh:
                json.dump(frames_out, fh)
            meta["scenarios"].append(dict(key=key, light=light_name, scenario=scen_name, frames=n))
            hit = sum(1 for fr in frames_out if fr["raw"])
            hit2 = sum(1 for fr in frames_out if fr["fixed"])
            print(f"{key:20s} frames={n} handFrames(raw)={hit} handFrames(fixed)={hit2}", flush=True)
    with open(os.path.join(out, "meta.json"), "w") as fh:
        json.dump(meta, fh)


if __name__ == "__main__":
    main()
