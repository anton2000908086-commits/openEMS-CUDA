# CUDA engine for openEMS

A GPU FDTD engine for this fork of openEMS (base: **v0.0.35**). It is selected with `--engine=cuda`
and replaces the time-stepping loop of the CPU engines. The operator build, the mesh, the processing
(probes, dumps) and the extensions' set-up still run on the host.

> **Status: experimental.** Verified on small models and on one GPU (RTX 3060, `sm_86`, Windows).
> Read [Known limitations](#known-limitations) before trusting a result. The engine is built to stop with a
> clear error instead of computing something it cannot compute correctly; it cannot guarantee that a
> result is physically right.

## Quick start

Requirements: Visual Studio 2022 (MSVC v143, toolset 14.44), CUDA Toolkit 12.2, CMake (3.18 or newer),
Ninja, Git, an NVIDIA GPU. Everything else (vcpkg libraries, CSXCAD, fparser) is downloaded and built
into `third_party/` inside the project on the first build; nothing is installed outside the project folder.

```
build.cmd            :: from a plain cmd window; builds into .\build
build.cmd clean      :: remove .\build first (the dependencies in third_party are kept)
```

`build_openems.ps1 -RebuildDeps` rebuilds the dependencies. The locations can be overridden with the
environment variables `OPENEMS_VCPKG_ROOT`, `OPENEMS_DEPS` and `OPENEMS_SRC`; the CUDA architecture with
`-Arch` (default of the script: `86`; default of CMake if nothing is given: `75;86;89`).
The dependencies are **not pinned**: the first build takes the current versions.

Linux (**not verified**: written without a Linux machine, no run so far): `./build.sh` and `./build_openems.sh`.
Boost, HDF5, TinyXML and VTK come from the system packages (the script prints the `apt` line if they are
missing); fparser and CSXCAD are built into `third_party/` like on Windows. Needs CMake 3.18 or newer, nvcc
and a host gcc that the CUDA version supports (CUDA 12.2: gcc 12 or older; set `CUDAHOSTCXX=g++-12`
otherwise, the script refuses a newer gcc). Settings by environment variables: `CUDA_ARCH` (default `86`),
`CUDACXX`, `CUDAHOSTCXX`, `OPENEMS_DEPS`, `OPENEMS_SRC`, `REBUILD_DEPS=1`, `SKIP_SYS_CHECK=1`. After the
build `python3 tests/cuda/run_tests.py` should work the same way (the executable is `build/openEMS`).
If the shell scripts are not executable after checkout: `chmod +x build.sh build_openems.sh`.

Run a model:

```
openEMS.exe model.xml --engine=cuda [--cuda-device=<n>]
```

## What runs where

| Part | On the GPU | Notes |
|---|---|---|
| Voltage and current updates | yes | float4 arrays, block 32x4x2 |
| Excitation (soft, voltage and current) | yes | deterministic, see changelog |
| UPML | yes | verified as `PML_8` on all faces |
| Lorentz / Drude, Conducting Sheet | yes | verified, see "Verification status" |
| Energy estimate (end criterion) | yes | one reduction on the GPU |
| Mur ABC, TFSF, Steady-State Detection | **no** | refused unless allowed, see below |
| Cylindrical coordinates | **no** | always refused |
| Probes, field dumps, DFT, NF2FF | host | the fields are copied to the host first; slow for dumps |

Models that need an extension without a GPU implementation are **refused**:

```
openEMS::SetupFDTD: Error: CUDA engine: the model uses extensions that have no GPU implementation yet: Mur ABC Extension.
```

Options: use another engine (`--engine=multithreaded`), or set `OPENEMS_CUDA_ALLOW_HOST_EXT=1` to let these
extensions run on the host. That works, but the fields are copied between the GPU and the host in every
step, so it is slow. The log then shows `Extension runs on the host (slow)` for each such extension.

A periodic excitation (sinusoidal signal) adds a Steady-State Detection extension automatically, so it
needs `OPENEMS_CUDA_ALLOW_HOST_EXT=1` for now.

## Environment variables

| Variable | Effect |
|---|---|
| `OPENEMS_CUDA_ALLOW_HOST_EXT=1` | extensions without a GPU version run on the host instead of being refused |
| `OPENEMS_CUDA_HOST_EXT=1` | **all** extensions run on the host (reference runs for comparisons); implies the above |
| `OPENEMS_CUDA_SELFTEST=<steps>` | compare the kernels with a CPU reference on random fields, including a host-GPU-host round trip |
| `OPENEMS_CUDA_CHECK_ENERGY=1` | compare the energy computed on the GPU with the host value |
| `OPENEMS_CUDA_TEST_FAIL_STEP=<n>` | test hook: fail with an error at time step `n` |
| `OPENEMS_CUDA_TEST_NAN_STEP=<n>` | test hook: put a NaN into one voltage at time step `n` |

A value of `0` or an empty value switches a flag off. The two `TEST` variables exist to test the error
handling; do not set them in production.

## Errors and exit codes

| Exit code | Meaning |
|---|---|
| 0 | the simulation finished |
| 2 | the operator could not be set up (e.g. cylindrical coordinates with `--engine=cuda`) |
| 3 | error while setting up the engine (no GPU, device out of range, out of GPU memory, extension refused) |
| 4 | error during the simulation (CUDA error, or the field energy became NaN/Inf: the simulation diverged) |

After exit code 4 the result files written so far are **incomplete and must not be used**. CUDA errors
are checked after every call and at the end of every batch of time steps.

## Known limitations

* **Base version v0.0.35.** The series RLC lumped element (`LEtype`) and `TimeStepFactor` of later
  upstream versions are missing. A model that uses them gives a wrong result **without a warning**, on
  the CPU engines of this fork as well. Do not compare such models with results from v0.0.36 or newer.
* Mur ABC, TFSF and Steady-State Detection run only on the host (see "What runs where"); a periodic
  excitation therefore needs `OPENEMS_CUDA_ALLOW_HOST_EXT=1`.
* Cylindrical coordinates are not supported (they used to be silently ignored; now refused).
* Not verified on the GPU: PML other than `PML_8` on all faces, `--cuda-device`
  other than 0, several GPUs, MPI.
* Tested on one GPU model (RTX 3060, `sm_86`), Windows, CUDA 12.2. **The Linux build has not been tried.**
* Verification used small models (about 12 000 cells) against the CPU engines, apart from the speed
  measurement. No real board and no microstrip S-parameters have been compared with upstream v0.37.0.
* **Floating point.** The fields are `float`. GPU and CPU results are not bit-identical (different order of
  operations, fused multiply-add). In the strong signals of the test models the relative difference is
  about 1e-6 to 5e-5. Quantities that are zero by symmetry (for example `E_z` of a magnetic line source
  along z) contain only rounding noise, and the noise is different in every engine: when comparing engines
  use the component that is physically excited.
* Field dumps and other processing read the fields through the host: they download the whole field,
  there is no asynchronous copy, and no DFT on the GPU.

## Verification status

Done with the models of the self-test set (12 075 cells, 300 time steps), GPU compared with the `basic`
engine:

| Case | Result |
|---|---|
| E-field source in a PEC cavity, PML, Conducting Sheet | agree within the tolerance of the comparison script (about 4e-6 relative in the PEC model) |
| Overlapping (wire) excitation | agree; summation order is fixed |
| Sinusoidal excitation (with `OPENEMS_CUDA_ALLOW_HOST_EXT=1`) | agree |
| Magnetic (current) excitation along y and z | agree (1e-5 to 5e-5 relative) when the excited component is probed |
| Magnetic (current) excitation along x | near probe agrees (8e-6); the far probe differs by 1.1e-4 relative at a weak signal, not investigated further |
| Drude and Lorentz slab (electric pole, magnetic pole, both) | agree within the tolerance of the comparison script, after the fix of the `basic` reference described in the changelog ("Lorentz reference") |
| Mur boundary | refused; with `OPENEMS_CUDA_ALLOW_HOST_EXT=1` it runs and agrees |
| `compute-sanitizer` memcheck, racecheck, initcheck, synccheck on the PEC, PML and Conducting Sheet models | 0 errors |
| Injected CUDA failure / injected NaN | exit code 4 with a message |
| Rebuilt after moving the code to `FDTD_CUDA` | bit-identical to the build before the move |

`racecheck` only sees hazards in shared memory (the energy reduction); it cannot see races in global memory.

## Memory and speed

Per cell the GPU holds six `float4` arrays (voltage, current and four operator coefficient arrays):
**96 bytes per cell**, plus the buffers of the extensions. The host keeps a copy of the operator
(64 bytes per cell, for the lifetime of the operator) and a mirror of the fields (32 bytes per cell).
The log line `GPU memory for fields and operator` shows the actual figure. The operator is built on the
host, so a model has to fit into the host memory as well.

Speed on an RTX 3060: about 900 MCells/s for a model of about one million cells (measured before the
latest changes and not repeated); 270 to 400 MCells/s for the 12 000-cell test models, where the launch
overhead dominates (the CPU `basic` engine needs 12 to 33 MCells/s on the same models: 12 with PML).
With an extension on the host (`OPENEMS_CUDA_ALLOW_HOST_EXT=1`) the speed drops to the level of the CPU
engine or below it (14 to 30 MCells/s on the test models with Mur and with a sinusoidal excitation), so for
such models `--engine=multithreaded` is the better choice. No performance tuning has been done: no CUDA graphs, streams, pinned memory or kernel
fusion.

## Tests

`tests/cuda/` holds the regression tests (19 cases: comparison with the CPU engine, refusals, error
handling) and a runner for `compute-sanitizer`; see `tests/cuda/README.md`.

```
python tests/cuda/run_tests.py
python tests/cuda/run_sanitizer.py
```

## Source layout

| File | Content |
|---|---|
| `engine_cuda.cu/.h` | engine, voltage and current kernels, host mirror and synchronisation, self-test |
| `operator_cuda.cpp/.h` | operator coefficients built on the host in flat `float4` arrays |
| `engine_cuda_ext.cpp` | choice between the GPU and the host version of every extension, refusal |
| `engine_ext_upml_cuda.*`, `upml_kernels_cuda.*` | UPML |
| `engine_ext_excitation_cuda.*`, `excitation_kernels_cuda.*` | excitation |
| `engine_ext_lorentz_cuda.*`, `lorentz_kernels_cuda.*` | Lorentz / Drude and Conducting Sheet |
| `engine_interface_cuda.*` | field access and the energy estimate on the GPU |
| `cuda_vec.h` | `float4` component access |

The changes outside this folder are listed in [CHANGELOG_CUDA.md](CHANGELOG_CUDA.md).

## License

The same as openEMS: GPLv3 (see `COPYING` at the root of the repository).
