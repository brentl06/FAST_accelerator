#!/usr/bin/env python3
"""
fast_check.py -- verify the RTL FAST detector against OpenCV.

    python3 tools/fast_check.py            # all configs (needs iverilog)
    python3 tools/fast_check.py --quick    # small images only

For each config it writes an image, runs fast_detector_tb in Icarus, and
compares the RTL keypoints (position and score) for both frames with:
  1. OpenCV FAST (TYPE_9_16, nonmaxSuppression=True)
  2. a brute-force NumPy FAST-9 written from the definition
The two references must agree with each other before the RTL is judged, so
neither can quietly share a mistake with the hardware.

Known, intended difference: OpenCV can report the last FAST column/row
(x = W-4, y = H-4); the streaming design cannot, so those are excluded.
OpenCV's response is S - 1 where S is the RTL score.

Requires: numpy, opencv-python, iverilog.
"""

import os
import subprocess
import sys
import tempfile

import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "camera_accelerator.srcs", "sources_1", "new")
SIM = os.path.join(ROOT, "camera_accelerator.srcs", "sim_1", "new")
RTL = [os.path.join(SRC, f) for f in
       ("line_window.v", "fast_score.v", "fast_nms.v", "fast_detector.v",
        "fast_pipeline_top.v")]
TB = os.path.join(SIM, "fast_detector_tb.v")

CIRCLE = [(0, -3), (1, -3), (2, -2), (3, -1), (3, 0), (3, 1), (2, 2), (1, 3),
          (0, 3), (-1, 3), (-2, 2), (-3, 1), (-3, 0), (-3, -1), (-2, -2), (-1, -3)]


# ---------------------------------------------------------------- references

def opencv_fast(img, t):
    det = cv2.FastFeatureDetector_create(
        threshold=t, nonmaxSuppression=True,
        type=cv2.FAST_FEATURE_DETECTOR_TYPE_9_16)
    h, w = img.shape
    out = {}
    for kp in det.detect(img, None):
        x, y = int(round(kp.pt[0])), int(round(kp.pt[1]))
        if x <= w - 5 and y <= h - 5:
            out[(x, y)] = int(round(kp.response)) + 1
    return out


def numpy_fast(img, t):
    """Brute force: S = max over arcs and polarities of the min difference."""
    h, w = img.shape
    a = img.astype(np.int32)
    c = a[3:h - 3, 3:w - 3]
    ring = np.stack([a[3 + dy:h - 3 + dy, 3 + dx:w - 3 + dx] for dx, dy in CIRCLE])
    best = np.zeros_like(c)
    for sign in (1, -1):
        d = sign * (ring - c)
        for start in range(16):
            arc = d[[(start + i) % 16 for i in range(9)]].min(axis=0)
            best = np.maximum(best, arc)
    score = np.zeros((h, w), np.int32)
    score[3:h - 3, 3:w - 3] = np.where(best > t, best, 0)

    out = {}
    ys, xs = np.nonzero(score)
    for y, x in zip(ys, xs):
        s = score[y, x]
        nb = score[y - 1:y + 2, x - 1:x + 2].copy()
        nb[1, 1] = -1
        if (s > nb).all() and x <= w - 5 and y <= h - 5:
            out[(int(x), int(y))] = int(s)
    return out


# ---------------------------------------------------------------- images

def test_image(w, h):
    """The png_to_hex.py pattern, scaled to w x h."""
    y, x = np.mgrid[0:h, 0:w]
    a = (x * 255 // max(w - 1, 1) * 0.4 + y * 255 // max(h - 1, 1) * 0.3).astype(np.uint8)
    sy, sx = h / 480, w / 640
    def box(y0, y1, x0, x1, v):
        a[int(y0 * sy):int(y1 * sy), int(x0 * sx):int(x1 * sx)] = v
    box(80, 200, 100, 260, 240)
    box(300, 420, 380, 500, 15)
    box(120, 160, 420, 560, 200)
    box(260, 290, 60, 340, 30)
    for i in range(6):
        for j in range(6):
            if (i + j) % 2 == 0:
                box(360 + i * 16, 376 + i * 16, 80 + j * 16, 96 + j * 16, 255)
    return a


def scene_image(w, h, seed):
    """Smooth background, random rectangles and blobs, sensor-like noise."""
    rng = np.random.default_rng(seed)
    a = cv2.GaussianBlur(rng.uniform(0, 255, (h, w)).astype(np.float32), (0, 0), 12)
    a = cv2.normalize(a, None, 40, 200, cv2.NORM_MINMAX)
    for _ in range(40):
        x0, y0 = rng.integers(0, w), rng.integers(0, h)
        cv2.rectangle(a, (int(x0), int(y0)),
                      (int(x0 + rng.integers(5, 80)), int(y0 + rng.integers(5, 80))),
                      float(rng.integers(0, 256)), -1)
    for _ in range(30):
        cv2.circle(a, (int(rng.integers(0, w)), int(rng.integers(0, h))),
                   int(rng.integers(3, 30)), float(rng.integers(0, 256)), -1)
    a += rng.normal(0, 4, (h, w))
    return np.clip(a, 0, 255).astype(np.uint8)


def noise_image(w, h, seed):
    return np.random.default_rng(seed).integers(0, 256, (h, w), dtype=np.uint8)


# ---------------------------------------------------------------- runner

def run_rtl(img, t0, t1, gaps, seed, work):
    h, w = img.shape
    hexf = os.path.join(work, "image.hex")
    kpf = os.path.join(work, "rtl_keypoints.txt")
    with open(hexf, "w") as f:
        f.write("\n".join(f"{v:02x}" for v in img.flatten()) + "\n")
    simf = os.path.join(work, "sim")
    subprocess.run(
        ["iverilog", "-g2012", "-o", simf, "-s", "fast_detector_tb",
         f"-Pfast_detector_tb.W={w}", f"-Pfast_detector_tb.H={h}",
         f"-Pfast_detector_tb.THRESH0={t0}", f"-Pfast_detector_tb.THRESH1={t1}",
         f"-Pfast_detector_tb.GAPS={gaps}", f"-Pfast_detector_tb.SEED={seed}",
         f'-Pfast_detector_tb.IMAGE="{hexf}"', f'-Pfast_detector_tb.KP_OUT="{kpf}"',
         TB] + RTL, check=True)
    log = subprocess.run(["vvp", "-n", simf], capture_output=True, text=True).stdout
    tb_ok = "TB PASS" in log
    frames = [{}, {}]
    for line in open(kpf):
        fr, x, y, s = map(int, line.split())
        frames[fr][(x, y)] = s
    return tb_ok, log.strip().splitlines(), frames


def diff(name, got, ref):
    missing = sorted(set(ref) - set(got))
    extra = sorted(set(got) - set(ref))
    bad = sorted(p for p in set(got) & set(ref) if got[p] != ref[p])
    if not (missing or extra or bad):
        return True
    print(f"    {name}: {len(missing)} missing, {len(extra)} extra, {len(bad)} wrong score")
    for label, pts in (("missing", missing), ("extra", extra), ("score", bad)):
        for p in pts[:5]:
            print(f"      {label} {p}: rtl={got.get(p)} ref={ref.get(p)}")
    return False


def main():
    quick = "--quick" in sys.argv
    configs = [
        # name,              image,                        t0, t1, gaps
        ("noise 64x48",      noise_image(64, 48, 1),        5, 30, 1),
        ("noise 100x50",     noise_image(100, 50, 2),       1, 60, 0),
        ("scene 160x120",    scene_image(160, 120, 3),     10, 25, 1),
    ]
    if not quick:
        configs += [
            ("test pattern 640x480", test_image(640, 480), 20, 40, 0),
            ("scene 640x480",        scene_image(640, 480, 4), 12, 30, 1),
        ]

    all_ok = True
    with tempfile.TemporaryDirectory() as work:
        for i, (name, img, t0, t1, gaps) in enumerate(configs):
            print(f"{name}  t={t0}/{t1}  gaps={gaps}")
            tb_ok, log, frames = run_rtl(img, t0, t1, gaps, i + 1, work)
            ok = tb_ok
            if not tb_ok:
                print("    testbench:", *log[-6:], sep="\n      ")
            for fr, t in enumerate((t0, t1)):
                cv_ref, np_ref = opencv_fast(img, t), numpy_fast(img, t)
                if not diff(f"frame {fr}: numpy vs OpenCV", np_ref, cv_ref):
                    print("    REFERENCE DISAGREEMENT -- fix the model first")
                    ok = False
                    continue
                ok &= diff(f"frame {fr}: RTL vs OpenCV", frames[fr], cv_ref)
                print(f"    frame {fr}: {len(cv_ref)} keypoints, RTL found {len(frames[fr])}")
            print("    PASS" if ok else "    FAIL")
            all_ok &= ok

    print("\nALL CONFIGS PASSED" if all_ok else "\nSOME CONFIGS FAILED")
    sys.exit(0 if all_ok else 1)


if __name__ == "__main__":
    main()
