param([switch]$FullFrame,[switch]$OriginalAddressRegression,[switch]$DelayBoundary)
$ErrorActionPreference='Stop'
$repoRoot=Split-Path $PSScriptRoot -Parent
$env:PATH='E:\msys2\ucrt64\bin;'+$env:PATH
$iverilog='E:\msys2\ucrt64\bin\iverilog.exe'
$vvp='E:\msys2\ucrt64\bin\vvp.exe'
$cache=Join-Path $repoRoot '.cache'
Push-Location -LiteralPath $repoRoot
try {
    & 'C:\Python314\python.exe' tools/prepare_panel_fixture.py
    if($LASTEXITCODE -ne 0){throw 'Panel AXI fixture preparation failed'}
    $patternArgs=@('-g2012','-s','tb_mipi_diagnostic','-o',
        (Join-Path $cache 'mipi_diagnostic.vvp'),'tests/tb_mipi_diagnostic.sv',
        'projects/mipi_diag/rtl/mipi_diagnostic_rgb2.v')
    if($FullFrame){
        $patternArgs=@('-Ptb_mipi_diagnostic.W=1920','-Ptb_mipi_diagnostic.H=1080',
            '-Ptb_mipi_diagnostic.HSP=4','-Ptb_mipi_diagnostic.HBP=88','-Ptb_mipi_diagnostic.HFP=120',
            '-Ptb_mipi_diagnostic.VSP=2','-Ptb_mipi_diagnostic.VBP=20','-Ptb_mipi_diagnostic.VFP=20')+$patternArgs
    }
    & $iverilog @patternArgs
    if($LASTEXITCODE -ne 0){throw 'MIPI diagnostic compile failed'}
    & $vvp (Join-Path $cache 'mipi_diagnostic.vvp')
    if($LASTEXITCODE -ne 0){throw 'MIPI diagnostic simulation failed'}
    & $iverilog -g2012 -s tb_panel_axi -o (Join-Path $cache 'panel_axi.vvp') `
        tests/tb_panel_axi.sv projects/mipi_diag/rtl/mipi_config/panel_config.v projects/mipi_diag/rtl/true_dual_port_ram.v
    if($LASTEXITCODE -ne 0){throw 'Panel AXI compile failed'}
    & $vvp (Join-Path $cache 'panel_axi.vvp')
    if($LASTEXITCODE -ne 0){throw 'Panel AXI simulation failed'}
    if($DelayBoundary){
        & $iverilog -g2012 -s tb_panel_delay -o (Join-Path $cache 'panel_delay.vvp') `
            tests/tb_panel_delay.sv projects/mipi_diag/rtl/mipi_config/panel_config.v projects/mipi_diag/rtl/true_dual_port_ram.v
        if($LASTEXITCODE -ne 0){throw 'Panel delay boundary compile failed'}
        & $vvp (Join-Path $cache 'panel_delay.vvp')
        if($LASTEXITCODE -ne 0){throw 'Panel delay boundary simulation failed'}
    }
    if($OriginalAddressRegression){
        & $iverilog -g2012 -s tb_panel_axi -o (Join-Path $cache 'panel_axi_original.vvp') `
            tests/tb_panel_axi.sv projects/mipi/rtl/mipi_config/panel_config.v projects/mipi/rtl/true_dual_port_ram.v
        if($LASTEXITCODE -ne 0){throw 'Original panel AXI compile failed'}
        $originalResult=& $vvp (Join-Path $cache 'panel_axi_original.vvp') 2>&1
        if($LASTEXITCODE -ne 1 -or ($originalResult -join "`n") -notmatch 'Wrong AR address at handshake: got=00 expected=24'){
            throw 'Expected original first-read address regression was not reproduced'
        }
        $originalResult
        Write-Output 'PASS original-address regression reproduced the expected first-read address failure.'
    }
} finally {Pop-Location}
