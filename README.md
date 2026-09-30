# FAST Accelerator
This features from accelerated segment test (FAST) accelerator aims to take in one pixel per clock to emit clean corner edge detection coordinates after suppression.

## Architecture

- OV7670 camera captures 640×480 UYVU video and places into async FIFO
- SW1 selects the processing pipeline or active video mode:
  - `0` = live camera output
  - `1` = Sobel edge detection
- Pixel outputs of processing pipeline are written into the frame buffer
- VGA controller reads the frame buffer and displays the image

## Processing Pipeline

- Sliding window generates a 3×3 pixel neighborhood
- Sobel filter calculates horizontal and vertical edges
- Threshold determines whether each pixel is an edge
- Edge pixels are written as white
- Non-edge pixels are written as black
- The one-pixel image border remains black

## Controls

- `SW1` selects live camera or Sobel mode
- `SW15:SW12` control the Sobel threshold
- Each threshold step equals 25
- Threshold range is 0–375

## Seven-Segment Display

- Live camera mode displays `LIVE`
- Sobel mode displays the current threshold value
- The left four seven-segment digits are used
- The right four digits are disabled

## Output

- Resolution: 640×480
- Live mode displays the grayscale camera image
- Sobel mode displays the processed edge image
- Processing occurs in real time using FPGA hardware
