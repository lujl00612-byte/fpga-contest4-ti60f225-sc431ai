// RGB888 pixels, high pixel first. Statistics are measured before correction.
// Mode 0: original; 1: gray-world AWB; 2: AWB + saturation/contrast; 3: test bars.
module video_white_balance #(
    parameter integer PIXELS=2,
    parameter integer WIDTH=1920,
    parameter integer SUM_BITS=28,
    parameter integer SAMPLE_LOG2=5,
    parameter integer MIN_SAMPLES=64
)(
    input wire clk,input wire rst_n,
    input wire [24*PIXELS-1:0] rgb_i,
    input wire de_i,input wire hs_i,input wire vs_i,
    input wire [1:0] mode_i,input wire [1:0] enhance_i,
    output reg [24*PIXELS-1:0] rgb_o,
    output reg de_o,output reg hs_o,output reg vs_o,
    output reg [9:0] gain_r,output reg [9:0] gain_b
);
    localparam integer DIV_BITS=SUM_BITS+8;
    reg vs_d;
    reg [SAMPLE_LOG2-1:0] sample_phase;
    reg [SUM_BITS-1:0] sum_r,sum_g,sum_b;
    reg [19:0] sample_count;
    reg [SUM_BITS-1:0] frame_g,frame_b;
    reg [DIV_BITS-1:0] numerator,quotient;
    reg [DIV_BITS:0] remainder;
    reg [SUM_BITS-1:0] denominator;
    reg [6:0] div_left;
    reg div_busy,div_blue;
    reg [9:0] next_r;
    reg [1:0] active_mode,active_enhance;
    reg [11:0] x;

    reg [SUM_BITS-1:0] add_r,add_g,add_b;
    reg [3:0] add_count;
    integer p;
    reg [7:0] sr,sg,sb,smin,smax;
    always @* begin
        add_r=0;add_g=0;add_b=0;add_count=0;
        sr=0;sg=0;sb=0;smin=0;smax=0;
        for(p=0;p<PIXELS;p=p+1) begin
            sr=rgb_i[p*24+16+:8];sg=rgb_i[p*24+8+:8];sb=rgb_i[p*24+:8];
            smin=(sr<sg)?sr:sg;smin=(smin<sb)?smin:sb;
            smax=(sr>sg)?sr:sg;smax=(smax>sb)?smax:sb;
            // Reject black, clipped pixels and strongly colored objects.
            if(smin>=16 && smax<=239 && (smax-smin)<=96) begin
                add_r=add_r+sr;add_g=add_g+sg;add_b=add_b+sb;add_count=add_count+1'b1;
            end
        end
    end
    wire [DIV_BITS:0] trial={remainder[DIV_BITS-1:0],numerator[DIV_BITS-1]};
    wire take=trial>={{9{1'b0}},denominator};
    wire [DIV_BITS-1:0] quotient_next={quotient[DIV_BITS-2:0],take};
    wire [9:0] bounded_gain=(quotient_next<128)?10'd128:
                            ((quotient_next>512)?10'd512:quotient_next[9:0]);
    wire [13:0] blended_r=({4'd0,gain_r}<<3)-{4'd0,gain_r}+{4'd0,next_r}+14'd4;
    wire [13:0] blended_b=({4'd0,gain_b}<<3)-{4'd0,gain_b}+{4'd0,bounded_gain}+14'd4;

    always @(posedge clk) begin
        if(!rst_n) begin
            vs_d<=0;sample_phase<=0;sum_r<=0;sum_g<=0;sum_b<=0;sample_count<=0;
            frame_g<=0;frame_b<=0;numerator<=0;quotient<=0;remainder<=0;denominator<=0;
            div_left<=0;div_busy<=0;div_blue<=0;next_r<=256;gain_r<=256;gain_b<=256;
            active_mode<=1;active_enhance<=0;x<=0;
        end else begin
            vs_d<=vs_i;
            if(de_i)x<=x+PIXELS;else x<=0;
            if(vs_i&&!vs_d) begin
                active_mode<=mode_i;active_enhance<=enhance_i;sample_phase<=0;
                sum_r<=0;sum_g<=0;sum_b<=0;sample_count<=0;
                if(sample_count>=MIN_SAMPLES&&!div_busy) begin
                    frame_g<=sum_g;frame_b<=sum_b;numerator<={sum_g,8'd0};
                    denominator<=sum_r;quotient<=0;remainder<=0;
                    div_left<=DIV_BITS;div_busy<=1;div_blue<=0;
                end
            end else if(de_i) begin
                sample_phase<=sample_phase+1'b1;
                if(sample_phase==0) begin
                    sum_r<=sum_r+add_r;sum_g<=sum_g+add_g;sum_b<=sum_b+add_b;
                    sample_count<=sample_count+add_count;
                end
            end
            if(div_busy) begin
                numerator<=numerator<<1;quotient<=quotient_next;div_left<=div_left-1'b1;
                remainder<=take?(trial-{{9{1'b0}},denominator}):trial;
                if(div_left==1) begin
                    if(!div_blue) begin
                        next_r<=bounded_gain;denominator<=frame_b;numerator<={frame_g,8'd0};
                        remainder<=0;quotient<=0;div_left<=DIV_BITS;div_blue<=1;
                    end else begin
                        gain_r<=blended_r[12:3];gain_b<=blended_b[12:3];div_busy<=0;
                    end
                end
            end
        end
    end

    function [7:0] clamp_product;
        input [17:0] v;
        begin clamp_product=(v[17:8]>255)?8'd255:v[15:8];end
    endfunction
    function [7:0] enhance_channel;
        input [7:0] channel,luma;
        input [1:0] strength;
        reg signed [11:0] delta,value,centered;
        begin
            delta=$signed({1'b0,channel})-$signed({1'b0,luma});
            case(strength)
                0:value=$signed({1'b0,channel});
                1:value=$signed({1'b0,channel})+(delta>>>2);
                2:value=$signed({1'b0,channel})+(delta>>>1);
                default:value=$signed({1'b0,channel})+delta;
            endcase
            centered=value-12'sd128;
            if(strength!=0)value=value+(centered>>>4);
            enhance_channel=(value<0)?8'd0:((value>255)?8'd255:value[7:0]);
        end
    endfunction
    function [23:0] color_bar;
        input [11:0] px;
        begin
            if(px<WIDTH/8)color_bar=24'hffffff;
            else if(px<WIDTH*2/8)color_bar=24'hffff00;
            else if(px<WIDTH*3/8)color_bar=24'h00ffff;
            else if(px<WIDTH*4/8)color_bar=24'h00ff00;
            else if(px<WIDTH*5/8)color_bar=24'hff00ff;
            else if(px<WIDTH*6/8)color_bar=24'hff0000;
            else if(px<WIDTH*7/8)color_bar=24'h0000ff;
            else color_bar=24'h000000;
        end
    endfunction
    reg [17:0] pr[0:PIXELS-1],pg[0:PIXELS-1],pb[0:PIXELS-1];
    reg [24*PIXELS-1:0] raw0,bars0,rgb1;
    reg de0,hs0,vs0,de1,hs1,vs1;
    reg [1:0] mode0,mode1,enhance0,enhance1;
    integer k;
    reg [7:0] cr,cg,cb;
    reg [9:0] lum_sum;
    always @(posedge clk) begin
        if(!rst_n) begin
            raw0<=0;bars0<=0;rgb1<=0;rgb_o<=0;
            de0<=0;hs0<=0;vs0<=0;de1<=0;hs1<=0;vs1<=0;de_o<=0;hs_o<=0;vs_o<=0;
            mode0<=0;mode1<=0;enhance0<=0;enhance1<=0;
            for(k=0;k<PIXELS;k=k+1)begin pr[k]<=0;pg[k]<=0;pb[k]<=0;end
        end else begin
            raw0<=rgb_i;mode0<=active_mode;enhance0<=active_enhance;
            de0<=de_i;hs0<=hs_i;vs0<=vs_i;
            for(k=0;k<PIXELS;k=k+1) begin
                pr[k]<=rgb_i[k*24+16+:8]*gain_r;
                pg[k]<={2'd0,rgb_i[k*24+8+:8],8'd0};
                pb[k]<=rgb_i[k*24+:8]*gain_b;
                bars0[k*24+:24]<=color_bar(x+PIXELS-1-k);
                if(mode0==0)rgb1[k*24+:24]<=raw0[k*24+:24];
                else if(mode0==3)rgb1[k*24+:24]<=bars0[k*24+:24];
                else rgb1[k*24+:24]<={clamp_product(pr[k]),clamp_product(pg[k]),clamp_product(pb[k])};
                cr=rgb1[k*24+16+:8];cg=rgb1[k*24+8+:8];cb=rgb1[k*24+:8];
                lum_sum={2'd0,cr}+{1'b0,cg,1'b0}+{2'd0,cb};
                if(!de1)rgb_o[k*24+:24]<=0;
                else if(mode1==2)rgb_o[k*24+:24]<={enhance_channel(cr,lum_sum[9:2],enhance1),
                    enhance_channel(cg,lum_sum[9:2],enhance1),enhance_channel(cb,lum_sum[9:2],enhance1)};
                else rgb_o[k*24+:24]<=rgb1[k*24+:24];
            end
            mode1<=mode0;enhance1<=enhance0;
            de1<=de0;hs1<=hs0;vs1<=vs0;de_o<=de1;hs_o<=hs1;vs_o<=vs1;
        end
    end
endmodule
