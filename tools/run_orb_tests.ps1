param([string]$VivadoBin = 'C:\Xilinx\Vivado\2024.1\bin')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$work = Join-Path $root 'orb_test_output'
New-Item -ItemType Directory -Path $work -Force | Out-Null
& python (Join-Path $PSScriptRoot 'orb_reference.py') generate $work
if ($LASTEXITCODE) { throw 'Reference generation failed' }
$src = Join-Path $root 'camera_accelerator.srcs\sources_1\new'
$sim = Join-Path $root 'camera_accelerator.srcs\sim_1\new'
$names = @('frame_buffer','test_pipeline','line_window','fast_score','fast_nms',
           'fast_detector','fast_pipeline_top','orb_grid_top_n','orb_patch_reader',
           'orb_pattern','orb_descriptor','orb_frontend','orb_accelerator')
$files = $names | ForEach-Object { Join-Path $src ($_.ToString()+'.v') }
$tests = @('orb_descriptor_tb','orb_grid_tracker_tb','orb_accelerator_tb','orb_accelerator_shared_tb','orb_grid_top_n_tb',
           'orb_patch_reader_tb','frame_buffer_system_read_tb','frame_buffer_vga_system_read_tb')
Push-Location $work
try {
    foreach ($test in $tests) {
        $testFile = switch ($test) {
            'orb_accelerator_shared_tb' { 'orb_accelerator_tb' }
            'frame_buffer_vga_system_read_tb' { 'frame_buffer_system_read_tb' }
            default { $test }
        }
        & (Join-Path $VivadoBin 'xvlog.bat') @files (Join-Path $sim ($testFile+'.v'))
        if ($LASTEXITCODE) { throw "Compile failed: $test" }
        & (Join-Path $VivadoBin 'xelab.bat') $test -s $test
        if ($LASTEXITCODE) { throw "Elaboration failed: $test" }
        $log = & (Join-Path $VivadoBin 'xsim.bat') $test -runall -log ($test+'.log') 2>&1
        $log | Write-Output
        if ($LASTEXITCODE -or !($log -match 'PASS:') -or ($log -match 'Fatal:|ERROR:|FAIL:')) {
            throw "Simulation failed: $test"
        }
        if ($test -match '^orb_accelerator') {
            & python (Join-Path $PSScriptRoot 'orb_reference.py') check $work
            if ($LASTEXITCODE) { throw "Reference comparison failed: $test" }
        }
    }
    & python (Join-Path $PSScriptRoot 'orb_reference.py') check $work
    if ($LASTEXITCODE) { throw 'End-to-end reference comparison failed' }
} finally { Pop-Location }
