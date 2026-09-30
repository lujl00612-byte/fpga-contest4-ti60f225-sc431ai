// Synchronize the request, then stop/resume writes only in frame blanking.
module frame_freeze_control(
    input wire clk,input wire rst_n,input wire vs,input wire request,
    output wire frozen
);
    (* async_reg = "true" *) reg request_meta,request_sync;
    reg vs_d,frozen_frame;
    // Apply the synchronized decision before the first VS sample reaches the buffer.
    assign frozen=(vs&&!vs_d)?request_sync:frozen_frame;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin request_meta<=0;request_sync<=0;vs_d<=0;frozen_frame<=0;end
        else begin
            request_meta<=request;request_sync<=request_meta;vs_d<=vs;
            if(vs&&!vs_d)frozen_frame<=request_sync;
        end
    end
endmodule
