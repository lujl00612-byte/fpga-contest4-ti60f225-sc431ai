// Five 4-bit states in each 20-bit word. Port A serves capture / DFS; port B displays.
// A read-modify-write transaction changes a single cell without touching its neighbors.
module canny_tag_memory #(
    parameter integer CELLS=640*480,ADDR_BITS=$clog2(CELLS),
    parameter integer WORDS=CELLS/5,WORD_BITS=$clog2(WORDS)
)(
    input wire clk,input wire rst_n,
    input wire capture_we,input wire [WORD_BITS-1:0] capture_addr,input wire [19:0] capture_word,
    input wire req_valid,input wire req_write,input wire [ADDR_BITS-1:0] req_addr,input wire [3:0] req_wdata,
    output reg req_ready,output reg [3:0] req_rdata,
    input wire video_en,input wire [WORD_BITS-1:0] video_addr,output reg [19:0] video_word
);
    localparam IDLE=0,READ_WORD=1,RESPOND=2,ACK=3;
    reg [1:0] state;
    reg [WORD_BITS-1:0] word_addr;
    reg [ADDR_BITS-1:0] cell_addr;
    reg write_latched;reg [3:0] tag_latched;reg [19:0] engine_word;
    reg [19:0] tags[0:WORDS-1];
    wire [2:0] lane=cell_addr-word_addr*5;
    reg [19:0] updated_word;reg [3:0] selected_tag;
    always @* begin
        selected_tag=0;updated_word=engine_word;
        case(lane)
            0:begin selected_tag=engine_word[3:0];updated_word[3:0]=tag_latched;end
            1:begin selected_tag=engine_word[7:4];updated_word[7:4]=tag_latched;end
            2:begin selected_tag=engine_word[11:8];updated_word[11:8]=tag_latched;end
            3:begin selected_tag=engine_word[15:12];updated_word[15:12]=tag_latched;end
            4:begin selected_tag=engine_word[19:16];updated_word[19:16]=tag_latched;end
            default:begin end
        endcase
    end
    // No reset on the memory array: every word is initialized by a complete capture.
    always @(posedge clk)begin
        if(video_en)video_word<=tags[video_addr];
        if(state==READ_WORD)engine_word<=tags[word_addr];
        if(capture_we)tags[capture_addr]<=capture_word;
        else if(state==RESPOND&&write_latched)tags[word_addr]<=updated_word;
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;word_addr<=0;cell_addr<=0;write_latched<=0;tag_latched<=0;req_ready<=0;req_rdata<=0;
        end else begin
            req_ready<=0;
            case(state)
                IDLE:if(req_valid)begin
                    word_addr<=req_addr/5;cell_addr<=req_addr;write_latched<=req_write;tag_latched<=req_wdata;
                    state<=READ_WORD;
                end
                READ_WORD:state<=RESPOND;
                RESPOND:begin req_rdata<=selected_tag;req_ready<=1;state<=ACK;end
                ACK:state<=IDLE;
            endcase
        end
    end
endmodule
