# Run from an A11 checkout. Use a fresh build name; existing releases are protected.
# Original build command: .\tools\build.ps1 -Target hdmi -Version A11
param([string]$BuildVersion='A11-reproduce')
$ErrorActionPreference='Stop'
$env:PATH='E:\msys2\ucrt64\bin;'+$env:PATH
$iv='E:\msys2\ucrt64\bin\iverilog.exe'
$vv='E:\msys2\ucrt64\bin\vvp.exe'
function Simulate($name,$arguments){
    & $iv @arguments
    if($LASTEXITCODE -ne 0){throw "$name compile failed"}
    & $vv ('.cache/'+$name+'.vvp') 2>&1 | Tee-Object -FilePath ('.cache/'+$name+'.txt')
    if($LASTEXITCODE -ne 0){throw "$name simulation failed"}
}
New-Item -ItemType Directory -Path .cache -Force | Out-Null
@'
from pathlib import Path
import subprocess
Path('.cache/A10-canny_tag_memory.v').write_bytes(subprocess.check_output([r'E:\Git\cmd\git.exe','show','A10:projects/hdmi/rtl/canny_tag_memory.v']))
'@ | & 'C:\Python314\python.exe' -
if($LASTEXITCODE -ne 0){throw 'A10 source extraction failed'}
& .\tools\test.ps1 2>&1 | Tee-Object -FilePath .cache/A11-regression.txt
if($LASTEXITCODE -ne 0){throw 'A11 regression failed'}
$engine='projects/hdmi/rtl/canny_hysteresis_exact.v'
$memory='projects/hdmi/rtl/canny_tag_memory.v'
$vendor='../efinity2025_clean/PFiles/Efinity/2025.1/sim_models/verilog/efx_ram10.v'
$fast='tests/models/efx_ram10_20bit_fast.v'
Simulate 'A10-calibration' @('-g2012','-s','tb_hysteresis_ram','-Ptb_hysteresis_ram.CACHED=0','-o','.cache/A10-calibration.vvp','tests/tb_hysteresis_ram.sv',$engine,'.cache/A10-canny_tag_memory.v',$vendor)
Simulate 'A11-banks' @('-g2012','-s','tb_snapshot','-Ptb_snapshot.RW=40','-Ptb_snapshot.RH=80','-o','.cache/A11-banks.vvp','tests/tb_snapshot.sv',$engine,$memory,'projects/hdmi/rtl/canny_snapshot_exact.v',$vendor)
Simulate 'A11-fast-ram' @('-g2012','-s','tb_hysteresis_ram','-o','.cache/A11-fast-ram.vvp','tests/tb_hysteresis_ram.sv',$engine,$memory,$fast)
Simulate 'A11-ram-full' @('-g2012','-s','tb_hysteresis_ram','-Ptb_hysteresis_ram.W=640','-Ptb_hysteresis_ram.H=480','-Ptb_hysteresis_ram.SCENES=2','-o','.cache/A11-ram-full.vvp','tests/tb_hysteresis_ram.sv',$engine,$memory,$fast)
@'
from pathlib import Path
import re
p=Path('.cache')
lines=lambda name:re.findall(r'^PASS production RAM scene=.*$',p.joinpath(name).read_text(encoding='utf-8-sig'),re.M)
a,b=lines('A11-regression.txt'),lines('A11-fast-ram.txt')
assert len(a)==4 and a==b
old=lines('A10-calibration.txt')
parse=lambda line:{k:int(v) for k,v in re.findall(r'(\w+)=(\d+)',line)}
for x,y in zip(map(parse,old),map(parse,a)):
    assert x['cycles']==y['four_cycle_equivalent']
    for k in ('scene','pixels','accepted','transactions','writes'):assert x[k]==y[k]
full=lines('A11-ram-full.txt')
baseline=re.findall(r'^PASS production RAM scene=.*$',Path('releases/A10/hdmi/A10-ram-full.txt').read_text(encoding='utf-8-sig'),re.M)
assert len(full)==len(baseline)==2
for x,y in zip(map(parse,baseline),map(parse,full)):
    assert x['cycles']==y['cycles']+y['cache_hits']
    assert y['ram_reads']+y['cache_hits']==y['transactions']
    for k in ('scene','pixels','accepted','transactions','writes'):assert x[k]==y[k]
print('PASS A10/A11 and vendor/fast RAM comparisons')
'@ | & 'C:\Python314\python.exe' -
if($LASTEXITCODE -ne 0){throw 'RAM comparison failed'}
$buildLog=Join-Path (Get-Location).Path ('.cache/'+$BuildVersion+'-build.log')
& .\tools\build.ps1 -Target hdmi -Version $BuildVersion 2>&1 | Tee-Object -FilePath $buildLog
if($LASTEXITCODE -ne 0){throw 'Build failed'}
