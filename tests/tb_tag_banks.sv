`timescale 1ns/1ps
// An independent per-cell scoreboard checks continuously changing video
// addresses, group boundaries, cache writes and restart at the RAM interface.
module tb_tag_banks #(parameter WORD_COUNT=16*512+13,HIT_CYCLES=2);
    localparam P=WORD_COUNT*5,AB=$clog2(P),WB=$clog2(WORD_COUNT),NB=(WORD_COUNT+511)/512;
    reg clk=0,rst_n=0,capture_we=0,valid=0,write=0,video_en=0;
    reg [WB-1:0] capture_addr=0,video_addr=0;
    reg [19:0] capture_word=0;
    reg [AB-1:0] addr=0;
    reg [3:0] wdata=0;
    wire ready; wire [3:0] rdata; wire [19:0] video_word;
    reg [3:0] cells[0:P-1];
    reg [31:0] rng=32'h67efade1;
    reg previous_video=0;
    integer previous_addr=0,video_checks=0,request_checks=0,n,bank_index,lane,word_index,oldtag;
    reg [19:0] expected_video;
    always #5 clk=~clk;
    canny_tag_memory #(.CELLS(P)) memory(
        .clk(clk),.rst_n(rst_n),.capture_we(capture_we),.capture_addr(capture_addr),.capture_word(capture_word),
        .req_valid(valid),.req_write(write),.req_addr(addr),.req_wdata(wdata),.req_ready(ready),.req_rdata(rdata),
        .video_en(video_en),.video_addr(video_addr),.video_word(video_word));

    always @(posedge clk)begin:video_scoreboard
        integer k;
        reg accepted_video;
        integer accepted_addr;
        accepted_video=video_en;accepted_addr=video_addr;
        if(!rst_n)begin previous_video=0;previous_addr=0;end
        else begin
            if(previous_video)begin
                expected_video=0;
                for(k=0;k<5;k=k+1)expected_video[k*4+:4]=cells[previous_addr*5+k];
                #1;
                if(video_word!==expected_video)$fatal(1,"streaming video mismatch word=%0d expected=%h got=%h",previous_addr,expected_video,video_word);
                video_checks=video_checks+5;
            end
            previous_video=accepted_video;previous_addr=accepted_addr;
        end
    end
    task access(input integer address,input bit do_write,input [3:0] data,input integer latency);
        integer elapsed;
        bit acknowledged;
        reg [3:0] expected_tag;
        begin
            expected_tag=cells[address];elapsed=0;acknowledged=0;
            @(negedge clk);valid=1;write=do_write;addr=address;wdata=data;
            while(!acknowledged&&elapsed<5)begin
                @(posedge clk);elapsed=elapsed+1;
                if(ready)begin
                    if(rdata!==expected_tag)$fatal(1,"bank request tag mismatch addr=%0d",address);
                    acknowledged=1;
                end
                #1;
            end
            if(!acknowledged||elapsed!=latency)$fatal(1,"bank request latency addr=%0d elapsed=%0d expected=%0d",address,elapsed,latency);
            if(do_write)cells[address]=data;
            request_checks=request_checks+2;
            @(negedge clk);valid=0;write=0;
        end
    endtask
    task stop_video;
        begin
            @(negedge clk);video_en=0;
            repeat(3)@(negedge clk);
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        // Capture unique pseudorandom words; reference stores individual cells.
        for(n=0;n<WORD_COUNT;n=n+1)begin
            rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
            @(negedge clk);capture_we=1;capture_addr=n;capture_word=rng[19:0];
            for(lane=0;lane<5;lane=lane+1)cells[n*5+lane]=rng[lane*4+:4];
        end
        @(negedge clk);capture_we=0;
        // Every bank, including a partial final group and a partial final bank.
        for(bank_index=0;bank_index<NB;bank_index=bank_index+1)begin
            word_index=bank_index*512;
            access(word_index*5,0,0,4);
            access(word_index*5+1,0,0,HIT_CYCLES);
            access(word_index*5+4,1,cells[word_index*5+4]^4'hf,HIT_CYCLES);
        end
        // Swap the two cached words across distant groups; retain writes.
        access(0,0,0,4);access((WORD_COUNT-1)*5,0,0,4);
        access(4,1,4'h7,HIT_CYCLES);access((WORD_COUNT-1)*5+4,1,4'h9,HIT_CYCLES);
        access(0,0,0,HIT_CYCLES);access((WORD_COUNT-1)*5+4,0,0,HIT_CYCLES);
        // A new word each clock checks data versus the previous accepted input.
        for(n=0;n<WORD_COUNT;n=n+1)begin
            @(negedge clk);video_en=1;video_addr=n;
        end
        stop_video();
        access((WORD_COUNT-1)*5+4,0,0,4); // video invalidated both cache entries
        for(n=0;n<WORD_COUNT;n=n+1)begin
            @(negedge clk);video_en=(n%7!=3);
            if(n%2==0)video_addr=(n*257)%WORD_COUNT;
            else video_addr=WORD_COUNT-1-(n*17)%WORD_COUNT;
        end
        stop_video();
        @(negedge clk);rst_n=0;
        repeat(3)@(negedge clk);rst_n=1;
        access((WORD_COUNT-1)*5+4,0,0,4);
        for(n=0;n<NB;n=n+1)begin
            @(negedge clk);video_en=1;video_addr=(NB-1-n)*512;
        end
        stop_video();
        $display("PASS tag_banks words=%0d banks=%0d request_checks=%0d video_cell_checks=%0d; %0d/4-cycle handshake, streamed two-edge video, gaps, group boundaries, partial bank, reset",WORD_COUNT,NB,request_checks,video_checks,HIT_CYCLES);
        $finish;
    end
    initial begin #20000000; $fatal(1,"tag banks timeout");end
endmodule
