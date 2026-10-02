`timescale 1ns/1ps
module orb_tracker_check #(parameter N=8)(output reg done=0);
    localparam CW=$clog2(N+1), SW=(N<=1)?1:$clog2(N);
    reg clk=0, reset=1, frame_start=0, valid=0;
    reg [7:0] score=0;
    wire accept;
    wire [SW-1:0] slot;
    wire [CW-1:0] count;
    integer values[0:N-1];
    integer n=0, cycle, i, minslot, expected_slot, seed;
    reg expected_accept;
    always #5 clk=~clk;
    orb_grid_cell_tracker #(.TOP_N(N)) dut(.clk(clk),.reset(reset),
        .frame_start(frame_start),.candidate_valid(valid),.candidate_score(score),
        .candidate_accept(accept),.candidate_slot(slot),.count(count));
    initial begin
        seed=571+N;
        repeat(3) @(negedge clk);
        reset=0;
        for(cycle=0;cycle<20000;cycle=cycle+1) begin
            @(negedge clk);
            frame_start=(cycle%100==99);
            valid=(cycle%7!=0);
            // Many ties and all-255 sets exercise insertion and physical slot order.
            score=(cycle%100<12)?255:($random(seed)&255);
            if(cycle%4==0) score=0;
            #1;
            if(count !== n) $fatal(1,"TOP_N=%0d count mismatch",N);
            minslot=0;
            for(i=0;i<n;i=i+1) if(values[i]<=values[minslot]) minslot=i;
            expected_accept=valid && (n<N || score>values[minslot]);
            expected_slot=(n<N)?n:minslot;
            if(accept !== expected_accept || (expected_accept && slot !== expected_slot))
                $fatal(1,"TOP_N=%0d cycle=%0d accept/slot mismatch",N,cycle);
            @(posedge clk);
            if(frame_start) n=0;
            else if(expected_accept) begin
                values[expected_slot]=score;
                if(n<N) n=n+1;
            end
        end
        @(negedge clk); valid=0; done=1;
    end
endmodule

module orb_grid_tracker_tb;
    wire a,b,c;
    orb_tracker_check #(.N(1)) one(a);
    orb_tracker_check #(.N(3)) three(b);
    orb_tracker_check #(.N(8)) eight(c);
    initial begin
        wait(a && b && c);
        $display("PASS: 60000 tracker cycles, TOP_N=1/3/8, ties, replacements, frame resets");
        $finish;
    end
    initial begin #1000000; $fatal(1,"tracker timeout"); end
endmodule
