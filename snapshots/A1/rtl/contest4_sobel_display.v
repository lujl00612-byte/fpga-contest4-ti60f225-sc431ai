// Contest 4 advanced A1: exact 3x3 median network, Sobel and red edge overlay.
module contest4_sobel_display #(
    parameter integer WIDTH = 1920,
    parameter integer X_BITS = 11,
    parameter integer Y_BITS = 11
) (
    input wire clk, input wire rst_n,
    input wire [7:0] in_r, input wire [7:0] in_g, input wire [7:0] in_b,
    input wire in_de, input wire in_hs, input wire in_vs,
    input wire [10:0] threshold_i,
    output wire [7:0] out_r, output wire [7:0] out_g, output wire [7:0] out_b,
    output wire out_de, output wire out_hs, output wire out_vs
);
    wire [7:0] median_gray;
    wire [23:0] median_rgb;
    wire median_de, median_hs, median_vs;

    median3x3_rgb #(.WIDTH(WIDTH), .X_BITS(X_BITS), .Y_BITS(Y_BITS)) u_median (
        .clk(clk), .rst_n(rst_n), .in_r(in_r), .in_g(in_g), .in_b(in_b),
        .in_de(in_de), .in_hs(in_hs), .in_vs(in_vs),
        .out_gray(median_gray), .out_rgb(median_rgb),
        .out_de(median_de), .out_hs(median_hs), .out_vs(median_vs)
    );

    sobel_color_overlay #(.WIDTH(WIDTH), .X_BITS(X_BITS), .Y_BITS(Y_BITS)) u_sobel (
        .clk(clk), .rst_n(rst_n), .in_gray(median_gray), .in_rgb(median_rgb),
        .in_de(median_de), .in_hs(median_hs), .in_vs(median_vs),
        .threshold_i(threshold_i), .out_r(out_r), .out_g(out_g), .out_b(out_b),
        .out_de(out_de), .out_hs(out_hs), .out_vs(out_vs)
    );
endmodule

module median3x3_rgb #(
    parameter integer WIDTH = 1920,
    parameter integer X_BITS = 11,
    parameter integer Y_BITS = 11
) (
    input wire clk, input wire rst_n,
    input wire [7:0] in_r, input wire [7:0] in_g, input wire [7:0] in_b,
    input wire in_de, input wire in_hs, input wire in_vs,
    output reg [7:0] out_gray, output reg [23:0] out_rgb,
    output reg out_de, output reg out_hs, output reg out_vs
);
    function [7:0] min3;
        input [7:0] a, b, c;
        reg [7:0] ab;
        begin ab = (a < b) ? a : b; min3 = (ab < c) ? ab : c; end
    endfunction
    function [7:0] max3;
        input [7:0] a, b, c;
        reg [7:0] ab;
        begin ab = (a > b) ? a : b; max3 = (ab > c) ? ab : c; end
    endfunction
    function [7:0] med3;
        input [7:0] a, b, c;
        reg [7:0] lo, hi;
        begin
            lo = (a < b) ? a : b;
            hi = (a > b) ? a : b;
            med3 = (c < lo) ? lo : ((c > hi) ? hi : c);
        end
    endfunction

    // 77/256 R + 150/256 G + 29/256 B, implemented by constants and a shift.
    wire [15:0] gray_sum = in_r * 8'd77 + in_g * 8'd150 + in_b * 8'd29;
    wire [7:0] gray = gray_sum[15:8];
    wire [23:0] rgb = {in_r,in_g,in_b};

    reg [7:0] gray_old [0:WIDTH-1];
    reg [7:0] gray_new [0:WIDTH-1];
    reg [23:0] rgb_old [0:WIDTH-1];
    reg [23:0] rgb_new [0:WIDTH-1];
    reg [X_BITS-1:0] x; reg [Y_BITS-1:0] y;
    reg de_d, vs_d;
    reg [7:0] s1_top, s1_mid, s1_bot;
    reg [23:0] s1_rgb_top, s1_rgb_mid, s1_rgb_bot;
    reg [X_BITS-1:0] s1_x; reg [Y_BITS-1:0] s1_y;
    reg s1_de, s1_hs, s1_vs;

    reg [7:0] t0,t1,t2,m0,m1,m2,b0,b1,b2;
    reg [23:0] rt0,rt1,rt2,rm0,rm1,rm2,rb0,rb1,rb2;
    reg [X_BITS-1:0] win_x; reg [Y_BITS-1:0] win_y;
    reg win_de, win_hs, win_vs;

    wire [7:0] row0_min = min3(t0,t1,t2);
    wire [7:0] row0_mid = med3(t0,t1,t2);
    wire [7:0] row0_max = max3(t0,t1,t2);
    wire [7:0] row1_min = min3(m0,m1,m2);
    wire [7:0] row1_mid = med3(m0,m1,m2);
    wire [7:0] row1_max = max3(m0,m1,m2);
    wire [7:0] row2_min = min3(b0,b1,b2);
    wire [7:0] row2_mid = med3(b0,b1,b2);
    wire [7:0] row2_max = max3(b0,b1,b2);

    reg [7:0] q0min,q0mid,q0max,q1min,q1mid,q1max,q2min,q2mid,q2max;
    reg [23:0] sort_rgb;
    reg [X_BITS-1:0] sort_x; reg [Y_BITS-1:0] sort_y;
    reg sort_de, sort_hs, sort_vs;
    wire [7:0] lower_candidate = max3(q0min,q1min,q2min);
    wire [7:0] middle_candidate = med3(q0mid,q1mid,q2mid);
    wire [7:0] upper_candidate = min3(q0max,q1max,q2max);
    wire [7:0] median9 = med3(lower_candidate,middle_candidate,upper_candidate);

    always @(posedge clk) begin
        if (!rst_n) begin
            x<=0; y<=0; de_d<=0; vs_d<=0;
            s1_top<=0; s1_mid<=0; s1_bot<=0;
            s1_rgb_top<=0; s1_rgb_mid<=0; s1_rgb_bot<=0;
            s1_x<=0; s1_y<=0; s1_de<=0; s1_hs<=0; s1_vs<=0;
            t0<=0; t1<=0; t2<=0; m0<=0; m1<=0; m2<=0; b0<=0; b1<=0; b2<=0;
            rt0<=0; rt1<=0; rt2<=0; rm0<=0; rm1<=0; rm2<=0; rb0<=0; rb1<=0; rb2<=0;
            win_x<=0; win_y<=0; win_de<=0; win_hs<=0; win_vs<=0;
            q0min<=0; q0mid<=0; q0max<=0; q1min<=0; q1mid<=0; q1max<=0;
            q2min<=0; q2mid<=0; q2max<=0; sort_rgb<=0;
            sort_x<=0; sort_y<=0; sort_de<=0; sort_hs<=0; sort_vs<=0;
            out_gray<=0; out_rgb<=0; out_de<=0; out_hs<=0; out_vs<=0;
        end else begin
            de_d <= in_de; vs_d <= in_vs;
            if (in_de) x <= x + 1'b1; else x <= 0;
            if (in_vs && !vs_d) y <= 0;
            else if (de_d && !in_de) y <= y + 1'b1;

            if (in_de && x < WIDTH) begin
                s1_top <= gray_old[x]; s1_mid <= gray_new[x]; s1_bot <= gray;
                s1_rgb_top <= rgb_old[x]; s1_rgb_mid <= rgb_new[x]; s1_rgb_bot <= rgb;
                gray_old[x] <= gray_new[x]; gray_new[x] <= gray;
                rgb_old[x] <= rgb_new[x]; rgb_new[x] <= rgb;
            end else begin
                s1_top<=0; s1_mid<=0; s1_bot<=0;
                s1_rgb_top<=0; s1_rgb_mid<=0; s1_rgb_bot<=0;
            end
            s1_x<=x; s1_y<=y; s1_de<=in_de; s1_hs<=in_hs; s1_vs<=in_vs;

            if (s1_de) begin
                t0<=t1; t1<=t2; t2<=s1_top;
                m0<=m1; m1<=m2; m2<=s1_mid;
                b0<=b1; b1<=b2; b2<=s1_bot;
                rt0<=rt1; rt1<=rt2; rt2<=s1_rgb_top;
                rm0<=rm1; rm1<=rm2; rm2<=s1_rgb_mid;
                rb0<=rb1; rb1<=rb2; rb2<=s1_rgb_bot;
            end else begin
                t0<=0; t1<=0; t2<=0; m0<=0; m1<=0; m2<=0; b0<=0; b1<=0; b2<=0;
                rt0<=0; rt1<=0; rt2<=0; rm0<=0; rm1<=0; rm2<=0; rb0<=0; rb1<=0; rb2<=0;
            end
            win_x <= (s1_x == 0) ? 0 : s1_x - 1'b1;
            win_y <= (s1_y == 0) ? 0 : s1_y - 1'b1;
            win_de<=s1_de; win_hs<=s1_hs; win_vs<=s1_vs;

            q0min<=row0_min; q0mid<=row0_mid; q0max<=row0_max;
            q1min<=row1_min; q1mid<=row1_mid; q1max<=row1_max;
            q2min<=row2_min; q2mid<=row2_mid; q2max<=row2_max;
            sort_rgb<=rm1;
            sort_x<=win_x; sort_y<=win_y; sort_de<=win_de; sort_hs<=win_hs; sort_vs<=win_vs;

            out_de<=sort_de; out_hs<=sort_hs; out_vs<=sort_vs;
            if (!sort_de || sort_x < 2 || sort_y < 2) begin
                out_gray<=0; out_rgb<=0;
            end else begin
                out_gray<=median9; out_rgb<=sort_rgb;
            end
        end
    end
endmodule

module sobel_color_overlay #(
    parameter integer WIDTH = 1920,
    parameter integer X_BITS = 11,
    parameter integer Y_BITS = 11
) (
    input wire clk, input wire rst_n,
    input wire [7:0] in_gray, input wire [23:0] in_rgb,
    input wire in_de, input wire in_hs, input wire in_vs,
    input wire [10:0] threshold_i,
    output reg [7:0] out_r, output reg [7:0] out_g, output reg [7:0] out_b,
    output reg out_de, output reg out_hs, output reg out_vs
);
    reg [7:0] gray_old [0:WIDTH-1];
    reg [7:0] gray_new [0:WIDTH-1];
    reg [23:0] rgb_old [0:WIDTH-1];
    reg [23:0] rgb_new [0:WIDTH-1];
    reg [X_BITS-1:0] x; reg [Y_BITS-1:0] y;
    reg de_d, vs_d;
    reg [7:0] s1_top,s1_mid,s1_bot;
    reg [23:0] s1_rgb_top,s1_rgb_mid,s1_rgb_bot;
    reg [X_BITS-1:0] s1_x; reg [Y_BITS-1:0] s1_y;
    reg s1_de,s1_hs,s1_vs;
    reg [7:0] t0,t1,t2,m0,m1,m2,b0,b1,b2;
    reg [23:0] rt0,rt1,rt2,rm0,rm1,rm2,rb0,rb1,rb2;
    reg [X_BITS-1:0] win_x; reg [Y_BITS-1:0] win_y;
    reg win_de,win_hs,win_vs;

    wire signed [11:0] gx_wire =
        $signed({4'd0,t2}) + ($signed({4'd0,m2}) <<< 1) + $signed({4'd0,b2})
      - $signed({4'd0,t0}) - ($signed({4'd0,m0}) <<< 1) - $signed({4'd0,b0});
    wire signed [11:0] gy_wire =
        $signed({4'd0,b0}) + ($signed({4'd0,b1}) <<< 1) + $signed({4'd0,b2})
      - $signed({4'd0,t0}) - ($signed({4'd0,t1}) <<< 1) - $signed({4'd0,t2});
    reg signed [11:0] grad_x,grad_y;
    reg [7:0] grad_gray;
    reg [23:0] grad_rgb;
    reg [X_BITS-1:0] grad_xpos; reg [Y_BITS-1:0] grad_ypos;
    reg grad_de,grad_hs,grad_vs;
    wire [11:0] abs_x = grad_x[11] ? -grad_x : grad_x;
    wire [11:0] abs_y = grad_y[11] ? -grad_y : grad_y;
    wire [11:0] max_abs = (abs_x >= abs_y) ? abs_x : abs_y;
    wire [11:0] min_abs = (abs_x >= abs_y) ? abs_y : abs_x;
    wire [12:0] magnitude = {1'b0,max_abs} + {2'b0,min_abs[11:1]};
    reg [15:0] noise_acc;
    wire [7:0] noise_floor = noise_acc[15:8];
    wire [7:0] noise_sample = (magnitude > 13'd255) ? 8'hff : magnitude[7:0];
    wire [12:0] threshold_sum = {2'b0,threshold_i} + {6'b0,noise_floor[7:1]};
    wire [10:0] adaptive_threshold = (threshold_sum > 13'd2047) ? 11'd2047 : threshold_sum[10:0];
    wire edge_on = magnitude >= {2'b0,adaptive_threshold};

    always @(posedge clk) begin
        if (!rst_n) begin
            x<=0; y<=0; de_d<=0; vs_d<=0;
            s1_top<=0; s1_mid<=0; s1_bot<=0; s1_rgb_top<=0; s1_rgb_mid<=0; s1_rgb_bot<=0;
            s1_x<=0; s1_y<=0; s1_de<=0; s1_hs<=0; s1_vs<=0;
            t0<=0; t1<=0; t2<=0; m0<=0; m1<=0; m2<=0; b0<=0; b1<=0; b2<=0;
            rt0<=0; rt1<=0; rt2<=0; rm0<=0; rm1<=0; rm2<=0; rb0<=0; rb1<=0; rb2<=0;
            win_x<=0; win_y<=0; win_de<=0; win_hs<=0; win_vs<=0;
            grad_x<=0; grad_y<=0; grad_gray<=0; grad_rgb<=0;
            grad_xpos<=0; grad_ypos<=0; grad_de<=0; grad_hs<=0; grad_vs<=0;
            noise_acc<=0; out_r<=0; out_g<=0; out_b<=0;
            out_de<=0; out_hs<=0; out_vs<=0;
        end else begin
            de_d<=in_de; vs_d<=in_vs;
            if (in_de) x<=x+1'b1; else x<=0;
            if (in_vs && !vs_d) y<=0; else if (de_d && !in_de) y<=y+1'b1;
            if (in_de && x < WIDTH) begin
                s1_top<=gray_old[x]; s1_mid<=gray_new[x]; s1_bot<=in_gray;
                s1_rgb_top<=rgb_old[x]; s1_rgb_mid<=rgb_new[x]; s1_rgb_bot<=in_rgb;
                gray_old[x]<=gray_new[x]; gray_new[x]<=in_gray;
                rgb_old[x]<=rgb_new[x]; rgb_new[x]<=in_rgb;
            end else begin
                s1_top<=0; s1_mid<=0; s1_bot<=0; s1_rgb_top<=0; s1_rgb_mid<=0; s1_rgb_bot<=0;
            end
            s1_x<=x; s1_y<=y; s1_de<=in_de; s1_hs<=in_hs; s1_vs<=in_vs;
            if (s1_de) begin
                t0<=t1; t1<=t2; t2<=s1_top; m0<=m1; m1<=m2; m2<=s1_mid; b0<=b1; b1<=b2; b2<=s1_bot;
                rt0<=rt1; rt1<=rt2; rt2<=s1_rgb_top; rm0<=rm1; rm1<=rm2; rm2<=s1_rgb_mid;
                rb0<=rb1; rb1<=rb2; rb2<=s1_rgb_bot;
            end else begin
                t0<=0; t1<=0; t2<=0; m0<=0; m1<=0; m2<=0; b0<=0; b1<=0; b2<=0;
                rt0<=0; rt1<=0; rt2<=0; rm0<=0; rm1<=0; rm2<=0; rb0<=0; rb1<=0; rb2<=0;
            end
            win_x<=(s1_x==0)?0:s1_x-1'b1; win_y<=(s1_y==0)?0:s1_y-1'b1;
            win_de<=s1_de; win_hs<=s1_hs; win_vs<=s1_vs;
            grad_x<=gx_wire; grad_y<=gy_wire; grad_gray<=m1; grad_rgb<=rm1;
            grad_xpos<=win_x; grad_ypos<=win_y; grad_de<=win_de; grad_hs<=win_hs; grad_vs<=win_vs;
            if (grad_de && grad_xpos>=2 && grad_ypos>=2)
                noise_acc <= noise_acc - (noise_acc >> 8) + noise_sample;
            out_de<=grad_de; out_hs<=grad_hs; out_vs<=grad_vs;
            if (!grad_de || grad_xpos<2 || grad_ypos<2) begin
                out_r<=0; out_g<=0; out_b<=0;
            end else if (grad_xpos < WIDTH/2) begin
                out_r<=grad_gray; out_g<=grad_gray; out_b<=grad_gray;
            end else if (edge_on) begin
                out_r<=8'hff; out_g<=8'h00; out_b<=8'h00;
            end else begin
                out_r<=grad_rgb[23:16]; out_g<=grad_rgb[15:8]; out_b<=grad_rgb[7:0];
            end
        end
    end
endmodule
