// Contest 4 V2: RGB grayscale, 3x3 Gaussian denoise, 3x3 Sobel and split HDMI.
module contest4_sobel_display #(
    parameter integer WIDTH = 1920,
    parameter integer X_BITS = 11,
    parameter integer Y_BITS = 11
) (
    input wire clk, input wire rst_n,
    input wire [7:0] in_r, input wire [7:0] in_g, input wire [7:0] in_b,
    input wire in_de, input wire in_hs, input wire in_vs,
    input wire [10:0] threshold_i,
    output wire [7:0] out_pixel,
    output wire out_de, output wire out_hs, output wire out_vs
);
    wire [7:0] smooth_gray;
    wire smooth_de, smooth_hs, smooth_vs;

    gaussian3x3_rgb #(.WIDTH(WIDTH), .X_BITS(X_BITS), .Y_BITS(Y_BITS)) u_gaussian (
        .clk(clk), .rst_n(rst_n), .in_r(in_r), .in_g(in_g), .in_b(in_b),
        .in_de(in_de), .in_hs(in_hs), .in_vs(in_vs),
        .out_gray(smooth_gray), .out_de(smooth_de),
        .out_hs(smooth_hs), .out_vs(smooth_vs)
    );
    sobel_gray_split #(.WIDTH(WIDTH), .X_BITS(X_BITS), .Y_BITS(Y_BITS)) u_sobel (
        .clk(clk), .rst_n(rst_n), .in_gray(smooth_gray),
        .in_de(smooth_de), .in_hs(smooth_hs), .in_vs(smooth_vs),
        .threshold_i(threshold_i), .out_pixel(out_pixel),
        .out_de(out_de), .out_hs(out_hs), .out_vs(out_vs)
    );
endmodule

module gaussian3x3_rgb #(
    parameter integer WIDTH = 1920,
    parameter integer X_BITS = 11,
    parameter integer Y_BITS = 11
) (
    input wire clk, input wire rst_n,
    input wire [7:0] in_r, input wire [7:0] in_g, input wire [7:0] in_b,
    input wire in_de, input wire in_hs, input wire in_vs,
    output reg [7:0] out_gray,
    output reg out_de, output reg out_hs, output reg out_vs
);
    // 77/256 R + 150/256 G + 29/256 B. No divider is inferred.
    wire [15:0] gray_sum = in_r * 8'd77 + in_g * 8'd150 + in_b * 8'd29;
    wire [7:0] gray = gray_sum[15:8];
    reg [7:0] line_old [0:WIDTH-1];
    reg [7:0] line_new [0:WIDTH-1];
    reg [X_BITS-1:0] x; reg [Y_BITS-1:0] y;
    reg de_d, vs_d;
    reg [7:0] s1_top, s1_mid, s1_bot;
    reg [X_BITS-1:0] s1_x; reg [Y_BITS-1:0] s1_y;
    reg s1_de, s1_hs, s1_vs;
    reg [7:0] t0, t1, t2, m0, m1, m2, b0, b1, b2;
    reg [X_BITS-1:0] win_x; reg [Y_BITS-1:0] win_y;
    reg win_de, win_hs, win_vs;
    wire [11:0] gauss_sum =
        {4'd0,t0} + {3'd0,t1,1'b0} + {4'd0,t2}
      + {3'd0,m0,1'b0} + {2'd0,m1,2'b0} + {3'd0,m2,1'b0}
      + {4'd0,b0} + {3'd0,b1,1'b0} + {4'd0,b2};

    always @(posedge clk) begin
        if (!rst_n) begin
            x <= 0; y <= 0; de_d <= 0; vs_d <= 0;
            s1_top <= 0; s1_mid <= 0; s1_bot <= 0;
            s1_x <= 0; s1_y <= 0; s1_de <= 0; s1_hs <= 0; s1_vs <= 0;
            t0 <= 0; t1 <= 0; t2 <= 0; m0 <= 0; m1 <= 0; m2 <= 0;
            b0 <= 0; b1 <= 0; b2 <= 0;
            win_x <= 0; win_y <= 0; win_de <= 0; win_hs <= 0; win_vs <= 0;
            out_gray <= 0; out_de <= 0; out_hs <= 0; out_vs <= 0;
        end else begin
            de_d <= in_de; vs_d <= in_vs;
            if (in_de) x <= x + 1'b1; else x <= 0;
            if (in_vs && !vs_d) y <= 0;
            else if (de_d && !in_de) y <= y + 1'b1;
            if (in_de && x < WIDTH) begin
                s1_top <= line_old[x]; s1_mid <= line_new[x]; s1_bot <= gray;
                line_old[x] <= line_new[x]; line_new[x] <= gray;
            end else begin
                s1_top <= 0; s1_mid <= 0; s1_bot <= 0;
            end
            s1_x <= x; s1_y <= y;
            s1_de <= in_de; s1_hs <= in_hs; s1_vs <= in_vs;
            if (s1_de) begin
                t0 <= t1; t1 <= t2; t2 <= s1_top;
                m0 <= m1; m1 <= m2; m2 <= s1_mid;
                b0 <= b1; b1 <= b2; b2 <= s1_bot;
            end else begin
                t0 <= 0; t1 <= 0; t2 <= 0; m0 <= 0; m1 <= 0; m2 <= 0;
                b0 <= 0; b1 <= 0; b2 <= 0;
            end
            win_x <= (s1_x == 0) ? 0 : s1_x - 1'b1;
            win_y <= (s1_y == 0) ? 0 : s1_y - 1'b1;
            win_de <= s1_de; win_hs <= s1_hs; win_vs <= s1_vs;
            out_de <= win_de; out_hs <= win_hs; out_vs <= win_vs;
            if (!win_de || win_x < 2 || win_y < 2) out_gray <= 8'd0;
            else out_gray <= gauss_sum[11:4];
        end
    end
endmodule

module sobel_gray_split #(
    parameter integer WIDTH = 1920,
    parameter integer X_BITS = 11,
    parameter integer Y_BITS = 11
) (
    input wire clk, input wire rst_n, input wire [7:0] in_gray,
    input wire in_de, input wire in_hs, input wire in_vs,
    input wire [10:0] threshold_i,
    output reg [7:0] out_pixel,
    output reg out_de, output reg out_hs, output reg out_vs
);
    reg [7:0] line_old [0:WIDTH-1];
    reg [7:0] line_new [0:WIDTH-1];
    reg [X_BITS-1:0] x; reg [Y_BITS-1:0] y;
    reg de_d, vs_d;
    reg [7:0] s1_top, s1_mid, s1_bot;
    reg [X_BITS-1:0] s1_x; reg [Y_BITS-1:0] s1_y;
    reg s1_de, s1_hs, s1_vs;
    reg [7:0] t0, t1, t2, m0, m1, m2, b0, b1, b2;
    reg [X_BITS-1:0] win_x; reg [Y_BITS-1:0] win_y;
    reg win_de, win_hs, win_vs;
    wire signed [11:0] gx_wire =
        $signed({4'd0,t2}) + ($signed({4'd0,m2}) <<< 1) + $signed({4'd0,b2})
      - $signed({4'd0,t0}) - ($signed({4'd0,m0}) <<< 1) - $signed({4'd0,b0});
    wire signed [11:0] gy_wire =
        $signed({4'd0,b0}) + ($signed({4'd0,b1}) <<< 1) + $signed({4'd0,b2})
      - $signed({4'd0,t0}) - ($signed({4'd0,t1}) <<< 1) - $signed({4'd0,t2});
    reg signed [11:0] grad_x, grad_y;
    reg [7:0] grad_gray;
    reg [X_BITS-1:0] grad_xpos; reg [Y_BITS-1:0] grad_ypos;
    reg grad_de, grad_hs, grad_vs;
    wire [11:0] abs_x = grad_x[11] ? -grad_x : grad_x;
    wire [11:0] abs_y = grad_y[11] ? -grad_y : grad_y;
    wire [12:0] magnitude = {1'b0,abs_x} + {1'b0,abs_y};

    always @(posedge clk) begin
        if (!rst_n) begin
            x <= 0; y <= 0; de_d <= 0; vs_d <= 0;
            s1_top <= 0; s1_mid <= 0; s1_bot <= 0;
            s1_x <= 0; s1_y <= 0; s1_de <= 0; s1_hs <= 0; s1_vs <= 0;
            t0 <= 0; t1 <= 0; t2 <= 0; m0 <= 0; m1 <= 0; m2 <= 0;
            b0 <= 0; b1 <= 0; b2 <= 0;
            win_x <= 0; win_y <= 0; win_de <= 0; win_hs <= 0; win_vs <= 0;
            grad_x <= 0; grad_y <= 0; grad_gray <= 0;
            grad_xpos <= 0; grad_ypos <= 0;
            grad_de <= 0; grad_hs <= 0; grad_vs <= 0;
            out_pixel <= 0; out_de <= 0; out_hs <= 0; out_vs <= 0;
        end else begin
            de_d <= in_de; vs_d <= in_vs;
            if (in_de) x <= x + 1'b1; else x <= 0;
            if (in_vs && !vs_d) y <= 0;
            else if (de_d && !in_de) y <= y + 1'b1;
            if (in_de && x < WIDTH) begin
                s1_top <= line_old[x]; s1_mid <= line_new[x]; s1_bot <= in_gray;
                line_old[x] <= line_new[x]; line_new[x] <= in_gray;
            end else begin
                s1_top <= 0; s1_mid <= 0; s1_bot <= 0;
            end
            s1_x <= x; s1_y <= y;
            s1_de <= in_de; s1_hs <= in_hs; s1_vs <= in_vs;
            if (s1_de) begin
                t0 <= t1; t1 <= t2; t2 <= s1_top;
                m0 <= m1; m1 <= m2; m2 <= s1_mid;
                b0 <= b1; b1 <= b2; b2 <= s1_bot;
            end else begin
                t0 <= 0; t1 <= 0; t2 <= 0; m0 <= 0; m1 <= 0; m2 <= 0;
                b0 <= 0; b1 <= 0; b2 <= 0;
            end
            win_x <= (s1_x == 0) ? 0 : s1_x - 1'b1;
            win_y <= (s1_y == 0) ? 0 : s1_y - 1'b1;
            win_de <= s1_de; win_hs <= s1_hs; win_vs <= s1_vs;
            grad_x <= gx_wire; grad_y <= gy_wire; grad_gray <= m1;
            grad_xpos <= win_x; grad_ypos <= win_y;
            grad_de <= win_de; grad_hs <= win_hs; grad_vs <= win_vs;
            out_de <= grad_de; out_hs <= grad_hs; out_vs <= grad_vs;
            if (!grad_de) out_pixel <= 0;
            else if (grad_xpos < WIDTH/2) out_pixel <= grad_gray;
            else if (grad_xpos < 2 || grad_ypos < 2) out_pixel <= 0;
            else out_pixel <= (magnitude >= {2'b0,threshold_i}) ? 8'hff : 8'h00;
        end
    end
endmodule
