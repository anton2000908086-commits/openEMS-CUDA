# Collects the result of a finished build into <build>\out, laid out like the official openEMS Windows
# package: executables and all runtime DLLs in the root, plus include\, lib\ and matlab\.
# It is called at the end of build_openems.ps1 and can be run alone:  powershell -File stage_out.ps1
# <build>\out is deleted and created again on every run, so it never keeps files of an older build.
# It needs 'dumpbin' (the MSVC environment loaded by build.cmd): the DLLs are found by following the
# imports of the programs, like vcpkg's applocal step does. A DLL that is neither a system DLL nor
# found in the known folders is an error (nothing is guessed).
param(
    [string]$Root      = $PSScriptRoot,
    [string]$Build     = $(Join-Path $PSScriptRoot 'build'),
    [string]$DepsRoot  = $(if ($env:OPENEMS_DEPS)       { $env:OPENEMS_DEPS }       else { Join-Path $PSScriptRoot 'third_party/deps' }),
    [string]$VcpkgRoot = $(if ($env:OPENEMS_VCPKG_ROOT) { $env:OPENEMS_VCPKG_ROOT } else { Join-Path $PSScriptRoot 'third_party/vcpkg' }),
    [string]$SrcRoot   = $(if ($env:OPENEMS_SRC)        { $env:OPENEMS_SRC }        else { Join-Path $PSScriptRoot 'third_party/src' }),
    [string]$Nvcc      = ''
)
$ErrorActionPreference = 'Stop'

$Root      = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
$Build     = [IO.Path]::GetFullPath($Build).TrimEnd('\','/')
$DepsRoot  = [IO.Path]::GetFullPath($DepsRoot).TrimEnd('\','/')
$VcpkgRoot = [IO.Path]::GetFullPath($VcpkgRoot).TrimEnd('\','/')
$SrcRoot   = [IO.Path]::GetFullPath($SrcRoot).TrimEnd('\','/')
$Out       = Join-Path $Build 'out'

function Need([string]$path) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "stage_out: file not found: $path" }
    return $path
}

if (-not (Get-Command dumpbin -ErrorAction SilentlyContinue)) {
    throw "stage_out: 'dumpbin' not found in PATH. Load the MSVC environment first (use build.cmd)."
}

# ---- the programs of the package ---------------------------------------------------------------------
$seeds = @(
    (Need "$Build/openEMS.exe"),
    (Need "$Build/openEMS.dll"),
    (Need "$Build/nf2ff/nf2ff.exe"),
    (Need "$Build/nf2ff/nf2ff.dll"),
    (Need "$DepsRoot/bin/CSXCAD.dll"),
    (Need "$DepsRoot/bin/fparser.dll")
)

# ---- where runtime DLLs may come from ------------------------------------------------------------------
$searchDirs = New-Object System.Collections.ArrayList
foreach ($d in @("$Build", "$Build/nf2ff", "$DepsRoot/bin", "$VcpkgRoot/installed/x64-windows/bin")) {
    if (Test-Path -LiteralPath $d -PathType Container) { [void]$searchDirs.Add($d) }
}
if ($env:VCToolsRedistDir) {
    foreach ($d in (Get-ChildItem -Path (Join-Path $env:VCToolsRedistDir 'x64') -Directory -Filter 'Microsoft.VC*.CRT' -ErrorAction SilentlyContinue)) {
        [void]$searchDirs.Add($d.FullName)
    }
}
if ($Nvcc -and (Test-Path -LiteralPath $Nvcc)) { [void]$searchDirs.Add((Split-Path -Parent $Nvcc)) }

function Test-SystemDll([string]$name) {
    if ($name -like 'api-ms-*' -or $name -like 'ext-ms-*') { return $true }
    return (Test-Path -LiteralPath (Join-Path $env:SystemRoot "System32/$name") -PathType Leaf)
}

function Get-Imports([string]$file) {
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'     # native stderr output must not abort the script
    $text = & dumpbin /nologo /dependents $file 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($code -ne 0) { throw "stage_out: dumpbin failed ($code) for $file" }
    # lines of the import list: four spaces and a DLL name (independent of the language of dumpbin)
    foreach ($line in $text) {
        if ("$line" -match '^\s+(\S+\.dll)\s*$') { $Matches[1] }
    }
}

# ---- follow the imports --------------------------------------------------------------------------------
$files      = @{}                       # lower-case name -> full path of every file that goes to the package
$queue      = New-Object System.Collections.Queue
$unresolved = New-Object System.Collections.ArrayList
foreach ($s in $seeds) {
    $files[(Split-Path -Leaf $s).ToLower()] = $s
    $queue.Enqueue($s)
}
while ($queue.Count -gt 0) {
    $cur = $queue.Dequeue()
    foreach ($dep in (Get-Imports $cur)) {
        $key = $dep.ToLower()
        if ($files.ContainsKey($key)) { continue }
        $path = $null
        foreach ($d in $searchDirs) {
            $cand = Join-Path $d $dep
            if (Test-Path -LiteralPath $cand -PathType Leaf) { $path = $cand; break }
        }
        if ($path) {
            $files[$key] = $path
            $queue.Enqueue($path)
        } elseif (-not (Test-SystemDll $dep)) {
            if ($unresolved -notcontains "$dep (needed by $(Split-Path -Leaf $cur))") {
                [void]$unresolved.Add("$dep (needed by $(Split-Path -Leaf $cur))")
            }
        }
    }
}
if ($unresolved.Count -gt 0) {
    throw ("stage_out: DLLs not found in any known folder (and not system DLLs):`n  " + ($unresolved -join "`n  ") +
           "`nSearched: " + ($searchDirs -join '; '))
}

# ---- create <build>\out --------------------------------------------------------------------------------
# safety: only a folder named 'out' directly inside the build folder is ever deleted
if ((Split-Path -Leaf $Out) -ne 'out' -or ([IO.Path]::GetFullPath((Split-Path -Parent $Out)).TrimEnd('\','/') -ne $Build)) {
    throw "stage_out: refusing to delete $Out"
}
if (Test-Path -LiteralPath $Out) { Remove-Item -LiteralPath $Out -Recurse -Force }
New-Item -ItemType Directory -Force $Out, "$Out/include/openEMS", "$Out/lib" | Out-Null

foreach ($p in $files.Values) { Copy-Item -LiteralPath $p -Destination $Out -Force }

# headers: those of the project (as in its INSTALL rules) and the ones of the dependencies
foreach ($h in @("$Root/openems.h", "$Root/openems_global.h", "$Root/nf2ff/nf2ff.h")) {
    Copy-Item -LiteralPath (Need $h) -Destination "$Out/include/openEMS" -Force
}
if (-not (Test-Path -LiteralPath "$DepsRoot/include" -PathType Container)) { throw "stage_out: folder not found: $DepsRoot/include" }
Copy-Item -Path "$DepsRoot/include/*" -Destination "$Out/include" -Recurse -Force

# import libraries
foreach ($l in @("$Build/openEMS.lib", "$Build/nf2ff/nf2ff.lib")) {
    Copy-Item -LiteralPath (Need $l) -Destination "$Out/lib" -Force
}
foreach ($pat in 'CSXCAD*.lib', 'fparser*.lib') {
    $found = Get-ChildItem -Path "$DepsRoot/lib" -File -Filter $pat -ErrorAction SilentlyContinue
    if (-not $found) { throw "stage_out: no $pat in $DepsRoot/lib" }
    $found | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination "$Out/lib" -Force }
}

# MATLAB / Octave scripts of the project
if (-not (Test-Path -LiteralPath "$Root/matlab" -PathType Container)) { throw "stage_out: folder not found: $Root/matlab" }
Copy-Item -LiteralPath "$Root/matlab" -Destination "$Out/matlab" -Recurse -Force

# ---- licenses ------------------------------------------------------------------------------------------------------------
# The package holds binaries of GPL / LGPL programs and of other libraries: their license texts travel with them.
# A missing text of the main components is an error (such a package must not be published); the texts of the
# libraries of vcpkg are collected as they are (each port keeps its own `copyright` file).
$lic = "$Out/licenses"
New-Item -ItemType Directory -Force "$lic/third-party" | Out-Null
Copy-Item -LiteralPath (Need "$Root/COPYING") -Destination "$lic/openEMS-COPYING-GPLv3.txt" -Force
Copy-Item -LiteralPath (Need "$Root/NOTICE.md") -Destination "$lic/NOTICE.md" -Force
Copy-Item -LiteralPath (Need "$SrcRoot/CSXCAD/COPYING") -Destination "$lic/CSXCAD-COPYING-LGPLv3.txt" -Force
Copy-Item -LiteralPath (Need "$SrcRoot/fparser/docs/lgpl.txt") -Destination "$lic/fparser-LGPLv3.txt" -Force
Copy-Item -LiteralPath (Need "$SrcRoot/fparser/docs/gpl.txt") -Destination "$lic/fparser-GPLv3.txt" -Force
$nports = 0
$share = "$VcpkgRoot/installed/x64-windows/share"
if (Test-Path -LiteralPath $share -PathType Container) {
    foreach ($d in (Get-ChildItem -LiteralPath $share -Directory)) {
        $c = Join-Path $d.FullName 'copyright'
        if (Test-Path -LiteralPath $c -PathType Leaf) {
            Copy-Item -LiteralPath $c -Destination "$lic/third-party/$($d.Name)-copyright.txt" -Force
            $nports++
        }
    }
}
if ($nports -eq 0) { throw "stage_out: no 'copyright' files found under $share" }
# the exact revisions that were built (the dependencies are not pinned), so that the sources can be found again
function GitInfo([string]$dir, [string]$name) {
    $h = 'unknown'; $u = 'unknown'
    try {
        $r = & git -C $dir rev-parse HEAD 2>$null;                  if ($LASTEXITCODE -eq 0 -and $r) { $h = "$r" }
        $r = & git -C $dir config --get remote.origin.url 2>$null; if ($LASTEXITCODE -eq 0 -and $r) { $u = "$r" }
    } catch { }
    return ("{0,-12} {1}  commit {2}" -f $name, $u, $h)
}
$rootRev = 'unknown'
try { $r = & git -C $Root describe --tags --always --dirty 2>$null; if ($LASTEXITCODE -eq 0 -and $r) { $rootRev = "$r" } } catch { }
Set-Content -LiteralPath "$lic/SOURCES.txt" -Encoding ASCII -Value @(
    "Sources of the binaries in this package (see NOTICE.md).",
    "",
    "openEMS-CUDA (this project, GPLv3): revision $rootRev",
    (GitInfo $Root 'openEMS-CUDA'),
    (GitInfo "$SrcRoot/CSXCAD" 'CSXCAD'),
    (GitInfo "$SrcRoot/fparser" 'fparser'),
    (GitInfo $VcpkgRoot 'vcpkg'),
    "",
    "The other libraries come from the ports of that vcpkg revision (source of every port: its portfile in",
    "<vcpkg>/ports/<name> and the upstream project named in the file third-party/<name>-copyright.txt).",
    "Python and its packages: https://www.python.org/ (NuGet package 'python') and https://pypi.org/ (wheels in venv)."
)
$cudaRoot = if ($Nvcc) { Split-Path -Parent (Split-Path -Parent $Nvcc) } elseif ($env:CUDA_PATH) { $env:CUDA_PATH } else { '' }
if ($cudaRoot -and (Test-Path -LiteralPath "$cudaRoot/EULA.txt" -PathType Leaf)) {
    Copy-Item -LiteralPath "$cudaRoot/EULA.txt" -Destination "$lic/NVIDIA-CUDA-EULA.txt" -Force
} else {
    Write-Warning "stage_out: the NVIDIA CUDA EULA (EULA.txt in the CUDA folder) was not found; copy it to $lic by hand"
}

# README
$rev = 'unknown'
try { $r = & git -C $Root describe --tags --always --dirty 2>$null; if ($LASTEXITCODE -eq 0 -and $r) { $rev = "$r" } } catch { }
$readme = @(
    "openEMS-CUDA (fork of openEMS, CUDA engine)",
    "Revision: $rev",
    "Built:    $((Get-Date).ToString('yyyy-MM-dd HH:mm'))",
    "",
    "Run:  openEMS.exe model.xml --engine=cuda",
    "Details: FDTD_CUDA/README.md of the source tree.",
    "",
    "Compared with the official openEMS package this one has NO: AppCSXCAD.exe, QCSXCAD, Qt DLLs and plugins\",
    "sar_calc.exe, CTB\, python\ (see below: the Python side is bin\ and venv\Scripts\), resources\phantoms\,",
    "include\QCSXCAD, include\openEMS\arraylib. Everything else is laid out the same way."
)
Set-Content -LiteralPath "$Out/README.txt" -Value ($readme -join "`r`n") -Encoding ASCII

$dllCount = @($files.Values | Where-Object { $_ -like '*.dll' }).Count
Write-Host "Package folder: $Out  ($dllCount DLLs, include\, lib\, matlab\, licenses\ with $nports library licenses)"
