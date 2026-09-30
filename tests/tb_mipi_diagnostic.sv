`timescale 1ns/1ps
module tb_mipi_diagnostic;
    parameter W=40, H=24, HSP=4, HBP=6, HFP=8, VSP=2, VBP=3, VFP=4;
    localparam HT=(W+HSP+HBP+HFP)/2, VT=H+VSP+VBP+VFP, FC=HT*VT;
    reg clk=0, rst_n=1, enable=0;
    wire hs, vs, de;
    wire [63:0] pixels;
    wire [31:0] frames;
    integer n, sx, sy, x, y, checks=0, active_pixels=0, pairs_differ=0;
    reg act;
    reg [23:0] p0,p1;
    always #5 clk=~clk;
    mipi_diagnostic_rgb2 #(.WIDTH(W),.HEIGHT(H),.HSP(HSP),.HBP(HBP),
        .HFP(HFP),.VSP(VSP),.VBP(VBP),.VFP(VFP)) dut (
        .clk(clk),.rst_n(rst_n),.enable_i(enable),.hs_o(hs),.vs_o(vs),
        .de_o(de),.pixels_o(pixels),.frame_count_o(frames));

    // Independent serial-pixel reference: scan the eight fractional ranges
    // rather than reusing the RTL's chain of comparator thresholds.
    function [23:0] reference_rgb(input integer ax, ay);
        integer b;
        begin
            reference_rgb=24'h000000;
            if (ax==0 || ax==W-1 || ay==0 || ay==H-1)
                reference_rgb=24'hffffff;
            else if (ay >= H*3/4) begin
                if ((ax%2) == ((ay/8)%2)) reference_rgb=24'hff4000;
                else reference_rgb=24'h0080ff;
            end else begin
                for (b=0;b<8;b=b+1) if (ax>=W*b/8 && ax<W*(b+1)/8)
                    case(b)
                        0: reference_rgb=24'hffffff;
                        1: reference_rgb=24'hffff00;
                        2: reference_rgb=24'h00ffff;
                        3: reference_rgb=24'h00ff00;
                        4: reference_rgb=24'hff00ff;
                        5: reference_rgb=24'hff0000;
                        6: reference_rgb=24'h0000ff;
                        7: reference_rgb=24'h000000;
                    endcase
            end
        end
    endfunction

    task check_zero;
        begin
            if ({hs,vs,de,pixels,frames} !== 99'd0)
                $fatal(1,"Outputs not cleared on reset/disable");
            checks=checks+1;
        end
    endtask
    task check_clock(input integer index);
        begin
            sx=2*(index%HT); sy=(index/HT)%VT;
            act=sx>=HSP+HBP && sx<HSP+HBP+W && sy>=VSP+VBP && sy<VSP+VBP+H;
            if (hs !== (sx<HSP) || vs !== (sy<VSP) || de !== act)
                $fatal(1,"Sync mismatch cycle=%0d serial x=%0d y=%0d",index,sx,sy);
            if (frames !== ((index+1)/FC)) $fatal(1,"Frame count mismatch %0d",index);
            if (act) begin
                x=sx-HSP-HBP; y=sy-VSP-VBP;
                p0=reference_rgb(x,y); p1=reference_rgb(x+1,y);
                if (pixels !== {16'd0,p1,p0})
                    $fatal(1,"RGB/packing mismatch x=%0d y=%0d got=%h expected=%h",x,y,pixels,{16'd0,p1,p0});
                active_pixels=active_pixels+2;
                if (p0!=p1) pairs_differ=pairs_differ+1;
            end else if (pixels !== 0) $fatal(1,"Nonzero blanking pixels");
            checks=checks+1;
        end
    endtask

    initial begin
        #1; rst_n=0; #1; check_zero();
        repeat(5) @(negedge clk);
        rst_n=1;
        repeat(3) begin @(posedge clk); #1; check_zero(); end
        @(negedge clk); enable=1;
        for (n=0;n<2*FC;n=n+1) begin @(posedge clk); #1; check_clock(n); end
        if (active_pixels!=2*W*H || pairs_differ==0) $fatal(1,"Incomplete pixel coverage");
        // Stop inside an active scan line, then require restart at frame origin.
        for (n=2*FC;n<2*FC+(VSP+VBP)*HT+(HSP+HBP)/2+3;n=n+1) begin
            @(posedge clk); #1; check_clock(n);
        end
        @(negedge clk); enable=0;
        repeat(5) begin @(posedge clk); #1; check_zero(); end
        @(negedge clk); enable=1;
        for (n=0;n<FC;n=n+1) begin @(posedge clk); #1; check_clock(n); end
        #2; rst_n=0; #1; check_zero();
        repeat(4) @(negedge clk);
        rst_n=1;
        for (n=0;n<HT*3;n=n+1) begin @(posedge clk); #1; check_clock(n); end
        $display("PASS mipi_diagnostic W=%0d H=%0d HT=%0d VT=%0d checks=%0d pixels_checked=%0d distinct_pairs=%0d frame_clocks=%0d",W,H,HT,VT,checks,active_pixels,pairs_differ,FC);
        $finish;
    end
    initial begin #200000000; $fatal(1,"Timeout"); end
endmodule
