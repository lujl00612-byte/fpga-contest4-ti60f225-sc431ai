`timescale 1ns/1ps
module tb_snapshot;
    localparam W=80,H=28,RW=40,RH=24,P=RW*RH;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=0,de=0,hs=0,vs=0;reg [10:0] threshold=96;
    reg [1:0] classification=0;reg [23:0] rgb=0;
    wire [23:0] out_rgb;wire od,oh,ov,ready,busy,error;wire [31:0] cycles;wire [10:0] accepted;
    canny_snapshot_exact #(.WIDTH(W),.ROI_WIDTH(RW),.ROI_HEIGHT(RH),.X_BITS(7),.Y_BITS(6),.SETTLE_FRAMES(1)) dut(
        .clk(clk),.rst_n(rst_n),.enable_i(enable),.threshold_i(threshold),.class_i(classification),.rgb_i(rgb),
        .de_i(de),.hs_i(hs),.vs_i(vs),.rgb_o(out_rgb),.de_o(od),.hs_o(oh),.vs_o(ov),
        .result_ready(ready),.engine_busy(busy),.engine_error(error),.processing_cycles(cycles),.accepted_pixels(accepted));
    integer source[0:P-1],queue[0:P-1];bit expected[0:P-1];
    reg [23:0] expected_rgb[0:2];reg [2:0] expected_control[0:2];bit score[0:2];
    integer x,y,f,i,j,a,nx,ny,n,head,tail,scenario,checks=0,roi_checks=0,ready_frames,white_unused;
    task reference;
        begin
            head=0;tail=0;
            for(i=0;i<P;i=i+1)begin expected[i]=source[i]==2;if(expected[i])begin queue[tail]=i;tail=tail+1;end end
            while(head<tail)begin
                a=queue[head];head=head+1;
                for(j=0;j<9;j=j+1)if(j!=4)begin
                    nx=a%RW+j%3-1;ny=a/RW+j/3-1;n=ny*RW+nx;
                    if(nx>=0&&nx<RW&&ny>=0&&ny<RH&&!expected[n]&&source[n]!=0)begin
                        expected[n]=1;queue[tail]=n;tail=tail+1;
                    end
                end
            end
        end
    endtask
    task tick(input bit valid,input bit v,input integer px,input integer py);
        reg [23:0] er;bit scored;
        begin
            @(negedge clk);de=valid;hs=!valid;vs=v;rgb=valid?24'h305060:0;
            classification=(valid&&px>=W/2&&py<RH)?source[py*RW+px-W/2]:0;
            scored=ready&&valid;er=rgb;
            if(valid&&px<W/2)er=24'h484848;
            else if(valid&&py>=RH&&py<RH+3)er=ready?24'h00ff40:24'hffd000;
            else if(ready&&valid&&py<RH&&expected[py*RW+px-W/2])er=24'hff0000;
            for(i=2;i>0;i=i-1)begin expected_rgb[i]=expected_rgb[i-1];expected_control[i]=expected_control[i-1];score[i]=score[i-1];end
            expected_rgb[0]=er;expected_control[0]={de,hs,vs};score[0]=scored;
            @(posedge clk);#1;
            if({od,oh,ov}!==expected_control[2])$fatal(1,"snapshot timing mismatch");
            if(error)$fatal(1,"snapshot DFS error");
            if(score[2]&&out_rgb!==expected_rgb[2])$fatal(1,"snapshot mismatch x=%0d y=%0d got=%h expected=%h",px,py,out_rgb,expected_rgb[2]);
            if(score[2])roi_checks=roi_checks+1;
            checks=checks+1;
        end
    endtask
    initial begin
        for(i=0;i<3;i=i+1)begin expected_rgb[i]=0;expected_control[i]=0;score[i]=0;end
        repeat(4)@(negedge clk);rst_n=1;
        for(scenario=0;scenario<2;scenario=scenario+1)begin
            for(i=0;i<P;i=i+1)source[i]=0;
            if(scenario==0)begin
                for(i=1;i<RW-1;i=i+1)source[12*RW+i]=1;
                source[12*RW+1]=2;
                for(i=5;i<12;i=i+1)source[3*RW+i]=1;
                for(i=0;i<12;i=i+1)source[i*RW+i]=1;
                source[0]=2;
            end else begin
                for(i=0;i<P;i=i+1)source[i]=$urandom_range(0,99)<40?1:0;
                for(i=0;i<10;i=i+1)source[$urandom_range(0,P-1)]=2;
            end
            reference();ready_frames=0;
            for(f=0;f<65&&ready_frames<3;f=f+1)begin
                enable=(f!=0);threshold=96+scenario;
                tick(0,1,0,0);repeat(6)tick(0,0,0,0);
                if(ready)begin ready_frames=ready_frames+1;if(accepted!==tail)$fatal(1,"snapshot accepted mismatch");end
                for(y=0;y<H;y=y+1)begin
                    for(x=0;x<W;x=x+1)tick(1,0,x,y);
                    repeat(8)tick(0,0,0,0);
                end
                repeat(8)tick(0,0,0,0);
            end
            if(ready_frames<3)$fatal(1,"snapshot never published");
            $display("snapshot scenario=%0d accepted=%0d processing_cycles=%0d frames=%0d",scenario,accepted,cycles,f);
        end
        if(roi_checks<1000)$fatal(1,"too few output comparisons");
        $display("PASS snapshot: %0d timing checks, %0d colored-output checks, packed RAM, recapture and frame publication",checks,roi_checks);$finish;
    end
endmodule
