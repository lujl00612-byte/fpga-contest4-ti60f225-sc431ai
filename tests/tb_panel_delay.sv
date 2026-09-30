`timescale 1ns/1ps
module tb_panel_delay;
    reg clk=0,rst_n=1;
    wire [1:0] awvalid,wvalid,bready,arvalid,rready,done;
    wire [6:0] awaddr[0:1],araddr[0:1];
    wire [31:0] wdata[0:1];
    reg [1:0] bvalid=0,rvalid=0;
    integer ticks=0,aw_count[0:1],w_count[0:1],first_aw[0:1],second_aw[0:1];
    integer i;
    always #5 clk=~clk;
    // Literal filenames avoid packed-vector/string conversion by Icarus.
`define PANEL_PORTS(g) \
    .i_axi_clk(clk),.i_restn(rst_n),.i_axi_awready(1'b1),.i_axi_wready(1'b1), \
    .i_axi_bvalid(bvalid[g]),.o_axi_awaddr(awaddr[g]),.o_axi_awvalid(awvalid[g]), \
    .o_axi_wdata(wdata[g]),.o_axi_wvalid(wvalid[g]),.o_axi_bready(bready[g]), \
    .i_axi_arready(1'b1),.i_axi_rdata(32'd0),.i_axi_rvalid(rvalid[g]), \
    .o_axi_araddr(araddr[g]),.o_axi_arvalid(arvalid[g]),.o_axi_rready(rready[g]), \
    .o_addr_cnt(),.o_state(),.o_confdone(done[g]), \
    .i_dbg_we(1'b0),.i_dbg_din(40'd0),.i_dbg_addr(9'd0),.o_dbg_dout(),.i_dbg_reconfig(1'b0)
    panel_config #(.INITIAL_CODE(".cache/panel_delay_short.mem"),.REG_DEPTH(9'd180)) short_dut (`PANEL_PORTS(0));
    panel_config #(.INITIAL_CODE(".cache/panel_delay_long.mem"),.REG_DEPTH(9'd180)) long_dut (`PANEL_PORTS(1));
`undef PANEL_PORTS
    always @(posedge clk) begin
        if(!rst_n) begin
            ticks=0; bvalid<=0; rvalid<=0;
            for(i=0;i<2;i=i+1) begin aw_count[i]=0; w_count[i]=0; first_aw[i]=0; second_aw[i]=0; end
        end else begin
            ticks=ticks+1;
            for(i=0;i<2;i=i+1) begin
                if(bvalid[i]&&bready[i]) bvalid[i]<=0;
                if(wvalid[i]) bvalid[i]<=1;
                if(rvalid[i]&&rready[i]) rvalid[i]<=0;
                if(arvalid[i]) begin
                    if(araddr[i]!==7'h24) $fatal(1,"Wrong status address");
                    rvalid[i]<=1;
                end
                if(awvalid[i]) begin
                    if(awaddr[i]!==7'h20 || aw_count[i]>1) $fatal(1,"Wrong delay-test AW");
                    if(aw_count[i]==0) first_aw[i]=ticks;
                    else second_aw[i]=ticks;
                    aw_count[i]=aw_count[i]+1;
                end
                if(wvalid[i]) begin
                    if(w_count[i]>1 || wdata[i] !== (w_count[i]==0 ? 32'h1105 : 32'h2905))
                        $fatal(1,"Wrong delay-test write payload");
                    w_count[i]=w_count[i]+1;
                end
            end
        end
    end
    initial begin
        #2; rst_n=0;
        repeat(6) @(negedge clk);
        #1; rst_n=1;
        wait(done===2'b11); @(negedge clk);
        if(first_aw[0]!=first_aw[1] || aw_count[0]!=2 || aw_count[1]!=2 || w_count[0]!=2 || w_count[1]!=2)
            $fatal(1,"Delay reference transactions differ");
        if(second_aw[1]-second_aw[0]!=4194304)
            $fatal(1,"Delay high bits lost: second-write difference=%0d expected=4194304",second_aw[1]-second_aw[0]);
        $display("PASS panel_delay short_second_AW=%0d long_second_AW=%0d difference=%0d clocks; unchanged payload; delay bit22 preserved",second_aw[0],second_aw[1],second_aw[1]-second_aw[0]);
        $finish;
    end
    initial begin #42000000; $fatal(1,"Delay simulation timeout"); end
endmodule
