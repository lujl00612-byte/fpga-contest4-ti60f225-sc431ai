`timescale 1ns/1ps
module tb_shapes;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,de=0,hs=0,vs=0,basic=0;reg [23:0] rgb=0;
    wire [23:0] out_rgb;wire od,oh,ov;wire [1:0] kind;
    shape_overlay #(.WIDTH(128),.X_BITS(8),.Y_BITS(8),.MIN_SIZE(10),.MIN_EDGES(20)) dut(
        .clk(clk),.rst_n(rst_n),.basic_i(basic),.edge_i(edge_pixel),.in_r(rgb[23:16]),.in_g(rgb[15:8]),.in_b(rgb[7:0]),
        .in_de(de),.in_hs(hs),.in_vs(vs),.out_r(out_rgb[23:16]),.out_g(out_rgb[15:8]),.out_b(out_rgb[7:0]),
        .out_de(od),.out_hs(oh),.out_vs(ov),.shape_class(kind));
    integer x,y,f,distance,white_pixels=0,checks=0;bit edge_pixel;
    task tick(input bit valid,input bit v,input reg [23:0] color);
        begin @(negedge clk);de=valid;hs=!valid;vs=v;rgb=color;@(posedge clk);#1;
            if({od,oh,ov}!=={de,hs,vs})$fatal(1,"shape output timing mismatch");checks=checks+1;
        end
    endtask
    initial begin
        repeat(4)@(posedge clk);@(negedge clk);rst_n=1;
        for(f=0;f<4;f=f+1)begin
            tick(0,1,0);repeat(5)tick(0,0,0);
            if(f==1&&kind!==1)$fatal(1,"circle classified as %d",kind);
            if(f==2&&kind!==2)$fatal(1,"rectangle classified as %d",kind);
            if(f==3&&kind!==0)$fatal(1,"empty frame classified as %d",kind);
            for(y=0;y<128;y=y+1)begin
                for(x=0;x<128;x=x+1)begin
                    distance=(x-96)*(x-96)+(y-64)*(y-64);
                    edge_pixel=f==0?(distance>=440&&distance<=484):
                        (f==1&&(((y==38||y==90)&&x>=80&&x<=118)||((x==80||x==118)&&y>=38&&y<=90)));
                    tick(1,0,edge_pixel||f==2?24'hff0000:24'h406080);
                    if(y==8&&x>=72&&x<82&&x%2==0&&f==1)begin
                        if((out_rgb==24'hffffff)!==(x!=72))$fatal(1,"CIRCLE label first glyph incorrect at %d",x);
                    end
                    if(y>=8&&y<22&&x>=72&&out_rgb==24'hffffff)white_pixels=white_pixels+1;
                end
                repeat(5)tick(0,0,0);
            end
        end
        if(white_pixels<100)$fatal(1,"text not rendered");
        $display("PASS shapes: %0d checks; first-frame circle/rectangle, empty frame, explicit text",checks);$finish;
    end
endmodule
