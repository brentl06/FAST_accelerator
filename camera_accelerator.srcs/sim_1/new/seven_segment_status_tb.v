`timescale 1ns / 1ps

module seven_segment_status_tb;

    reg clk;
    reg reset;
    reg processing_mode;
    reg [10:0] threshold;
    reg show_count;
    reg [15:0] count_bcd;

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
        .show_count(show_count),
        .count_bcd(count_bcd),
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

    // Right-half digits must be dark when the count is not shown.
    task check_off;
        begin
            #1;
            if (anodes !== 8'hFF) begin
                $display("ERROR: anodes=%b; expected all digits off", anodes);
                errors = errors + 1;
            end
        end
    endtask

    // 3 scan bits of a 4-bit refresh counter: each digit lasts 2 clocks.
    task advance_digit;
        begin
            repeat (2) @(posedge clk);
        end
    endtask

    initial begin
        reset = 1'b1;
        processing_mode = 1'b0;
        threshold = 11'd0;
        show_count = 1'b0;
        count_bcd = 16'h0000;
        errors = 0;

        repeat (2) @(posedge clk);
        #1;
        reset = 1'b0;

        // The scan starts at AN0. AN3-AN0 stay dark outside FAST mode.
        check_off;
        advance_digit;
        check_off;
        advance_digit;
        check_off;
        advance_digit;
        check_off;
        advance_digit;

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

        check_off;
        advance_digit;
        check_off;
        advance_digit;
        check_off;
        advance_digit;
        check_off;
        advance_digit;

        check_digit(8'hEF, 7'b0100100); // AN4: 5
        advance_digit;
        check_digit(8'hDF, 7'b0001111); // AN5: 7
        advance_digit;
        check_digit(8'hBF, 7'b0000110); // AN6: 3
        advance_digit;
        check_digit(8'h7F, 7'b0000001); // AN7: 0

        // FAST mode: threshold 0045 on the left, keypoint count 1234 on the right.
        reset = 1'b1;
        processing_mode = 1'b1;
        threshold = 11'd45;
        show_count = 1'b1;
        count_bcd = 16'h1234;
        @(posedge clk);
        #1;
        reset = 1'b0;

        check_digit(8'hFE, 7'b1001100); // AN0: 4
        advance_digit;
        check_digit(8'hFD, 7'b0000110); // AN1: 3
        advance_digit;
        check_digit(8'hFB, 7'b0010010); // AN2: 2
        advance_digit;
        check_digit(8'hF7, 7'b1001111); // AN3: 1
        advance_digit;
        check_digit(8'hEF, 7'b0100100); // AN4: 5
        advance_digit;
        check_digit(8'hDF, 7'b1001100); // AN5: 4
        advance_digit;
        check_digit(8'hBF, 7'b0000001); // AN6: 0
        advance_digit;
        check_digit(8'h7F, 7'b0000001); // AN7: 0

        if (errors == 0)
            $display("PASS: seven-segment LIVE, threshold and keypoint displays are correct");
        else
            $fatal(1, "FAIL: seven-segment test found %0d errors", errors);

        $finish;
    end

endmodule
