// Five 4-bit states in each 20-bit word. Capture/DFS share one write port;
// DFS and result display are mutually exclusive and share one read port.
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
    reg write_latched;reg [3:0] tag_latched;
    // Keep the most recent word in the writeback register, and one displaced
    // word in a victim entry. A hit responds at acceptance; writes commit on ACK.
    reg [19:0] write_word_q;
    reg cache_valid;
    reg [19:0] victim_word_q;
    reg [WORD_BITS-1:0] victim_addr_q;
    reg victim_valid;
    localparam integer BANKS=(WORDS+511)/512;
    localparam integer BANK_BITS=(BANKS>1)?$clog2(BANKS):1;
    localparam integer GROUPS=(BANKS+7)/8;
    localparam integer GROUP_LEAVES=1<<$clog2(GROUPS);
    wire [19:0] bank_data[0:BANKS-1];
    // Decode on the RAM acceptance edge, then select 8 banks per group.
    // Both selectors describe the same read as the bank RDATA. This replaces
    // the long variable-index mux without adding a response/video pipeline.
    reg [7:0] read_slot_q;
    reg [GROUPS-1:0] read_group_q;
    wire [19:0] group_word[0:GROUPS-1];
    wire [19:0] group_tree[0:2*GROUP_LEAVES-2];
    reg video_en_q;
    wire [19:0] read_word=group_tree[0];
    wire [WORD_BITS-1:0] requested_word=req_addr/5;
    wire cache_allowed=!(capture_we||video_en||video_en_q);
    wire primary_hit=cache_valid&&(requested_word==word_addr)&&cache_allowed;
    wire victim_hit=victim_valid&&(requested_word==victim_addr_q)&&cache_allowed;
    wire cache_hit=primary_hit||victim_hit;
    wire [19:0] engine_word=read_word;
    wire [19:0] hit_word=primary_hit?write_word_q:victim_word_q;
    wire [2:0] request_lane=req_addr-requested_word*5;
    reg [19:0] hit_updated_word;reg [3:0] hit_tag;
    always @* begin
        hit_tag=0;hit_updated_word=hit_word;
        case(request_lane)
            0:begin hit_tag=hit_word[3:0];hit_updated_word[3:0]=req_wdata;end
            1:begin hit_tag=hit_word[7:4];hit_updated_word[7:4]=req_wdata;end
            2:begin hit_tag=hit_word[11:8];hit_updated_word[11:8]=req_wdata;end
            3:begin hit_tag=hit_word[15:12];hit_updated_word[15:12]=req_wdata;end
            4:begin hit_tag=hit_word[19:16];hit_updated_word[19:16]=req_wdata;end
            default:begin end
        endcase
    end
    // Video retains its two-edge read latency, independently of cache hits.
    wire ram_re=(state==READ_WORD)||video_en;
    wire [WORD_BITS-1:0] ram_raddr=(state==READ_WORD)?word_addr:video_addr;
    // Commit on the edge on which the requester consumes req_ready. The existing
    // ACK cycle separates the bank mux/RMW from RAM write data without a new wait.
    wire ram_we=capture_we||((state==ACK)&&write_latched);
    wire [WORD_BITS-1:0] ram_waddr=capture_we?capture_addr:word_addr;
    wire [19:0] ram_wdata=capture_we?capture_word:write_word_q;
    wire [BANK_BITS-1:0] read_bank=ram_raddr>>9,write_bank=ram_waddr>>9;
    wire [8:0] read_row=ram_raddr,write_row=ram_waddr;
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
    // Explicit 512x20 banks preserve all parity bits. Automatic inference split 20
    // into 16+4 and used 150 blocks; this packing uses exactly 120 for 640x480.
    genvar b,g,s,t;
    generate for(b=0;b<BANKS;b=b+1)begin:bank
        EFX_RAM10 #(.READ_WIDTH(20),.WRITE_WIDTH(20),.OUTPUT_REG(0),.WRITE_MODE("READ_FIRST")) ram(
            .WCLK(clk),.WE({2{ram_we&&(write_bank==b)}}),.WCLKE(1'b1),.WADDREN(1'b1),
            .WDATA(ram_wdata),.WADDR(write_row),.RCLK(clk),.RE(ram_re&&(read_bank==b)),
            .RST(1'b0),.RADDREN(1'b1),.RDATA(bank_data[b]),.RADDR(read_row));
    end endgenerate
    generate for(g=0;g<GROUPS;g=g+1)begin:read_group
        wire [19:0] slot[0:7];
        for(s=0;s<8;s=s+1)begin:read_slot
            if(g*8+s<BANKS)begin:present
                assign slot[s]=bank_data[g*8+s]&{20{read_slot_q[s]}};
            end else begin:padding
                assign slot[s]=20'd0;
            end
        end
        assign group_word[g]=((slot[0]|slot[1])|(slot[2]|slot[3]))|
                             ((slot[4]|slot[5])|(slot[6]|slot[7]));
    end
    for(t=0;t<GROUP_LEAVES;t=t+1)begin:group_leaf
        if(t<GROUPS)begin:present
            assign group_tree[GROUP_LEAVES-1+t]=group_word[t]&{20{read_group_q[t]}};
        end else begin:padding
            assign group_tree[GROUP_LEAVES-1+t]=20'd0;
        end
    end
    for(t=0;t<GROUP_LEAVES-1;t=t+1)begin:group_branch
        assign group_tree[t]=group_tree[t*2+1]|group_tree[t*2+2];
    end endgenerate
    integer select_index;
    always @(posedge clk)begin
        if(ram_re)begin
            for(select_index=0;select_index<8;select_index=select_index+1)
                read_slot_q[select_index]<=(read_bank%8==select_index);
            for(select_index=0;select_index<GROUPS;select_index=select_index+1)
                read_group_q[select_index]<=(read_bank/8==select_index);
        end
        if(!rst_n)begin video_en_q<=0;video_word<=0;end
        else begin
            video_en_q<=video_en;
            if(video_en_q)video_word<=read_word;
        end
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;word_addr<=0;cell_addr<=0;write_latched<=0;tag_latched<=0;write_word_q<=0;
            cache_valid<=0;req_ready<=0;req_rdata<=0;
            victim_word_q<=0;victim_addr_q<=0;victim_valid<=0;
        end else begin
            req_ready<=0;
            case(state)
                IDLE:if(req_valid)begin
                    if(!primary_hit)begin
                        // Retain the old MRU on a miss, or swap it into the
                        // victim entry when the victim responds immediately.
                        victim_word_q<=write_word_q;victim_addr_q<=word_addr;victim_valid<=cache_valid;
                    end
                    word_addr<=requested_word;cell_addr<=req_addr;write_latched<=req_write;tag_latched<=req_wdata;
                    if(cache_hit)begin
                        req_rdata<=hit_tag;write_word_q<=req_write?hit_updated_word:hit_word;
                        cache_valid<=1;req_ready<=1;state<=ACK;
                    end else state<=READ_WORD;
                end
                READ_WORD:state<=RESPOND;
                RESPOND:begin
                    req_rdata<=selected_tag;
                    // A read must cache the unchanged word, including all neighbors.
                    write_word_q<=write_latched?updated_word:engine_word;
                    cache_valid<=1;req_ready<=1;state<=ACK;
                end
                ACK:state<=IDLE;
            endcase
            // Capture can replace any word; display also changes the RAM bank
            // selection. Do not carry cache state across either ownership switch.
            if(capture_we||video_en||video_en_q)begin cache_valid<=0;victim_valid<=0;end
        end
    end
endmodule
