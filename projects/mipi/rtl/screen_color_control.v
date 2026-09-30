// Synchronize the two active-low keys and debounce over three complete frames.
module screen_color_control(
    input wire clk,input wire rst_n,input wire vs,input wire [1:0] key_n,
    output reg [1:0] mode,output reg [1:0] enhance
);
    reg [1:0] meta,sync;
    reg [2:0] h0,h1;
    reg held0,held1,vs_d;
    always @(posedge clk) begin
        if(!rst_n) begin
            meta<=3;sync<=3;h0<=7;h1<=7;held0<=0;held1<=0;vs_d<=0;mode<=1;enhance<=0;
        end else begin
            meta<=key_n;sync<=meta;vs_d<=vs;
            if(vs&&!vs_d) begin
                h0<={h0[1:0],sync[0]};h1<={h1[1:0],sync[1]};
                if(h0==0&&!held0)begin mode<=mode+1'b1;held0<=1;end
                else if(h0==7)held0<=0;
                if(h1==0&&!held1)begin enhance<=enhance+1'b1;held1<=1;mode<=2;end
                else if(h1==7)held1<=0;
            end
        end
    end
endmodule
