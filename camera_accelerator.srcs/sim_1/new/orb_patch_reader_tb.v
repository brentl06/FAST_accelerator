`timescale 1ns / 1ps

module orb_patch_reader_tb;
    localparam W = 16;
    localparam H = 12;
    localparam PATCH = 5;
    reg clk = 0;
    reg reset = 1;
    reg start = 0;
    reg [9:0] keypoint_x = 0;
    reg [8:0] keypoint_y = 0;
    wire start_ready;
    wire busy;
    wire [9:0] fb_read_x;
    wire [8:0] fb_read_y;
    wire fb_read_en;
    reg fb_read_ready = 1;
    reg [3:0] fb_read_data = 0;
    reg fb_read_valid = 0;
    wire patch_valid;
    wire [3:0] patch_pixel;
    wire [5:0] patch_col;
    wire [5:0] patch_row;
    wire patch_done;
    wire keypoint_rejected;
    reg pending = 0;
    reg [9:0] pending_x = 0;
    reg [8:0] pending_y = 0;
    integer output_count = 0;
    integer read_count = 0;
    integer errors = 0;
    integer expected_x;
    integer expected_y;

    always #5 clk = ~clk;

    function [3:0] pixel_pattern;
        input integer x;
        input integer y;
        pixel_pattern = (x + 3*y) & 15;
    endfunction

    orb_patch_reader #(
        .FRAME_WIDTH(W), .FRAME_HEIGHT(H), .PATCH_SIZE(PATCH),
        .PIXEL_WIDTH(4)
    ) dut (
        .clk(clk), .reset(reset), .start(start),
        .keypoint_x(keypoint_x), .keypoint_y(keypoint_y),
        .start_ready(start_ready), .busy(busy),
        .fb_read_x(fb_read_x), .fb_read_y(fb_read_y),
        .fb_read_en(fb_read_en), .fb_read_ready(fb_read_ready),
        .fb_read_data(fb_read_data), .fb_read_valid(fb_read_valid),
        .patch_valid(patch_valid), .patch_pixel(patch_pixel),
        .patch_col(patch_col), .patch_row(patch_row),
        .patch_done(patch_done), .keypoint_rejected(keypoint_rejected)
    );

    // Synchronous framebuffer model with one-cycle response signaling.
    always @(posedge clk) begin
        fb_read_valid <= pending;
        if (pending)
            fb_read_data <= pixel_pattern(pending_x, pending_y);
        pending <= fb_read_en;
        if (fb_read_en) begin
            pending_x <= fb_read_x;
            pending_y <= fb_read_y;
            read_count <= read_count + 1;
        end
    end

    task fail;
        input [8*96-1:0] message;
        begin
            errors = errors + 1;
            if (errors <= 20)
                $display("ERROR: %0s", message);
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (patch_valid) begin
            expected_x = 7 - PATCH/2 + patch_col;
            expected_y = 6 - PATCH/2 + patch_row;
            if (patch_pixel !== pixel_pattern(expected_x, expected_y))
                fail("patch pixel did not match the requested framebuffer location");
            if ((patch_col !== output_count % PATCH) ||
                (patch_row !== output_count / PATCH))
                fail("patch coordinates were not emitted in raster order");
            output_count = output_count + 1;
        end
    end

    initial begin
        repeat (3) @(posedge clk);
        reset = 0;
        @(negedge clk);
        keypoint_x = 7;
        keypoint_y = 6;
        start = 1;
        @(negedge clk);
        start = 0;
        wait (patch_done);
        @(posedge clk);
        if (output_count != PATCH*PATCH)
            fail("patch did not contain exactly PATCH_SIZE squared pixels");
        if (read_count != PATCH*PATCH)
            fail("patch reader issued an incorrect number of framebuffer reads");
        if (busy)
            fail("patch reader remained busy after the final pixel");

        @(negedge clk);
        keypoint_x = 1;
        keypoint_y = 1;
        start = 1;
        @(negedge clk);
        start = 0;
        #1;
        if (!keypoint_rejected || !patch_done)
            fail("border keypoint was not rejected immediately");
        if (read_count != PATCH*PATCH)
            fail("rejected keypoint generated framebuffer traffic");

        if (errors == 0)
            $display("PASS: patch raster order, pixels, handshake, count, and border rejection verified");
        else
            $fatal(1, "FAIL: %0d patch reader errors", errors);
        $finish;
    end
endmodule
