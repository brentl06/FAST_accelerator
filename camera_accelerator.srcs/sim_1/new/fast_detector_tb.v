`timescale 1ns / 1ps

// Streams an image through fast_detector twice and dumps the keypoints.
// The keypoint list is checked against OpenCV by tools/fast_check.py.
//
// Checked here, from the outputs only:
//   - every position x = 0..W-5, y = 0..H-5 is reported exactly once per frame,
//     in raster order
//   - out_gray equals the input image at (out_x, out_y)
//   - keypoints lie inside x = 3..W-5, y = 3..H-5
//   - fast_pipeline_top (run in parallel on the same input) writes each
//     position once with the dimmed gray or 0xF for a keypoint, pulses
//     frame_done on the last write, and reports the per-frame keypoint count
//     in binary and BCD
//
// Frame 0 uses THRESH0, frame 1 uses THRESH1. The threshold changes on the
// same clock as frame 1's frame_start, while frame 0's tail is still in the
// pipeline. GAPS=1 inserts random 0-3 clock gaps between pixels.
// Before frame 0 a truncated junk frame (PARTIAL pixels of noise) is sent, so
// the detector must resynchronize on frame_start rather than on counter wrap.
module fast_detector_tb;

    parameter W       = 640;
    parameter H       = 480;
    parameter THRESH0 = 20;
    parameter THRESH1 = 40;
    parameter GAPS    = 0;
    parameter SEED    = 1;
    parameter PARTIAL = W*3 + W/2 + 3;   // < 4 rows: produces no outputs
    parameter IMAGE   = "image.hex";
    parameter KP_OUT  = "rtl_keypoints.txt";

    reg        clk = 0;
    reg        reset = 1;
    reg  [7:0] pixel_in = 0;
    reg        pixel_valid = 0;
    reg        frame_start = 0;
    reg  [7:0] threshold = THRESH0;

    wire       out_valid, out_inside, out_keypoint;
    wire [9:0] out_x;
    wire [8:0] out_y;
    wire [7:0] out_score, out_gray;

    fast_detector #(.FRAME_WIDTH(W), .FRAME_HEIGHT(H)) dut (
        .clk(clk), .reset(reset),
        .pixel_in(pixel_in), .pixel_valid(pixel_valid),
        .frame_start(frame_start), .threshold(threshold),
        .out_valid(out_valid), .out_inside(out_inside),
        .out_x(out_x), .out_y(out_y), .out_keypoint(out_keypoint),
        .out_score(out_score), .out_gray(out_gray)
    );

    wire [3:0]  fb_pixel;
    wire [9:0]  fb_x;
    wire [8:0]  fb_y;
    wire        fb_we, fb_done, kp_valid;
    wire [9:0]  kp_x;
    wire [8:0]  kp_y;
    wire [7:0]  kp_score;
    wire [15:0] frame_kps, frame_kps_bcd;

    fast_pipeline_top #(.FRAME_WIDTH(W), .FRAME_HEIGHT(H)) fb_dut (
        .clk(clk), .reset(reset),
        .pixel_in(pixel_in), .pixel_valid(pixel_valid),
        .frame_start(frame_start), .threshold(threshold),
        .pixel_out(fb_pixel), .x(fb_x), .y(fb_y),
        .write_en(fb_we), .frame_done(fb_done),
        .kp_valid(kp_valid), .kp_x(kp_x), .kp_y(kp_y), .kp_score(kp_score),
        .frame_keypoints(frame_kps), .frame_keypoints_bcd(frame_kps_bcd)
    );

    always #5 clk = ~clk;

    reg [7:0] image [0:W*H-1];
    integer   fd, errors, frame_out, exp_x, exp_y, kp_count, seed, x, y, f, g;
    integer   fb_frame, fb_ex, fb_ey, fb_kps, fb_kps_total, kp_stream_count;
    reg [3:0] fb_expect;

    initial begin
        $readmemh(IMAGE, image);
        fd = $fopen(KP_OUT, "w");
        errors = 0; frame_out = 0; exp_x = 0; exp_y = 0; kp_count = 0;
        fb_frame = 0; fb_ex = 0; fb_ey = 0; fb_kps = 0; fb_kps_total = 0;
        kp_stream_count = 0;
        seed = SEED;
    end

    // Output monitor: sample after the edge.
    always @(posedge clk) begin
        #1;
        if (out_valid && out_inside && frame_out < 2) begin
            if (out_x !== exp_x || out_y !== exp_y) begin
                if (errors < 10)
                    $display("ERROR: frame %0d output at (%0d,%0d), expected (%0d,%0d)",
                             frame_out, out_x, out_y, exp_x, exp_y);
                errors = errors + 1;
            end
            if (out_gray !== image[out_y*W + out_x]) begin
                if (errors < 10)
                    $display("ERROR: gray at (%0d,%0d) = %0d, expected %0d",
                             out_x, out_y, out_gray, image[out_y*W + out_x]);
                errors = errors + 1;
            end
            if (out_keypoint === 1'b1) begin
                if (out_x < 3 || out_x > W-5 || out_y < 3 || out_y > H-5) begin
                    $display("ERROR: keypoint outside valid region at (%0d,%0d)", out_x, out_y);
                    errors = errors + 1;
                end
                $fwrite(fd, "%0d %0d %0d %0d\n", frame_out, out_x, out_y, out_score);
                kp_count = kp_count + 1;
            end else if (out_keypoint !== 1'b0) begin
                $display("ERROR: out_keypoint is X at (%0d,%0d)", out_x, out_y);
                errors = errors + 1;
            end

            if (exp_x == W-5) begin
                exp_x = 0;
                if (exp_y == H-5) begin
                    exp_y = 0;
                    frame_out = frame_out + 1;
                end else
                    exp_y = exp_y + 1;
            end else
                exp_x = exp_x + 1;
        end
    end

    function [15:0] to_bcd;
        input integer v;
        begin
            if (v > 9999) v = 9999;
            to_bcd = (v / 1000 % 10) * 4096 + (v / 100 % 10) * 256 +
                     (v / 10 % 10) * 16 + (v % 10);
        end
    endfunction

    // fast_pipeline_top write port: checked against the input image and
    // against the detector's keypoint stream (one cycle earlier).
    always @(posedge clk) begin
        #1;
        if (kp_valid) kp_stream_count = kp_stream_count + 1;
        if (fb_we && fb_frame < 2) begin
            if (fb_x !== fb_ex || fb_y !== fb_ey) begin
                if (errors < 10)
                    $display("ERROR: framebuffer write at (%0d,%0d), expected (%0d,%0d)",
                             fb_x, fb_y, fb_ex, fb_ey);
                errors = errors + 1;
            end
            fb_expect = {1'b0, image[fb_y*W + fb_x][7:5]};
            if (fb_pixel == 4'hF)
                fb_kps = fb_kps + 1;
            else if (fb_pixel !== fb_expect) begin
                if (errors < 10)
                    $display("ERROR: framebuffer pixel %h at (%0d,%0d), expected %h or F",
                             fb_pixel, fb_x, fb_y, fb_expect);
                errors = errors + 1;
            end
            if (fb_done !== (fb_ex == W-5 && fb_ey == H-5)) begin
                $display("ERROR: frame_done=%b at (%0d,%0d)", fb_done, fb_x, fb_y);
                errors = errors + 1;
            end

            if (fb_ex == W-5) begin
                fb_ex = 0;
                if (fb_ey == H-5) begin
                    fb_ey = 0;
                    fb_frame = fb_frame + 1;
                    fb_kps_total = fb_kps_total + fb_kps;
                    // counts are registered on the same clock as frame_done
                    if (frame_kps !== fb_kps || frame_kps_bcd !== to_bcd(fb_kps)) begin
                        $display("ERROR: frame_keypoints=%0d bcd=%h, expected %0d",
                                 frame_kps, frame_kps_bcd, fb_kps);
                        errors = errors + 1;
                    end
                    fb_kps = 0;
                end else
                    fb_ey = fb_ey + 1;
            end else
                fb_ex = fb_ex + 1;
        end
    end

    initial begin
        repeat (4) @(posedge clk);
        reset <= 0;
        @(posedge clk);

        for (x = 0; x < PARTIAL; x = x + 1) begin
            pixel_in    <= $random(seed);
            pixel_valid <= 1;
            frame_start <= (x == 0);
            @(posedge clk);
        end
        pixel_valid <= 0;
        frame_start <= 0;
        repeat (20) @(posedge clk);

        for (f = 0; f < 2; f = f + 1) begin
            for (y = 0; y < H; y = y + 1)
                for (x = 0; x < W; x = x + 1) begin
                    pixel_in    <= image[y*W + x];
                    pixel_valid <= 1;
                    frame_start <= (x == 0 && y == 0);
                    if (x == 0 && y == 0)
                        threshold <= (f == 0) ? THRESH0 : THRESH1;
                    @(posedge clk);
                    if (GAPS) begin
                        pixel_valid <= 0;
                        frame_start <= 0;
                        for (g = $unsigned($random(seed)) % 4; g > 0; g = g - 1)
                            @(posedge clk);
                    end
                end
        end
        pixel_valid <= 0;
        frame_start <= 0;

        // Drain the pipeline.
        repeat (50) @(posedge clk);
        $fclose(fd);

        if (fb_kps_total != kp_count || kp_stream_count != kp_count) begin
            $display("ERROR: keypoints: detector %0d, framebuffer 0xF writes %0d, kp stream %0d",
                     kp_count, fb_kps_total, kp_stream_count);
            errors = errors + 1;
        end

        if (frame_out != 2) begin
            $display("ERROR: %0d complete frames reported, expected 2", frame_out);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TB PASS: coverage/order/gray checks OK, %0d keypoints written to %s",
                     kp_count, KP_OUT);
        else
            $display("TB FAIL: %0d errors", errors);
        $finish;
    end

endmodule
