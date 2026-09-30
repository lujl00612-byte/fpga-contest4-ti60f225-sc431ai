param(
    [ValidateSet('mipi','mipi_diag','hdmi')][string]$Target='mipi',
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Version,
    [ValidateSet('map','interface','pnr','pgm')][string]$ResumeFrom='map'
)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path $PSScriptRoot -Parent
$toolRoot=Join-Path (Split-Path $repoRoot -Parent) 'efinity2025_clean\PFiles\Efinity\2025.1'
$projectDir=Join-Path $repoRoot ('projects\'+$Target)
$isMipi=$Target -in @('mipi','mipi_diag')
if($isMipi){
    & 'C:\Python314\python.exe' (Join-Path $PSScriptRoot 'check_dsi_constraints.py') --project $projectDir
    if($LASTEXITCODE -ne 0){throw 'DSI clock-lane constraint applicability check failed'}
}
$out=Join-Path $repoRoot ('builds\'+$Version+'\'+$Target)
$release=Join-Path $repoRoot ('releases\'+$Version+'\'+$Target)
if((Test-Path -LiteralPath $release) -and (($ResumeFrom -ne 'pgm') -or (Test-Path -LiteralPath (Join-Path $release 'manifest.json')))){
    throw "Release already exists: $release"
}
if(Get-PSDrive H -ErrorAction SilentlyContinue){throw 'H: is already occupied'}
if(Get-PSDrive V -ErrorAction SilentlyContinue){throw 'V: is already occupied'}
$hCreated=$false;$vCreated=$false
try {
    & subst H: $repoRoot
    if($LASTEXITCODE -ne 0){throw 'H: mapping failed'}
    $hCreated=$true
    & subst V: $toolRoot
    if($LASTEXITCODE -ne 0){throw 'V: mapping failed'}
    $vCreated=$true
    $env:PROCESSOR_ARCHITECTURE='AMD64'
    New-Item -ItemType Directory -Path $out -Force|Out-Null
    $shortOut='H:\builds\'+$Version+'\'+$Target
    $shortProject='H:\projects\'+$Target
    Push-Location -LiteralPath $shortProject
    try {
        $mapArgs=@('ti60f225_oob','-f','map','--family','Titanium','-d','Ti60F225','--timing_model','I3',
            '--flist',($shortProject+'\all_sources.f'),'--dir',($shortProject+'\ip\csi_rx_controller'))
        if($isMipi){$mapArgs+=@('--dir',($shortProject+'\ip\dsi_tx'))}
        $mapArgs+=@('--map_opts','veri_options=verilog_mode=sv_09,vhdl_mode=vhdl_2008','root=ti60f225_oob_top',
            '--output_dir',$shortOut,'--work_dir',($shortOut+'\work_syn'))
        if($ResumeFrom -eq 'map'){
            & 'V:\bin\efx_run.bat' @mapArgs
            if($LASTEXITCODE -ne 0){throw 'map failed'}
        } elseif(!(Test-Path -LiteralPath (Join-Path $out 'ti60f225_oob.vdb'))){throw 'No mapped design to resume'}
        $stages=@('map','interface','pnr','pgm')
        foreach($stage in $stages[1..3]){
            if([array]::IndexOf($stages,$stage) -lt [array]::IndexOf($stages,$ResumeFrom)){continue}
            $stageWork=if($stage -eq 'pgm'){'pnr'}else{$stage}
            & 'V:\bin\efx_run.bat' ti60f225_oob -f $stage --family Titanium -d Ti60F225 --timing_model I3 --output_dir $shortOut --work_dir ($shortOut+'\work_'+$stageWork)
            if($LASTEXITCODE -ne 0){throw "$stage failed"}
        }
        foreach($ext in @('bit','hex')){
            $artifact=Join-Path $out ('ti60f225_oob.'+$ext)
            if(!(Test-Path -LiteralPath $artifact) -or ((Get-Item -LiteralPath $artifact).Length -eq 0)){
                throw "Missing or empty programming artifact: $artifact"
            }
        }
        New-Item -ItemType Directory -Path $release -Force|Out-Null
        foreach($ext in @('bit','hex','timing.rpt','map.rpt','pinout.rpt','info.log','warn.log','cdc.rpt')){
            $src=Join-Path $out ('ti60f225_oob.'+$ext)
            if(Test-Path -LiteralPath $src){Copy-Item -LiteralPath $src -Destination (Join-Path $release ($Version+'.'+$ext))}
        }
        $info=Get-Content -LiteralPath (Join-Path $out 'ti60f225_oob.info.log') -Raw
        $resources=[ordered]@{}
        foreach($resource in @('EFX_LUT4','EFX_FF','EFX_RAM10','EFX_DPRAM10','EFX_DSP24','EFX_DSP48')){
            $match=[regex]::Match($info,$resource+'\s*:\s*(\d+)')
            if($match.Success){$resources[$resource]=[int]$match.Groups[1].Value}
        }
        $timing=Get-Content -LiteralPath (Join-Path $out 'ti60f225_oob.timing.rpt') -Raw
        $setupSection=($timing -split 'Setup \(Max\) Clock Relationship')[1] -split 'Hold \(Min\) Clock Relationship' | Select-Object -First 1
        $pathPattern='(?m)^\s*(\S+)\s+(\S+)\s+(-?\d+\.\d+)\s+(-?\d+\.\d+)\s+\(([RF]-[RF])\)'
        $setupPaths=@([regex]::Matches($setupSection,$pathPattern) | ForEach-Object {
            [ordered]@{launch=$_.Groups[1].Value;capture=$_.Groups[2].Value;slack_ns=[double]$_.Groups[4].Value}
        })
        $negativePaths=@($setupPaths | Where-Object {$_.slack_ns -lt 0})
        $holdSection=($timing -split 'Hold \(Min\) Clock Relationship')[1] -split 'NOTE: Values' | Select-Object -First 1
        $holdPaths=@([regex]::Matches($holdSection,$pathPattern) | ForEach-Object {
            [ordered]@{launch=$_.Groups[1].Value;capture=$_.Groups[2].Value;slack_ns=[double]$_.Groups[4].Value}
        })
        $negativeHoldPaths=@($holdPaths | Where-Object {$_.slack_ns -lt 0})
        $sourceHashes=Get-ChildItem -LiteralPath $projectDir -File -Recurse|Where-Object {
            $_.FullName.Substring($projectDir.Length+1) -notmatch '(^|\\)(outflow[^\\]*|work_syn[^\\]*|work_pnr[^\\]*|work_pt[^\\]*|__pycache__)(\\|$)'
        }|ForEach-Object {
            [ordered]@{path=$_.FullName.Substring($projectDir.Length+1);sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
        }
        $generatedInterfaceFiles=@(Get-ChildItem -LiteralPath $projectDir -File -Recurse|Where-Object {
            $_.FullName.Substring($projectDir.Length+1) -match '^outflow[^\\]*\\'
        }|ForEach-Object {
            $relative=$_.FullName.Substring($projectDir.Length+1)
            $saved='interface-generated\'+($relative -replace '^outflow[^\\]*\\','')
            $destination=Join-Path $release $saved
            New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force|Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $destination
            [ordered]@{path=$relative;release_path=$saved;sha256=(Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash}
        })
        $manifest=[ordered]@{
            version=$Version;target=$Target;tool='Efinity 2025.1.110';device='Ti60F225I3';
            stages=@('map PASS','interface PASS','pnr PASS','pgm PASS');resources=$resources;
            bit_sha256=(Get-FileHash -LiteralPath (Join-Path $release ($Version+'.bit')) -Algorithm SHA256).Hash;
            hex_sha256=(Get-FileHash -LiteralPath (Join-Path $release ($Version+'.hex')) -Algorithm SHA256).Hash;
            timing_status=$(if($setupPaths.Count -eq 0 -or $holdPaths.Count -eq 0){'unparsed'}elseif($negativePaths.Count -gt 0 -or $negativeHoldPaths.Count -gt 0){'FAIL'}else{'PASS'});
            setup_paths=$setupPaths;negative_setup_paths=$negativePaths;
            hold_paths=$holdPaths;negative_hold_paths=$negativeHoldPaths;
            hardware_video_validation='pending';source_files=$sourceHashes;
            generated_interface_files=$generatedInterfaceFiles
        }
        $manifest|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $release 'manifest.json') -Encoding utf8
        Write-Output "Build complete: $release; timing: $($manifest.timing_status)"
    } finally {Pop-Location}
} finally {
    if($vCreated){& subst V: /D}
    if($hCreated){& subst H: /D}
}
