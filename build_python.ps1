# Builds the Python side of the package from the SAME sources and libraries as openEMS.exe and puts everything into
# build\out, so that build\out is a COMPLETE, self-contained package that can be copied to any computer:
#     build\out\openEMS.exe, nf2ff.exe, *.dll, include\, lib\, matlab\     (from stage_out.ps1)
#     build\out\bin\                a copy of the executables and DLLs (RFsim looks for <folder>\bin\openEMS.exe)
#     build\out\venv\Scripts\       a private CPython (copied from third_party\python) with the wheels of this build
#                                   (CSXCAD, openEMS, numpy, h5py, matplotlib). RFsim looks for
#                                   <folder>\venv\Scripts\python.exe. It is a plain copy of Python, NOT a virtual
#                                   environment, so it does not point to any other folder or drive.
#     build\wheels\                 the wheels (kept for reference)
# It is called at the end of build.cmd and can be run alone from the MSVC environment of build.cmd:
#     powershell -File build_python.ps1
# The Python is taken from third_party\python (fetch_python.ps1 downloads it once). The Python of the computer is NOT
# used, unless -Python is given on purpose (a 64-bit Python of the same series as the one that will run the modules).
# Nothing is written into the source trees: the sources are copied to build\pywork first.
param(
    [string]$Python    = '',
    [string]$Root      = $PSScriptRoot,
    [string]$Build     = $(Join-Path $PSScriptRoot 'build'),
    [string]$DepsRoot  = $(if ($env:OPENEMS_DEPS)       { $env:OPENEMS_DEPS }       else { Join-Path $PSScriptRoot 'third_party/deps' }),
    [string]$VcpkgRoot = $(if ($env:OPENEMS_VCPKG_ROOT) { $env:OPENEMS_VCPKG_ROOT } else { Join-Path $PSScriptRoot 'third_party/vcpkg' }),
    [string]$SrcRoot   = $(if ($env:OPENEMS_SRC)        { $env:OPENEMS_SRC }        else { Join-Path $PSScriptRoot 'third_party/src' })
)
$ErrorActionPreference = 'Stop'

function Run($exe, $argList) {
    Write-Host ">>> $exe $($argList -join ' ')"
    & $exe @argList
    if ($LASTEXITCODE -ne 0) { throw "Failed ($LASTEXITCODE): $exe $($argList -join ' ')" }
}

$Root      = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
$Build     = [IO.Path]::GetFullPath($Build).TrimEnd('\','/')
$DepsRoot  = [IO.Path]::GetFullPath($DepsRoot).TrimEnd('\','/')
$VcpkgRoot = [IO.Path]::GetFullPath($VcpkgRoot).TrimEnd('\','/')
$SrcRoot   = [IO.Path]::GetFullPath($SrcRoot).TrimEnd('\','/')
$Out       = Join-Path $Build 'out'
$Work      = Join-Path $Build 'pywork'
$Wheels    = Join-Path $Build 'wheels'

# ---- inputs -------------------------------------------------------------------------------------------
foreach ($f in @("$Out\openEMS.exe", "$Out\openEMS.dll", "$Out\CSXCAD.dll", "$Out\lib\openEMS.lib",
                 "$Out\lib\nf2ff.lib", "$Out\lib\CSXCAD.lib", "$Out\include\openEMS\openems.h",
                 "$SrcRoot\CSXCAD\python\setup.py", "$Root\python\setup.py")) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "build_python: file not found: $f (run build.cmd first)" }
}

# the MSVC x64 environment of build.cmd must be loaded (cl.exe in PATH, target x64)
if (-not (Get-Command cl -ErrorAction SilentlyContinue) -or $env:VSCMD_ARG_TGT_ARCH -ne 'x64') {
    throw "build_python: the MSVC x64 environment is not loaded. Run build.cmd (a plain cmd window), not this script alone."
}

# ---- the private Python ---------------------------------------------------------------------------------------
$PrivPy = Join-Path $Root 'third_party\python'
if (-not $Python) {
    & (Join-Path $Root 'fetch_python.ps1') -Dest $PrivPy
    $Python = Join-Path $PrivPy 'python.exe'
}
if (-not (Test-Path -LiteralPath $Python -PathType Leaf)) { throw "build_python: python.exe not found: $Python" }
$info = (& $Python -c "import sys; print('%d.%d %d' % (sys.version_info[0], sys.version_info[1], 64 if sys.maxsize > 2**32 else 32))")
if ($LASTEXITCODE -ne 0 -or "$info" -notmatch '^(\d+)\.(\d+) (\d+)$') { throw "build_python: cannot run $Python" }
$pyMajor = [int]$Matches[1]; $pyMinor = [int]$Matches[2]; $pyBits = [int]$Matches[3]
if ($pyBits -ne 64 -or $pyMajor -ne 3 -or $pyMinor -lt 9) { throw "build_python: need a 64-bit Python 3.9 or newer, got: $info ($Python)" }
Write-Host "Python for the wheels: $Python (version $pyMajor.$pyMinor)"

# PYTHONHOME / PYTHONPATH of the computer must not leak into this Python
Remove-Item Env:PYTHONHOME, Env:PYTHONPATH -ErrorAction SilentlyContinue

# ---- clean work folders (only these names, directly inside the build folder) -----------------------------------
foreach ($d in @($Work, $Wheels)) {
    if ((Split-Path -Parent $d).TrimEnd('\','/') -ne $Build) { throw "build_python: refusing to delete $d" }
    if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force }
}
New-Item -ItemType Directory -Force $Work, $Wheels | Out-Null

# ---- copy the sources (the source trees stay clean) ----------------------------------------------------------
$csxSrc = Join-Path $Work 'csxcad-py'
$emsSrc = Join-Path $Work 'openems-py'
Copy-Item -LiteralPath "$SrcRoot\CSXCAD\python" -Destination $csxSrc -Recurse -Force
New-Item -ItemType Directory -Force $emsSrc | Out-Null
Copy-Item -LiteralPath "$Root\python\setup.py" -Destination $emsSrc -Force
Copy-Item -LiteralPath "$Root\python\openEMS" -Destination $emsSrc -Recurse -Force

# the version of the wheel: the base of the source tree + a local tag (PEP 440)
$setup = Join-Path $emsSrc 'setup.py'
$text = [IO.File]::ReadAllText($setup)
$new = [regex]::Replace($text, "version\s*=\s*'[^']*'", "version = '0.0.35+cuda'", 1)
if ($new -eq $text) { throw "build_python: no version line found in python\setup.py" }
[IO.File]::WriteAllText($setup, $new)

# ---- build environment (only for building; it is NOT shipped) ------------------------------------------------------
$venv = Join-Path $Work 'venv'
Run $Python @('-m', 'venv', $venv)
$vpy = Join-Path $venv 'Scripts\python.exe'
Run $vpy @('-m', 'pip', 'install', '--upgrade', 'pip', 'setuptools', 'wheel')
Run $vpy @('-m', 'pip', 'install', 'cython', 'numpy', 'matplotlib', 'h5py')

# the compiler and the linker find headers and libraries through INCLUDE and LIB
$vcpkgBin = Join-Path $VcpkgRoot 'installed\x64-windows'
$env:INCLUDE = "$DepsRoot\include;$Out\include;$vcpkgBin\include;" + $env:INCLUDE
$env:LIB     = "$DepsRoot\lib;$Out\lib;$vcpkgBin\lib;" + $env:LIB
# C++17 as in the CSXCAD build; WITH_CUDA because openems.h has a different enum without it (it must match the library)
$env:CL = '/std:c++17 /DWITH_CUDA'
$env:CSXCAD_INSTALL_PATH = $DepsRoot
$env:CSXCAD_NOSCM = '1'
# The MSVC environment of build.cmd (x64, 14.44) is already loaded. Tell setuptools to use it as it is, and NOT to
# start vcvarsall.bat again (a second start inside this environment fails with "input line is too long", and it
# would choose a different toolchain).
$env:DISTUTILS_USE_SDK = '1'
$env:MSSdk = '1'

# ---- 1. CSXCAD ------------------------------------------------------------------------------------------------
Run $vpy @('-m', 'pip', 'wheel', '--no-build-isolation', '--no-deps', '-w', $Wheels, $csxSrc)
$csxWheel = Get-ChildItem -LiteralPath $Wheels -Filter 'CSXCAD*.whl' | Select-Object -First 1
if (-not $csxWheel) { throw "build_python: no CSXCAD wheel was built" }
# the openEMS build needs the .pxd files of CSXCAD: install it into the build environment
Run $vpy @('-m', 'pip', 'install', '--no-deps', '--force-reinstall', $csxWheel.FullName)

# ---- 2. openEMS -----------------------------------------------------------------------------------------------
Run $vpy @('-m', 'pip', 'wheel', '--no-build-isolation', '--no-deps', '-w', $Wheels, $emsSrc)
$emsWheel = Get-ChildItem -LiteralPath $Wheels -Filter 'openEMS*.whl' | Select-Object -First 1
if (-not $emsWheel) { throw "build_python: no openEMS wheel was built" }

# ---- 3. run-time dependencies (so that the next step needs no internet) ------------------------------------------
Run $vpy @('-m', 'pip', 'download', '--dest', $Wheels, 'numpy', 'h5py', 'matplotlib')

# ---- 4. assemble the package in build\out -----------------------------------------------------------------------
# bin\: the executables and DLLs once more (RFsim wants <folder>\bin\openEMS.exe)
$bin = Join-Path $Out 'bin'
if (Test-Path -LiteralPath $bin) { Remove-Item -LiteralPath $bin -Recurse -Force }
New-Item -ItemType Directory -Force $bin | Out-Null
Get-ChildItem -LiteralPath $Out -File | Where-Object { $_.Extension -in '.exe', '.dll' } |
    ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $bin -Force }

# venv\Scripts\: a plain copy of the private Python. Not a virtual environment: no pyvenv.cfg, no path to another place.
# (RFsim runs <folder>\venv\Scripts\python.exe; a Python finds its Lib\ and DLLs next to python.exe.)
$rt = Join-Path $Out 'venv\Scripts'
$rtRoot = Join-Path $Out 'venv'
if (Test-Path -LiteralPath $rtRoot) { Remove-Item -LiteralPath $rtRoot -Recurse -Force }
New-Item -ItemType Directory -Force $rt | Out-Null
$srcPy = Split-Path -Parent $Python
& robocopy $srcPy $rt /E /XD (Join-Path $srcPy 'Lib\test') (Join-Path $srcPy 'Lib\idlelib') (Join-Path $srcPy 'Lib\turtledemo') `
    (Join-Path $srcPy 'Lib\site-packages') /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "build_python: copying the Python failed (robocopy $LASTEXITCODE)" }
$global:LASTEXITCODE = 0
New-Item -ItemType Directory -Force (Join-Path $rt 'Lib\site-packages') | Out-Null
$rtpy = Join-Path $rt 'python.exe'

# the license of Python itself (the wheels carry their own license files in their .dist-info folders)
$pyLic = Join-Path $srcPy 'LICENSE.txt'
if (Test-Path -LiteralPath $pyLic -PathType Leaf) {
    New-Item -ItemType Directory -Force (Join-Path $Out 'licenses') | Out-Null
    Copy-Item -LiteralPath $pyLic -Destination (Join-Path $Out 'licenses\Python-LICENSE.txt') -Force
} else {
    Write-Warning "build_python: no LICENSE.txt in $srcPy; copy the Python license to $Out\licenses by hand"
}

# pip into the copy (the copy has ensurepip) and the wheels, all from build\wheels
Run $rtpy @('-m', 'ensurepip', '--upgrade')
Run $rtpy @('-m', 'pip', 'install', '--no-index', '--find-links', $Wheels, '--no-warn-script-location',
            'CSXCAD', 'openEMS', 'numpy', 'h5py', 'matplotlib')

# The Python modules need the DLLs of this package (openEMS.dll, CSXCAD.dll ... in the package root). Python 3.8+
# does not search PATH for them: register the root at start-up. The path is computed from the location of python.exe, so
# the folder can be moved. The handle must stay alive: it is kept in builtins.
$pth = Join-Path $rt 'Lib\site-packages\openems_dll.pth'
$line = "import os, sys, builtins; builtins._openems_dll_dir = os.add_dll_directory(os.path.abspath(os.path.join(sys.prefix, '..', '..')))"
[IO.File]::WriteAllText($pth, $line + "`r`n", (New-Object Text.ASCIIEncoding))

# ---- 5. checks, with a minimal environment: nothing of this computer may be needed -------------------------------
$savedPath = $env:PATH
$env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
try {
    Run $rtpy @('-c', "import sys, CSXCAD, openEMS; print('python', sys.version.split()[0], '|', sys.prefix); print(CSXCAD.__file__); print(openEMS.__file__)")
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $usage = (& (Join-Path $bin 'openEMS.exe') 2>&1 | Out-String)
    $ErrorActionPreference = $eap
    if ($usage -notmatch '--engine=cuda') { throw "build_python: bin\openEMS.exe does not list --engine=cuda" }
    Write-Host "bin\openEMS.exe lists --engine=cuda"
}
finally { $env:PATH = $savedPath }

Add-Content -LiteralPath (Join-Path $Out 'README.txt') -Encoding ASCII -Value @(
    "",
    "licenses\     license texts of this package and of the libraries in it (start with NOTICE.md).",
    "bin\          a copy of the executables and DLLs (RFsim looks for <folder>\bin\openEMS.exe).",
    "venv\Scripts\ a private CPython with the Python modules built from the same sources (CSXCAD, openEMS) and numpy,",
    "              h5py, matplotlib. It is a plain copy of Python, not a virtual environment: this folder can be copied",
    "              to another computer and to another place as it is. RFsim looks for <folder>\venv\Scripts\python.exe."
)

Write-Host "`nPackage ready: $Out"
Write-Host "Copy it as it is, or: install_package.cmd C:\openEMS"
