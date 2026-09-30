// Exact 8-connected hysteresis. 4 bits per cell: 0 background, 1 weak, 2 strong,
// 3 visited root, 4..11 visited with the direction back to its DFS parent.
// Returning from a child also recovers the parent's next neighbor index.
// Each pixel is scanned once and each accepted pixel examines its 8 neighbors once.
// Time O(WIDTH*HEIGHT), storage 4*WIDTH*HEIGHT bits, no external DFS stack.
module canny_hysteresis_exact #(
    parameter integer WIDTH=640,HEIGHT=480,
    parameter integer ADDR_BITS=$clog2(WIDTH*HEIGHT),
    parameter integer X_BITS=$clog2(WIDTH),Y_BITS=$clog2(HEIGHT)
)(
    input wire clk,input wire rst_n,input wire start,
    output reg busy,output reg done,output reg error,
    output wire mem_valid,output wire mem_write,
    output reg [ADDR_BITS-1:0] mem_addr,output reg [3:0] mem_wdata,
    input wire mem_ready,input wire [3:0] mem_rdata,
    output reg [ADDR_BITS:0] accepted_pixels,output reg [31:0] cycles
);
    localparam IDLE=0,ROOT_READ=1,ROOT_MARK=2,CHOOSE=3,
        NEIGHBOR_READ=4,CHILD_MARK=5,BACK_READ=6,ADVANCE=7;
    reg [3:0] state,neighbor_index;
    reg [ADDR_BITS-1:0] scan_addr,current_addr,neighbor_addr;
    reg [X_BITS-1:0] scan_x,current_x,neighbor_x;
    reg [Y_BITS-1:0] scan_y,current_y,neighbor_y;
    reg candidate_valid;reg [ADDR_BITS-1:0] candidate_addr;
    reg [X_BITS-1:0] candidate_x;reg [Y_BITS-1:0] candidate_y;
    reg [2:0] move_dir;
    // 0 NW, 1 N, 2 NE, 3 W, 4 E, 5 SW, 6 S, 7 SE. Opposite = 7-dir.
    always @* begin
        move_dir=(state==BACK_READ)?(mem_rdata-4):neighbor_index[2:0];
        candidate_addr=current_addr;candidate_x=current_x;candidate_y=current_y;
        candidate_valid=1;
        case(move_dir)
            0:begin candidate_addr=current_addr-WIDTH-1;candidate_x=current_x-1;candidate_y=current_y-1;
                candidate_valid=current_x!=0&&current_y!=0;end
            1:begin candidate_addr=current_addr-WIDTH;candidate_y=current_y-1;candidate_valid=current_y!=0;end
            2:begin candidate_addr=current_addr-WIDTH+1;candidate_x=current_x+1;candidate_y=current_y-1;
                candidate_valid=current_x<WIDTH-1&&current_y!=0;end
            3:begin candidate_addr=current_addr-1;candidate_x=current_x-1;candidate_valid=current_x!=0;end
            4:begin candidate_addr=current_addr+1;candidate_x=current_x+1;candidate_valid=current_x<WIDTH-1;end
            5:begin candidate_addr=current_addr+WIDTH-1;candidate_x=current_x-1;candidate_y=current_y+1;
                candidate_valid=current_x!=0&&current_y<HEIGHT-1;end
            6:begin candidate_addr=current_addr+WIDTH;candidate_y=current_y+1;candidate_valid=current_y<HEIGHT-1;end
            7:begin candidate_addr=current_addr+WIDTH+1;candidate_x=current_x+1;candidate_y=current_y+1;
                candidate_valid=current_x<WIDTH-1&&current_y<HEIGHT-1;end
        endcase
    end
    assign mem_valid=(state==ROOT_READ)||(state==ROOT_MARK)||(state==NEIGHBOR_READ)||(state==CHILD_MARK)||(state==BACK_READ);
    assign mem_write=(state==ROOT_MARK)||(state==CHILD_MARK);
    always @* begin
        mem_addr=current_addr;mem_wdata=0;
        case(state)
            ROOT_READ:mem_addr=scan_addr;
            ROOT_MARK:mem_wdata=3;
            NEIGHBOR_READ:mem_addr=neighbor_addr;
            CHILD_MARK:begin mem_addr=neighbor_addr;mem_wdata=11-neighbor_index;end
            default:begin end
        endcase
    end
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state<=IDLE;neighbor_index<=0;scan_addr<=0;current_addr<=0;neighbor_addr<=0;
            scan_x<=0;scan_y<=0;current_x<=0;current_y<=0;neighbor_x<=0;neighbor_y<=0;
            busy<=0;done<=0;error<=0;accepted_pixels<=0;cycles<=0;
        end else begin
            done<=0;
            if(busy)cycles<=cycles+1'b1;
            case(state)
                IDLE:if(start)begin
                    scan_addr<=0;scan_x<=0;scan_y<=0;accepted_pixels<=0;cycles<=0;error<=0;
                    busy<=1;state<=ROOT_READ;
                end
                ROOT_READ:if(mem_ready)begin
                    if(mem_rdata==2)begin
                        current_addr<=scan_addr;current_x<=scan_x;current_y<=scan_y;
                        neighbor_index<=0;state<=ROOT_MARK;
                    end else state<=ADVANCE;
                end
                ROOT_MARK:if(mem_ready)begin accepted_pixels<=accepted_pixels+1'b1;state<=CHOOSE;end
                CHOOSE:begin
                    if(neighbor_index==8)state<=BACK_READ;
                    else if(candidate_valid)begin
                        neighbor_addr<=candidate_addr;neighbor_x<=candidate_x;neighbor_y<=candidate_y;
                        state<=NEIGHBOR_READ;
                    end else neighbor_index<=neighbor_index+1'b1;
                end
                NEIGHBOR_READ:if(mem_ready)begin
                    if(mem_rdata==1||mem_rdata==2)state<=CHILD_MARK;
                    else begin neighbor_index<=neighbor_index+1'b1;state<=CHOOSE;end
                end
                CHILD_MARK:if(mem_ready)begin
                    current_addr<=neighbor_addr;current_x<=neighbor_x;current_y<=neighbor_y;
                    neighbor_index<=0;accepted_pixels<=accepted_pixels+1'b1;state<=CHOOSE;
                end
                BACK_READ:if(mem_ready)begin
                    if(mem_rdata==3)state<=ADVANCE;
                    else if(mem_rdata>=4&&mem_rdata<=11&&candidate_valid)begin
                        current_addr<=candidate_addr;current_x<=candidate_x;current_y<=candidate_y;
                        neighbor_index<=12-mem_rdata;state<=CHOOSE;
                    end else begin error<=1;busy<=0;done<=1;state<=IDLE;end
                end
                ADVANCE:begin
                    if(scan_addr==WIDTH*HEIGHT-1)begin busy<=0;done<=1;state<=IDLE;end
                    else begin
                        scan_addr<=scan_addr+1'b1;
                        if(scan_x==WIDTH-1)begin scan_x<=0;scan_y<=scan_y+1'b1;end else scan_x<=scan_x+1'b1;
                        state<=ROOT_READ;
                    end
                end
                default:begin error<=1;busy<=0;done<=1;state<=IDLE;end
            endcase
        end
    end
endmodule
