param(
    [string]$Root = 'D:\openEMS-CUDA-master',
    [string]$Nvcc = 'C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.2/bin/nvcc.exe',
    [string]$Arch = '86'    # RTX 3060 = 86; 'native' needs a visible GPU at build time
)
$ErrorActionPreference = 'Stop'

function Run($exe, $argList) {
    Write-Host ">>> $exe $($argList -join ' ')"
    & $exe @argList
    if ($LASTEXITCODE -ne 0) { throw "Failed ($LASTEXITCODE): $exe" }
}

if (-not (Test-Path $Nvcc)) { throw "nvcc not found at $Nvcc (pass -Nvcc <path>)" }
foreach ($tool in 'cl', 'cmake', 'ninja') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "'$tool' not found in PATH. Load the MSVC environment first."
    }
}
# the toolchain must be MSVC 14.44, 64-bit host and target (a wrong environment gives LNK1112 / "no GPU detected")
$linkExe = (Get-Command link.exe -ErrorAction SilentlyContinue).Source
Write-Host "link.exe: $linkExe"
if (-not $linkExe -or $linkExe -notmatch '\\MSVC\\14\.44[^\\]*\\bin\\Hostx64\\x64\\') {
    throw "link.exe is not MSVC 14.44 Hostx64\x64. Start from a PLAIN cmd window (not 'Developer Command Prompt') and use build_all.cmd."
}

if (-not $env:NVCC_PREPEND_FLAGS) {
    Write-Warning 'NVCC_PREPEND_FLAGS is not set; nvcc 12.2 may reject the MSVC version.'
}

# Plain .cpp files include cuda_runtime.h: give them the CUDA toolkit include dirs (idempotent patch)
$cml = Join-Path $Root 'CMakeLists.txt'
$text = Get-Content $cml -Raw
if ($text -match 'enable_language\(CUDA\)' -and $text -notmatch 'CMAKE_CUDA_TOOLKIT_INCLUDE_DIRECTORIES') {
    $text = $text -replace 'enable_language\(CUDA\)', "enable_language(CUDA)`r`n  include_directories(`${CMAKE_CUDA_TOOLKIT_INCLUDE_DIRECTORIES})"
    Set-Content -Path $cml -Value $text -NoNewline
    Write-Host 'Patched CMakeLists.txt: CUDA toolkit include directories added for C++ files.'
}

# MSVC treats 'and'/'or'/'not' as keywords only with <iso646.h>: force-include it for C++ files (idempotent patch)
$text = Get-Content $cml -Raw
if ($text -notmatch 'iso646') {
    $needle = 'set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -g")'
    if ($text.Contains($needle)) {
        $text = $text.Replace($needle, $needle + "`r`nif(MSVC)`r`n  set(CMAKE_CXX_FLAGS `"`${CMAKE_CXX_FLAGS} /FIiso646.h`")`r`nendif()")
        Set-Content -Path $cml -Value $text -NoNewline
        Write-Host 'Patched CMakeLists.txt: /FIiso646.h added for MSVC C++ files.'
    } else {
        Write-Warning 'Could not find the CMAKE_CXX_FLAGS line to patch; add /FIiso646.h to CMAKE_CXX_FLAGS manually.'
    }
}

$build = Join-Path $Root 'build'
Run cmake @('-S', $Root, '-B', $build, '-G', 'Ninja',
    '-DCMAKE_BUILD_TYPE=Release',
    '-DCMAKE_TOOLCHAIN_FILE=D:/vcpkg/scripts/buildsystems/vcpkg.cmake',
    '-DVCPKG_TARGET_TRIPLET=x64-windows', '-DVCPKG_MANIFEST_MODE=OFF', '-DVCPKG_MANIFEST_INSTALL=OFF',
    '-DFPARSER_ROOT_DIR=D:/deps', '-DCSXCAD_ROOT_DIR=D:/deps',
    '-DWITH_CUDA=ON', "-DCMAKE_CUDA_COMPILER=$Nvcc", "-DCMAKE_CUDA_ARCHITECTURES=$Arch",
    '-DCMAKE_POLICY_VERSION_MINIMUM=3.5')
$log = 'D:\openEMS-CUDA-master\build_openems.log'
Write-Host ">>> cmake --build $build -- -k 0   (full log: $log)"
$ErrorActionPreference = 'Continue'   # native stderr output must not abort the script
& cmake --build $build -- -k 0 *>&1 | Tee-Object -FilePath $log | Out-Null
$code = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
Write-Host "`n===== errors (first 3 per file) ====="
$errs = Select-String -Path $log -Pattern '(fatal )?error [A-Z]*\d+|FAILED:|error:|LNK\d+' |
    Where-Object { $_.Line -notmatch 'warning' } | ForEach-Object { $_.Line.Trim() }
$groups = $errs | Where-Object { $_ -match '^(.*?)\(\d+\)' } | Group-Object { ($_ -split '\(\d+\)')[0] }
foreach ($g in $groups) {
    Write-Host ("--- " + $g.Name + "  (" + $g.Count + " errors)")
    $g.Group | Select-Object -First 3
}
$other = $errs | Where-Object { $_ -notmatch '^(.*?)\(\d+\)' -and $_ -notmatch '^FAILED:' } | Select-Object -First 10
if ($other) { Write-Host '--- other'; $other }
if ($code -ne 0) { throw "Build failed ($code). Full log: $log" }
Write-Host "`nBuild finished: $build"
