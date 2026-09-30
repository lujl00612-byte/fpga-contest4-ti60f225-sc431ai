`timescale 1ns/1ps
// Word-level model only for this controller's 512x20, full-word write, no reset,
// non-overlapping read/write configuration. Compare against vendor RAM before scale tests.
module EFX_RAM10 #(
    parameter READ_WIDTH=20,WRITE_WIDTH=20,OUTPUT_REG=0,WRITE_MODE="READ_FIRST"
)(
    input wire WCLK,input wire [1:0] WE,input wire WCLKE,input wire WADDREN,
    input wire [19:0] WDATA,input wire [8:0] WADDR,
    input wire RCLK,input wire RE,input wire RST,input wire RADDREN,
    output reg [19:0] RDATA=0,input wire [8:0] RADDR
);
    reg [19:0] words[0:511];integer i;
    initial begin
        if(READ_WIDTH!=20||WRITE_WIDTH!=20||OUTPUT_REG!=0||WRITE_MODE!="READ_FIRST")$fatal(1,"unsupported fast RAM configuration");
        for(i=0;i<512;i=i+1)words[i]=0;
    end
    // Sleep inactive banks until enabled. Wait for the next real clock edge;
    // never form CLK & enable, which would create false edges when enable changes.
    always @(WE)begin
        if(WE!=0&&WE!=3)$fatal(1,"fast model requires full-word writes");
    end
    always @(RST)if(RST)$fatal(1,"fast model requires unused RAM reset");
    initial forever begin
        wait(WCLKE&&WE==3);
        @(posedge WCLK);
        if(WCLKE&&WE==3)begin
            if(!WADDREN||RE)$fatal(1,"fast model requires enabled address and non-overlapping ports");
            words[WADDR]<=WDATA;
        end
        @(negedge WCLK);
    end
    initial forever begin
        wait(RE);
        @(posedge RCLK);
        if(RE)begin
            if(!RADDREN)$fatal(1,"fast model requires enabled read address");
            RDATA<=words[RADDR];
        end
        @(negedge RCLK);
    end
endmodule
