# Copies the finished package (build\out, made by build.cmd) to a folder, for example C:\openEMS:
#     install_package.cmd [target]        target defaults to C:\openEMS
# build\out is already complete (exe, DLLs, bin\, venv\Scripts\ with its own Python), so it can also be copied by
# hand to any computer and to any place; this script only does that copy safely and checks the result.
# Safety: the target must be missing, empty, or a folder that this script installed before (it holds the file
# INSTALLED_BY_OPENEMS_CUDA.txt, then the old content is replaced as a whole). Any other folder, for example an
# official openEMS package, is refused, because mixing files of two builds is what this avoids: rename the old
# folder first. Close KiCad and every openEMS run before installing: running files cannot be replaced.
param(
    [string]$Target = 'C:\openEMS',
    [string]$Build  = $(Join-Path $PSScriptRoot 'build')
)
$ErrorActionPreference = 'Stop'

$Target = [IO.Path]::GetFullPath($Target).TrimEnd('\','/')
$Build  = [IO.Path]::GetFullPath($Build).TrimEnd('\','/')
$Out    = Join-Path $Build 'out'
$Marker = Join-Path $Target 'INSTALLED_BY_OPENEMS_CUDA.txt'

# ---- checks -----------------------------------------------------------------------------------------------
if ($Target.Length -lt 4 -or $Target -eq $Out -or $Target.StartsWith($Build) -or $PSScriptRoot.StartsWith($Target)) {
    throw "install_package: refusing this target: $Target"
}
foreach ($f in @("$Out\openEMS.exe", "$Out\bin\openEMS.exe", "$Out\venv\Scripts\python.exe")) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "install_package: $f not found. Run build.cmd first (it must finish without errors)." }
}
if (Test-Path -LiteralPath $Target) {
    $items = @(Get-ChildItem -LiteralPath $Target -Force)
    if ($items.Count -gt 0 -and -not (Test-Path -LiteralPath $Marker -PathType Leaf)) {
        throw ("install_package: $Target is not empty and was not installed by this script. Rename or remove it first " +
               "(for example: ren $Target $(Split-Path -Leaf $Target)_old), then run this again.")
    }
}

# ---- replace what an earlier install of this script put there ---------------------------------------------------------
if (Test-Path -LiteralPath $Marker) {
    Write-Host "Removing the previous installation in $Target"
    Get-ChildItem -LiteralPath $Target -Force | ForEach-Object { Remove-Item -LiteralPath $_.FullName -Recurse -Force }
}
New-Item -ItemType Directory -Force $Target | Out-Null
Write-Host "Copying $Out to $Target"
& robocopy $Out $Target /E /NFL /NDL /NJH /NJS /NP | Out-Null
if ($LASTEXITCODE -ge 8) { throw "install_package: copy failed (robocopy $LASTEXITCODE)" }
$global:LASTEXITCODE = 0

# ---- checks, with a minimal environment ------------------------------------------------------------------------------------
Remove-Item Env:PYTHONHOME, Env:PYTHONPATH -ErrorAction SilentlyContinue
$savedPath = $env:PATH
$env:PATH = "$env:SystemRoot\System32;$env:SystemRoot"
try {
    $py = Join-Path $Target 'venv\Scripts\python.exe'
    & $py -c "import sys, CSXCAD, openEMS; print('python modules ok:', sys.prefix)"
    if ($LASTEXITCODE -ne 0) { throw "install_package: the Python modules do not import from $py" }
    $eap = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $usage = (& (Join-Path $Target 'bin\openEMS.exe') 2>&1 | Out-String)
    $ErrorActionPreference = $eap
    if ($usage -notmatch '--engine=cuda') { throw "install_package: $Target\bin\openEMS.exe does not list --engine=cuda" }
    Write-Host "bin\openEMS.exe lists --engine=cuda"
}
finally { $env:PATH = $savedPath }

$rev = (Get-Content -LiteralPath "$Out\README.txt" -ErrorAction SilentlyContinue | Select-Object -First 2) -join ' / '
Set-Content -LiteralPath $Marker -Encoding ASCII -Value @(
    "Installed by install_package.ps1 of openEMS-CUDA. $rev",
    "Installed: $((Get-Date).ToString('yyyy-MM-dd HH:mm'))",
    "This file marks the folder as safe to replace by the next run of the script."
)
Write-Host "`nInstalled to $Target"
if ($Target -ne 'C:\openEMS') {
    Write-Host "RFsim finds C:\openEMS by itself. For this folder set OPENEMS_PATH=$Target (for KiCad)."
}
