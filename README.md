# FAST Accelerator
This features from accelerated segment test (FAST) accelerator aims to take in one pixel per clock to emit clean corner edge detection coordinates after suppression.

## Architecture

- OV7670 camera captures 640×480 UYVU video and places into async FIFO
- SW1/SW2 select the processing pipeline or active video mode:
  - SW2 `0`, SW1 `0` = live camera output
  - SW2 `0`, SW1 `1` = Sobel edge detection
  - SW2 `1` = FAST keypoint overlay
- Pixel outputs of processing pipeline are written into the frame buffer
- VGA controller reads the frame buffer and displays the image

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
- Display: dimmed grayscale with each keypoint drawn as a full-white pixel

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

## Output

- Resolution: 640×480
- Live mode displays the grayscale camera image
- Sobel mode displays the processed edge image
- Processing occurs in real time using FPGA hardware
