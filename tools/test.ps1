$ErrorActionPreference='Stop'
$repoRoot=Split-Path $PSScriptRoot -Parent
$env:PATH='E:\msys2\ucrt64\bin;'+$env:PATH
$iverilog='E:\msys2\ucrt64\bin\iverilog.exe'
$vvp='E:\msys2\ucrt64\bin\vvp.exe'
$cache=Join-Path $repoRoot '.cache'
New-Item -ItemType Directory -Path $cache -Force | Out-Null
Push-Location -LiteralPath $repoRoot
try {
    & $iverilog -g2012 -s tb_white_balance -o (Join-Path $cache 'white_balance.vvp') 'tests/tb_white_balance.sv' 'projects/mipi/rtl/video_white_balance.v'
    if($LASTEXITCODE -ne 0){throw 'White balance simulation compile failed'}
    & $vvp (Join-Path $cache 'white_balance.vvp')
    if($LASTEXITCODE -ne 0){throw 'White balance simulation failed'}
    $suites=@(
        @{name='filters';sources=@('projects/hdmi/rtl/contest4_sobel_display.v')},
        @{name='controls';sources=@('projects/hdmi/rtl/threshold_control.v','projects/hdmi/rtl/frame_freeze_control.v')},
        @{name='shapes';sources=@('projects/hdmi/rtl/shape_overlay.v')},
        @{name='hysteresis_exact';sources=@('projects/hdmi/rtl/canny_hysteresis_exact.v')},
        @{name='snapshot';sources=@('projects/hdmi/rtl/canny_hysteresis_exact.v','projects/hdmi/rtl/canny_tag_memory.v','projects/hdmi/rtl/canny_snapshot_exact.v')}
    )
    foreach($suite in $suites){
        $name=$suite.name
        $args=@('-g2012','-s',('tb_'+$name),'-o',(Join-Path $cache ($name+'.vvp')),('tests/tb_'+$name+'.sv'))+$suite.sources
        & $iverilog @args
        if($LASTEXITCODE -ne 0){throw "$name simulation compile failed"}
        & $vvp (Join-Path $cache ($name+'.vvp'))
        if($LASTEXITCODE -ne 0){throw "$name simulation failed"}
    }
} finally {Pop-Location}
