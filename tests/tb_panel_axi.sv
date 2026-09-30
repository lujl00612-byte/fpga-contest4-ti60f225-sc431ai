`timescale 1ns/1ps
module tb_panel_axi;
    reg clk=0, rst_n=1;
    reg awready=0,wready=0,bvalid=0,arready=0,rvalid=0;
    reg [31:0] rdata=0;
    wire [6:0] awaddr,araddr;
    wire [31:0] wdata;
    wire awvalid,wvalid,bready,arvalid,rready,done;
    reg [39:0] expected[0:118];
    reg [31:0] random_bits=32'h137fa53d;
    reg aw_seen=0,b_pending=0,r_pending=0,await_idle=0;
    reg aw_stalled=0,w_stalled=0,ar_stalled=0;
    reg [6:0] held_aw,held_ar;
    reg [31:0] held_w,response_word;
    integer writes=0,reads=0,poll_index=0,b_delay=0,r_delay=0;
    integer checks=0,stalls=0,runs=0;
    always #5 clk=~clk;
    panel_config #(.INITIAL_CODE(".cache/panel_axi_fixture.mem"),.REG_DEPTH(9'd180)) dut (
        .i_axi_clk(clk),.i_restn(rst_n),.i_axi_awready(awready),.i_axi_wready(wready),
        .i_axi_bvalid(bvalid),.o_axi_awaddr(awaddr),.o_axi_awvalid(awvalid),
        .o_axi_wdata(wdata),.o_axi_wvalid(wvalid),.o_axi_bready(bready),
        .i_axi_arready(arready),.i_axi_rdata(rdata),.i_axi_rvalid(rvalid),
        .o_axi_araddr(araddr),.o_axi_arvalid(arvalid),.o_axi_rready(rready),
        .o_addr_cnt(),.o_state(),.o_confdone(done),
        .i_dbg_we(1'b0),.i_dbg_din(40'd0),.i_dbg_addr(9'd0),.o_dbg_dout(),.i_dbg_reconfig(1'b0));

    // Ready and responses are driven on falling edges. All transfers and
    // payload checks use the signals present before the rising handshake edge.
    always @(negedge clk) begin
        if (!rst_n) begin
            awready=0; wready=0; arready=0; bvalid=0; rvalid=0; rdata=0;
        end else begin
            random_bits={random_bits[30:0],random_bits[31]^random_bits[21]^random_bits[1]^random_bits[0]};
            awready=random_bits[0]; wready=random_bits[1]; arready=random_bits[2];
            if (!b_pending) bvalid=0;
            else if (b_delay==0) bvalid=1;
            else begin b_delay=b_delay-1; bvalid=0; end
            if (!r_pending) rvalid=0;
            else if (r_delay==0) begin rvalid=1; rdata=response_word; end
            else begin r_delay=r_delay-1; rvalid=0; end
        end
    end
    always @(posedge clk) begin
        if (!rst_n) begin
            writes=0; reads=0; poll_index=0;
            aw_seen=0; b_pending=0; r_pending=0; await_idle=0;
            aw_stalled=0; w_stalled=0; ar_stalled=0;
        end else begin
            if (aw_stalled && (!awvalid || awaddr !== held_aw)) $fatal(1,"AW payload changed while stalled");
            if (w_stalled && (!wvalid || wdata !== held_w)) $fatal(1,"W payload changed while stalled");
            if (ar_stalled && (!arvalid || araddr !== held_ar)) $fatal(1,"AR payload changed while stalled");
            aw_stalled=awvalid&&!awready; held_aw=awaddr;
            w_stalled=wvalid&&!wready; held_w=wdata;
            ar_stalled=arvalid&&!arready; held_ar=araddr;
            if (aw_stalled || w_stalled || ar_stalled) stalls=stalls+1;
            if (awvalid&&awready) begin
                if (writes>=119 || aw_seen || await_idle || b_pending || r_pending)
                    $fatal(1,"New write before preceding transaction/status completed");
                if (awaddr !== expected[writes][38:32]) $fatal(1,"Wrong AW %0d got=%h",writes,awaddr);
                aw_seen=1;
            end
            if (wvalid&&wready) begin
                if (!aw_seen || wdata !== expected[writes][31:0]) $fatal(1,"Wrong/missing W %0d",writes);
                writes=writes+1; aw_seen=0; b_pending=1; await_idle=1;
                b_delay=1+random_bits[5:3]; poll_index=0;
            end
            if (bvalid&&bready) begin
                if (!b_pending) $fatal(1,"Unexpected B response");
                b_pending=0;
            end
            if (arvalid&&arready) begin
                if (araddr !== 7'h24) $fatal(1,"Wrong AR address at handshake: got=%h expected=24 read=%0d",araddr,reads);
                if (r_pending || b_pending || !await_idle) $fatal(1,"Unexpected status read");
                // Two distinct busy values precede the idle value per write.
                response_word=(poll_index==0 ? 32'h400 : poll_index==1 ? 32'h800 : 32'd0) | 32'h35;
                poll_index=poll_index+1; reads=reads+1;
                r_delay=1+random_bits[8:6]; r_pending=1;
            end
            if (rvalid&&rready) begin
                if (!r_pending) $fatal(1,"Unexpected R response");
                if (rdata[11:10]==0) await_idle=0;
                r_pending=0;
            end
            if (done && (writes!=119 || reads!=357 || await_idle || b_pending || r_pending))
                $fatal(1,"Premature confdone writes=%0d reads=%0d",writes,reads);
            checks=checks+1;
        end
    end
    task reset_controller;
        begin
            #2; rst_n=0; #1;
            if ({awvalid,wvalid,bready,arvalid,rready,done} !== 0) $fatal(1,"Async reset did not clear AXI/done");
            repeat(6) @(negedge clk);
            #1; rst_n=1;
        end
    endtask
    task finish_configuration;
        integer prior_writes,prior_reads;
        begin
            wait(done===1'b1); @(negedge clk);
            prior_writes=writes; prior_reads=reads;
            repeat(12) @(negedge clk);
            if (writes!=119 || reads!=357 || prior_writes!=writes || prior_reads!=reads)
                $fatal(1,"Missing writes/reads or requests after completion");
            runs=runs+1;
        end
    endtask
    initial begin
        $readmemh(".cache/panel_axi_expected.mem",expected);
        reset_controller(); finish_configuration();
        reset_controller(); finish_configuration();
        reset_controller();
        wait(writes==5 && arvalid===1'b1);
        reset_controller(); finish_configuration();
        $display("PASS panel_axi complete_runs=%0d writes_per_run=%0d status_reads_per_run=%0d stalls=%0d checks=%0d aborted_read_reset=PASS",runs,writes,reads,stalls,checks);
        $finish;
    end
    initial begin #2000000; $fatal(1,"Panel AXI timeout writes=%0d reads=%0d",writes,reads); end
endmodule
