# Changes to the CUDA engine

Changes of this fork relative to upstream openEMS **v0.0.35** (tag `upstream-base`), in the order they were made.
Files outside `FDTD_CUDA/` are marked **[upstream file]**; they are the places that will conflict when
the fork is moved to a newer upstream version.

## Stage 1: correctness of the first kernels
* `UpdateVoltages`: the z component used `v.y * vv.y`; now `v.z * vv.z`.
* `UpdateCurrents`: the neighbour of the z term was read at the wrong index; now `volt[x][y][z+1]`.
* Grid size by division rounded up; an empty grid is an error.
* Every CUDA call is checked (`CUDA_CHECK`), including `cudaDeviceSynchronize()` at the end of `IterateTS`.
* The device is selected and checked before the arrays are allocated.
* `~Engine_CUDA` releases the GPU memory (it was never released before).
* Self-test `OPENEMS_CUDA_SELFTEST=<steps>`.

## Stage 2: memory layout
* Fields and operator coefficients in flat `float4` arrays on the GPU, index `(x*Ny+y)*Nz+z`.
* The operator is built on the host and uploaded once when the engine is created.
* Host mirror of the fields with lazy synchronisation (`SyncToHost`, `SyncToDevice`).
* Block 32x4x2 with `threadIdx.x` along z.

## Stage 3: extensions on the GPU
* `IterateTS` calls the extensions in the order of `Engine::IterateTS`.
* UPML, excitation, Lorentz / Drude and Conducting Sheet on the GPU (`engine_ext_*_cuda`).
* Reading of fields and the energy estimate on the GPU (`engine_interface_cuda`, `OPENEMS_CUDA_CHECK_ENERGY`).

## Hardening (this work)
* Extensions without a GPU version are refused; `OPENEMS_CUDA_ALLOW_HOST_EXT` allows the host version.
  Cylindrical coordinates with `--engine=cuda` are refused (the CUDA engine used to be ignored silently).
* A failed `Init()` frees what it has allocated.
* Errors during set-up and simulation end with a message and exit code 3 or 4 (they were uncaught
  exceptions). Test hooks `OPENEMS_CUDA_TEST_FAIL_STEP` and `OPENEMS_CUDA_TEST_NAN_STEP`.
* The field energy is checked for NaN/Inf while the simulation runs and once more at the end of it.
  Before, a diverged simulation ended silently because every comparison with NaN is false.
* Excitation: entries that address the same field value are summed in a fixed order by one thread,
  instead of `atomicAdd`. The result is deterministic and equals the host version.
* CMake: `CMAKE_CUDA_ARCHITECTURES` is honoured (policy CMP0104), default `75;86;89`.

## Build system
* The CUDA sources moved to `FDTD_CUDA/` (pure rename, history kept).
* `build.cmd` and `build_openems.ps1` build the project and its dependencies into `third_party/`;
  no absolute paths, no changes to the sources by the script.

## Changes in upstream files
| File | Change |
|---|---|
| `CMakeLists.txt` **[upstream file]** | CUDA language, architectures and include directories, `/FIiso646.h` for MSVC, `VTK_USE_FILE` guarded |
| `FDTD/CMakeLists.txt` **[upstream file]** | CUDA sources added to the build |
| `openems.cpp` **[upstream file]** | CUDA includes, `NewEngineInterface` for the CUDA engine, error handling around the engine creation, refusal of cylindrical coordinates, NaN/Inf check of the energy |
| `main.cpp` **[upstream file]** | `try/catch` around `SetupFDTD` and `RunFDTD`, exit codes 3 and 4 |
| `FDTD/extensions/operator_ext_{dispersive,excitation,lorentzmaterial,upml}.h` **[upstream file]** | one `friend class` line each, so that the GPU extensions can read the operator data |
| `README`, `TODO` **[upstream file]** | a short pointer to this documentation; the open items of the CUDA engine appended to `TODO` |
| `.gitignore`, `.gitattributes` **[upstream file]** | `third_party/`, `*.log`; line-ending rules for the new files |

## Not done
* Steady-State Detection, Mur ABC and TFSF on the GPU.
* Verification of the Lorentz term of the ADE, of PML types other than `PML_8`, of `--cuda-device` other than 0.
* Batched voltage/current integrals, asynchronous field copies, DFT on the GPU.
* Performance tuning (CUDA graphs, streams, pinned memory, kernel fusion).
* A Linux build, and a comparison with upstream v0.37.0 on real models.
