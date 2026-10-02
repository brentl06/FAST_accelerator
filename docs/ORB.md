# Single-scale ORB accelerator

`orb_accelerator` is a connected, synthesizable camera-stream core. It contains
the existing FAST-9/NMS detector, two raw 4-bit framebuffers, grid selection,
patch reading, intensity-centroid orientation and a 256-bit rotated descriptor.
The core is registered in the Vivado project and instantiated in `vga_test_top`.
The board selects `EXTERNAL_FAST=1` to share the continuously running detector
in `runtime_pipeline_selector`; standalone use defaults to an internal detector.
The existing 5-bit display framebuffer is retained to preserve raw, Sobel and
red FAST overlay modes, in addition to the two 4-bit ORB raw banks. This board
configuration uses nearly all available BRAM; memory sharing or packing must
be revisited before adding stored descriptors/matching. It does not yet expose
descriptors to a host.

```text
8-bit camera pixels ─┬─> FAST-9 + NMS ─> grid top-N ─────────────┐
                    │                                         │
                    └─> upper 4 bits ─> frame banks A/B ─> patch reader
                                                              │
                                               41×41 patch cache
                                                  ┌───────────┴─────────┐
                                           centroid moments     smoothed samples
                                                  │                    │
                                           32-bin orientation ─> rotated BRIEF
                                                                       │
                                             tagged 256-bit ready/valid output
```

## Interface and frame ownership

- All accelerator ports use the same system clock. Feed `pixel_in`,
  `pixel_valid`, and `frame_start` from `OV7670_interface` after its FIFO.
  `frame_start` accompanies the first valid pixel, with exactly width × height
  raster pixels in a complete frame. Valid gaps are permitted.
- A new frame is accepted only when `frame_ready` is high. The detector and
  raster writer see the same accepted pixels. `fast_threshold` is latched
  for that frame; FAST runs on the original 8-bit values.
- The controller waits for both raw storage and the FAST pipeline to finish,
  including the framebuffer's delayed final write, before requesting patches.
- A bank stays locked through the final descriptor handshake. The next
  accepted frame uses the other bank, retaining at least one completed frame
  after the first capture. This version serializes capture and description;
  it does not yet collect the next frame's keypoints during description.
- Busy camera frames are discarded in full. `frame_dropped` pulses at their
  first pixel and `dropped_frames` counts them. If a new marker interrupts a
  partial capture, that capture is aborted, the new frame is discarded, and
  acquisition resumes on a subsequent marker. `aborted_frames` counts partial
  captures separately.
- `descriptor_valid && descriptor_ready` transfers one feature: descriptor,
  angle bin, x, y, FAST score, frame ID, and timestamp. These fields remain
  stable during a stall. The 32-bit frame ID counts all camera frame starts,
  including skipped frames. The 64-bit timestamp is system-clock ticks since
  reset, sampled at the accepted frame's first pixel (not UTC).
- `frame_done` pulses after all selected descriptors have been accepted,
  including for zero-feature frames. `frame_feature_count` is then final.
  `completed_frame_valid/bank` describe raw storage completion; they are not
  a VGA clock-domain handoff or a bank-release handshake for another reader.

## Defined descriptor variant

| Property | Implemented behavior |
|---|---|
| Scale | One, no image pyramid |
| Selection | Default 8×6 cells, up to 8 features per cell (384 total) |
| Border | Reject candidates within 20 pixels of the raw image edge before selection |
| Feature order | Cell-major then storage-slot-major, not sorted by score |
| Ties | Equal incoming minimum scores do not replace existing entries; replacement minimum ties choose highest storage slot |
| Pixels | Upper four bits of the incoming grayscale value |
| Orientation | Intensity moments inside `dx² + dy² <= 225` |
| Angle | Maximum projection onto 32 Q10 unit vectors; lowest bin wins ties |
| Rotation | 11.25° bins, increasing clockwise in image coordinates |
| Sampling pattern | OpenCV 4.12.0 `bit_pattern_31_`, 256 pairs; license retained in `orb_pattern.v` |
| Coordinate rounding | `(rotated_Q10 + 512) // 1024`, ties toward +infinity |
| Smoothing | 3×3 binomial kernel `[1,2,1]ᵀ[1,2,1]`, unnormalized 8-bit sums |
| Descriptor | Bit i is 1 when smoothed sample 2i is less than sample 2i+1 |

This is **not bit-compatible with OpenCV ORB**: pixel precision, orientation,
circle discretization, and smoothing differ. It uses the published sampling
pattern, not a new learned pattern. Matching quality on camera scenes still
needs evaluation. The first hardware implementation favors a small patch
cache and serial processing over peak throughput. Without memory or output
stalls, one feature takes roughly 21,500 system clocks; at a target 100 MHz,
384 features alone take about 83 ms, in addition to capture time.

## Verification and reports

Run from the repository root:

```powershell
./tools/run_orb_tests.ps1
& 'C:\Xilinx\Vivado\2024.1\bin\vivado.bat' -mode batch -source bram_tests/run_orb_accelerator_probe.tcl
```

The tests generate numerical vectors in `orb_test_output`, which is ignored
except for its local `.gitignore`. The pure-Python reference computes FAST/NMS,
selection, moments, smoothing and descriptors independently of the HDL; only
the published sampling constants are shared. Coverage includes 40 patches
(all 32 angle bins, uniform pixels and random texture), all 256 output bits,
pixel gaps, descriptor stalls, complete busy-frame drops, bank alternation,
empty frames, and interrupted capture recovery. Tracker tests add 60,000
candidate cycles for TOP_N=1/3/8, including ties and frame resets.
Framebuffer tests also cover all 307,200 addresses at 640×480, with concurrent
ping-pong writes/system reads, independent VGA reads, same-bank contention,
and full readback. The existing full-frame VGA grayscale/overlay test passes.

Integration tests use 64×64 frames with 2×2 cells and TOP_N=2 for runtime;
synthesis uses the default 640×480 and 384 features. Reports are in
`bram_tests/orb_accelerator_{utilization,hierarchy,timing_synth}.rpt` and cover
the complete stream core, not the camera FIFO/VGA/board peripherals. Synthesis
timing is an estimate; the routed board result below supersedes it. On-device
testing remains.

The FAST score reduction now uses explicit comparator wires instead of nested
function calls, resolving unknown score values seen in XSim integration.
Grid trackers maintain score/physical-slot pairs in descending score order
using parallel insertion. Equal scores sort by ascending physical slot, so
replacement and emitted feature ordering remain unchanged. This removes the
minimum-reduction feedback path while still accepting one candidate per clock.

Board timing work also registers grid candidate coordinates/cell indices and
the final feature-memory write, draining both stages before emission. Patch
coordinates are registered. System framebuffer reads now use a one-entry
address queue: without write contention, a request accepted at edge N returns
`sys_read_valid` and its pixel after edge N+1. Consecutive requests can still
be accepted every clock. Queued reads wait safely behind same-bank writes;
clients must honor `sys_read_ready` and wait for `sys_read_valid`.
Frontend frame, reset and keypoint events are registered together to isolate
camera FIFO outputs from high-fanout control paths. Descriptor rotation uses
separate lookup, product, sum and rounding cycles without changing its values.
The BRIEF comparison uses registered blur sums to isolate patch BRAM output
timing from the 256-bit descriptor write mux.
The centroid disk is implemented as exact row bounds rather than combinational
squaring; simulation exhaustively checks all 4,096 possible 6-bit row/column
inputs against the original radius-squared inequality.

## Remaining integration

The descriptor extractor is connected. Hamming matching, descriptor storage
across frames, host transport, ROS 2, pose estimation, pyramids, and IMU fusion
are not implemented here. The board consumes descriptors into a rolling digest
and uses the seven-segment decimal point as an activity indication. Every
descriptor bit participates, preventing removal of unused descriptor logic.
Descriptor, frame identity and status nets are marked for debugging; there is
no ILA inserted or host interface in this build. Existing VGA modes and numeric
status fields are preserved. Routed timing now passes for the build below;
device verification and board-interface constraint completion remain.

For an isolated board build that preserves existing runs, run:

```powershell
& 'C:\Xilinx\Vivado\2024.1\bin\vivado.bat' -mode batch -source tools/build_orb_board.tcl -tclargs 'C:/Users/joshr/camera_accelerator'
```

The script creates a timestamped project under `orb_test_output`, builds the
board, checks setup/hold timing, and then writes `orb_board.bit`. `write_bitstream`
also runs Vivado's required DRC checks. No FPGA is programmed automatically.

The existing board XDC defines the system, camera and VGA clocks but omits
external input/output delays. Internal setup/hold closure is not a complete
camera-interface timing sign-off. The VGA buffer also has Vivado warnings for
asynchronously reset address/control drivers. These existing board-level
limitations and real-camera descriptor quality need hardware validation.

## Verified board build — 2026-10-02

Vivado 2024.1 successfully generated
`orb_test_output/board_20261002_151538/orb_board.bit` for `xc7a100tcsg324-1`,
top `vga_test_top`. Its isolated project is `orb_board.xpr` in that directory.
No FPGA was programmed. The primary project also includes all current RTL.

| Routed resource | Used | Available | Utilization |
|---|---:|---:|---:|
| LUTs | 12,538 | 63,400 | 19.78% |
| Registers | 7,950 | 126,800 | 6.27% |
| BRAM tiles | 134.5 | 135 | 99.63% |
| DSPs | 7 | 240 | 2.92% |

The 100 MHz system-clock design meets the supplied timing constraints:
setup WNS **+0.385 ns**, hold WHS **+0.022 ns**, pulse-width slack **+3.750 ns**,
with zero failing setup/hold/pulse-width endpoints. Camera FIFO bus-skew
constraints also pass. Reports are `board_routed_timing.rpt`,
`board_routed_utilization.rpt`, `board_bus_skew.rpt`, and `board_drc.rpt` in
the same build directory.

Bitstream generation finished with **0 errors, 0 critical warnings, and
39 warnings**. Warnings include missing configuration-voltage properties,
DSP pipelining advisories, existing VGA asynchronous BRAM controls, and unused
FIFO reset nets. They were not suppressed. Treat this as a descriptor-core
bring-up build, not a completed matching/host pipeline or camera timing sign-off.

Pattern source: https://github.com/opencv/opencv/blob/4.12.0/modules/features2d/src/orb.cpp
