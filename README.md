# FAST / Single-Scale ORB Accelerator

An OV7670 camera accelerator for the Nexys A7-100T. The streaming FAST-9
detector feeds both a VGA keypoint overlay and a connected single-scale ORB
descriptor extractor. Matching, host transport and pose estimation are not
implemented yet.

## Architecture

- OV7670 camera must be configured for 640×480 YUV422; capture extracts
  grayscale bytes and crosses into the 100 MHz system clock through an async FIFO
- SW1/SW2 select the processing pipeline or active video mode:
  - SW2 `0`, SW1 `0` = live camera output
  - SW2 `0`, SW1 `1` = Sobel edge detection
  - SW2 `1` = FAST keypoint overlay
- Pixel outputs of processing pipeline are written into the frame buffer
- VGA controller reads the frame buffer and displays the image

```text
OV7670 -> capture / async FIFO -> 8-bit grayscale stream
                                  |
              +-------------------+--------------------------+
              |                   |                          |
          Raw / Sobel        Shared FAST-9 + NMS       Upper 4 pixel bits
              |                   |                          |
              +-> display mux <---+ red markers        Two raw frame banks
                       |          |                          |
                5-bit display     +-> grid top-N              |
                 framebuffer          |                      |
                       |         selected keypoints -> patch reader
                      VGA                              |
                                                 41x41 patch cache
                                                       |
                                              centroid orientation
                                                       |
                                              rotated 256-bit BRIEF
                                                       |
                                            tagged descriptor output
                                                       |
                                          digest / decimal-point activity
```

The board shares one continuously running FAST detector across both paths.
VGA uses a separate processed framebuffer; ORB owns two 640×480×4-bit raw
banks. Thus the current board design has **three framebuffers**, not two.

## ORB Descriptor Extraction

- An 8×6 grid retains up to 8 features per cell: **384 features per frame**.
  Candidates within 20 pixels of the image edge are rejected.
- A system-clock framebuffer read interface fetches 41×41 patches. Read
  requests use ready/valid handshaking and wait safely behind same-bank writes.
- Intensity-centroid orientation uses a radius-15 disk and 32 angle bins.
- Rotated BRIEF uses the published OpenCV sampling pattern and 3×3 binomial
  smoothing to produce 256-bit descriptors.
- Each output includes x/y, FAST score, orientation bin, frame ID and a
  timestamp in system-clock ticks since reset.
- Capture and description are serialized. Busy camera frames are skipped;
  banks alternate between accepted frames, preserving a completed raw frame.
  VGA continues independently.
- At 100 MHz, extracting 384 descriptors takes roughly **83 ms plus capture
  time**. This is not full-camera-rate ORB at the maximum feature count.

This quantized implementation is **not bit-compatible with OpenCV ORB**.
Pixel precision, orientation and smoothing differ. Descriptor quality on real
camera scenes still needs evaluation.

The current board consumes descriptors into a rolling digest. Decimal-point
activity is a basic bring-up indication, not a descriptor correctness check.
There is no host output or ILA in this build. VGA red points and the numeric
feature count still represent FAST detections, not the grid-selected ORB set.
See [docs/ORB.md](docs/ORB.md) for interfaces and numerical details.

## Processing Pipeline

- Sliding window generates a 3×3 pixel neighborhood
- Sobel filter calculates horizontal and vertical edges
- Threshold determines whether each pixel is an edge
- Edge pixels are written as white
- Non-edge pixels are written as black
- The one-pixel image border remains black

## FAST Corner Detector

- 7×7 window from six line buffers packed into one BRAM word per column
- FAST-9 segment test on the 16-pixel radius-3 circle, fully pipelined
  at one pixel per clock
- Corner score = best 9-pixel arc's minimum contrast (OpenCV's score + 1)
- 3×3 non-maximum suppression on the streamed score map, strict `>`
  as in OpenCV
- Pixel coordinates travel through the pipeline as tags, so no stage
  depends on another stage's latency
- Keypoints at x = 3..W-5, y = 3..H-5. OpenCV can also report the last
  FAST column/row (x = W-4, y = H-4), which a streaming design can't
- Display: full-brightness grayscale with each keypoint drawn in red

## FAST Verification

- `tools/fast_check.py` runs `fast_detector_tb` in Icarus and compares
  every keypoint position and score against both OpenCV
  (`FAST_FEATURE_DETECTOR_TYPE_9_16`, NMS on) and a brute-force NumPy
  FAST-9. The two references must agree before the RTL is judged
- Configs: noise, synthetic scenes and the test pattern at 64×48 up to
  640×480; random gaps in `pixel_valid`; back-to-back frames with the
  threshold changed at `frame_start`; a truncated junk frame first
- `line_window_tb` checks every window element against the image
  (catches mirrored windows, which FAST is blind to)
- Mutation-tested: a 9-arc shortened to 8, `>=` threshold,
  non-strict NMS, a dropped NMS neighbor, border mask, wrong center
  pixel, swapped ring pixel, ignored `frame_start`, framebuffer gray bits
  and the keypoint count are all caught

```
python3 tools/fast_check.py --quick   # small images, ~30 s
python3 tools/fast_check.py           # adds 640x480
```

## Controls

- `SW1` selects live camera or Sobel mode
- `SW2` selects FAST mode (overrides SW1)
- `SW15:SW12` control the Sobel threshold
- Each threshold step equals 25
- Threshold range is 0–375
- In FAST mode, `SW15:SW12` set the FAST threshold to 5–80 in steps of 5

## Seven-Segment Display

- Live camera mode displays `LIVE`
- Sobel mode displays the current threshold value
- FAST mode displays the FAST threshold on the left four digits and the
  keypoint count of the last frame on the right four (saturates at 9999)
- The right four digits are dark outside FAST mode
- Decimal points also expose digest-based ORB activity

## Output

- Resolution: 640×480
- Live mode displays the grayscale camera image
- Sobel mode displays the processed edge image
- The streaming display pipeline runs independently of frame-based ORB processing

## ORB Verification and Build

```powershell
./tools/run_orb_tests.ps1
& 'C:\Xilinx\Vivado\2024.1\bin\vivado.bat' -mode batch -source tools/build_orb_board.tcl -tclargs (Get-Location).Path
```

The test runner requires Python and Vivado/XSim (Vivado 2024.1 by default).
Tests cover descriptor reference vectors, all orientation bins, grid selection,
patch reads, output stalls, frame skipping/recovery, shared FAST integration,
and concurrent framebuffer reads/writes including full VGA-sized readback.
The existing VGA grayscale/red-overlay regression also passed.

The isolated build writes reports and a bitstream under
`orb_test_output/board_<timestamp>/` without programming the FPGA. Currently
the project and build script use the external board constraints at
`../OneDrive/Documents/ChatGPT/FPGA Side Projects/nexys_a7_vga_test.xdc`;
other checkouts must provide that file or update the constraint path.

The verified 2026-10-02 routed board build used:

| Resource | Used / available | Utilization |
| --- | --- | --- |
| LUTs | 12,538 / 63,400 | 19.78% |
| Registers | 7,950 / 126,800 | 6.27% |
| BRAM tiles | 134.5 / 135 | 99.63% |
| DSPs | 7 / 240 | 2.92% |

Setup slack was +0.385 ns and hold slack +0.022 ns under the supplied
constraints. Bitstream generation completed with no errors or critical
warnings. On-device validation remains; missing external I/O delays and
other board-level warnings mean internal timing closure is not complete
camera-interface timing sign-off. Detailed caveats are in [docs/ORB.md](docs/ORB.md).

## What's Next

1. Validate camera/VGA and ORB operation on the board; complete board-interface
   constraints and evaluate descriptors from real scenes.
2. Make ORB observable: expose selected feature counts and orientation overlays
   and/or add debug capture.
3. Add host transport for descriptors, coordinates, frame IDs and timestamps.
4. Start with PC-side Hamming matching and RANSAC/pose estimation, followed by
   a C++ ROS 2 interface. These are planned, not present in the current RTL.
5. Revisit memory allocation before adding a PL matcher: two sets of 384
   descriptors need 24 KiB before metadata, but only half a BRAM tile is free.
   Display-buffer sharing or LUT-based storage would require further design work.
6. Add an image pyramid and IMU fusion later for scale changes and improved
   motion estimation robustness.
