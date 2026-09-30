// Contest 4 advanced A2: streaming Canny pipeline with color edge overlay.
module contest4_sobel_display #(
    parameter integer WIDTH=1920, parameter integer X_BITS=11, parameter integer Y_BITS=11
)(
    input wire clk, input wire rst_n,
    input wire [7:0] in_r,input wire [7:0] in_g,input wire [7:0] in_b,
    input wire in_de,input wire in_hs,input wire in_vs,input wire [10:0] threshold_i,
    output wire [7:0] out_r,output wire [7:0] out_g,output wire [7:0] out_b,
    output wire out_de,output wire out_hs,output wire out_vs
);
    wire [7:0] smooth_gray; wire [23:0] smooth_rgb;
    wire smooth_de,smooth_hs,smooth_vs;
    wire [12:0] grad_mag; wire [1:0] grad_dir; wire [7:0] grad_gray; wire [23:0] grad_rgb;
    wire grad_de,grad_hs,grad_vs;
    wire [1:0] edge_class; wire [7:0] nms_gray; wire [23:0] nms_rgb;
    wire nms_de,nms_hs,nms_vs;

    gaussian3x3_rgb_aligned #(.WIDTH(WIDTH),.X_BITS(X_BITS),.Y_BITS(Y_BITS)) u_gaussian(
        .clk(clk),.rst_n(rst_n),.in_r(in_r),.in_g(in_g),.in_b(in_b),
        .in_de(in_de),.in_hs(in_hs),.in_vs(in_vs),
        .out_gray(smooth_gray),.out_rgb(smooth_rgb),.out_de(smooth_de),.out_hs(smooth_hs),.out_vs(smooth_vs));
    sobel_gradient_direction #(.WIDTH(WIDTH),.X_BITS(X_BITS),.Y_BITS(Y_BITS)) u_gradient(
        .clk(clk),.rst_n(rst_n),.in_gray(smooth_gray),.in_rgb(smooth_rgb),
        .in_de(smooth_de),.in_hs(smooth_hs),.in_vs(smooth_vs),
        .out_mag(grad_mag),.out_dir(grad_dir),.out_gray(grad_gray),.out_rgb(grad_rgb),
        .out_de(grad_de),.out_hs(grad_hs),.out_vs(grad_vs));
    canny_nms_dual_threshold #(.WIDTH(WIDTH),.X_BITS(X_BITS),.Y_BITS(Y_BITS)) u_nms(
        .clk(clk),.rst_n(rst_n),.in_mag(grad_mag),.in_dir(grad_dir),.in_gray(grad_gray),.in_rgb(grad_rgb),
        .in_de(grad_de),.in_hs(grad_hs),.in_vs(grad_vs),.high_threshold(threshold_i),
        .out_class(edge_class),.out_gray(nms_gray),.out_rgb(nms_rgb),
        .out_de(nms_de),.out_hs(nms_hs),.out_vs(nms_vs));
    canny_hysteresis_overlay #(.WIDTH(WIDTH),.X_BITS(X_BITS),.Y_BITS(Y_BITS)) u_hysteresis(
        .clk(clk),.rst_n(rst_n),.in_class(edge_class),.in_gray(nms_gray),.in_rgb(nms_rgb),
        .in_de(nms_de),.in_hs(nms_hs),.in_vs(nms_vs),
        .out_r(out_r),.out_g(out_g),.out_b(out_b),.out_de(out_de),.out_hs(out_hs),.out_vs(out_vs));
endmodule

module gaussian3x3_rgb_aligned #(
    parameter integer WIDTH=1920, parameter integer X_BITS=11, parameter integer Y_BITS=11
)(
    input wire clk,input wire rst_n,input wire [7:0] in_r,input wire [7:0] in_g,input wire [7:0] in_b,
    input wire in_de,input wire in_hs,input wire in_vs,
    output reg [7:0] out_gray,output reg [23:0] out_rgb,
    output reg out_de,output reg out_hs,output reg out_vs
);
    wire [15:0] gray_sum=in_r*8'd77+in_g*8'd150+in_b*8'd29;
    wire [7:0] gray=gray_sum[15:8]; wire [23:0] rgb={in_r,in_g,in_b};
    reg [7:0] go[0:WIDTH-1],gn[0:WIDTH-1]; reg [23:0] ro[0:WIDTH-1],rn[0:WIDTH-1];
    reg [X_BITS-1:0] x; reg [Y_BITS-1:0] y; reg de_d,vs_d;
    reg [7:0] st,sm,sb; reg [23:0] srt,srm,srb;
    reg [X_BITS-1:0] sx; reg [Y_BITS-1:0] sy; reg sde,shs,svs;
    reg [7:0] t0,t1,t2,m0,m1,m2,b0,b1,b2;
    reg [23:0] rt0,rt1,rt2,rm0,rm1,rm2,rb0,rb1,rb2;
    reg [X_BITS-1:0] wx; reg [Y_BITS-1:0] wy; reg wde,whs,wvs;
    wire [11:0] sum={4'd0,t0}+{3'd0,t1,1'b0}+{4'd0,t2}
                   +{3'd0,m0,1'b0}+{2'd0,m1,2'b0}+{3'd0,m2,1'b0}
                   +{4'd0,b0}+{3'd0,b1,1'b0}+{4'd0,b2};
    always @(posedge clk) begin
        if(!rst_n) begin
            x<=0;y<=0;de_d<=0;vs_d<=0;st<=0;sm<=0;sb<=0;srt<=0;srm<=0;srb<=0;
            sx<=0;sy<=0;sde<=0;shs<=0;svs<=0;t0<=0;t1<=0;t2<=0;m0<=0;m1<=0;m2<=0;b0<=0;b1<=0;b2<=0;
            rt0<=0;rt1<=0;rt2<=0;rm0<=0;rm1<=0;rm2<=0;rb0<=0;rb1<=0;rb2<=0;
            wx<=0;wy<=0;wde<=0;whs<=0;wvs<=0;out_gray<=0;out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;
        end else begin
            de_d<=in_de;vs_d<=in_vs;if(in_de)x<=x+1'b1;else x<=0;
            if(in_vs&&!vs_d)y<=0;else if(de_d&&!in_de)y<=y+1'b1;
            if(in_de&&x<WIDTH) begin
                st<=go[x];sm<=gn[x];sb<=gray;srt<=ro[x];srm<=rn[x];srb<=rgb;
                go[x]<=gn[x];gn[x]<=gray;ro[x]<=rn[x];rn[x]<=rgb;
            end else begin st<=0;sm<=0;sb<=0;srt<=0;srm<=0;srb<=0;end
            sx<=x;sy<=y;sde<=in_de;shs<=in_hs;svs<=in_vs;
            if(sde) begin
                t0<=t1;t1<=t2;t2<=st;m0<=m1;m1<=m2;m2<=sm;b0<=b1;b1<=b2;b2<=sb;
                rt0<=rt1;rt1<=rt2;rt2<=srt;rm0<=rm1;rm1<=rm2;rm2<=srm;rb0<=rb1;rb1<=rb2;rb2<=srb;
            end else begin
                t0<=0;t1<=0;t2<=0;m0<=0;m1<=0;m2<=0;b0<=0;b1<=0;b2<=0;
                rt0<=0;rt1<=0;rt2<=0;rm0<=0;rm1<=0;rm2<=0;rb0<=0;rb1<=0;rb2<=0;
            end
            wx<=(sx==0)?0:sx-1'b1;wy<=(sy==0)?0:sy-1'b1;wde<=sde;whs<=shs;wvs<=svs;
            out_de<=wde;out_hs<=whs;out_vs<=wvs;
            if(!wde||wx<2||wy<2)begin out_gray<=0;out_rgb<=0;end
            else begin out_gray<=sum[11:4];out_rgb<=rm1;end
        end
    end
endmodule

module sobel_gradient_direction #(
    parameter integer WIDTH=1920, parameter integer X_BITS=11, parameter integer Y_BITS=11
)(
    input wire clk,input wire rst_n,input wire [7:0] in_gray,input wire [23:0] in_rgb,
    input wire in_de,input wire in_hs,input wire in_vs,
    output reg [12:0] out_mag,output reg [1:0] out_dir,output reg [7:0] out_gray,output reg [23:0] out_rgb,
    output reg out_de,output reg out_hs,output reg out_vs
);
    reg [7:0] go[0:WIDTH-1],gn[0:WIDTH-1];reg [23:0] ro[0:WIDTH-1],rn[0:WIDTH-1];
    reg [X_BITS-1:0] x;reg [Y_BITS-1:0] y;reg de_d,vs_d;
    reg [7:0] st,sm,sb;reg [23:0] srt,srm,srb;reg [X_BITS-1:0] sx;reg [Y_BITS-1:0] sy;reg sde,shs,svs;
    reg [7:0] t0,t1,t2,m0,m1,m2,b0,b1,b2;reg [23:0] rt0,rt1,rt2,rm0,rm1,rm2,rb0,rb1,rb2;
    reg [X_BITS-1:0] wx;reg [Y_BITS-1:0] wy;reg wde,whs,wvs;
    wire signed [11:0] gx=$signed({4'd0,t2})+($signed({4'd0,m2})<<<1)+$signed({4'd0,b2})
                         -$signed({4'd0,t0})-($signed({4'd0,m0})<<<1)-$signed({4'd0,b0});
    wire signed [11:0] gy=$signed({4'd0,b0})+($signed({4'd0,b1})<<<1)+$signed({4'd0,b2})
                         -$signed({4'd0,t0})-($signed({4'd0,t1})<<<1)-$signed({4'd0,t2});
    wire [11:0] ax=gx[11]?-gx:gx;wire [11:0] ay=gy[11]?-gy:gy;
    wire [11:0] mx=(ax>=ay)?ax:ay;wire [11:0] mn=(ax>=ay)?ay:ax;
    wire [12:0] mag={1'b0,mx}+{2'b0,mn[11:1]};
    wire [1:0] dir=(ay<=(ax>>1))?2'd0:((ax<=(ay>>1))?2'd2:((gx[11]==gy[11])?2'd1:2'd3));
    always @(posedge clk) begin
        if(!rst_n)begin
            x<=0;y<=0;de_d<=0;vs_d<=0;st<=0;sm<=0;sb<=0;srt<=0;srm<=0;srb<=0;sx<=0;sy<=0;sde<=0;shs<=0;svs<=0;
            t0<=0;t1<=0;t2<=0;m0<=0;m1<=0;m2<=0;b0<=0;b1<=0;b2<=0;rt0<=0;rt1<=0;rt2<=0;rm0<=0;rm1<=0;rm2<=0;rb0<=0;rb1<=0;rb2<=0;
            wx<=0;wy<=0;wde<=0;whs<=0;wvs<=0;out_mag<=0;out_dir<=0;out_gray<=0;out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;
        end else begin
            de_d<=in_de;vs_d<=in_vs;if(in_de)x<=x+1'b1;else x<=0;if(in_vs&&!vs_d)y<=0;else if(de_d&&!in_de)y<=y+1'b1;
            if(in_de&&x<WIDTH)begin st<=go[x];sm<=gn[x];sb<=in_gray;srt<=ro[x];srm<=rn[x];srb<=in_rgb;go[x]<=gn[x];gn[x]<=in_gray;ro[x]<=rn[x];rn[x]<=in_rgb;end
            else begin st<=0;sm<=0;sb<=0;srt<=0;srm<=0;srb<=0;end
            sx<=x;sy<=y;sde<=in_de;shs<=in_hs;svs<=in_vs;
            if(sde)begin t0<=t1;t1<=t2;t2<=st;m0<=m1;m1<=m2;m2<=sm;b0<=b1;b1<=b2;b2<=sb;rt0<=rt1;rt1<=rt2;rt2<=srt;rm0<=rm1;rm1<=rm2;rm2<=srm;rb0<=rb1;rb1<=rb2;rb2<=srb;end
            else begin t0<=0;t1<=0;t2<=0;m0<=0;m1<=0;m2<=0;b0<=0;b1<=0;b2<=0;rt0<=0;rt1<=0;rt2<=0;rm0<=0;rm1<=0;rm2<=0;rb0<=0;rb1<=0;rb2<=0;end
            wx<=(sx==0)?0:sx-1'b1;wy<=(sy==0)?0:sy-1'b1;wde<=sde;whs<=shs;wvs<=svs;
            out_de<=wde;out_hs<=whs;out_vs<=wvs;
            if(!wde||wx<2||wy<2)begin out_mag<=0;out_dir<=0;out_gray<=0;out_rgb<=0;end
            else begin out_mag<=mag;out_dir<=dir;out_gray<=m1;out_rgb<=rm1;end
        end
    end
endmodule

module canny_nms_dual_threshold #(
    parameter integer WIDTH=1920,parameter integer X_BITS=11,parameter integer Y_BITS=11
)(
    input wire clk,input wire rst_n,input wire [12:0] in_mag,input wire [1:0] in_dir,
    input wire [7:0] in_gray,input wire [23:0] in_rgb,input wire in_de,input wire in_hs,input wire in_vs,
    input wire [10:0] high_threshold,
    output reg [1:0] out_class,output reg [7:0] out_gray,output reg [23:0] out_rgb,
    output reg out_de,output reg out_hs,output reg out_vs
);
    reg [12:0] mo[0:WIDTH-1],mn[0:WIDTH-1];reg [1:0] do_[0:WIDTH-1],dn[0:WIDTH-1];
    reg [7:0] go[0:WIDTH-1],gn[0:WIDTH-1];reg [23:0] ro[0:WIDTH-1],rn[0:WIDTH-1];
    reg [X_BITS-1:0] x;reg [Y_BITS-1:0] y;reg de_d,vs_d;
    reg [12:0] st,sm,sb;reg [1:0] sdt,sdm,sdb;reg [7:0] sgt,sgm,sgb;reg [23:0] srt,srm,srb;
    reg [X_BITS-1:0] sx;reg [Y_BITS-1:0] sy;reg sde,shs,svs;
    reg [12:0] t0,t1,t2,m0,m1,m2,b0,b1,b2;reg [1:0] dt0,dt1,dt2,dm0,dm1,dm2,db0,db1,db2;
    reg [7:0] gt0,gt1,gt2,gm0,gm1,gm2,gb0,gb1,gb2;reg [23:0] rt0,rt1,rt2,rm0,rm1,rm2,rb0,rb1,rb2;
    reg [X_BITS-1:0] wx;reg [Y_BITS-1:0] wy;reg wde,whs,wvs;
    reg [12:0] n1,n2;
    wire [12:0] low_threshold={3'b000,high_threshold[10:1]};
    always @(*) begin
        case(dm1)
            2'd0:begin n1=m0;n2=m2;end
            2'd1:begin n1=t0;n2=b2;end
            2'd2:begin n1=t1;n2=b1;end
            default:begin n1=t2;n2=b0;end
        endcase
    end
    wire [12:0] nms_mag=((m1>=n1)&&(m1>=n2))?m1:13'd0;
    wire [1:0] classified=(nms_mag>={2'b00,high_threshold})?2'd2:((nms_mag>=low_threshold)?2'd1:2'd0);
    always @(posedge clk)begin
        if(!rst_n)begin
            x<=0;y<=0;de_d<=0;vs_d<=0;st<=0;sm<=0;sb<=0;sdt<=0;sdm<=0;sdb<=0;sgt<=0;sgm<=0;sgb<=0;srt<=0;srm<=0;srb<=0;sx<=0;sy<=0;sde<=0;shs<=0;svs<=0;
            t0<=0;t1<=0;t2<=0;m0<=0;m1<=0;m2<=0;b0<=0;b1<=0;b2<=0;dt0<=0;dt1<=0;dt2<=0;dm0<=0;dm1<=0;dm2<=0;db0<=0;db1<=0;db2<=0;
            gt0<=0;gt1<=0;gt2<=0;gm0<=0;gm1<=0;gm2<=0;gb0<=0;gb1<=0;gb2<=0;rt0<=0;rt1<=0;rt2<=0;rm0<=0;rm1<=0;rm2<=0;rb0<=0;rb1<=0;rb2<=0;
            wx<=0;wy<=0;wde<=0;whs<=0;wvs<=0;out_class<=0;out_gray<=0;out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;
        end else begin
            de_d<=in_de;vs_d<=in_vs;if(in_de)x<=x+1'b1;else x<=0;if(in_vs&&!vs_d)y<=0;else if(de_d&&!in_de)y<=y+1'b1;
            if(in_de&&x<WIDTH)begin
                st<=mo[x];sm<=mn[x];sb<=in_mag;sdt<=do_[x];sdm<=dn[x];sdb<=in_dir;sgt<=go[x];sgm<=gn[x];sgb<=in_gray;srt<=ro[x];srm<=rn[x];srb<=in_rgb;
                mo[x]<=mn[x];mn[x]<=in_mag;do_[x]<=dn[x];dn[x]<=in_dir;go[x]<=gn[x];gn[x]<=in_gray;ro[x]<=rn[x];rn[x]<=in_rgb;
            end else begin st<=0;sm<=0;sb<=0;sdt<=0;sdm<=0;sdb<=0;sgt<=0;sgm<=0;sgb<=0;srt<=0;srm<=0;srb<=0;end
            sx<=x;sy<=y;sde<=in_de;shs<=in_hs;svs<=in_vs;
            if(sde)begin
                t0<=t1;t1<=t2;t2<=st;m0<=m1;m1<=m2;m2<=sm;b0<=b1;b1<=b2;b2<=sb;
                dt0<=dt1;dt1<=dt2;dt2<=sdt;dm0<=dm1;dm1<=dm2;dm2<=sdm;db0<=db1;db1<=db2;db2<=sdb;
                gt0<=gt1;gt1<=gt2;gt2<=sgt;gm0<=gm1;gm1<=gm2;gm2<=sgm;gb0<=gb1;gb1<=gb2;gb2<=sgb;
                rt0<=rt1;rt1<=rt2;rt2<=srt;rm0<=rm1;rm1<=rm2;rm2<=srm;rb0<=rb1;rb1<=rb2;rb2<=srb;
            end else begin
                t0<=0;t1<=0;t2<=0;m0<=0;m1<=0;m2<=0;b0<=0;b1<=0;b2<=0;dt0<=0;dt1<=0;dt2<=0;dm0<=0;dm1<=0;dm2<=0;db0<=0;db1<=0;db2<=0;
                gt0<=0;gt1<=0;gt2<=0;gm0<=0;gm1<=0;gm2<=0;gb0<=0;gb1<=0;gb2<=0;rt0<=0;rt1<=0;rt2<=0;rm0<=0;rm1<=0;rm2<=0;rb0<=0;rb1<=0;rb2<=0;
            end
            wx<=(sx==0)?0:sx-1'b1;wy<=(sy==0)?0:sy-1'b1;wde<=sde;whs<=shs;wvs<=svs;
            out_de<=wde;out_hs<=whs;out_vs<=wvs;
            if(!wde||wx<2||wy<2)begin out_class<=0;out_gray<=0;out_rgb<=0;end
            else begin out_class<=classified;out_gray<=gm1;out_rgb<=rm1;end
        end
    end
endmodule

module canny_hysteresis_overlay #(
    parameter integer WIDTH=1920,parameter integer X_BITS=11,parameter integer Y_BITS=11
)(
    input wire clk,input wire rst_n,input wire [1:0] in_class,input wire [7:0] in_gray,input wire [23:0] in_rgb,
    input wire in_de,input wire in_hs,input wire in_vs,
    output reg [7:0] out_r,output reg [7:0] out_g,output reg [7:0] out_b,
    output reg out_de,output reg out_hs,output reg out_vs
);
    reg [1:0] co[0:WIDTH-1],cn[0:WIDTH-1];reg [7:0] go[0:WIDTH-1],gn[0:WIDTH-1];reg [23:0] ro[0:WIDTH-1],rn[0:WIDTH-1];
    reg [X_BITS-1:0] x;reg [Y_BITS-1:0] y;reg de_d,vs_d;reg [1:0] st,sm,sb;reg [7:0] sgt,sgm,sgb;reg [23:0] srt,srm,srb;
    reg [X_BITS-1:0] sx;reg [Y_BITS-1:0] sy;reg sde,shs,svs;
    reg [1:0] t0,t1,t2,m0,m1,m2,b0,b1,b2;reg [7:0] gt0,gt1,gt2,gm0,gm1,gm2,gb0,gb1,gb2;
    reg [23:0] rt0,rt1,rt2,rm0,rm1,rm2,rb0,rb1,rb2;reg [X_BITS-1:0] wx;reg [Y_BITS-1:0] wy;reg wde,whs,wvs;
    wire neighbor_strong=(t0==2)||(t1==2)||(t2==2)||(m0==2)||(m2==2)||(b0==2)||(b1==2)||(b2==2);
    wire keep_edge=(m1==2)||((m1==1)&&neighbor_strong);
    always @(posedge clk)begin
        if(!rst_n)begin
            x<=0;y<=0;de_d<=0;vs_d<=0;st<=0;sm<=0;sb<=0;sgt<=0;sgm<=0;sgb<=0;srt<=0;srm<=0;srb<=0;sx<=0;sy<=0;sde<=0;shs<=0;svs<=0;
            t0<=0;t1<=0;t2<=0;m0<=0;m1<=0;m2<=0;b0<=0;b1<=0;b2<=0;gt0<=0;gt1<=0;gt2<=0;gm0<=0;gm1<=0;gm2<=0;gb0<=0;gb1<=0;gb2<=0;
            rt0<=0;rt1<=0;rt2<=0;rm0<=0;rm1<=0;rm2<=0;rb0<=0;rb1<=0;rb2<=0;wx<=0;wy<=0;wde<=0;whs<=0;wvs<=0;
            out_r<=0;out_g<=0;out_b<=0;out_de<=0;out_hs<=0;out_vs<=0;
        end else begin
            de_d<=in_de;vs_d<=in_vs;if(in_de)x<=x+1'b1;else x<=0;if(in_vs&&!vs_d)y<=0;else if(de_d&&!in_de)y<=y+1'b1;
            if(in_de&&x<WIDTH)begin st<=co[x];sm<=cn[x];sb<=in_class;sgt<=go[x];sgm<=gn[x];sgb<=in_gray;srt<=ro[x];srm<=rn[x];srb<=in_rgb;co[x]<=cn[x];cn[x]<=in_class;go[x]<=gn[x];gn[x]<=in_gray;ro[x]<=rn[x];rn[x]<=in_rgb;end
            else begin st<=0;sm<=0;sb<=0;sgt<=0;sgm<=0;sgb<=0;srt<=0;srm<=0;srb<=0;end
            sx<=x;sy<=y;sde<=in_de;shs<=in_hs;svs<=in_vs;
            if(sde)begin t0<=t1;t1<=t2;t2<=st;m0<=m1;m1<=m2;m2<=sm;b0<=b1;b1<=b2;b2<=sb;gt0<=gt1;gt1<=gt2;gt2<=sgt;gm0<=gm1;gm1<=gm2;gm2<=sgm;gb0<=gb1;gb1<=gb2;gb2<=sgb;rt0<=rt1;rt1<=rt2;rt2<=srt;rm0<=rm1;rm1<=rm2;rm2<=srm;rb0<=rb1;rb1<=rb2;rb2<=srb;end
            else begin t0<=0;t1<=0;t2<=0;m0<=0;m1<=0;m2<=0;b0<=0;b1<=0;b2<=0;gt0<=0;gt1<=0;gt2<=0;gm0<=0;gm1<=0;gm2<=0;gb0<=0;gb1<=0;gb2<=0;rt0<=0;rt1<=0;rt2<=0;rm0<=0;rm1<=0;rm2<=0;rb0<=0;rb1<=0;rb2<=0;end
            wx<=(sx==0)?0:sx-1'b1;wy<=(sy==0)?0:sy-1'b1;wde<=sde;whs<=shs;wvs<=svs;
            out_de<=wde;out_hs<=whs;out_vs<=wvs;
            if(!wde||wx<2||wy<2)begin out_r<=0;out_g<=0;out_b<=0;end
            else if(wx<WIDTH/2)begin out_r<=gm1;out_g<=gm1;out_b<=gm1;end
            else if(keep_edge)begin out_r<=8'hff;out_g<=0;out_b<=0;end
            else begin out_r<=rm1[23:16];out_g<=rm1[15:8];out_b<=rm1[7:0];end
        end
    end
endmodule
