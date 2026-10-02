`timescale 1ns/1ps
module orb_descriptor_tb;
    reg clk=0, reset=1, start=0, pv=0, pd=0, reject=0, ready=0;
    reg [3:0] pixel=0;
    reg [5:0] col=0, row=0;
    wire start_ready, valid, rejected;
    wire [255:0] descriptor;
    wire [4:0] angle;
    reg [3:0] pixels[0:67239];
    reg [263:0] expected[0:39];
    integer patch, i;
    reg [260:0] held;
    always #5 clk=~clk;
    orb_descriptor dut(.clk(clk),.reset(reset),.start(start),
        .patch_valid(pv),.patch_pixel(pixel),.patch_col(col),.patch_row(row),
        .patch_done(pd),.patch_rejected(reject),.start_ready(start_ready),
        .descriptor_valid(valid),.descriptor_ready(ready),.descriptor(descriptor),
        .angle_bin(angle),.rejected(rejected));
    initial begin
        #20000000; $fatal(1,"descriptor timeout");
    end
    initial begin
        $readmemh("patches.hex",pixels);
        $readmemh("descriptor_expected.hex",expected);
        repeat(4) @(negedge clk);
        for(i=0;i<4096;i=i+1) begin
            col=i%64; row=i/64;
            #1;
            if(dut.in_centroid !== (((i%64-20)*(i%64-20)+(i/64-20)*(i/64-20))<=225))
                $fatal(1,"centroid mask mismatch at %0d,%0d",col,row);
        end
        @(negedge clk);
        reset=0;
        for(patch=0;patch<40;patch=patch+1) begin
            wait(start_ready); @(negedge clk); start=1;
            @(negedge clk); start=0;
            for(i=0;i<1681;i=i+1) begin
                pv=1; pixel=pixels[patch*1681+i]; col=i%41; row=i/41; pd=(i==1680);
                @(negedge clk);
                if(i%7==0) begin pv=0; pd=0; @(negedge clk); end
            end
            pv=0; pd=0;
            wait(valid); @(negedge clk);
            if({3'b0,angle,descriptor} !== expected[patch])
                $fatal(1,"patch %0d: got angle=%0d desc=%h expected=%h",patch,angle,descriptor,expected[patch]);
            held={angle,descriptor};
            repeat(13) begin
                @(negedge clk);
                if(!valid || {angle,descriptor} !== held) $fatal(1,"stalled output changed");
            end
            ready=1; @(negedge clk); ready=0;
        end
        wait(start_ready); @(negedge clk); start=1;
        @(negedge clk); start=0; reject=1; pd=1;
        @(negedge clk); reject=0; pd=0;
        if(!rejected || !start_ready || valid) $fatal(1,"reject handshake failed");
        $display("PASS: exhaustive centroid mask, 40 reference patches, all angle bins, 256-bit descriptors, gaps, stalls, rejection");
        $finish;
    end
endmodule
