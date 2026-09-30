`timescale 1ns/1ps
module tb_hysteresis_exact;
    localparam W=32,H=24,P=W*H;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,start=0,ready=0;reg [3:0] rdata=0;
    wire busy,done,error,valid,write;wire [9:0] addr;wire [3:0] wdata;wire [10:0] accepted;wire [31:0] cycles;
    canny_hysteresis_exact #(.WIDTH(W),.HEIGHT(H)) dut(.clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),.error(error),
        .mem_valid(valid),.mem_write(write),.mem_addr(addr),.mem_wdata(wdata),.mem_ready(ready),.mem_rdata(rdata),
        .accepted_pixels(accepted),.cycles(cycles));
    reg [3:0] memory[0:P-1];integer source[0:P-1];bit expected[0:P-1];integer queue[0:P-1];
    integer delay_left=0;reg pending=0,pwrite=0;reg [9:0] paddr;reg [3:0] pdata;
    integer transactions=0,f,i,j,x,y,head,tail,v,nx,ny,n,expected_count,checks=0,timeout;
    // Variable-latency memory with a one-cycle response. Check request stability while stalled.
    always @(posedge clk)begin
        if(!rst_n)begin ready<=0;pending<=0;delay_left<=0;end
        else if(ready)ready<=0;
        else if(pending)begin
            if(!valid||addr!==paddr||write!==pwrite||(write&&wdata!==pdata))$fatal(1,"memory request changed while waiting");
            if(delay_left==0)begin
                if(pwrite)memory[paddr]<=pdata;else rdata<=memory[paddr];
                ready<=1;pending<=0;transactions<=transactions+1;
            end else delay_left<=delay_left-1;
        end else if(valid)begin
            if(addr>=P)$fatal(1,"memory address outside frame");
            pending<=1;paddr<=addr;pwrite<=write;pdata<=wdata;delay_left<=$urandom_range(0,3);
        end
    end
    task reference;
        begin
            head=0;tail=0;expected_count=0;
            for(i=0;i<P;i=i+1)begin
                expected[i]=(source[i]==2);
                if(expected[i])begin queue[tail]=i;tail=tail+1;end
            end
            // Independent multi-source BFS of every strong seed.
            while(head<tail)begin
                v=queue[head];head=head+1;x=v%W;y=v/W;
                for(j=0;j<9;j=j+1)if(j!=4)begin
                    nx=x+(j%3)-1;ny=y+(j/3)-1;n=ny*W+nx;
                    if(nx>=0&&nx<W&&ny>=0&&ny<H&&!expected[n]&&source[n]!=0)begin
                        expected[n]=1;queue[tail]=n;tail=tail+1;
                    end
                end
            end
            expected_count=tail;
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        for(f=0;f<24;f=f+1)begin
            for(i=0;i<P;i=i+1)begin
                case(f)
                    0:source[i]=0;
                    1:source[i]=1;
                    2:source[i]=2;
                    3:source[i]=(i%W==W/2)?1:0;
                    4:source[i]=((i%W==4||i%W==W-5)&&i/W>=4&&i/W<=H-5)||
                                 ((i/W==4||i/W==H-5)&&i%W>=4&&i%W<=W-5)?1:0;
                    5:source[i]=(i%W==i/W)?1:0;
                    default:source[i]=$urandom_range(0,99)<55?1:0;
                endcase
            end
            if(f==3)source[W/2]=2;
            if(f==4)source[4*W+4]=2;
            if(f==5)source[0]=2;
            if(f>=6)for(i=0;i<12;i=i+1)source[$urandom_range(0,P-1)]=2;
            for(i=0;i<P;i=i+1)memory[i]=source[i];
            reference();transactions=0;
            @(negedge clk);start=1;@(negedge clk);start=0;timeout=0;
            while(!done&&timeout<P*160)begin @(negedge clk);timeout=timeout+1;end
            if(!done||error)$fatal(1,"hysteresis did not complete frame=%0d",f);
            if(accepted!==expected_count)$fatal(1,"accepted count mismatch frame=%0d",f);
            for(i=0;i<P;i=i+1)begin
                if((memory[i]>=3)!==expected[i])$fatal(1,"connectivity mismatch frame=%0d pixel=%0d",f,i);
                checks=checks+1;
            end
            if(transactions>P+10*expected_count)$fatal(1,"nonlinear work: transactions=%0d",transactions);
            $display("hysteresis frame=%0d accepted=%0d cycles=%0d transactions=%0d",f,accepted,cycles,transactions);
            repeat(5)@(negedge clk);
        end
        $display("PASS exact hysteresis: %0d pixels, 24 frames; BFS reference, chains, loops, diagonals and stalls",checks);$finish;
    end
endmodule
