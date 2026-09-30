// Streaming dominant-shape detector. It tracks the red Canny edge bounding box,
// distinguishes corner-rich rectangles from rounded objects, and draws the prior-frame box.
module shape_overlay #(
    parameter integer WIDTH=1920,parameter integer X_BITS=11,parameter integer Y_BITS=11,
    parameter integer MIN_SIZE=50,parameter integer MIN_EDGES=100,parameter integer CORNER_MARGIN=12
)(
    input wire clk,input wire rst_n,input wire [7:0] in_r,input wire [7:0] in_g,input wire [7:0] in_b,
    input wire in_de,input wire in_hs,input wire in_vs,
    output reg [7:0] out_r,output reg [7:0] out_g,output reg [7:0] out_b,
    output reg out_de,output reg out_hs,output reg out_vs,output reg [1:0] shape_class
);
    reg [X_BITS-1:0] x;reg [Y_BITS-1:0] y;reg de_d,vs_d;
    reg [X_BITS-1:0] cur_min_x,cur_max_x,box_min_x,box_max_x;
    reg [Y_BITS-1:0] cur_min_y,cur_max_y,box_min_y,box_max_y;
    reg [21:0] cur_edge_count;reg [15:0] corner_hits;reg box_valid;
    reg corner_hit_pending;
    reg [X_BITS:0] width_pipe;
    reg [Y_BITS:0] height_pipe;
    reg width_ok_pipe,height_ok_pipe,edges_ok_pipe,squareish_pipe,corners_pipe;
    wire edge_pixel=in_de&&(x>=WIDTH/2)&&(in_r>=8'd224)&&(in_g<=8'd32)&&(in_b<=8'd32);
    wire [X_BITS:0] cur_width={1'b0,cur_max_x}-{1'b0,cur_min_x}+1'b1;
    wire [Y_BITS:0] cur_height={1'b0,cur_max_y}-{1'b0,cur_min_y}+1'b1;
    wire squareish=(({2'b0,width_pipe}<<2)>=(({2'b0,height_pipe}<<1)+{2'b0,height_pipe}))&&
                    (({2'b0,height_pipe}<<2)>=(({2'b0,width_pipe}<<1)+{2'b0,width_pipe}));
    wire near_left=(x>=box_min_x)&&(x<=box_min_x+CORNER_MARGIN);
    wire near_right=(x<=box_max_x)&&(x+CORNER_MARGIN>=box_max_x);
    wire near_top=(y>=box_min_y)&&(y<=box_min_y+CORNER_MARGIN);
    wire near_bottom=(y<=box_max_y)&&(y+CORNER_MARGIN>=box_max_y);
    wire in_corner=(near_left||near_right)&&(near_top||near_bottom);
    wire on_top=(y>=box_min_y)&&(y<=box_min_y+2);
    wire on_bottom=(y<=box_max_y)&&(y+2>=box_max_y);
    wire on_left=(x>=box_min_x)&&(x<=box_min_x+2);
    wire on_right=(x<=box_max_x)&&(x+2>=box_max_x);
    wire on_box=box_valid&&in_de&&((((on_top||on_bottom)&&(x>=box_min_x)&&(x<=box_max_x)))||
                (((on_left||on_right)&&(y>=box_min_y)&&(y<=box_max_y))));
    always @(posedge clk)begin
        if(!rst_n)begin
            x<=0;y<=0;de_d<=0;vs_d<=0;cur_min_x<={X_BITS{1'b1}};cur_max_x<=0;cur_min_y<={Y_BITS{1'b1}};cur_max_y<=0;
            box_min_x<=0;box_max_x<=0;box_min_y<=0;box_max_y<=0;cur_edge_count<=0;corner_hits<=0;box_valid<=0;shape_class<=0;
            corner_hit_pending<=0;
            width_pipe<=0;height_pipe<=0;width_ok_pipe<=0;height_ok_pipe<=0;edges_ok_pipe<=0;squareish_pipe<=0;corners_pipe<=0;
            out_r<=0;out_g<=0;out_b<=0;out_de<=0;out_hs<=0;out_vs<=0;
        end else begin
            // Frame blanking gives these summaries time to settle before the next VS edge.
            width_pipe<=cur_width;height_pipe<=cur_height;
            width_ok_pipe<=width_pipe>=MIN_SIZE;height_ok_pipe<=height_pipe>=MIN_SIZE;
            edges_ok_pipe<=cur_edge_count>=MIN_EDGES;
            squareish_pipe<=squareish;corners_pipe<=corner_hits>=16;
            corner_hit_pending<=edge_pixel&&box_valid&&in_corner;
            vs_d<=in_vs;de_d<=in_de;if(in_de)x<=x+1'b1;else x<=0;
            if(in_vs&&!vs_d)y<=0;else if(de_d&&!in_de)y<=y+1'b1;
            if(in_vs&&!vs_d)begin
                if(edges_ok_pipe&&width_ok_pipe&&height_ok_pipe)begin
                    box_min_x<=cur_min_x;box_max_x<=cur_max_x;box_min_y<=cur_min_y;box_max_y<=cur_max_y;box_valid<=1;
                    if(corners_pipe)shape_class<=2'd2;
                    else if(squareish_pipe)shape_class<=2'd1;
                    else shape_class<=2'd2;
                end else begin box_valid<=0;shape_class<=0;end
                cur_min_x<={X_BITS{1'b1}};cur_max_x<=0;cur_min_y<={Y_BITS{1'b1}};cur_max_y<=0;cur_edge_count<=0;corner_hits<=0;
            end else if(edge_pixel)begin
                if(cur_edge_count==0)begin cur_min_x<=x;cur_max_x<=x;cur_min_y<=y;cur_max_y<=y;end
                else begin
                    if(x<cur_min_x)cur_min_x<=x;if(x>cur_max_x)cur_max_x<=x;
                    if(y<cur_min_y)cur_min_y<=y;if(y>cur_max_y)cur_max_y<=y;
                end
                cur_edge_count<=cur_edge_count+1'b1;
            end
            if(!(in_vs&&!vs_d)&&corner_hit_pending&&corner_hits!=16'hffff)
                corner_hits<=corner_hits+1'b1;
            out_de<=in_de;out_hs<=in_hs;out_vs<=in_vs;
            if(!in_de)begin out_r<=0;out_g<=0;out_b<=0;end
            else if(on_box)begin
                case(shape_class)
                    2'd1:begin out_r<=0;out_g<=8'h60;out_b<=8'hff;end
                    2'd2:begin out_r<=0;out_g<=8'hff;out_b<=8'h40;end
                    default:begin out_r<=8'hff;out_g<=8'hd0;out_b<=0;end
                endcase
            end else begin out_r<=in_r;out_g<=in_g;out_b<=in_b;end
        end
    end
endmodule

