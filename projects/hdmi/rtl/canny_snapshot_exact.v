// Exact Canny connectivity over a frozen 640x480 analysis area in the right half.
// Wait three display frames for camera-domain freeze, capture the NMS classes,
// run linear DFS once, and publish the result on a later frame boundary.
module canny_snapshot_exact #(
    parameter integer WIDTH=1920,ROI_WIDTH=640,ROI_HEIGHT=480,START_X=WIDTH/2,
    parameter integer X_BITS=11,Y_BITS=11,SETTLE_FRAMES=3,
    parameter integer CELLS=ROI_WIDTH*ROI_HEIGHT,WORDS=CELLS/5,
    parameter integer ADDR_BITS=$clog2(CELLS),WORD_BITS=$clog2(WORDS)
)(
    input wire clk,input wire rst_n,input wire enable_i,input wire [10:0] threshold_i,
    input wire [1:0] class_i,input wire [23:0] rgb_i,input wire de_i,input wire hs_i,input wire vs_i,
    output reg [23:0] rgb_o,output reg de_o,output reg hs_o,output reg vs_o,output reg edge_o,
    output reg result_ready,output wire engine_busy,output wire engine_error,
    output wire [31:0] processing_cycles,output wire [ADDR_BITS:0] accepted_pixels
);
    reg [X_BITS-1:0] x;reg [Y_BITS-1:0] y;reg de_d,vs_d;
    reg [10:0] seen_threshold;reg [3:0] settle;
    reg capturing,start_pending,engine_start,complete_pending;
    reg [19:0] pack;reg [2:0] capture_lane,video_lane;
    reg [WORD_BITS-1:0] capture_index,video_index,capture_addr;
    reg capture_we;reg [19:0] capture_word;
    wire roi=de_i&&x>=START_X&&x<START_X+ROI_WIDTH&&y<ROI_HEIGHT;
    wire valid_input_class=(class_i==1)||(class_i==2);
    wire [3:0] captured_tag=valid_input_class?{2'd0,class_i}:4'd0;
    wire mem_valid,mem_write,mem_ready,engine_done;
    wire [ADDR_BITS-1:0] mem_addr;wire [3:0] mem_wdata,mem_rdata;
    wire [19:0] video_word;
    wire engine_rst_n=rst_n&&enable_i;
    canny_hysteresis_exact #(.WIDTH(ROI_WIDTH),.HEIGHT(ROI_HEIGHT)) engine(
        .clk(clk),.rst_n(engine_rst_n),.start(engine_start),.busy(engine_busy),.done(engine_done),.error(engine_error),
        .mem_valid(mem_valid),.mem_write(mem_write),.mem_addr(mem_addr),.mem_wdata(mem_wdata),
        .mem_ready(mem_ready),.mem_rdata(mem_rdata),.accepted_pixels(accepted_pixels),.cycles(processing_cycles));
    canny_tag_memory #(.CELLS(CELLS)) memory(
        .clk(clk),.rst_n(engine_rst_n),.capture_we(capture_we&&enable_i),.capture_addr(capture_addr),.capture_word(capture_word),
        .req_valid(mem_valid),.req_write(mem_write),.req_addr(mem_addr),.req_wdata(mem_wdata),.req_ready(mem_ready),.req_rdata(mem_rdata),
        .video_en(roi&&result_ready),.video_addr(video_index),.video_word(video_word));
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            x<=0;y<=0;de_d<=0;vs_d<=0;seen_threshold<=0;settle<=0;capturing<=0;
            start_pending<=0;engine_start<=0;complete_pending<=0;result_ready<=0;
            pack<=0;capture_lane<=0;video_lane<=0;capture_index<=0;video_index<=0;
            capture_we<=0;capture_word<=0;capture_addr<=0;
        end else begin
            vs_d<=vs_i;de_d<=de_i;capture_we<=0;engine_start<=0;
            if(de_i)x<=x+1'b1;else x<=0;
            if(vs_i&&!vs_d)y<=0;else if(de_d&&!de_i)y<=y+1'b1;
            if(vs_i&&!vs_d)begin video_index<=0;video_lane<=0;end
            else if(roi)begin
                if(video_lane==4)begin video_lane<=0;video_index<=video_index+1'b1;end
                else video_lane<=video_lane+1'b1;
            end
            if(!enable_i)begin
                seen_threshold<=threshold_i;settle<=0;capturing<=0;start_pending<=0;
                complete_pending<=0;result_ready<=0;capture_lane<=0;capture_index<=0;
            end else begin
                if(engine_done&&!engine_error)complete_pending<=1;
                if(threshold_i!=seen_threshold&&!engine_busy&&!capturing)begin
                    seen_threshold<=threshold_i;settle<=0;complete_pending<=0;result_ready<=0;
                end else if(vs_i&&!vs_d)begin
                    if(complete_pending)begin result_ready<=1;complete_pending<=0;end
                    else if(!result_ready&&!capturing&&!engine_busy&&!start_pending&&!engine_start)begin
                        if(settle>=SETTLE_FRAMES)begin
                            capturing<=1;capture_lane<=0;capture_index<=0;pack<=0;
                        end else settle<=settle+1'b1;
                    end
                end
                if(capturing&&roi)begin
                    case(capture_lane)
                        0:pack[3:0]<=captured_tag;
                        1:pack[7:4]<=captured_tag;
                        2:pack[11:8]<=captured_tag;
                        3:pack[15:12]<=captured_tag;
                        4:begin
                            capture_word<={captured_tag,pack[15:0]};capture_addr<=capture_index;capture_we<=1;
                            capture_index<=capture_index+1'b1;
                            if(capture_index==WORDS-1)begin capturing<=0;start_pending<=1;end
                        end
                    endcase
                    capture_lane<=capture_lane==4?0:capture_lane+1'b1;
                end
                if(start_pending)begin engine_start<=1;start_pending<=0;end
            end
        end
    end
    reg [23:0] rgb0,rgb1;reg de0,hs0,vs0,de1,hs1,vs1;
    reg roi0,ready0,left0,status0;reg [2:0] lane0;
    reg edge1;
    reg [3:0] tag;reg [15:0] gray_sum;
    always @* begin
        case(lane0)
            0:tag=video_word[3:0];1:tag=video_word[7:4];2:tag=video_word[11:8];
            3:tag=video_word[15:12];default:tag=video_word[19:16];
        endcase
        gray_sum=rgb0[23:16]*8'd77+rgb0[15:8]*8'd150+rgb0[7:0]*8'd29;
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            rgb0<=0;rgb1<=0;rgb_o<=0;de0<=0;hs0<=0;vs0<=0;de1<=0;hs1<=0;vs1<=0;
            de_o<=0;hs_o<=0;vs_o<=0;roi0<=0;ready0<=0;left0<=0;status0<=0;lane0<=0;edge_o<=0;edge1<=0;
        end else begin
            rgb0<=rgb_i;de0<=de_i;hs0<=hs_i;vs0<=vs_i;roi0<=roi;ready0<=result_ready;lane0<=video_lane;
            left0<=x<WIDTH/2;
            status0<=de_i&&x>=START_X&&x<START_X+ROI_WIDTH&&y>=ROI_HEIGHT&&y<ROI_HEIGHT+3;
            de1<=de0;hs1<=hs0;vs1<=vs0;de_o<=de1;hs_o<=hs1;vs_o<=vs1;rgb_o<=rgb1;
            edge1<=de0&&!left0&&!status0&&roi0&&ready0&&tag>=3;edge_o<=edge1;
            if(!de0)rgb1<=0;
            else if(left0)rgb1<={gray_sum[15:8],gray_sum[15:8],gray_sum[15:8]};
            else if(status0)rgb1<=ready0?24'h00ff40:24'hffd000;
            else if(roi0&&ready0&&tag>=3)rgb1<=24'hff0000;
            else rgb1<=rgb0;
        end
    end
endmodule
