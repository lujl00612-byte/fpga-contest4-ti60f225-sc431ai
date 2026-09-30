`timescale 1ns/1ps
module tb_white_balance;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,de=0,hs=0,vs=0;
    reg [47:0] rgb=0;
    reg [1:0] mode=1,enhance=0;
    wire [47:0] out_rgb;wire out_de,out_hs,out_vs;
    wire [9:0] gr,gb;
    video_white_balance #(.WIDTH(16),.SUM_BITS(20),.SAMPLE_LOG2(1),.MIN_SAMPLES(16)) dut(
        .clk(clk),.rst_n(rst_n),.rgb_i(rgb),.de_i(de),.hs_i(hs),.vs_i(vs),
        .mode_i(mode),.enhance_i(enhance),.rgb_o(out_rgb),.de_o(out_de),.hs_o(out_hs),.vs_o(out_vs),
        .gain_r(gr),.gain_b(gb));
    function automatic integer clip(input integer v);
        clip=v<0?0:v>255?255:v;
    endfunction
    function automatic integer enhanced(input integer c,input integer y,input integer s);
        integer v,d;
        begin
            d=c-y;
            case(s)
                0:v=c;1:v=c+(d>>>2);2:v=c+(d>>>1);3:v=c+d;
            endcase
            if(s!=0)v=v+((v-128)>>>4);
            enhanced=clip(v);
        end
    endfunction
    function automatic [23:0] golden(input [23:0] pixel,input integer gainr,input integer gainb,
                                    input integer m,input integer s,input integer x);
        integer r,g,b,y;reg [7:0] rr,gg,bb;
        begin
            r=pixel[23:16];g=pixel[15:8];b=pixel[7:0];
            if(m==3)begin
                case(x/2)
                    0:golden=24'hffffff;1:golden=24'hffff00;2:golden=24'h00ffff;3:golden=24'h00ff00;
                    4:golden=24'hff00ff;5:golden=24'hff0000;6:golden=24'h0000ff;default:golden=0;
                endcase
            end else begin
                if(m!=0)begin r=clip(r*gainr/256);b=clip(b*gainb/256);end
                y=(r+2*g+b)/4;
                if(m==2)begin r=enhanced(r,y,s);g=enhanced(g,y,s);b=enhanced(b,y,s);end
                rr=r;gg=g;bb=b;golden={rr,gg,bb};
            end
        end
    endfunction
    reg [47:0] expected[0:2];reg [2:0] sync_expected[0:2];
    integer model_mode=1,model_enhance=0,model_x=0,checks=0;
    reg model_vs=0;
    always @(posedge clk) begin
        if(!rst_n)begin
            expected[0]=0;expected[1]=0;expected[2]=0;
            sync_expected[0]=0;sync_expected[1]=0;sync_expected[2]=0;
            model_mode=1;model_enhance=0;model_x=0;model_vs=0;
        end else begin
            expected[2]=expected[1];expected[1]=expected[0];
            expected[0]=de?{golden(rgb[47:24],gr,gb,model_mode,model_enhance,model_x),
                           golden(rgb[23:0],gr,gb,model_mode,model_enhance,model_x+1)}:48'd0;
            sync_expected[2]=sync_expected[1];sync_expected[1]=sync_expected[0];sync_expected[0]={de,hs,vs};
            if(vs&&!model_vs)begin model_mode=mode;model_enhance=enhance;end
            model_vs=vs;model_x=de?model_x+2:0;
            #1;
            if(out_rgb!==expected[2]||{out_de,out_hs,out_vs}!==sync_expected[2])
                $fatal(1,"pixel/sync mismatch at %0t got %h expected %h",$time,out_rgb,expected[2]);
            checks=checks+1;
        end
    end
    task automatic cycle(input [47:0] v,input d,input h,input s);
        begin @(negedge clk);rgb=v;de=d;hs=h;vs=s;end
    endtask
    task automatic frame(input [23:0] pixel);
        integer k,l;
        begin
            cycle(0,0,0,1);cycle(0,0,0,0);
            repeat(100)cycle(0,0,0,0);
            for(l=0;l<20;l=l+1)begin
                for(k=0;k<8;k=k+1)cycle({pixel,pixel},1,0,0);
                cycle(0,0,1,0);cycle(0,0,0,0);
            end
            repeat(100)cycle(0,0,0,0);
        end
    endtask
    integer i;
    initial begin
        repeat(5)@(negedge clk);rst_n=1;
        frame(24'h8c6450); // R=140 G=100 B=80, reference target gains 182/320.
        cycle(0,0,0,1);cycle(0,0,0,0);repeat(100)cycle(0,0,0,0);
        @(negedge clk);
        if(gr!=247||gb!=264)$fatal(1,"AWB division/smoothing mismatch %0d %0d",gr,gb);
        for(i=0;i<500;i=i+1)cycle({$random,$random},1,i%7==0,0);
        mode=0;frame(24'h646464);
        for(i=0;i<500;i=i+1)cycle({$random,$random},i%9!=0,i%7==0,0);
        mode=2;
        for(i=0;i<4;i=i+1)begin enhance=i;frame(24'h646464);end
        mode=3;frame(24'h646464);
        // A neutral scene has no artificial channel difference at unity after reset.
        @(negedge clk);rst_n=0;repeat(4)@(negedge clk);rst_n=1;mode=1;enhance=0;
        frame(24'h646464);cycle(0,0,0,1);cycle(0,0,0,0);repeat(100)cycle(0,0,0,0);
        @(negedge clk);if(gr!=256||gb!=256)$fatal(1,"neutral gains changed");
        $display("PASS white balance: %0d pixel/sync checks, divider, neutral scene, clipping, bypass, bars",checks);
        $finish;
    end
endmodule
