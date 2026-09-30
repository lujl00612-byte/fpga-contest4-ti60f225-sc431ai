// Independent two-pixel RGB888 source for the 3.5 inch DSI diagnostic build.
// No camera, DDR, or white-balance input is used. The carrier PLLs and each
// DSI channel's initialization enable are still required.
module mipi_diagnostic_rgb2 #(
    parameter WIDTH = 1920, HEIGHT = 1080,
    parameter HSP = 4, HBP = 88, HFP = 120,
    parameter VSP = 2, VBP = 20, VFP = 20
) (
    input wire clk, rst_n, enable_i,
    output reg hs_o, vs_o, de_o,
    output reg [63:0] pixels_o,
    output reg [31:0] frame_count_o
);
    localparam H_WORDS = (HSP + HBP + WIDTH + HFP) / 2;
    localparam V_LINES = VSP + VBP + HEIGHT + VFP;
    localparam H_BEGIN = (HSP + HBP) / 2;
    localparam V_BEGIN = VSP + VBP;
    localparam HW = $clog2(H_WORDS);
    localparam VW = $clog2(V_LINES);
    reg [HW-1:0] h_word;
    reg [VW-1:0] v_line;
    wire active = h_word >= H_BEGIN && h_word < H_BEGIN + WIDTH/2 &&
                  v_line >= V_BEGIN && v_line < V_BEGIN + HEIGHT;
    wire [15:0] x0 = (h_word - H_BEGIN) * 2;
    wire [15:0] x1 = x0 + 16'd1;
    wire [15:0] y = v_line - V_BEGIN;

    // All divisions are elaboration constants. Bars have non-overlapping
    // floor(WIDTH*n/8) boundaries; adjacent pixels can straddle a boundary.
    function [23:0] rgb_at;
        input [15:0] px, py;
        begin
            if (px == 0 || px == WIDTH-1 || py == 0 || py == HEIGHT-1)
                rgb_at = 24'hffffff;
            else if (py >= HEIGHT*3/4)
                rgb_at = (px[0] ^ py[3]) ? 24'h0080ff : 24'hff4000;
            else if (px < WIDTH/8)   rgb_at = 24'hffffff;
            else if (px < WIDTH*2/8) rgb_at = 24'hffff00;
            else if (px < WIDTH*3/8) rgb_at = 24'h00ffff;
            else if (px < WIDTH*4/8) rgb_at = 24'h00ff00;
            else if (px < WIDTH*5/8) rgb_at = 24'hff00ff;
            else if (px < WIDTH*6/8) rgb_at = 24'hff0000;
            else if (px < WIDTH*7/8) rgb_at = 24'h0000ff;
            else                    rgb_at = 24'h000000;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            h_word <= 0; v_line <= 0; frame_count_o <= 0;
            hs_o <= 0; vs_o <= 0; de_o <= 0; pixels_o <= 0;
        end else if (!enable_i) begin
            h_word <= 0; v_line <= 0; frame_count_o <= 0;
            hs_o <= 0; vs_o <= 0; de_o <= 0; pixels_o <= 0;
        end else begin
            hs_o <= h_word < HSP/2;
            vs_o <= v_line < VSP;
            de_o <= active;
            // RGB is R[23:16], G[15:8], B[7:0]. Pixel x is the low 24 bits;
            // pixel x+1 is bits [47:24]. The DSI bus's upper 16 bits are zero.
            pixels_o <= active ? {16'd0, rgb_at(x1,y), rgb_at(x0,y)} : 64'd0;
            if (h_word == H_WORDS-1) begin
                h_word <= 0;
                if (v_line == V_LINES-1) begin
                    v_line <= 0;
                    frame_count_o <= frame_count_o + 1'b1;
                end else v_line <= v_line + 1'b1;
            end else h_word <= h_word + 1'b1;
        end
    end
`ifndef SYNTHESIS
    initial begin
        if (WIDTH < 16 || HEIGHT < 16 || WIDTH > 32768 || HEIGHT > 32768 ||
            HSP < 2 || VSP < 1 || H_WORDS < 2 || V_LINES < 2 ||
            (WIDTH % 2) || (HSP % 2) || (HBP % 2) || (HFP % 2))
            $fatal(1, "Invalid two-pixel diagnostic timing parameters");
    end
`endif
endmodule
