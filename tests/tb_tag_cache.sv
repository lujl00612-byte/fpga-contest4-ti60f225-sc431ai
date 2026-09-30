`timescale 1ns/1ps
// Exercise ownership changes and aborted writes with the production controller
// and vendor RAM. Expected data is kept per cell, independently of word packing.
module tb_tag_cache #(parameter CACHE_WORDS=2);
    localparam P=5200,WORDS=P/5,AB=$clog2(P),WB=$clog2(WORDS);
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,capture_we=0,valid=0,write=0,video_en=0;
    reg [WB-1:0] capture_addr=0,video_addr=0;reg [19:0] capture_word=0;
    reg [AB-1:0] addr=0;reg [3:0] wdata=0;
    wire ready;wire [3:0] rdata;wire [19:0] video_word;
    canny_tag_memory #(.CELLS(P)) memory(
        .clk(clk),.rst_n(rst_n),.capture_we(capture_we),.capture_addr(capture_addr),.capture_word(capture_word),
        .req_valid(valid),.req_write(write),.req_addr(addr),.req_wdata(wdata),.req_ready(ready),.req_rdata(rdata),
        .video_en(video_en),.video_addr(video_addr),.video_word(video_word));
    reg [3:0] cells[0:P-1];
    integer checks=0,hits=0,misses=0,i,r,word_index,recent_count=0;
    integer recent_words[0:1];
    task capture(input integer word_index,input [19:0] data);
        integer lane;
        begin
            @(negedge clk);capture_we=1;capture_addr=word_index;capture_word=data;
            @(posedge clk);#1;
            for(lane=0;lane<5;lane=lane+1)cells[word_index*5+lane]=data[lane*4+:4];
            recent_count=0;
            @(negedge clk);capture_we=0;
        end
    endtask
    task access(input integer address,input bit do_write,input [3:0] data,input integer latency);
        integer elapsed,expected_latency,index,k;bit acknowledged;reg [3:0] old_tag;
        begin
            old_tag=cells[address];elapsed=0;acknowledged=0;
            expected_latency=4;
            for(k=0;k<recent_count;k=k+1)if(recent_words[k]==address/5)expected_latency=3;
            if(latency>=0&&latency!=expected_latency)$fatal(1,"directed test cache expectation inconsistent");
            @(negedge clk);valid=1;addr=address;write=do_write;wdata=data;
            while(!acknowledged&&elapsed<5)begin
                @(posedge clk);elapsed=elapsed+1;
                // Sample before NBA: this is the edge consuming ready, also
                // the write commit edge. Writes return the previous cell tag.
                if(ready)begin
                    if(rdata!==old_tag)$fatal(1,"tag mismatch addr=%0d expected=%0h got=%0h",address,old_tag,rdata);
                    acknowledged=1;
                end
                #1;
            end
            if(!acknowledged||elapsed!=expected_latency)$fatal(1,"latency addr=%0d expected=%0d got=%0d",address,expected_latency,elapsed);
            if(do_write)cells[address]=data;
            if(expected_latency==3)hits=hits+1;else misses=misses+1;
            index=recent_count;
            for(k=0;k<recent_count;k=k+1)if(recent_words[k]==address/5)index=k;
            if(index==recent_count&&recent_count<CACHE_WORDS)recent_count=recent_count+1;
            if(index>=CACHE_WORDS)index=CACHE_WORDS-1;
            for(k=index;k>0;k=k-1)recent_words[k]=recent_words[k-1];
            recent_words[0]=address/5;
            checks=checks+2;
            @(negedge clk);valid=0;write=0;
        end
    endtask
    task video(input integer word_index);
        integer lane;
        begin
            @(negedge clk);video_en=1;video_addr=word_index;
            repeat(2)begin @(posedge clk);#1;end
            recent_count=0;
            for(lane=0;lane<5;lane=lane+1)begin
                if(video_word[lane*4+:4]!==cells[word_index*5+lane])
                    $fatal(1,"video/neighbors mismatch word=%0d lane=%0d",word_index,lane);
                checks=checks+1;
            end
            @(negedge clk);video_en=0;
            repeat(2)@(negedge clk);
        end
    endtask
    task reset_cache;
        begin
            @(negedge clk);rst_n=0;valid=0;write=0;recent_count=0;
            repeat(2)@(negedge clk);rst_n=1;
        end
    endtask
    task abort_write(input integer address,input integer latency);
        begin
            @(negedge clk);valid=1;write=1;addr=address;wdata=cells[address]^4'hf;
            repeat(latency-1)@(posedge clk);
            #1;if(!ready)$fatal(1,"abort test did not reach response");
            // Reset before ready is consumed; the speculative cached write
            // must be discarded and the RAM word must remain unchanged.
            reset_cache();
            access(address,0,0,4);
            video(address/5);
            checks=checks+1;
        end
    endtask
    initial begin
        for(i=0;i<P;i=i+1)cells[i]=0;
        repeat(4)@(negedge clk);rst_n=1;
        capture(0,20'h54321);capture(512,20'habcde);capture(1039,20'h13579);
        access(0,0,0,4);access(1,0,0,3);access(4,1,4'hf,3);access(4,0,0,3);
        for(i=0;i<4;i=i+1)access(i,0,0,3);
        access(2560,0,0,4);access(2564,1,4'h6,3);access(2563,0,0,3);
        // Revisit the displaced word, then the other bank. Both hits must use
        // their own modified data, and a third word must evict the least recent.
        access(1,1,4'h8,CACHE_WORDS==2?3:4);
        access(2564,0,0,CACHE_WORDS==2?3:4);
        access(0,0,0,CACHE_WORDS==2?3:4);
        access(5195,0,0,4);access(2,0,0,CACHE_WORDS==2?3:4);
        access(2564,0,0,4);
        capture(512,20'hfedcb);
        access(2560,0,0,4);access(0,0,0,4); // capture invalidates both entries
        access(2564,0,0,CACHE_WORDS==2?3:4);
        video(1039);access(2561,0,0,4);access(2562,0,0,3);
        access(0,0,0,4); // populate the other entry before reset
        reset_cache();access(2562,0,0,4);access(0,0,0,4);
        access(2563,0,0,CACHE_WORDS==2?3:4);
        access(5199,1,4'h8,4);access(5199,0,0,3);video(1039);
        access(0,0,0,4);abort_write(2,3); // primary-entry write aborted before ACK
        access(0,0,0,4);access(2560,0,0,4);
        abort_write(2,CACHE_WORDS==2?3:4); // displaced-entry write aborted before ACK
        abort_write(2562,4);             // RAM miss write aborted before ACK
        for(r=0;r<120;r=r+1)begin
            case($urandom_range(0,2))0:word_index=0;1:word_index=512;default:word_index=1039;endcase
            access(word_index*5+$urandom_range(0,4),$urandom_range(0,1),$urandom_range(0,15),-1);
        end
        video(0);video(512);video(1039);
        $display("PASS tag cache: %0d data/latency/coherence checks, hits=%0d misses=%0d, words=%0d, capture/video/reset/eviction/aborted primary, displaced and miss writes",checks,hits,misses,CACHE_WORDS);
        $finish;
    end
endmodule
