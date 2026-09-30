# Run from the A13 checkout with a fresh build name; existing releases are protected.
# Actual original build: .\tools\build.ps1 -Target hdmi -Version A13
param([string]$BuildVersion='A13-reproduce')
$ErrorActionPreference='Stop'
$env:PATH='E:\msys2\ucrt64\bin;'+$env:PATH
$iv='E:\msys2\ucrt64\bin\iverilog.exe'
$vv='E:\msys2\ucrt64\bin\vvp.exe'
function Simulate($name,$arguments){
    & $iv @arguments
    if($LASTEXITCODE -ne 0){throw "$name compile failed"}
    & $vv ('.cache/'+$name+'.vvp') 2>&1 | Tee-Object -FilePath ('.cache/'+$name+'.log')
    if($LASTEXITCODE -ne 0){throw "$name simulation failed"}
}
New-Item -ItemType Directory -Path .cache -Force | Out-Null
@'
from pathlib import Path
import subprocess
Path('.cache/A13-A12-canny_tag_memory.v').write_bytes(subprocess.check_output([r'E:\Git\cmd\git.exe','show','A12:projects/hdmi/rtl/canny_tag_memory.v']))
'@ | & 'C:\Python314\python.exe' -
if($LASTEXITCODE -ne 0){throw 'A12 source extraction failed'}
$engine='projects/hdmi/rtl/canny_hysteresis_exact.v'
$memory='projects/hdmi/rtl/canny_tag_memory.v'
$vendor='../efinity2025_clean/PFiles/Efinity/2025.1/sim_models/verilog/efx_ram10.v'
$fast='tests/models/efx_ram10_20bit_fast.v'
Simulate 'A13-bank-boundaries' @('-g2012','-s','tb_tag_banks','-o','.cache/A13-bank-boundaries.vvp','tests/tb_tag_banks.sv',$memory,$vendor)
Simulate 'A13-baseline-banks' @('-g2012','-s','tb_tag_banks','-o','.cache/A13-baseline-banks.vvp','tests/tb_tag_banks.sv','.cache/A13-A12-canny_tag_memory.v',$vendor)
Simulate 'A13-banks-full' @('-g2012','-s','tb_tag_banks','-Ptb_tag_banks.WORD_COUNT=61440','-o','.cache/A13-banks-full.vvp','tests/tb_tag_banks.sv',$memory,$vendor)
& .\tools\test.ps1 2>&1 | Tee-Object -FilePath .cache/A13-regression.log
if($LASTEXITCODE -ne 0){throw 'Regression failed'}
Simulate 'A13-snapshot-banks' @('-g2012','-s','tb_snapshot','-Ptb_snapshot.RW=40','-Ptb_snapshot.RH=80','-o','.cache/A13-snapshot-banks.vvp','tests/tb_snapshot.sv',$engine,$memory,'projects/hdmi/rtl/canny_snapshot_exact.v',$vendor)
Simulate 'A13-fast-ram' @('-g2012','-s','tb_hysteresis_ram','-o','.cache/A13-fast-ram.vvp','tests/tb_hysteresis_ram.sv',$engine,$memory,$fast)
Simulate 'A13-ram-full' @('-g2012','-s','tb_hysteresis_ram','-Ptb_hysteresis_ram.W=640','-Ptb_hysteresis_ram.H=480','-Ptb_hysteresis_ram.SCENES=2','-o','.cache/A13-ram-full.vvp','tests/tb_hysteresis_ram.sv',$engine,$memory,$fast)
@'
from pathlib import Path
import re
lines=lambda p:re.findall(r'^PASS production RAM scene=.*$',Path(p).read_text(encoding='utf-8-sig'),re.M)
vendor=lines('.cache/A13-regression.log')
fast=lines('.cache/A13-fast-ram.log')
assert len(vendor)==4 and vendor==fast==lines('releases/A12/hdmi/A12-vendor-ram.txt')
full=lines('.cache/A13-ram-full.log')
assert len(full)==2 and full==lines('releases/A12/hdmi/A12-ram-full.txt')
bank=lambda p:re.findall(r'^PASS tag_banks.*$',Path(p).read_text(encoding='utf-8-sig'),re.M)
assert bank('.cache/A13-bank-boundaries.log')==bank('.cache/A13-baseline-banks.log')
print('PASS A12/A13 cycle, transaction, cache and vendor/fast comparisons')
'@ | & 'C:\Python314\python.exe' -
if($LASTEXITCODE -ne 0){throw 'Comparison failed'}
$taskA13ReproduceLog=Join-Path (Get-Location).Path ('.cache/'+$BuildVersion+'-build.log')
& .\tools\build.ps1 -Target hdmi -Version $BuildVersion 2>&1 | Tee-Object -FilePath $taskA13ReproduceLog
if($LASTEXITCODE -ne 0){throw 'Build failed'}
$manifest=Get-Content -LiteralPath ('releases/'+$BuildVersion+'/hdmi/manifest.json') -Raw | ConvertFrom-Json
if($manifest.timing_status -ne 'PASS'){throw 'Build static timing failed'}
