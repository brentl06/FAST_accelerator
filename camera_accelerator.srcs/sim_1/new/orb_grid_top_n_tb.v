`timescale 1ns / 1ps

module orb_grid_top_n_tb;
    reg clk = 0;
    reg reset = 1;
    reg frame_start = 0;
    reg frame_done = 0;
    reg kp_valid = 0;
    reg [9:0] kp_x = 0;
    reg [8:0] kp_y = 0;
    reg [7:0] kp_score = 0;

    wire selected_valid;
    reg selected_ready = 1;
    wire [9:0] selected_x;
    wire [8:0] selected_y;
    wire [7:0] selected_score;
    wire selection_done;
    wire busy;

    integer errors = 0;
    integer output_index = 0;
    reg [9:0] expected_x [0:6];
    reg [8:0] expected_y [0:6];
    reg [7:0] expected_score [0:6];

    always #5 clk = ~clk;

    orb_grid_top_n #(
        .FRAME_WIDTH(16), .FRAME_HEIGHT(8),
        .GRID_COLS(2), .GRID_ROWS(2), .TOP_N(2)
    ) dut (
        .clk(clk), .reset(reset),
        .frame_start(frame_start), .frame_done(frame_done),
        .kp_valid(kp_valid), .kp_x(kp_x), .kp_y(kp_y),
        .kp_score(kp_score),
        .selected_valid(selected_valid), .selected_ready(selected_ready),
        .selected_x(selected_x),
        .selected_y(selected_y), .selected_score(selected_score),
        .selection_done(selection_done), .busy(busy)
    );

    task send_keypoint;
        input [9:0] x;
        input [8:0] y;
        input [7:0] score;
        begin
            @(negedge clk);
            kp_x = x;
            kp_y = y;
            kp_score = score;
            kp_valid = 1;
        end
    endtask

    task fail;
        input [8*96-1:0] message;
        begin
            errors = errors + 1;
            if (errors <= 20)
                $display("ERROR: %0s", message);
        end
    endtask

    always @(posedge clk) begin
        // Sample the ready/valid handshake at the clock edge, before the DUT
        // clears selected_valid with a nonblocking assignment.
        if (selected_valid && selected_ready) begin
            if (output_index > 6)
                fail("selector emitted more than the bounded feature count");
            else if ((selected_x !== expected_x[output_index]) ||
                     (selected_y !== expected_y[output_index]) ||
                     (selected_score !== expected_score[output_index])) begin
                $display("MISMATCH index=%0d got=(%0d,%0d,%0d) expected=(%0d,%0d,%0d)",
                         output_index, selected_x, selected_y, selected_score,
                         expected_x[output_index], expected_y[output_index],
                         expected_score[output_index]);
                fail("selected keypoint or score was incorrect");
            end
            output_index = output_index + 1;
        end
    end

    initial begin
        // Cell-major, slot-major output. Membership is the strongest N in
        // each cell; output order is intentionally not score-sorted.
        expected_x[0] = 3;  expected_y[0] = 2; expected_score[0] = 20;
        expected_x[1] = 2;  expected_y[1] = 1; expected_score[1] = 30;
        expected_x[2] = 9;  expected_y[2] = 1; expected_score[2] = 5;
        expected_x[3] = 11; expected_y[3] = 1; expected_score[3] = 7;
        expected_x[4] = 1;  expected_y[4] = 5; expected_score[4] = 40;
        expected_x[5] = 9;  expected_y[5] = 5; expected_score[5] = 12;
        expected_x[6] = 11; expected_y[6] = 6; expected_score[6] = 50;

        repeat (3) @(posedge clk);
        reset = 0;
        @(negedge clk);
        frame_start = 1;
        @(negedge clk);
        frame_start = 0;

        // Cell 0: weakest entry is displaced after the cell fills.
        send_keypoint(1, 1, 10);
        send_keypoint(2, 1, 30);
        send_keypoint(3, 2, 20);

        // Cell 1: equal scores remain stable; score 7 takes first place.
        send_keypoint(9, 1, 5);
        send_keypoint(10, 2, 5);
        send_keypoint(11, 1, 7);

        // Cells 2 and 3, including another displacement.
        send_keypoint(1, 5, 40);
        send_keypoint(9, 5, 12);
        send_keypoint(10, 6, 2);
        send_keypoint(11, 6, 50);

        // All candidates arrive back-to-back. EOF accompanies the last one,
        // exercising both newly added collection pipeline drain stages.
        frame_done = 1;
        @(negedge clk);
        frame_done = 0;
        kp_valid = 0;

        // Hold the first emitted entry under backpressure. The selector must
        // retain it and resume without duplicating or dropping keypoints.
        selected_ready = 0;
        repeat (5) @(posedge clk);
        @(negedge clk);
        selected_ready = 1;

        wait (selection_done);
        @(posedge clk);
        if (output_index != 7)
            fail("selector did not emit the expected bounded list");
        if (busy)
            fail("busy remained asserted after selection_done");

        if (errors == 0)
            $display("PASS: grid top-N membership, ties, bounds, and emission verified");
        else
            $fatal(1, "FAIL: %0d grid selector errors", errors);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1, "FAIL: grid test timed out");
    end
endmodule
