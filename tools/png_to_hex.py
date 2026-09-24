#!/usr/bin/env python3
"""
png_to_hex.py -- make image.hex for the FPGA simulation.

  python3 png_to_hex.py                 # generates a 640x480 test image
  python3 png_to_hex.py photo.jpg       # uses a real image, resized to 640x480

Writes:
  test.png    the exact image that went in (compare against this, not the original)
  image.hex   one 8-bit grayscale value per line, plain hex, row-major

Requires: pillow, numpy   ->   pip install pillow numpy
"""

import sys
import numpy as np
from PIL import Image

WIDTH, HEIGHT = 640, 480


def make_test_image():
    """Gradient background with hard-edged shapes on top.

    The gradient proves the pipe is lossless. The shapes give real corners,
    which is what you actually want once FAST goes in at step 4 -- a pure
    gradient has no corners at all and would make FAST output nothing.
    """
    y, x = np.mgrid[0:HEIGHT, 0:WIDTH]
    a = (x * 255 // (WIDTH - 1) * 0.4 + y * 255 // (HEIGHT - 1) * 0.3).astype(np.uint8)

    a[80:200, 100:260] = 240      # bright rectangle  -> 4 strong corners
    a[300:420, 380:500] = 15      # dark rectangle    -> 4 strong corners
    a[120:160, 420:560] = 200     # thin bar
    a[260:290, 60:340]  = 30      # thin bar

    # Small checkerboard: dense corners, good stress test for NMS later.
    for i in range(6):
        for j in range(6):
            if (i + j) % 2 == 0:
                a[360 + i*16 : 376 + i*16, 80 + j*16 : 96 + j*16] = 255

    return Image.fromarray(a)


def main():
    if len(sys.argv) > 1:
        src = sys.argv[1]
        img = Image.open(src).convert("L").resize((WIDTH, HEIGHT))
        print(f"loaded {src} -> {WIDTH}x{HEIGHT} grayscale")
    else:
        img = make_test_image()
        print(f"generated {WIDTH}x{HEIGHT} test image")

    # Save the exact thing being streamed in, so the later comparison is
    # against post-resize, post-grayscale data rather than the original file.
    img.save("test.png")

    a = np.array(img, dtype=np.uint8)
    assert a.shape == (HEIGHT, WIDTH), a.shape

    with open("image.hex", "w") as f:
        f.write(f"// {WIDTH}x{HEIGHT} grayscale, row-major, one pixel per line\n")
        for v in a.flatten():
            f.write(f"{v:02x}\n")

    print(f"wrote test.png and image.hex ({a.size} pixels)")


if __name__ == "__main__":
    main()
