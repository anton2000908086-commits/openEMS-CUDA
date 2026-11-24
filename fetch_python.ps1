# Fetches a PRIVATE, relocatable CPython into third_party\python, like the other dependencies of this project
# (vcpkg, CSXCAD, fparser). The Python of the computer (PATH, another drive, an installer) is never used by the
# build and not needed to run the result.
# Source: the NuGet package "python" (python.org builds for build scenarios: a complete, unpacked installation).
# Only the series is chosen (default 3.13); the newest stable release of that series is taken, as the other
# third_party items are not pinned either. The wheels are built for that series, so keep it unless you
# want a different Python version (set OPENEMS_PY_SERIES, for example 3.12).
# Idempotent: if third_party\python\python.exe works, nothing is downloaded.
param(
    [string]$Series = $(if ($env:OPENEMS_PY_SERIES) { $env:OPENEMS_PY_SERIES } else { '3.13' }),
    [string]$Dest   = $(Join-Path $PSScriptRoot 'third_party\python'),
    [string]$Work   = $(Join-Path $PSScriptRoot 'build\pydownload')
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch { }

$Dest = [IO.Path]::GetFullPath($Dest).TrimEnd('\','/')
$Work = [IO.Path]::GetFullPath($Work).TrimEnd('\','/')
if ((Split-Path -Leaf $Dest) -ne 'python') { throw "fetch_python: the destination folder must be named 'python': $Dest" }

function Test-PrivatePython($root) {
    $exe = Join-Path $root 'python.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $false }
    foreach ($need in @('Lib\os.py', 'include\Python.h')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $need))) { return $false }
    }
    if (-not (Get-ChildItem -LiteralPath (Join-Path $root 'libs') -Filter 'python3*.lib' -ErrorAction SilentlyContinue)) { return $false }
    & $exe -c "import sys, ensurepip, venv; sys.exit(0 if sys.maxsize > 2**32 else 1)" 2>$null
    return ($LASTEXITCODE -eq 0)
}

if (Test-PrivatePython $Dest) {
    $v = & (Join-Path $Dest 'python.exe') -c "import sys; print(sys.version.split()[0])"
    Write-Host "Private Python is ready: $Dest (version $v)"
    return
}

# ---- which release ----------------------------------------------------------------------------------------
Write-Host "Looking for the newest Python $Series on nuget.org"
$idx = Invoke-RestMethod -Uri 'https://api.nuget.org/v3-flatcontainer/python/index.json'
$pattern = '^' + [regex]::Escape($Series) + '\.\d+$'
$versions = @($idx.versions | Where-Object { $_ -match $pattern } | Sort-Object { [version]$_ })
if ($versions.Count -eq 0) { throw "fetch_python: no stable Python $Series found in the NuGet package 'python'" }
$ver = $versions[-1]
Write-Host "Python $ver"

# ---- download and unpack -------------------------------------------------------------------------------------
if (Test-Path -LiteralPath $Work) { Remove-Item -LiteralPath $Work -Recurse -Force }
New-Item -ItemType Directory -Force $Work | Out-Null
$zip = Join-Path $Work "python.$ver.zip"
$url = "https://api.nuget.org/v3-flatcontainer/python/$ver/python.$ver.nupkg"
Write-Host "Downloading $url"
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
$x = Join-Path $Work 'x'
Expand-Archive -LiteralPath $zip -DestinationPath $x -Force

# the folder with python.exe (normally "tools")
$exe = Get-ChildItem -LiteralPath $x -Recurse -Filter 'python.exe' | Sort-Object { $_.FullName.Length } | Select-Object -First 1
if (-not $exe) { throw "fetch_python: python.exe not found in the package (see $x)" }
$root = $exe.DirectoryName
Write-Host "Python tree: $root"
if (-not (Test-PrivatePython $root)) {
    throw ("fetch_python: the unpacked package is not a complete Python (needs python.exe, Lib\os.py, include\Python.h, " +
           "libs\python3*.lib, ensurepip, venv): $root")
}

# ---- install -------------------------------------------------------------------------------------------------------
if (Test-Path -LiteralPath $Dest) { Remove-Item -LiteralPath $Dest -Recurse -Force }
New-Item -ItemType Directory -Force (Split-Path -Parent $Dest) | Out-Null
Copy-Item -LiteralPath $root -Destination $Dest -Recurse -Force
Remove-Item -LiteralPath $Work -Recurse -Force

# pip is needed to build the wheels and to install them
$py = Join-Path $Dest 'python.exe'
& $py -m ensurepip --upgrade
if ($LASTEXITCODE -ne 0) { throw "fetch_python: ensurepip failed" }
$v = & $py -c "import sys; print(sys.version)"
Write-Host "Private Python is ready: $Dest`n$v"
