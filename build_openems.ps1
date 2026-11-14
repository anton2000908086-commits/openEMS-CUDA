param(
    [string]$Root        = $PSScriptRoot,
    [string]$VcpkgRoot   = $(if ($env:OPENEMS_VCPKG_ROOT) { $env:OPENEMS_VCPKG_ROOT } else { Join-Path $PSScriptRoot 'third_party/vcpkg' }),
    [string]$DepsRoot    = $(if ($env:OPENEMS_DEPS)       { $env:OPENEMS_DEPS }       else { Join-Path $PSScriptRoot 'third_party/deps' }),
    [string]$SrcRoot     = $(if ($env:OPENEMS_SRC)        { $env:OPENEMS_SRC }        else { Join-Path $PSScriptRoot 'third_party/src' }),
    [string]$Nvcc        = 'C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.2/bin/nvcc.exe',
    [string]$Arch        = '86',    # RTX 3060 = 86; 'native' needs a visible GPU at build time
    [string]$VcpkgCommit = '',      # хэш коммита vcpkg для воспроизводимости
    [string]$FparserRef  = '',      # коммит или тег fparser
    [string]$CsxcadRef   = '',      # коммит или тег CSXCAD
    [switch]$RebuildDeps            # принудительно пересобрать зависимости
)
$ErrorActionPreference = 'Stop'

function Run($exe, $argList) {
    Write-Host ">>> $exe $($argList -join ' ')"
    & $exe @argList
    if ($LASTEXITCODE -ne 0) { throw "Failed ($LASTEXITCODE): $exe" }
}

$VcpkgRoot = $VcpkgRoot.Replace('\','/')
$DepsRoot  = $DepsRoot.Replace('\','/')
$SrcRoot   = $SrcRoot.Replace('\','/')

if (-not (Test-Path $Nvcc)) { throw "nvcc not found at $Nvcc (pass -Nvcc <path>)" }
foreach ($tool in 'cl', 'cmake', 'ninja', 'git') {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "'$tool' not found in PATH. Load the MSVC environment first."
    }
}
# the toolchain must be MSVC 14.44, 64-bit host and target (a wrong environment gives LNK1112 / "no GPU detected")
$linkExe = (Get-Command link.exe -ErrorAction SilentlyContinue).Source
Write-Host "link.exe: $linkExe"
if (-not $linkExe -or $linkExe -notmatch '\\MSVC\\14\.44[^\\]*\\bin\\Hostx64\\x64\\') {
    throw "link.exe is not MSVC 14.44 Hostx64\x64. Start from a PLAIN cmd window (not 'Developer Command Prompt') and use build.cmd."
}

if (-not $env:NVCC_PREPEND_FLAGS) {
    Write-Warning 'NVCC_PREPEND_FLAGS is not set; nvcc 12.2 may reject the MSVC version.'
}

function Test-Deps {
    (Test-Path "$VcpkgRoot/vcpkg.exe") -and
    (Get-ChildItem "$DepsRoot/lib" -Filter '*CSXCAD*'  -ErrorAction SilentlyContinue) -and
    (Get-ChildItem "$DepsRoot/lib" -Filter '*fparser*' -ErrorAction SilentlyContinue)
}

function Initialize-Deps {
    New-Item -ItemType Directory -Force $SrcRoot, $DepsRoot | Out-Null

    # vcpkg
    if (-not (Test-Path "$VcpkgRoot/vcpkg.exe")) {
        if (-not (Test-Path "$VcpkgRoot/.git")) {
            Run git @('clone', 'https://github.com/microsoft/vcpkg.git', $VcpkgRoot)
            if ($VcpkgCommit) { Run git @('-C', $VcpkgRoot, 'checkout', $VcpkgCommit) }
        }
        Run "$VcpkgRoot/bootstrap-vcpkg.bat" @('-disableMetrics')
    }
    Run "$VcpkgRoot/vcpkg.exe" @('install', 'boost-thread', 'boost-date-time', 'boost-serialization',
        'boost-chrono', 'boost-program-options', 'hdf5', 'tinyxml', 'vtk', '--triplet', 'x64-windows')
    $toolchain = "$VcpkgRoot/scripts/buildsystems/vcpkg.cmake"

    # fparser
    if (-not (Test-Path "$SrcRoot/fparser")) {
        Run git @('clone', 'https://github.com/thliebig/fparser.git', "$SrcRoot/fparser")
        if ($FparserRef) { Run git @('-C', "$SrcRoot/fparser", 'checkout', $FparserRef) }
    }
    Run cmake @('-S', "$SrcRoot/fparser", '-B', "$SrcRoot/fparser/build", '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_WINDOWS_EXPORT_ALL_SYMBOLS=ON',
        "-DCMAKE_INSTALL_PREFIX=$DepsRoot", '-DCMAKE_POLICY_VERSION_MINIMUM=3.5')
    Run cmake @('--build', "$SrcRoot/fparser/build")
    Run cmake @('--install', "$SrcRoot/fparser/build")

    # CSXCAD
    if (-not (Test-Path "$SrcRoot/CSXCAD")) {
        Run git @('clone', 'https://github.com/thliebig/CSXCAD.git', "$SrcRoot/CSXCAD")
        if ($CsxcadRef) { Run git @('-C', "$SrcRoot/CSXCAD", 'checkout', $CsxcadRef) }
    }
    Run cmake @('-S', "$SrcRoot/CSXCAD", '-B', "$SrcRoot/CSXCAD/build", '-G', 'Ninja',
        '-DCMAKE_BUILD_TYPE=Release', "-DCMAKE_TOOLCHAIN_FILE=$toolchain",
        '-DVCPKG_TARGET_TRIPLET=x64-windows', '-DVCPKG_MANIFEST_MODE=OFF', '-DVCPKG_MANIFEST_INSTALL=OFF',
        "-DCMAKE_INSTALL_PREFIX=$DepsRoot", "-DFPARSER_ROOT_DIR=$DepsRoot", '-DCMAKE_POLICY_VERSION_MINIMUM=3.5')
    Run cmake @('--build', "$SrcRoot/CSXCAD/build")
    Run cmake @('--install', "$SrcRoot/CSXCAD/build")
}

if ($RebuildDeps -or -not (Test-Deps)) { Initialize-Deps }

$build = Join-Path $Root 'build'
Run cmake @('-S', $Root, '-B', $build, '-G', 'Ninja',
    '-DCMAKE_BUILD_TYPE=Release',
    "-DCMAKE_TOOLCHAIN_FILE=$VcpkgRoot/scripts/buildsystems/vcpkg.cmake",
    '-DVCPKG_TARGET_TRIPLET=x64-windows', '-DVCPKG_MANIFEST_MODE=OFF', '-DVCPKG_MANIFEST_INSTALL=OFF',
    "-DFPARSER_ROOT_DIR=$DepsRoot", "-DCSXCAD_ROOT_DIR=$DepsRoot",
    '-DWITH_CUDA=ON', "-DCMAKE_CUDA_COMPILER=$Nvcc", "-DCMAKE_CUDA_ARCHITECTURES=$Arch",
    '-DCMAKE_POLICY_VERSION_MINIMUM=3.5')
$log = Join-Path $Root 'build_openems.log'
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
