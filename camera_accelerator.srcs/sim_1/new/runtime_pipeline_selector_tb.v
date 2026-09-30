`timescale 1ns / 1ps

module runtime_pipeline_selector_tb;

    localparam FRAME_WIDTH  = 5;
    localparam FRAME_HEIGHT = 4;
    localparam RAW_PIXELS   = FRAME_WIDTH * FRAME_HEIGHT;
    localparam EDGE_PIXELS  = (FRAME_WIDTH - 2) * (FRAME_HEIGHT - 2);

    reg        clk;
    reg        reset;
    reg  [7:0] pixel_in;
    reg        pixel_valid;
    reg        frame_start;
    reg        mode_select;
    reg  [3:0] threshold_select;

    wire [3:0] pixel_out;
    wire [9:0] x;
    wire [8:0] y;
    wire       write_en;
    wire       frame_done;
    wire       active_mode;
    wire       mode_changed;
    wire [10:0] active_threshold;

    integer input_x;
    integer input_y;
    integer output_count;
    integer done_count;
    integer change_count;
    integer errors;
    integer expected_x;
    integer expected_y;
    integer expected_mode;
    integer expected_pixels;
    integer expected_threshold;

    runtime_pipeline_selector #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) dut (
        .pixel_in(pixel_in),
        .pixel_valid(pixel_valid),
        .frame_start(frame_start),
        .mode_select(mode_select),
        .threshold_select(threshold_select),
        .clk(clk),
        .reset(reset),
        .pixel_out(pixel_out),
        .x(x),
        .y(y),
        .write_en(write_en),
        .frame_done(frame_done),
        .active_mode(active_mode),
        .mode_changed(mode_changed),
        .active_threshold(active_threshold)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        #1;

        if (mode_changed)
            change_count = change_count + 1;

        if (write_en) begin
            if (active_mode !== expected_mode[0]) begin
                $display("ERROR: write used mode %0d, expected %0d",
                         active_mode, expected_mode);
                errors = errors + 1;
            end

            if (active_threshold !== expected_threshold) begin
                $display("ERROR: threshold was %0d, expected %0d",
                         active_threshold, expected_threshold);
                errors = errors + 1;
            end

            if (expected_mode == 0) begin
                expected_x = output_count % FRAME_WIDTH;
                expected_y = output_count / FRAME_WIDTH;
            end else begin
                expected_x = 1 + (output_count % (FRAME_WIDTH - 2));
                expected_y = 1 + (output_count / (FRAME_WIDTH - 2));
            end

            if ((x !== expected_x) || (y !== expected_y)) begin
                $display("ERROR: output %0d was (%0d,%0d), expected (%0d,%0d)",
                         output_count, x, y, expected_x, expected_y);
                errors = errors + 1;
            end

            output_count = output_count + 1;
        end

        if (frame_done) begin
            done_count = done_count + 1;
            if (!write_en) begin
                $display("ERROR: frame_done asserted without write_en");
                errors = errors + 1;
            end
        end
    end

    task stream_frame;
        input integer mode;
        input integer threshold;
        input integer change_switch_midframe;
        begin
            expected_mode = mode;
            expected_threshold = threshold;
            expected_pixels = mode ? EDGE_PIXELS : RAW_PIXELS;
            output_count = 0;
            done_count = 0;

            for (input_y = 0; input_y < FRAME_HEIGHT; input_y = input_y + 1) begin
                for (input_x = 0; input_x < FRAME_WIDTH; input_x = input_x + 1) begin
                    @(negedge clk);
                    pixel_in = (input_y * FRAME_WIDTH) + input_x;
                    pixel_valid = 1'b1;
                    frame_start = ((input_x == 0) && (input_y == 0));

                    // Request raw mode partway through the Sobel frame. The
                    // active selection must not change until the next frame.
                    if (change_switch_midframe && (input_x == 2) && (input_y == 1))
                        mode_select = 1'b0;
                    if (change_switch_midframe && (input_x == 2) && (input_y == 1))
                        threshold_select = 4'b1111;
                end
            end

            @(negedge clk);
            pixel_valid = 1'b0;
            frame_start = 1'b0;

            repeat (8) @(posedge clk);
            #2;

            if (output_count != expected_pixels) begin
                $display("ERROR: mode %0d produced %0d writes, expected %0d",
                         mode, output_count, expected_pixels);
                errors = errors + 1;
            end

            if (done_count != 1) begin
                $display("ERROR: mode %0d produced %0d frame_done pulses",
                         mode, done_count);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        reset = 1'b1;
        pixel_in = 8'd0;
        pixel_valid = 1'b0;
        frame_start = 1'b0;
        mode_select = 1'b0;
        threshold_select = 4'b0010;
        output_count = 0;
        done_count = 0;
        change_count = 0;
        errors = 0;
        expected_mode = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Power-up mode is raw.
        repeat (3) @(posedge clk);
        stream_frame(0, 50, 0);

        // Allow SW1 to synchronize, then select Sobel at the next frame.
        mode_select = 1'b1;
        threshold_select = 4'b0100;
        repeat (3) @(posedge clk);
        stream_frame(1, 100, 1);

        // The mid-frame request above takes effect only at this frame start.
        stream_frame(0, 375, 0);

        if (change_count != 2) begin
            $display("ERROR: observed %0d mode changes, expected 2", change_count);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: mode and threshold selections change only at frame boundaries");
        else
            $fatal(1, "FAIL: runtime selector test found %0d errors", errors);

        $finish;
    end

endmodule
