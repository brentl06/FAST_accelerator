`timescale 1ns / 1ps

module processing_pipeline_tb;

    localparam FRAME_WIDTH  = 5;
    localparam FRAME_HEIGHT = 4;
    localparam OUTPUT_COUNT = (FRAME_WIDTH - 2) * (FRAME_HEIGHT - 2);

    reg        clk;
    reg        reset;
    reg  [7:0] pixel_in;
    reg        pixel_valid;
    reg        frame_start;

    wire [3:0] pixel_out;
    wire [9:0] x;
    wire [8:0] y;
    wire       write_en;
    wire       frame_done;

    integer input_x;
    integer input_y;
    integer output_index;
    integer errors;
    integer expected_x;
    integer expected_y;

    processing_pipeline_top #(
        .FRAME_WIDTH(FRAME_WIDTH),
        .FRAME_HEIGHT(FRAME_HEIGHT)
    ) dut (
        .pixel_in(pixel_in),
        .pixel_valid(pixel_valid),
        .frame_start(frame_start),
        .edge_threshold(11'd300),
        .clk(clk),
        .reset(reset),
        .pixel_out(pixel_out),
        .x(x),
        .y(y),
        .write_en(write_en),
        .frame_done(frame_done)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    always @(posedge clk) begin
        #1;
        if (write_en) begin
            expected_x = 1 + (output_index % (FRAME_WIDTH - 2));
            expected_y = 1 + (output_index / (FRAME_WIDTH - 2));

            if ((x !== expected_x) || (y !== expected_y)) begin
                $display("ERROR: output %0d was (%0d,%0d), expected (%0d,%0d)",
                         output_index, x, y, expected_x, expected_y);
                errors = errors + 1;
            end

            if (frame_done !== (output_index == OUTPUT_COUNT - 1)) begin
                $display("ERROR: frame_done mismatch at output %0d", output_index);
                errors = errors + 1;
            end

            output_index = output_index + 1;
        end else if (frame_done) begin
            $display("ERROR: frame_done asserted without write_en");
            errors = errors + 1;
        end
    end

    initial begin
        reset        = 1'b1;
        pixel_in     = 8'd0;
        pixel_valid  = 1'b0;
        frame_start  = 1'b0;
        output_index = 0;
        errors       = 0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        for (input_y = 0; input_y < FRAME_HEIGHT; input_y = input_y + 1) begin
            for (input_x = 0; input_x < FRAME_WIDTH; input_x = input_x + 1) begin
                @(negedge clk);
                pixel_in    = input_x + input_y;
                pixel_valid = 1'b1;
                frame_start = ((input_x == 0) && (input_y == 0));
            end
        end

        @(negedge clk);
        pixel_valid = 1'b0;
        frame_start = 1'b0;

        repeat (8) @(posedge clk);
        #2;

        if (output_index != OUTPUT_COUNT) begin
            $display("ERROR: produced %0d writes, expected %0d",
                     output_index, OUTPUT_COUNT);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: processing pipeline coordinates and frame_done are correct");
        else
            $display("FAIL: processing pipeline test found %0d errors", errors);

        $finish;
    end

endmodule
