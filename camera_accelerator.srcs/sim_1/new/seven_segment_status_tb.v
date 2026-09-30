`timescale 1ns / 1ps

module seven_segment_status_tb;

    reg clk;
    reg reset;
    reg processing_mode;
    reg [10:0] threshold;

    wire [6:0] segments;
    wire decimal_point;
    wire [7:0] anodes;

    integer errors;

    seven_segment_status #(
        .REFRESH_COUNTER_BITS(4)
    ) dut (
        .clk(clk),
        .reset(reset),
        .processing_mode(processing_mode),
        .threshold(threshold),
        .segments(segments),
        .decimal_point(decimal_point),
        .anodes(anodes)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    task check_digit;
        input [7:0] expected_anodes;
        input [6:0] expected_segments;
        begin
            #1;
            if ((anodes !== expected_anodes) ||
                (segments !== expected_segments) ||
                (decimal_point !== 1'b1)) begin
                $display("ERROR: anodes=%b segments=%b dp=%b; expected %b %b 1",
                         anodes, segments, decimal_point,
                         expected_anodes, expected_segments);
                errors = errors + 1;
            end
        end
    endtask

    task advance_digit;
        begin
            repeat (4) @(posedge clk);
        end
    endtask

    initial begin
        reset = 1'b1;
        processing_mode = 1'b0;
        threshold = 11'd0;
        errors = 0;

        repeat (2) @(posedge clk);
        #1;
        reset = 1'b0;

        // AN7-AN4 must read L-I-V-E from left to right.
        check_digit(8'hEF, 7'b0110000); // AN4: E
        advance_digit;
        check_digit(8'hDF, 7'b1100011); // AN5: V
        advance_digit;
        check_digit(8'hBF, 7'b1001111); // AN6: I
        advance_digit;
        check_digit(8'h7F, 7'b1110001); // AN7: L

        // Reset the scan position and display threshold 0375.
        reset = 1'b1;
        processing_mode = 1'b1;
        threshold = 11'd375;
        @(posedge clk);
        #1;
        reset = 1'b0;

        check_digit(8'hEF, 7'b0100100); // AN4: 5
        advance_digit;
        check_digit(8'hDF, 7'b0001111); // AN5: 7
        advance_digit;
        check_digit(8'hBF, 7'b0000110); // AN6: 3
        advance_digit;
        check_digit(8'h7F, 7'b0000001); // AN7: 0

        if (errors == 0)
            $display("PASS: seven-segment LIVE and threshold displays are correct");
        else
            $fatal(1, "FAIL: seven-segment test found %0d errors", errors);

        $finish;
    end

endmodule
