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
} finally {Pop-Location}
