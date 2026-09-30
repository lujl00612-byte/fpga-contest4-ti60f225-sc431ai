`timescale 1ns/1ps
module tb_hysteresis_scale;
    localparam W=640,H=480,P=W*H;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,start=0,ready=0;reg [3:0] rdata=0;
    wire busy,done,error,valid,write;wire [18:0] addr;wire [3:0] wdata;wire [19:0] accepted;wire [31:0] cycles;
    canny_hysteresis_exact dut(.clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),.error(error),
        .mem_valid(valid),.mem_write(write),.mem_addr(addr),.mem_wdata(wdata),.mem_ready(ready),.mem_rdata(rdata),
        .accepted_pixels(accepted),.cycles(cycles));
    reg [3:0] memory[0:P-1];integer i,scene,timeout,transactions=0;
    always @(posedge clk)begin
        if(!rst_n)ready<=0;
        else if(ready)ready<=0;
        else if(valid)begin
            if(addr>=P)$fatal(1,"address outside full-size frame");
            if(write)memory[addr]<=wdata;else rdata<=memory[addr];
            ready<=1;transactions<=transactions+1;
        end
    end
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        for(scene=0;scene<2;scene=scene+1)begin
            for(i=0;i<P;i=i+1)memory[i]=1;
            // No seed rejects every weak edge; one seed in a full grid accepts every pixel.
            if(scene==1)memory[0]=2;
            transactions=0;@(negedge clk);start=1;@(negedge clk);start=0;timeout=0;
            while(!done&&timeout<P*60)begin @(negedge clk);timeout=timeout+1;end
            if(!done||error)$fatal(1,"full-size connectivity failed");
            if(accepted!==(scene==0?0:P))$fatal(1,"full-size accepted count incorrect");
            for(i=0;i<P;i=i+1)if((memory[i]>=3)!==(scene==1))$fatal(1,"full-size pixel %0d incorrect",i);
            if(transactions>P+10*accepted)$fatal(1,"linear transaction bound exceeded");
            $display("PASS full-size scene=%0d pixels=%0d accepted=%0d cycles=%0d transactions=%0d",scene,P,accepted,cycles,transactions);
            repeat(5)@(negedge clk);
        end
        $finish;
    end
endmodule
