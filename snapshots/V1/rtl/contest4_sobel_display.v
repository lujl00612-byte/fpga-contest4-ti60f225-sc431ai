// Grayscale on the left half; binary Sobel edges on the right half.
// Input and output timing are identical apart from four pixel clocks of latency.
module contest4_sobel_display #(
    parameter integer WIDTH = 1920,
    parameter integer X_BITS = 11,
    parameter integer Y_BITS = 11
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] in_r,
    input  wire [7:0] in_g,
    input  wire [7:0] in_b,
    input  wire       in_de,
    input  wire       in_hs,
    input  wire       in_vs,
    input  wire [10:0] threshold_i,
    output reg  [7:0] out_pixel,
    output reg        out_de,
    output reg        out_hs,
    output reg        out_vs
);
    // 77/256 R + 150/256 G + 29/256 B; constants synthesize as shifts/adds.
    wire [15:0] gray_sum = in_r * 8'd77 + in_g * 8'd150 + in_b * 8'd29;
    wire [7:0] gray = gray_sum[15:8];

    reg [7:0] line_old [0:WIDTH-1];
    reg [7:0] line_new [0:WIDTH-1];
    reg [X_BITS-1:0] x;
    reg [Y_BITS-1:0] y;
    reg de_prev, vs_prev;

    reg [7:0] s1_top, s1_mid, s1_gray;
    reg [X_BITS-1:0] s1_x;
    reg [Y_BITS-1:0] s1_y;
    reg s1_de, s1_hs, s1_vs;

    reg [7:0] t0, t1, t2, m0, m1, m2, b0, b1, b2;
    reg [7:0] s2_gray;
    reg [X_BITS-1:0] s2_x;
    reg [Y_BITS-1:0] s2_y;
    reg s2_de, s2_hs, s2_vs;

    wire signed [11:0] gx_wire =
        $signed({4'b0,t2}) + ($signed({4'b0,m2}) <<< 1) + $signed({4'b0,b2})
      - $signed({4'b0,t0}) - ($signed({4'b0,m0}) <<< 1) - $signed({4'b0,b0});
    wire signed [11:0] gy_wire =
        $signed({4'b0,b0}) + ($signed({4'b0,b1}) <<< 1) + $signed({4'b0,b2})
      - $signed({4'b0,t0}) - ($signed({4'b0,t1}) <<< 1) - $signed({4'b0,t2});

    reg signed [11:0] s3_gx, s3_gy;
    reg [7:0] s3_gray;
    reg [X_BITS-1:0] s3_x;
    reg [Y_BITS-1:0] s3_y;
    reg s3_de, s3_hs, s3_vs;
    wire [11:0] abs_gx = s3_gx[11] ? -s3_gx : s3_gx;
    wire [11:0] abs_gy = s3_gy[11] ? -s3_gy : s3_gy;
    wire [12:0] magnitude = {1'b0,abs_gx} + {1'b0,abs_gy};

    always @(posedge clk) begin
        if (!rst_n) begin
            x <= 0; y <= 0; de_prev <= 0; vs_prev <= 0;
            s1_top <= 0; s1_mid <= 0; s1_gray <= 0;
            s1_x <= 0; s1_y <= 0; s1_de <= 0; s1_hs <= 0; s1_vs <= 0;
            t0 <= 0; t1 <= 0; t2 <= 0;
            m0 <= 0; m1 <= 0; m2 <= 0;
            b0 <= 0; b1 <= 0; b2 <= 0;
            s2_gray <= 0; s2_x <= 0; s2_y <= 0;
            s2_de <= 0; s2_hs <= 0; s2_vs <= 0;
            s3_gx <= 0; s3_gy <= 0; s3_gray <= 0;
            s3_x <= 0; s3_y <= 0;
            s3_de <= 0; s3_hs <= 0; s3_vs <= 0;
            out_pixel <= 0; out_de <= 0; out_hs <= 0; out_vs <= 0;
        end else begin
            de_prev <= in_de;
            vs_prev <= in_vs;
            if (in_de) x <= x + 1'b1;
            else       x <= 0;
            if (in_vs && !vs_prev) y <= 0;
            else if (de_prev && !in_de) y <= y + 1'b1;

            // The two reads return the previous two image rows at column x.
            if (in_de && x < WIDTH) begin
                s1_top <= line_old[x];
                s1_mid <= line_new[x];
                line_old[x] <= line_new[x];
                line_new[x] <= gray;
            end else begin
                s1_top <= 0;
                s1_mid <= 0;
            end
            s1_gray <= gray;
            s1_x <= x; s1_y <= y;
            s1_de <= in_de; s1_hs <= in_hs; s1_vs <= in_vs;

            // Advance the 3x3 window once per active input pixel.
            if (s1_de) begin
                t0 <= t1; t1 <= t2; t2 <= s1_top;
                m0 <= m1; m1 <= m2; m2 <= s1_mid;
                b0 <= b1; b1 <= b2; b2 <= s1_gray;
            end else begin
                t0 <= 0; t1 <= 0; t2 <= 0;
                m0 <= 0; m1 <= 0; m2 <= 0;
                b0 <= 0; b1 <= 0; b2 <= 0;
            end
            s2_gray <= s1_gray;
            s2_x <= s1_x; s2_y <= s1_y;
            s2_de <= s1_de; s2_hs <= s1_hs; s2_vs <= s1_vs;

            s3_gx <= gx_wire;
            s3_gy <= gy_wire;
            s3_gray <= s2_gray;
            s3_x <= s2_x; s3_y <= s2_y;
            s3_de <= s2_de; s3_hs <= s2_hs; s3_vs <= s2_vs;

            out_de <= s3_de; out_hs <= s3_hs; out_vs <= s3_vs;
            if (!s3_de) out_pixel <= 0;
            else if (s3_x < WIDTH / 2) out_pixel <= s3_gray;
            else if (s3_x < 2 || s3_y < 2) out_pixel <= 0;
            else out_pixel <= (magnitude >= {2'b0,threshold_i}) ? 8'hff : 8'h00;
        end
    end
endmodule
