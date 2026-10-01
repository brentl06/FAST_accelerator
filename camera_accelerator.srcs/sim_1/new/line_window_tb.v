`timescale 1ns / 1ps

// Checks every element of every fully-inside window against the image, for
// N = 3 and N = 7, with random input gaps. Orientation matters: FAST and NMS
// are symmetric under flips, so they cannot catch a mirrored window, but ORB
// orientation and BRIEF will depend on it.
module line_window_tb;

    localparam W = 23, H = 17;

    reg        clk = 0, reset = 1;
    reg        in_valid = 0;
    reg  [7:0] in_data = 0;
    reg  [9:0] in_col = 0;
    reg  [8:0] in_row = 0;

    wire                v3, v7;
    wire [3*3*8-1:0]    win3;
    wire [7*7*8-1:0]    win7;
    wire [18:0]         tag3, tag7;

    line_window #(.N(3), .LINE_W(W), .DATA_W(8), .TAG_W(19)) dut3 (
        .clk(clk), .reset(reset), .in_valid(in_valid), .in_data(in_data),
        .in_col(in_col), .in_tag({in_col, in_row}),
        .out_valid(v3), .out_win(win3), .out_tag(tag3));

    line_window #(.N(7), .LINE_W(W), .DATA_W(8), .TAG_W(19)) dut7 (
        .clk(clk), .reset(reset), .in_valid(in_valid), .in_data(in_data),
        .in_col(in_col), .in_tag({in_col, in_row}),
        .out_valid(v7), .out_win(win7), .out_tag(tag7));

    always #5 clk = ~clk;

    reg [7:0] image [0:W*H-1];
    integer errors = 0, checked = 0, seed = 7, x, y, i, j, g, n3 = 0, n7 = 0;

    task check;
        input integer n;
        input [7*7*8-1:0] win;
        input [18:0] tag;
        integer c, r, ii, jj;
        begin
            c = tag[18:9];
            r = tag[8:0];
            if (c >= n-1 && r >= n-1) begin
                for (ii = 0; ii < n; ii = ii + 1)
                    for (jj = 0; jj < n; jj = jj + 1)
                        if (win[(ii*n + jj)*8 +: 8] !==
                            image[(r - (n-1) + ii)*W + (c - (n-1) + jj)]) begin
                            if (errors < 10)
                                $display("ERROR: N=%0d at (%0d,%0d) element (%0d,%0d)",
                                         n, c, r, ii, jj);
                            errors = errors + 1;
                        end
                checked = checked + 1;
            end
        end
    endtask

    always @(posedge clk) begin
        #1;
        if (v3) begin check(3, win3, tag3); n3 = n3 + 1; end
        if (v7) begin check(7, win7, tag7); n7 = n7 + 1; end
    end

    initial begin
        for (i = 0; i < W*H; i = i + 1)
            image[i] = $random(seed);

        repeat (3) @(posedge clk);
        reset <= 0;

        for (y = 0; y < H; y = y + 1)
            for (x = 0; x < W; x = x + 1) begin
                in_valid <= 1;
                in_data  <= image[y*W + x];
                in_col   <= x;
                in_row   <= y;
                @(posedge clk);
                in_valid <= 0;
                for (g = $unsigned($random(seed)) % 3; g > 0; g = g - 1)
                    @(posedge clk);
            end
        in_valid <= 0;
        repeat (5) @(posedge clk);

        if (n3 != W*H || n7 != W*H) begin
            $display("ERROR: %0d / %0d windows out, expected %0d each", n3, n7, W*H);
            errors = errors + 1;
        end

        if (errors == 0)
            $display("PASS: line_window, %0d windows checked element by element", checked);
        else
            $display("FAIL: line_window, %0d errors", errors);
        $finish;
    end

endmodule
