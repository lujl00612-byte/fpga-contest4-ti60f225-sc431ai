# Run from A14 checkout with a fresh build name. Original build used Version A14.
param([string]$BuildVersion='A14-reproduce')
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
Path('.cache/A14-A13-canny_tag_memory.v').write_bytes(subprocess.check_output([r'E:\Git\cmd\git.exe','show','A13:projects/hdmi/rtl/canny_tag_memory.v']))
'@ | & 'C:\Python314\python.exe' -
if($LASTEXITCODE -ne 0){throw 'A13 source extraction failed'}
$engine='projects/hdmi/rtl/canny_hysteresis_exact.v'
$memory='projects/hdmi/rtl/canny_tag_memory.v'
$old='.cache/A14-A13-canny_tag_memory.v'
$vendor='../efinity2025_clean/PFiles/Efinity/2025.1/sim_models/verilog/efx_ram10.v'
$fast='tests/models/efx_ram10_20bit_fast.v'
& .\tools\test.ps1 2>&1 | Tee-Object -FilePath .cache/A14-regression.log
if($LASTEXITCODE -ne 0){throw 'Regression failed'}
Simulate 'A14-baseline-cache' @('-g2012','-s','tb_tag_cache','-Ptb_tag_cache.HIT_CYCLES=3','-o','.cache/A14-baseline-cache.vvp','tests/tb_tag_cache.sv',$old,$vendor)
Simulate 'A14-baseline-banks' @('-g2012','-s','tb_tag_banks','-Ptb_tag_banks.HIT_CYCLES=3','-o','.cache/A14-baseline-banks.vvp','tests/tb_tag_banks.sv',$old,$vendor)
Simulate 'A14-baseline-ram' @('-g2012','-s','tb_hysteresis_ram','-Ptb_hysteresis_ram.HIT_CYCLES=3','-o','.cache/A14-baseline-ram.vvp','tests/tb_hysteresis_ram.sv',$engine,$old,$vendor)
Simulate 'A14-banks-full' @('-g2012','-s','tb_tag_banks','-Ptb_tag_banks.WORD_COUNT=61440','-o','.cache/A14-banks-full.vvp','tests/tb_tag_banks.sv',$memory,$vendor)
Simulate 'A14-snapshot-banks' @('-g2012','-s','tb_snapshot','-Ptb_snapshot.RW=40','-Ptb_snapshot.RH=80','-o','.cache/A14-snapshot-banks.vvp','tests/tb_snapshot.sv',$engine,$memory,'projects/hdmi/rtl/canny_snapshot_exact.v',$vendor)
Simulate 'A14-fast-ram' @('-g2012','-s','tb_hysteresis_ram','-o','.cache/A14-fast-ram.vvp','tests/tb_hysteresis_ram.sv',$engine,$memory,$fast)
Simulate 'A14-ram-full' @('-g2012','-s','tb_hysteresis_ram','-Ptb_hysteresis_ram.W=640','-Ptb_hysteresis_ram.H=480','-Ptb_hysteresis_ram.SCENES=2','-o','.cache/A14-ram-full.vvp','tests/tb_hysteresis_ram.sv',$engine,$memory,$fast)
@'
from pathlib import Path
import re
rows=lambda p:[{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)} for line in re.findall(r'^PASS production RAM scene=.*$',Path(p).read_text(encoding='utf-8-sig'),re.M)]
old=rows('.cache/A14-baseline-ram.log');new=rows('.cache/A14-regression.log');fast=rows('.cache/A14-fast-ram.log')
assert len(old)==len(new)==len(fast)==4 and new==fast
assert old==rows('releases/A13/hdmi/A13-regression.log')
for baseline,candidate in ((old,new),(rows('releases/A13/hdmi/A13-ram-full.log'),rows('.cache/A14-ram-full.log'))):
    for a,b in zip(baseline,candidate):
        for k in ('scene','pixels','accepted','transactions','writes','cache_hits','ram_reads','four_cycle_equivalent'):assert a[k]==b[k],k
        assert a['cycles']-b['cycles']==b['cache_hits']
        assert b['ram_reads']+b['cache_hits']==b['transactions']
assert len(rows('.cache/A14-ram-full.log'))==2
print('PASS A13/A14 data, counts, one-clock-per-hit cycle savings and vendor/fast comparisons')
'@ | & 'C:\Python314\python.exe' -
if($LASTEXITCODE -ne 0){throw 'Comparison failed'}
$taskA14ReproduceLog=Join-Path (Get-Location).Path ('.cache/'+$BuildVersion+'-build.log')
& .\tools\build.ps1 -Target hdmi -Version $BuildVersion 2>&1 | Tee-Object -FilePath $taskA14ReproduceLog
if($LASTEXITCODE -ne 0){throw 'Build failed'}
$manifest=Get-Content -LiteralPath ('releases/'+$BuildVersion+'/hdmi/manifest.json') -Raw | ConvertFrom-Json
if($manifest.timing_status -ne 'PASS'){throw 'Static timing failed'}
