// Single keys adjust threshold. Short chord freezes; a long chord changes algorithm.
module threshold_control #(parameter integer LONG_PRESS_FRAMES=60)(
    input wire clk,input wire rst_n,input wire vs,input wire [1:0] key_n,
    output reg [1:0] level,output reg [10:0] threshold,output reg freeze,output reg basic_mode
);
    reg [1:0] key_meta,key_sync;reg vs_d;
    reg [2:0] hist_down,hist_up;reg held_down,held_up,held_both;
    reg [7:0] both_frames;reg long_handled;
    always @(*) begin
        case(level)
            2'd0:threshold=11'd32;
            2'd1:threshold=11'd64;
            2'd2:threshold=11'd96;
            default:threshold=11'd160;
        endcase
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            key_meta<=2'b11;key_sync<=2'b11;vs_d<=0;hist_down<=3'b111;hist_up<=3'b111;
            held_down<=0;held_up<=0;held_both<=0;level<=2'd2;freeze<=0;
            both_frames<=0;long_handled<=0;basic_mode<=1;
        end else begin
            key_meta<=key_n;key_sync<=key_meta;vs_d<=vs;
            if(vs&&!vs_d)begin
                hist_down<={hist_down[1:0],key_sync[0]};hist_up<={hist_up[1:0],key_sync[1]};
                if((hist_down==3'b000)&&(hist_up==3'b000))begin
                    held_both<=1;held_down<=1;held_up<=1;
                    if(!held_both)begin both_frames<=1;long_handled<=0;end
                    else if(!long_handled)begin
                        if(both_frames>=LONG_PRESS_FRAMES-1)begin
                            basic_mode<=~basic_mode;long_handled<=1;
                        end else both_frames<=both_frames+1'b1;
                    end
                end else begin
                    if((hist_down==3'b111)&&(hist_up==3'b111))begin
                        if(held_both&&!long_handled)freeze<=~freeze;
                        held_both<=0;held_down<=0;held_up<=0;
                        both_frames<=0;long_handled<=0;
                    end
                    if((hist_down==3'b000)&&(hist_up==3'b111)&&!held_down)begin
                        held_down<=1;if(level!=0)level<=level-1'b1;
                    end else if(hist_down==3'b111)held_down<=0;
                    if((hist_up==3'b000)&&(hist_down==3'b111)&&!held_up)begin
                        held_up<=1;if(level!=3)level<=level+1'b1;
                    end else if(hist_up==3'b111)held_up<=0;
                end
            end
        end
    end
endmodule
