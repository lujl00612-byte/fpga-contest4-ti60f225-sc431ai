`timescale 1ns/1ps
module tb_filters;
    localparam W=32,H=20;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,de=0,hs=0,vs=0,bypass=0;
    reg [23:0] rgb=0;reg [7:0] gray=0;
    wire [7:0] med,gauss,ggray;wire [23:0] mrgb,grgb,srgb;
    wire md,mh,mv,gd,gh,gv,sd,sh,sv;wire [12:0] mag;wire [1:0] dir;
    median3x3_rgb #(.WIDTH(W),.X_BITS(6),.Y_BITS(6)) m(
        .clk(clk),.rst_n(rst_n),.in_r(rgb[23:16]),.in_g(rgb[15:8]),.in_b(rgb[7:0]),
        .in_de(de),.in_hs(hs),.in_vs(vs),.bypass_i(bypass),.out_gray(med),.out_rgb(mrgb),.out_de(md),.out_hs(mh),.out_vs(mv));
    gaussian3x3_rgb_aligned #(.WIDTH(W),.X_BITS(6),.Y_BITS(6)) g(
        .clk(clk),.rst_n(rst_n),.in_gray(gray),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),.bypass_i(bypass),
        .out_gray(gauss),.out_rgb(grgb),.out_de(gd),.out_hs(gh),.out_vs(gv));
    sobel_gradient_direction #(.WIDTH(W),.X_BITS(6),.Y_BITS(6)) s(
        .clk(clk),.rst_n(rst_n),.in_gray(gray),.in_rgb(rgb),.in_de(de),.in_hs(hs),.in_vs(vs),
        .out_mag(mag),.out_dir(dir),.out_gray(ggray),.out_rgb(srgb),.out_de(sd),.out_hs(sh),.out_vs(sv));
    integer pixels[0:H-1][0:W-1];reg [23:0] colors[0:H-1][0:W-1];
    integer eqm[0:4],eqg[0:4],eqs[0:4];reg [23:0] eqr[0:4];
    reg [2:0] eqc[0:4];integer checks=0,x,y,f,i,j,a,b,tmp,gx,gy,sum,values[0:8];
    function integer rgb_gray(input reg [23:0] c);
        rgb_gray=(77*c[23:16]+150*c[15:8]+29*c[7:0])/256;
    endfunction
    task tick(input integer px,input integer py,input bit valid,input bit v);
        integer em,eg,es;reg [23:0] er;
        begin
            @(negedge clk);de=valid;vs=v;hs=!valid;rgb=valid?colors[py][px]:0;gray=valid?pixels[py][px]:0;
            em=0;eg=0;es=0;er=0;
            if(valid&&px>=3&&py>=3)begin
                i=0;sum=0;
                for(a=0;a<3;a=a+1)for(b=0;b<3;b=b+1)begin
                    values[i]=rgb_gray(colors[py-2+a][px-2+b]);i=i+1;
                    sum=sum+pixels[py-2+a][px-2+b]*((a==1)?2:1)*((b==1)?2:1);
                end
                // Independent insertion sort of all nine samples.
                for(a=1;a<9;a=a+1)begin
                    tmp=values[a];b=a-1;
                    while(b>=0&&values[b]>tmp)begin values[b+1]=values[b];b=b-1;end
                    values[b+1]=tmp;
                end
                er=colors[py-1][px-1];em=bypass?rgb_gray(er):values[4];
                eg=bypass?pixels[py-1][px-1]:sum/16;
                gx=pixels[py-2][px]+2*pixels[py-1][px]+pixels[py][px]
                  -pixels[py-2][px-2]-2*pixels[py-1][px-2]-pixels[py][px-2];
                gy=pixels[py][px-2]+2*pixels[py][px-1]+pixels[py][px]
                  -pixels[py-2][px-2]-2*pixels[py-2][px-1]-pixels[py-2][px];
                es=((gx<0)?-gx:gx)+((gy<0)?-gy:gy);
            end
            for(j=4;j>0;j=j-1)begin eqm[j]=eqm[j-1];eqg[j]=eqg[j-1];eqs[j]=eqs[j-1];eqr[j]=eqr[j-1];eqc[j]=eqc[j-1];end
            eqm[0]=em;eqg[0]=eg;eqs[0]=es;eqr[0]=er;eqc[0]={de,hs,vs};
            @(posedge clk);#1;
            if({md,mh,mv}!==eqc[4]||med!==eqm[4]||mrgb!==eqr[4])
                $fatal(1,"median frame=%0d x=%0d y=%0d got=%0d expected=%0d RGB=%h/%h",f,px,py,med,eqm[4],mrgb,eqr[4]);
            if({gd,gh,gv}!==eqc[2]||gauss!==eqg[2]||grgb!==eqr[2])$fatal(1,"Gaussian got=%0d expected=%0d",gauss,eqg[2]);
            if({sd,sh,sv}!==eqc[2]||mag!==eqs[2]||srgb!==eqr[2])$fatal(1,"Sobel L1 got=%0d expected=%0d",mag,eqs[2]);
            checks=checks+3;
        end
    endtask
    initial begin
        for(j=0;j<5;j=j+1)begin eqm[j]=0;eqg[j]=0;eqs[j]=0;eqr[j]=0;eqc[j]=0;end
        repeat(4)@(posedge clk);@(negedge clk);rst_n=1;
        for(f=0;f<8;f=f+1)begin
            bypass=f%2;
            for(y=0;y<H;y=y+1)for(x=0;x<W;x=x+1)begin
                colors[y][x]=$urandom;pixels[y][x]=f<4?rgb_gray(colors[y][x]):(((x>=W/2)^(y>=H/2))?255:0);
            end
            tick(0,0,0,1);repeat(8)tick(0,0,0,0);
            for(y=0;y<H;y=y+1)begin
                for(x=0;x<W;x=x+1)tick(x,y,1,0);
                repeat(8)tick(0,0,0,0);
            end
            repeat(8)tick(0,0,0,0);
        end
        $display("PASS filters: %0d checks; independent median, Gaussian and L1 Sobel references",checks);$finish;
    end
endmodule
