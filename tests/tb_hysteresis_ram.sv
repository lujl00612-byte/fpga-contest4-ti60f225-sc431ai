`timescale 1ns/1ps
// Production controller/engine; independent BFS and readback of all packed cells.
module tb_hysteresis_ram #(parameter W=40,H=80,SCENES=4,CACHED=1,CACHE_WORDS=2);
    localparam P=W*H,WORDS=P/5,AB=$clog2(P),WB=$clog2(WORDS);
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,start=0,capture_we=0,video_en=0;
    reg [WB-1:0] capture_addr=0,video_addr=0;reg [19:0] capture_word=0;
    wire busy,done,error,valid,write,ready;wire [AB-1:0] addr;wire [3:0] wdata,rdata;
    wire [AB:0] accepted;wire [31:0] cycles;wire [19:0] video_word;
    canny_hysteresis_exact #(.WIDTH(W),.HEIGHT(H)) engine(
        .clk(clk),.rst_n(rst_n),.start(start),.busy(busy),.done(done),.error(error),
        .mem_valid(valid),.mem_write(write),.mem_addr(addr),.mem_wdata(wdata),.mem_ready(ready),.mem_rdata(rdata),
        .accepted_pixels(accepted),.cycles(cycles));
    canny_tag_memory #(.CELLS(P)) memory(
        .clk(clk),.rst_n(rst_n),.capture_we(capture_we),.capture_addr(capture_addr),.capture_word(capture_word),
        .req_valid(valid),.req_write(write),.req_addr(addr),.req_wdata(wdata),.req_ready(ready),.req_rdata(rdata),
        .video_en(video_en),.video_addr(video_addr),.video_word(video_word));
    integer source[0:P-1],queue[0:P-1];bit expected[0:P-1];
    integer scene,i,j,a,nx,ny,n,head,tail,timeout,transactions=0,writes=0,checks=0,request_wait=0;
    integer hits=0,ram_reads=0,expected_cycles=4,recent_count=0,model_index,k;
    integer recent_words[0:1];
    reg model_hit,previous_video=0;
    reg pending=0,pwrite;reg [AB-1:0] paddr;reg [3:0] pdata;
    always @(posedge clk)begin
        if(!rst_n)begin pending=0;request_wait=0;recent_count=0;previous_video=0;end
        else if(ready)begin
            if(!valid||!pending)$fatal(1,"RAM response without held request");
            if(addr!==paddr||write!==pwrite||(write&&wdata!==pdata))$fatal(1,"request changed at acknowledgement");
            if(request_wait+1!=expected_cycles)$fatal(1,"RAM response latency: expected=%0d actual=%0d",expected_cycles,request_wait+1);
            transactions=transactions+1;if(write)writes=writes+1;
            if(expected_cycles==3)hits=hits+1;
            // Independent bounded MRU list models the cache contract, without
            // reading internal controller state, entry tags or swap controls.
            if(CACHED)begin
                model_index=recent_count;
                for(k=0;k<recent_count;k=k+1)if(recent_words[k]==addr/5)model_index=k;
                if(model_index==recent_count&&recent_count<CACHE_WORDS)recent_count=recent_count+1;
                if(model_index>=CACHE_WORDS)model_index=CACHE_WORDS-1;
                for(k=model_index;k>0;k=k-1)recent_words[k]=recent_words[k-1];
                recent_words[0]=addr/5;
            end
            pending=0;request_wait=0;
        end else if(valid)begin
            if(addr>=P)$fatal(1,"request outside ROI");
            if(!pending)begin
                pending=1;paddr=addr;pwrite=write;pdata=wdata;request_wait=0;
                model_hit=0;
                for(k=0;k<recent_count;k=k+1)if(recent_words[k]==addr/5)model_hit=1;
                expected_cycles=(CACHED&&model_hit&&!(capture_we||video_en||previous_video))?3:4;
            end
            else if(addr!==paddr||write!==pwrite||(write&&wdata!==pdata))$fatal(1,"request changed while waiting");
            request_wait=request_wait+1;
        end
        if(rst_n)begin
            if(memory.ram_re&&!video_en)ram_reads=ram_reads+1;
            if(capture_we||video_en||previous_video)recent_count=0;
            previous_video=video_en;
        end
    end
    task reference;
        begin
            head=0;tail=0;
            for(i=0;i<P;i=i+1)begin expected[i]=source[i]==2;if(expected[i])begin queue[tail]=i;tail=tail+1;end end
            while(head<tail)begin
                a=queue[head];head=head+1;
                for(j=0;j<9;j=j+1)if(j!=4)begin
                    nx=a%W+j%3-1;ny=a/W+j/3-1;n=ny*W+nx;
                    if(nx>=0&&nx<W&&ny>=0&&ny<H&&!expected[n]&&source[n]!=0)begin
                        expected[n]=1;queue[tail]=n;tail=tail+1;
                    end
                end
            end
        end
    endtask
    reg [19:0] packed_input;reg [3:0] tag;
    initial begin
        if(P%5!=0)$fatal(1,"test requires complete packed words");
        if(CACHE_WORDS<1||CACHE_WORDS>2)$fatal(1,"monitor supports one or two cached words");
        repeat(4)@(negedge clk);rst_n=1;
        for(scene=0;scene<SCENES;scene=scene+1)begin
            for(i=0;i<P;i=i+1)begin
                case(scene)
                    0,1:source[i]=1;
                    2:source[i]=$urandom_range(0,99)<55?1:0;
                    default:source[i]=((i/W)%4==0||i%W==0)?1:0;
                endcase
            end
            if(scene==1||scene==3)source[0]=2;
            if(scene==2)for(i=0;i<12;i=i+1)source[$urandom_range(0,P-1)]=2;
            reference();
            for(a=0;a<WORDS;a=a+1)begin
                packed_input=0;for(j=0;j<5;j=j+1)packed_input[j*4+:4]=source[a*5+j];
                @(negedge clk);capture_we=1;capture_addr=a;capture_word=packed_input;
            end
            @(negedge clk);capture_we=0;transactions=0;writes=0;hits=0;ram_reads=0;start=1;
            @(negedge clk);start=0;timeout=0;
            while(!done&&timeout<54*P+2)begin
                @(negedge clk);timeout=timeout+1;
                if(P>=307200&&timeout%1000000==0)$display("progress scene=%0d cycles=%0d",scene,cycles);
            end
            if(!done||error||accepted!==tail)$fatal(1,"engine result mismatch scene=%0d",scene);
            if(transactions>P+10*tail||writes!=tail)$fatal(1,"linear work bound or write count failed");
            if(ram_reads+hits!=transactions)$fatal(1,"physical RAM reads do not match cache misses");
            if(cycles+hits>5*P+49*tail+2)$fatal(1,"production RAM cycle bound failed");
            for(a=0;a<WORDS;a=a+1)begin
                @(negedge clk);video_en=1;video_addr=a;
                // The read is accepted at the first edge and the selected
                // word is registered at the second, independent of engine hits.
                repeat(2)begin @(posedge clk);#1;end
                for(j=0;j<5;j=j+1)begin
                    tag=video_word[j*4+:4];
                    if((tag>=3)!==expected[a*5+j])$fatal(1,"packed cell mismatch scene=%0d cell=%0d tag=%0d",scene,a*5+j,tag);
                    if(!expected[a*5+j]&&tag!==source[a*5+j])$fatal(1,"untouched cell was modified");
                    checks=checks+1;
                end
            end
            @(negedge clk);video_en=0;
            $display("PASS production RAM scene=%0d pixels=%0d accepted=%0d cycles=%0d transactions=%0d writes=%0d cache_hits=%0d ram_reads=%0d four_cycle_equivalent=%0d",scene,P,accepted,cycles,transactions,writes,hits,ram_reads,cycles+hits);
            repeat(5)@(negedge clk);
        end
        $display("PASS production RAM total: %0d packed-cell checks, BFS, %0d-cycle hit / 4-cycle miss handshake and linear bounds",checks,CACHED?3:4);$finish;
    end
endmodule
