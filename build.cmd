uild_all.cmd
@echo off
rem Loads the MSVC v143 (14.44) + CUDA 12.2 environment and builds openEMS-CUDA.
rem Run it from a PLAIN cmd window (Win+R, cmd), not from "Developer Command Prompt".
rem Options: "clean" deletes the CMake build folder first, "compare" runs the CPU/CUDA comparison afterwards:
rem    build_all.cmd clean compare

call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvarsall.bat" x64 -vcvars_ver=14.44
if errorlevel 1 (
    echo Failed to load the MSVC environment.
    exit /b 1
)

set NVCC_PREPEND_FLAGS=--allow-unsupported-compiler -D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH
set PATH=C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin;C:\Program Files\Microsoft Visual Studio\18\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja;%PATH%

echo Target arch: %VSCMD_ARG_TGT_ARCH%, host arch: %VSCMD_ARG_HOST_ARCH%
where link
cl 2>&1 | findstr /i "версии version"
"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v12.2\bin\nvcc.exe" --version | findstr /i "release"

if /i "%1"=="clean" rmdir /s /q D:\openEMS-CUDA-master\build
if /i "%2"=="clean" rmdir /s /q D:\openEMS-CUDA-master\build

powershell -NoProfile -ExecutionPolicy Bypass -File D:\openEMS-CUDA-master\build_openems.ps1
if errorlevel 1 (
    echo Build failed, see D:\build_openems.log
    exit /b 1
)

if /i "%1"=="compare" call D:\selftest\run_compare.cmd
if /i "%2"=="compare" call D:\selftest\run_compare.cmd
 
