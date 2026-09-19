`timescale 1ns / 1ps

module sliding_window_tb;

    reg        clk;
    reg        reset;
    reg  [7:0] pixel;
    reg        pixel_valid;

    wire [7:0] w00, w01, w02;
    wire [7:0] w10, w11, w12;
    wire [7:0] w20, w21, w22;
    wire       window_valid;

    integer row;
    integer col;

    sliding_window DUT (
        .clk(clk),
        .reset(reset),
        .pixel(pixel),
        .pixel_valid(pixel_valid),
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22),
        .window_valid(window_valid)
    );

    // 100 MHz clock
    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        reset       = 1'b1;
        pixel       = 8'd0;
        pixel_valid = 1'b0;

        // Hold reset for two clock cycles.
        repeat (2) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Send three complete rows. Data is driven before each rising edge.
        for (row = 0; row < 3; row = row + 1) begin
            for (col = 0; col < 640; col = col + 1) begin
                @(negedge clk);
                pixel       = row + col;
                pixel_valid = 1'b1;
            end
        end

        @(negedge clk);
        pixel_valid = 1'b0;
        pixel       = 8'd0;

        repeat (3) @(posedge clk);
        $finish;
    end

    // Delay one timestep so registered DUT outputs have updated.
    always @(posedge clk) begin
        #1;
        if (window_valid) begin
            $display("time=%0t window: %0d %0d %0d | %0d %0d %0d | %0d %0d %0d",
                     $time,
                     w00, w01, w02,
                     w10, w11, w12,
                     w20, w21, w22);
        end
    end

endmodule