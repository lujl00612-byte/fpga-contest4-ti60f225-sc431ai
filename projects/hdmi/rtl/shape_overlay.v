// Single dominant contour: current-frame top-row span distinguishes flat and rounded tops.
// The resulting box and explicit text are drawn on the following frame.
module shape_overlay #(
    parameter integer WIDTH=1920,parameter integer X_BITS=11,parameter integer Y_BITS=11,
    parameter integer MIN_SIZE=50,parameter integer MIN_EDGES=100,parameter integer CORNER_MARGIN=12
)(
    input wire clk,input wire rst_n,input wire [7:0] in_r,input wire [7:0] in_g,input wire [7:0] in_b,
    input wire basic_i,input wire edge_i,
    input wire in_de,input wire in_hs,input wire in_vs,
    output reg [7:0] out_r,output reg [7:0] out_g,output reg [7:0] out_b,
    output reg out_de,output reg out_hs,output reg out_vs,output reg [1:0] shape_class
);
    reg [X_BITS-1:0] x;reg [Y_BITS-1:0] y;reg de_d,vs_d;
    reg [X_BITS-1:0] cur_min_x,cur_max_x,box_min_x,box_max_x;
    reg [Y_BITS-1:0] cur_min_y,cur_max_y,box_min_y,box_max_y;
    reg [21:0] cur_edge_count;reg box_valid;
    reg [X_BITS-1:0] top_min_x,top_max_x;
    reg [X_BITS:0] width_pipe;
    reg [Y_BITS:0] height_pipe;
    reg width_ok_pipe,height_ok_pipe,edges_ok_pipe,squareish_pipe,flat_top_pipe;
    wire edge_pixel=in_de&&!basic_i&&(x>=WIDTH/2)&&edge_i;
    wire [X_BITS:0] cur_width={1'b0,cur_max_x}-{1'b0,cur_min_x}+1'b1;
    wire [Y_BITS:0] cur_height={1'b0,cur_max_y}-{1'b0,cur_min_y}+1'b1;
    wire squareish=(({2'b0,width_pipe}<<2)>=(({2'b0,height_pipe}<<1)+{2'b0,height_pipe}))&&
                    (({2'b0,height_pipe}<<2)>=(({2'b0,width_pipe}<<1)+{2'b0,width_pipe}));
    wire [X_BITS:0] top_span={1'b0,top_max_x}-{1'b0,top_min_x}+1'b1;
    wire on_top=(y>=box_min_y)&&(y<=box_min_y+2);
    wire on_bottom=(y<=box_max_y)&&(y+2>=box_max_y);
    wire on_left=(x>=box_min_x)&&(x<=box_min_x+2);
    wire on_right=(x<=box_max_x)&&(x+2>=box_max_x);
    wire on_box=box_valid&&in_de&&((((on_top||on_bottom)&&(x>=box_min_x)&&(x<=box_max_x)))||
                (((on_left||on_right)&&(y>=box_min_y)&&(y<=box_max_y))));

    function [7:0] letter;
        input [1:0] kind;input basic;input [3:0] index;
        begin
            letter=8'd32;
            if(basic)begin case(index)0:letter=8'd83;1:letter=8'd79;2:letter=8'd66;3:letter=8'd69;4:letter=8'd76;default:letter=32;endcase end
            else case(kind)
                1:begin case(index)0:letter=8'd67;1:letter=8'd73;2:letter=8'd82;3:letter=8'd67;4:letter=8'd76;5:letter=8'd69;default:letter=32;endcase end
                2:begin case(index)0:letter=8'd82;1:letter=8'd69;2:letter=8'd67;3:letter=8'd84;4:letter=8'd65;5:letter=8'd78;6:letter=8'd71;7:letter=8'd76;8:letter=8'd69;default:letter=32;endcase end
                default:begin case(index)0:letter=8'd85;1:letter=8'd78;2:letter=8'd75;3:letter=8'd78;4:letter=8'd79;5:letter=8'd87;6:letter=8'd78;default:letter=32;endcase end
            endcase
        end
    endfunction
    function [34:0] glyph;
        input [7:0] code;
        begin case(code)
            8'd65:glyph=35'b01110100011000111111100011000110001;
            8'd66:glyph=35'b11110100011000111110100011000111110;
            8'd67:glyph=35'b01111100001000010000100001000001111;
            8'd69:glyph=35'b11111100001000011110100001000011111;
            8'd71:glyph=35'b01111100001000010111100011000101111;
            8'd73:glyph=35'b11111001000010000100001000010011111;
            8'd75:glyph=35'b10001100101010011000101001001010001;
            8'd76:glyph=35'b10000100001000010000100001000011111;
            8'd78:glyph=35'b10001110011100110101100111001110001;
            8'd79:glyph=35'b01110100011000110001100011000101110;
            8'd82:glyph=35'b11110100011000111110101001001010001;
            8'd83:glyph=35'b01111100001000001110000010000111110;
            8'd84:glyph=35'b11111001000010000100001000010000100;
            8'd85:glyph=35'b10001100011000110001100011000101110;
            8'd87:glyph=35'b10001100011000110101101011010101010;
            default:glyph=0;
        endcase end
    endfunction
    wire [X_BITS-1:0] label_x=x-(WIDTH/2+8);
    wire [Y_BITS-1:0] label_y=y-8;
    wire label_region=in_de&&(x>=WIDTH/2+8)&&(x<WIDTH/2+8+108)&&(y>=8)&&(y<22);
    wire [3:0] letter_index=label_x/12;
    wire [3:0] letter_column=(label_x%12)>>1;
    wire [34:0] letter_bits=glyph(letter(shape_class,basic_i,letter_index));
    wire letter_on=label_region&&(letter_column<5)&&letter_bits[34-(label_y>>1)*5-letter_column];

    always @(posedge clk)begin
        if(!rst_n)begin
            x<=0;y<=0;de_d<=0;vs_d<=0;cur_min_x<={X_BITS{1'b1}};cur_max_x<=0;cur_min_y<={Y_BITS{1'b1}};cur_max_y<=0;
            box_min_x<=0;box_max_x<=0;box_min_y<=0;box_max_y<=0;cur_edge_count<=0;box_valid<=0;shape_class<=0;
            top_min_x<=0;top_max_x<=0;
            width_pipe<=0;height_pipe<=0;width_ok_pipe<=0;height_ok_pipe<=0;edges_ok_pipe<=0;squareish_pipe<=0;flat_top_pipe<=0;
            out_r<=0;out_g<=0;out_b<=0;out_de<=0;out_hs<=0;out_vs<=0;
        end else begin
            // Frame blanking gives these summaries time to settle before the next VS edge.
            width_pipe<=cur_width;height_pipe<=cur_height;
            width_ok_pipe<=width_pipe>=MIN_SIZE;height_ok_pipe<=height_pipe>=MIN_SIZE;
            edges_ok_pipe<=cur_edge_count>=MIN_EDGES;
            squareish_pipe<=squareish;
            flat_top_pipe<=(({2'd0,top_span}<<2)>=(({2'd0,cur_width}<<1)+{2'd0,cur_width}));
            vs_d<=in_vs;de_d<=in_de;if(in_de)x<=x+1'b1;else x<=0;
            if(in_vs&&!vs_d)y<=0;else if(de_d&&!in_de)y<=y+1'b1;
            if(in_vs&&!vs_d)begin
                if(edges_ok_pipe&&width_ok_pipe&&height_ok_pipe)begin
                    box_min_x<=cur_min_x;box_max_x<=cur_max_x;box_min_y<=cur_min_y;box_max_y<=cur_max_y;box_valid<=1;
                    if(flat_top_pipe)shape_class<=2'd2;
                    else if(squareish_pipe)shape_class<=2'd1;
                    else shape_class<=2'd0;
                end else begin box_valid<=0;shape_class<=0;end
                cur_min_x<={X_BITS{1'b1}};cur_max_x<=0;cur_min_y<={Y_BITS{1'b1}};cur_max_y<=0;cur_edge_count<=0;
                top_min_x<=0;top_max_x<=0;
            end else if(edge_pixel)begin
                if(cur_edge_count==0)begin
                    cur_min_x<=x;cur_max_x<=x;cur_min_y<=y;cur_max_y<=y;
                    top_min_x<=x;top_max_x<=x;
                end
                else begin
                    if(x<cur_min_x)cur_min_x<=x;if(x>cur_max_x)cur_max_x<=x;
                    if(y<cur_min_y)cur_min_y<=y;if(y>cur_max_y)cur_max_y<=y;
                    if(y==cur_min_y)begin
                        if(x<top_min_x)top_min_x<=x;if(x>top_max_x)top_max_x<=x;
                    end
                end
                cur_edge_count<=cur_edge_count+1'b1;
            end
            out_de<=in_de;out_hs<=in_hs;out_vs<=in_vs;
            if(!in_de)begin out_r<=0;out_g<=0;out_b<=0;end
            else if(letter_on)begin out_r<=255;out_g<=255;out_b<=255;end
            else if(label_region)begin out_r<=0;out_g<=0;out_b<=0;end
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

