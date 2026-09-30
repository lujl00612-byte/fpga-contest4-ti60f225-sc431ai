# Commands used for this release; run from the repository root in PowerShell.
$env:PATH='E:\msys2\ucrt64\bin;'+$env:PATH
$iv='E:\msys2\ucrt64\bin\iverilog.exe'
$vp='E:\msys2\ucrt64\bin\vvp.exe'
$vendor='../efinity2025_clean/PFiles/Efinity/2025.1/sim_models/verilog/efx_ram10.v'
$core='projects/hdmi/rtl/canny_hysteresis_exact.v'
$ram='projects/hdmi/rtl/canny_tag_memory.v'
# A9-regression.txt was run before the new RAM suite was added to tools/test.ps1.
# A9-vendor-ram.txt covers that new suite separately; running the current script
# reproduces both portions. Nonzero compile or simulation exit is a failure.
.\tools\test.ps1
& $iv -g2012 -s tb_snapshot -Ptb_snapshot.RW=40 -Ptb_snapshot.RH=80 -o .cache/snapshot_A9_banks.vvp tests/tb_snapshot.sv $core $ram projects/hdmi/rtl/canny_snapshot_exact.v $vendor
& $vp .cache/snapshot_A9_banks.vvp
& $iv -g2012 -s tb_hysteresis_ram -o .cache/A9-vendor-ram.vvp tests/tb_hysteresis_ram.sv $core $ram $vendor
& $vp .cache/A9-vendor-ram.vvp
& $iv -g2012 -s tb_hysteresis_ram -o .cache/A9-fast-ram.vvp tests/tb_hysteresis_ram.sv $core $ram tests/models/efx_ram10_20bit_fast.v
& $vp .cache/A9-fast-ram.vvp
& $iv -g2012 -s tb_hysteresis_ram -Ptb_hysteresis_ram.W=640 -Ptb_hysteresis_ram.H=480 -Ptb_hysteresis_ram.SCENES=2 -o .cache/A9-ram-full.vvp tests/tb_hysteresis_ram.sv $core $ram tests/models/efx_ram10_20bit_fast.v
& $vp .cache/A9-ram-full.vvp
# Archived baseline is exactly git show A8R2:projects/hdmi/rtl/canny_tag_memory.v.
& $iv -g2012 -s tb_hysteresis_ram -Ptb_hysteresis_ram.W=640 -Ptb_hysteresis_ram.H=480 -Ptb_hysteresis_ram.SCENES=2 -o .cache/A8R2-ram-full.vvp tests/tb_hysteresis_ram.sv $core releases/A9/hdmi/A8R2-canny_tag_memory.v tests/models/efx_ram10_20bit_fast.v
& $vp .cache/A8R2-ram-full.vvp
# Already completed: reuse a NEW name if rebuilding, because releases are immutable.
# .\tools\build.ps1 -Target hdmi -Version A9
