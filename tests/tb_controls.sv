`timescale 1ns/1ps
module tb_controls;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,vs=0,cam_vs=0,request=0;reg [1:0] keys=3;
    wire [1:0] level;wire [10:0] threshold;wire freeze,basic,frozen;
    threshold_control #(.LONG_PRESS_FRAMES(8)) c(.clk(clk),.rst_n(rst_n),.vs(vs),.key_n(keys),
        .level(level),.threshold(threshold),.freeze(freeze),.basic_mode(basic));
    frame_freeze_control f(.clk(clk),.rst_n(rst_n),.vs(cam_vs),.request(request),.frozen(frozen));
    integer checks=0,i,j,allowed_vs;
    task frame(input [1:0] k);
        begin @(negedge clk);keys=k;vs=0;repeat(6)@(negedge clk);vs=1;repeat(4)@(negedge clk);vs=0;#1;end
    endtask
    task expect_state(input integer l,input bit z,input bit b);
        begin if(level!==l||freeze!==z||basic!==b)$fatal(1,"controls got level=%d freeze=%b mode=%b",level,freeze,basic);checks=checks+1;end
    endtask
    task camera_frame(input bit expect_frozen,input bit next_request);
        begin
            @(negedge clk);cam_vs=1;allowed_vs=0;
            for(j=0;j<4;j=j+1)begin @(posedge clk);if(cam_vs&&!frozen)allowed_vs=allowed_vs+1;#1;@(negedge clk);end
            cam_vs=0;
            if(allowed_vs!==(expect_frozen?0:4))$fatal(1,"partial VS passed freeze gate: %0d samples",allowed_vs);
            for(j=0;j<20;j=j+1)begin
                if(j==8)request=next_request;
                @(posedge clk);#1;if(frozen!==expect_frozen)$fatal(1,"freeze changed within active frame");checks=checks+1;@(negedge clk);
            end
        end
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;
        repeat(5)frame(3);expect_state(2,0,1);
        frame(2);frame(3);frame(2);repeat(5)frame(3);expect_state(2,0,1);
        repeat(6)frame(2);expect_state(1,0,1);repeat(20)frame(2);expect_state(1,0,1);
        repeat(5)frame(3);repeat(6)frame(2);expect_state(0,0,1);
        repeat(5)frame(3);repeat(6)frame(2);expect_state(0,0,1);
        for(i=0;i<5;i=i+1)begin repeat(5)frame(3);repeat(6)frame(1);end
        expect_state(3,0,1);
        repeat(5)frame(3);repeat(6)frame(0);expect_state(3,0,1);repeat(5)frame(3);expect_state(3,1,1);
        repeat(20)frame(0);expect_state(3,1,0);repeat(5)frame(3);expect_state(3,1,0);
        camera_frame(0,1);camera_frame(1,0);camera_frame(0,0);
        $display("PASS controls: %0d checks; debounce, limits, chords, complete frames and VS pulses",checks);$finish;
    end
endmodule
