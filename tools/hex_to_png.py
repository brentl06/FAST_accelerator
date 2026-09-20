#!/usr/bin/env python3

import sys
import numpy as np
from PIL import Image
WIDTH, HEIGHT = 640, 480
BORDER = 1

def load_hex(path):
    vals = []
    with open(path) as f:
        for line in f:
            line = line.split("//")[0].strip()
            if line:
                vals.append(int(line, 16))
    return np.array(vals, dtype=np.uint8)

def main():
    w = WIDTH - 2 * BORDER
    h = HEIGHT - 2 * BORDER
    expected = w * h
    vals = load_hex("out.hex")
    print(f"out.hex: {vals.size} values (expected {expected})")

    if vals.size != expected:
        delta = vals.size - expected
        print(f"FAIL: count off by {delta}.")
        if delta % w == 0:
            print(f"      exactly {delta // w} row(s) -- check the row loop bounds "
                  "and end-of-frame handling.")
        else:
            print("      not a whole number of rows -- check valid-signal alignment.")
        sys.exit(1)

    out = vals.reshape(h, w)
    Image.fromarray(out).save("out.png")
    print("wrote out.png")

    ref = np.array(Image.open("test.png").convert("L"), dtype=np.uint8)
    if BORDER:
        ref = ref[BORDER:-BORDER, BORDER:-BORDER]

    if np.array_equal(out, ref):
        print("PASS: out.png matches the input.")
        return

    diff = out.astype(int) - ref.astype(int)
    nbad = int(np.count_nonzero(diff))
    print(f"FAIL: {nbad} of {ref.size} pixels differ (max |diff| = {abs(diff).max()}).")
    
    # Pure shift:
    fo, fr = out.flatten(), ref.flatten()
    for s in range(1, 4):
        if np.array_equal(fo[s:], fr[:-s]):
            print(f"      shifted LATE by {s} pixel(s) -- valid asserts too early.")
            return
        if np.array_equal(fo[:-s], fr[s:]):
            print(f"      shifted EARLY by {s} pixel(s) -- valid asserts too late.")
            return

    # Per-row shift:
    for s in (1, 2):
        if np.array_equal(out[:, s:], ref[:, :-s]):
            print(f"      every row shifted LEFT by {s} px -- window_valid fires "
                  f"{s} cycle(s) early relative to the window contents.")
            return
        if np.array_equal(out[:, :-s], ref[:, s:]):
            print(f"      every row shifted RIGHT by {s} px -- window_valid fires "
                  f"{s} cycle(s) late relative to the window contents.")
            return

    # Whole-row offset:
    for s in (1, 2):
        if np.array_equal(out[s:, :], ref[:-s, :]):
            print(f"      output starts {s} row(s) late -- line buffer fill / "
                  "row counter threshold.")
            return

    print("      not a simple shift. Open out.png and look at it.")


if __name__ == "__main__":
    main()
