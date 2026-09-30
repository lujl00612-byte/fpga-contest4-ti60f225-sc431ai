# Run from the repository root at tag A10. Reports and bitstreams are immutable.
$ErrorActionPreference='Stop'
$env:PATH='E:\msys2\ucrt64\bin;'+$env:PATH
$iv='E:\msys2\ucrt64\bin\iverilog.exe'
$vp='E:\msys2\ucrt64\bin\vvp.exe'
$vendor='../efinity2025_clean/PFiles/Efinity/2025.1/sim_models/verilog/efx_ram10.v'
$core='projects/hdmi/rtl/canny_hysteresis_exact.v'
$ram='projects/hdmi/rtl/canny_tag_memory.v'
.\tools\test.ps1
& $iv -g2012 -s tb_snapshot '-Ptb_snapshot.RW=40' '-Ptb_snapshot.RH=80' -o .cache/snapshot_A10_banks.vvp tests/tb_snapshot.sv $core $ram projects/hdmi/rtl/canny_snapshot_exact.v $vendor
if($LASTEXITCODE -ne 0){throw 'Cross-bank compile failed'}
& $vp .cache/snapshot_A10_banks.vvp
if($LASTEXITCODE -ne 0){throw 'Cross-bank simulation failed'}
& $iv -g2012 -s tb_hysteresis_ram -o .cache/A10-fast-ram.vvp tests/tb_hysteresis_ram.sv $core $ram tests/models/efx_ram10_20bit_fast.v
if($LASTEXITCODE -ne 0){throw 'Fast RAM model compile failed'}
& $vp .cache/A10-fast-ram.vvp
if($LASTEXITCODE -ne 0){throw 'Fast RAM model simulation failed'}
& $iv -g2012 -s tb_hysteresis_ram '-Ptb_hysteresis_ram.W=640' '-Ptb_hysteresis_ram.H=480' '-Ptb_hysteresis_ram.SCENES=2' -o .cache/A10-ram-full.vvp tests/tb_hysteresis_ram.sv $core $ram tests/models/efx_ram10_20bit_fast.v
if($LASTEXITCODE -ne 0){throw 'Full-size compile failed'}
& $vp .cache/A10-ram-full.vvp
if($LASTEXITCODE -ne 0){throw 'Full-size simulation failed'}
# These baseline files were read from tag A9 via git show, byte for byte.
& $iv -g2012 -s tb_snapshot '-Ptb_snapshot.RW=40' '-Ptb_snapshot.RH=80' -o .cache/snapshot_A9_comparison.vvp tests/tb_snapshot.sv $core releases/A10/hdmi/A9-canny_tag_memory.v releases/A10/hdmi/A9-canny_snapshot_exact.v $vendor
if($LASTEXITCODE -ne 0){throw 'A9 baseline compile failed'}
& $vp .cache/snapshot_A9_comparison.vvp
if($LASTEXITCODE -ne 0){throw 'A9 baseline simulation failed'}
# Completed build: .\tools\build.ps1 -Target hdmi -Version A10
# Use a NEW unused version name if repeating a build.
