`timescale 1ns / 1ps

// Verifies the ping-pong memory use needed by ORB:
//   * framebuffer A accepts one system write per clock,
//   * framebuffer B accepts one system read per clock at the same time,
//   * framebuffer B also serves independent VGA-clock reads,
//   * the newly written contents of A can be read back afterward.
module frame_buffer_system_read_tb #(parameter W=16, H=8);
    localparam PIXELS = W * H;

    reg sys_clk = 0;
    reg vga_clk = 0;
    reg reset = 1;
    always #5 sys_clk = ~sys_clk;
    always #7 vga_clk = ~vga_clk;

    reg [9:0] a_wr_x = 0;
    reg [8:0] a_wr_y = 0;
    reg [3:0] a_wr_data = 0;
    reg       a_wr_en = 0;
    reg [9:0] a_sys_x = 0;
    reg [8:0] a_sys_y = 0;
    reg       a_sys_en = 0;
    wire [3:0] a_sys_data;
    wire       a_sys_valid;
    wire       a_sys_ready;

    reg [9:0] b_wr_x = 0;
    reg [8:0] b_wr_y = 0;
    reg [3:0] b_wr_data = 0;
    reg       b_wr_en = 0;
    reg [9:0] b_sys_x = 0;
    reg [8:0] b_sys_y = 0;
    reg       b_sys_en = 0;
    wire [3:0] b_sys_data;
    wire       b_sys_valid;
    wire       b_sys_ready;

    reg [9:0] b_vga_x = 0;
    reg [8:0] b_vga_y = 0;
    reg       b_vga_en = 0;
    wire [3:0] b_vga_data;

    integer i;
    integer j;
    integer errors = 0;
    reg [3:0] expected_a [0:PIXELS+8];
    reg [3:0] expected_b [0:PIXELS+8];
    integer a_sent=0, a_received=0, b_sent=0, b_received=0;
    reg vga_finished=0;

    // Scoreboard accepted requests, not a hard-coded response latency. This
    // also checks that reads queued behind same-bank writes are not lost.
    always @(posedge sys_clk) begin
        if (!reset) begin
            if (a_sys_en && a_sys_ready && a_sys_x<W && a_sys_y<H) begin
                expected_a[a_sent] = pattern_a(a_sys_y*W+a_sys_x);
                a_sent = a_sent+1;
            end
            if (b_sys_en && b_sys_ready && b_sys_x<W && b_sys_y<H) begin
                expected_b[b_sent] = pattern_b(b_sys_y*W+b_sys_x);
                b_sent = b_sent+1;
            end
            #1;
            if (a_sys_valid) begin
                if (a_received>=a_sent || a_sys_data !== expected_a[a_received])
                    fail("unexpected or incorrect A read response");
                a_received = a_received+1;
            end
            if (b_sys_valid) begin
                if (b_received>=b_sent || b_sys_data !== expected_b[b_received])
                    fail("unexpected or incorrect B read response");
                b_received = b_received+1;
            end
        end
    end

    function [3:0] pattern_a;
        input integer index;
        pattern_a = (index * 5 + 3) & 15;
    endfunction

    function [3:0] pattern_b;
        input integer index;
        pattern_b = (index * 7 + 1) & 15;
    endfunction

    frame_buffer #(.FRAME_WIDTH(W), .FRAME_HEIGHT(H)) buffer_a (
        .write_clk(sys_clk), .write_x(a_wr_x), .write_y(a_wr_y),
        .data_in(a_wr_data), .write_en(a_wr_en),
        .sys_read_x(a_sys_x), .sys_read_y(a_sys_y),
        .sys_read_en(a_sys_en), .sys_data_out(a_sys_data),
        .sys_read_valid(a_sys_valid), .sys_read_ready(a_sys_ready),
        .read_clk(vga_clk), .read_x(10'd0), .read_y(9'd0),
        .read_en(1'b0), .data_out(), .reset(reset)
    );

    frame_buffer #(.FRAME_WIDTH(W), .FRAME_HEIGHT(H)) buffer_b (
        .write_clk(sys_clk), .write_x(b_wr_x), .write_y(b_wr_y),
        .data_in(b_wr_data), .write_en(b_wr_en),
        .sys_read_x(b_sys_x), .sys_read_y(b_sys_y),
        .sys_read_en(b_sys_en), .sys_data_out(b_sys_data),
        .sys_read_valid(b_sys_valid), .sys_read_ready(b_sys_ready),
        .read_clk(vga_clk), .read_x(b_vga_x), .read_y(b_vga_y),
        .read_en(b_vga_en), .data_out(b_vga_data), .reset(reset)
    );

    task fail;
        input [8*96-1:0] message;
        begin
            errors = errors + 1;
            if (errors <= 20)
                $display("ERROR t=%0t: %0s", $time, message);
        end
    endtask

    initial begin
        repeat (3) @(posedge sys_clk);
        reset = 0;

        // Preload B. The final extra cycle drains the registered write request.
        for (i = 0; i < PIXELS; i = i + 1) begin
            @(negedge sys_clk);
            b_wr_x = i % W;
            b_wr_y = i / W;
            b_wr_data = pattern_b(i);
            b_wr_en = 1;
        end
        @(negedge sys_clk);
        b_wr_en = 0;
        @(posedge sys_clk);
        #1;

        // Concurrent system-clock operation: write A while reading B.
        for (i = 0; i < PIXELS; i = i + 1) begin
            @(negedge sys_clk);
            a_wr_x = i % W;
            a_wr_y = i / W;
            a_wr_data = pattern_a(i);
            a_wr_en = 1;

            if (!b_sys_ready)
                fail("processing framebuffer unexpectedly not ready for a read");
            b_sys_x = i % W;
            b_sys_y = i / W;
            b_sys_en = 1;

            @(posedge sys_clk);
            #1;
        end
        @(negedge sys_clk);
        a_wr_en = 0;
        b_sys_en = 0;
        @(posedge sys_clk);
        #1;

        // Read A back through the new port.
        for (i = 0; i < PIXELS; i = i + 1) begin
            @(negedge sys_clk);
            if (!a_sys_ready)
                fail("capture framebuffer did not become readable after write drain");
            a_sys_x = i % W;
            a_sys_y = i / W;
            a_sys_en = 1;
            @(posedge sys_clk);
            #1;
        end
        @(negedge sys_clk);
        a_sys_en = 0;

        // Queue a read behind a burst of writes to the SAME bank. The writes
        // keep their priority; the accepted request must eventually respond.
        a_wr_x = 0; a_wr_y = 0; a_wr_data = pattern_a(0); a_wr_en = 1;
        repeat (2) @(negedge sys_clk);
        a_sys_x = 3; a_sys_y = 2; a_sys_en = 1;
        if (!a_sys_ready) fail("empty request queue was not ready");
        @(negedge sys_clk);
        a_sys_en = 0;
        if (a_sys_ready) fail("queued read did not backpressure during writes");
        repeat (8) @(negedge sys_clk);
        a_wr_en = 0;
        repeat (4) @(negedge sys_clk);

        // Invalid coordinates must not produce a valid response.
        b_sys_x = W;
        b_sys_y = 0;
        b_sys_en = 1;
        @(posedge sys_clk);
        #1;
        if (b_sys_valid)
            fail("out-of-range system read was accepted");
        b_sys_en = 0;

        repeat (4) @(negedge sys_clk);
        if (a_sent != a_received || b_sent != b_received)
            fail("accepted read request was lost");
        wait (vga_finished);

        if (errors == 0)
            $display("PASS: %0dx%0d simultaneous ping-pong writes, system reads, and readback verified", W, H);
        else
            $fatal(1, "FAIL: %0d framebuffer errors", errors);
        $finish;
    end

    // Independently exercise the VGA port of B during system-side activity.
    initial begin
        wait (!reset);
        wait (b_wr_en == 0 && b_sys_en == 1);
        for (j = PIXELS-1; j >= 0; j = j - 1) begin
            @(negedge vga_clk);
            b_vga_x = j % W;
            b_vga_y = j / W;
            b_vga_en = 1;
            @(posedge vga_clk);
            #1;
            if (b_vga_data !== pattern_b(j))
                fail("VGA-port read conflicted with system-port activity");
        end
        @(negedge vga_clk);
        b_vga_en = 0;
        vga_finished = 1;
    end

    initial begin
        #(PIXELS*100+100000);
        $fatal(1, "FAIL: framebuffer test timed out");
    end
endmodule

module frame_buffer_vga_system_read_tb;
    frame_buffer_system_read_tb #(.W(640), .H(480)) full_frame();
endmodule
