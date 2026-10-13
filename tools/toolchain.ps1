function Resolve-ContestExecutable {
    param([string]$Name, [string]$Override, [string]$Fallback)
    if ($Override) {
        $command = Get-Command -Name $Override -CommandType Application -ErrorAction SilentlyContinue
        if (!$command) { throw "Executable not found: $Override" }
        return $command.Source
    }
    $command = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    if (Test-Path -LiteralPath $Fallback -PathType Leaf) { return $Fallback }
    throw "Executable not found: $Name. Configure the toolchain as described in README.md."
}

function Get-ContestToolchain {
    param([switch]$Simulation, [switch]$Python, [switch]$Efinity)
    $resolved = @{}
    if ($Simulation) {
        if ($env:IVERILOG_BIN) {
            if (!(Test-Path -LiteralPath $env:IVERILOG_BIN -PathType Container)) {
                throw 'IVERILOG_BIN must point to the directory containing iverilog.exe and vvp.exe.'
            }
            $env:PATH = $env:IVERILOG_BIN + ';' + $env:PATH
        }
        $resolved.iverilog = Resolve-ContestExecutable 'iverilog.exe' '' 'E:\msys2\ucrt64\bin\iverilog.exe'
        $env:PATH = (Split-Path $resolved.iverilog -Parent) + ';' + $env:PATH
        $resolved.vvp = Resolve-ContestExecutable 'vvp.exe' '' 'E:\msys2\ucrt64\bin\vvp.exe'
    }
    if ($Python) {
        $resolved.python = Resolve-ContestExecutable 'python.exe' $env:PYTHON_EXE 'C:\Python314\python.exe'
    }
    if ($Efinity) {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $efinityRoot = $env:EFINITY_HOME
        if (!$efinityRoot) {
            $efinityRoot = Join-Path (Split-Path $repoRoot -Parent) 'efinity2025_clean\PFiles\Efinity\2025.1'
        }
        if (!(Test-Path -LiteralPath (Join-Path $efinityRoot 'bin\efx_run.bat') -PathType Leaf)) {
            throw 'Efinity was not found. Set EFINITY_HOME to the Efinity 2025.1 installation directory.'
        }
        $resolved.efinity = (Resolve-Path -LiteralPath $efinityRoot).Path
    }
    return $resolved
}
