# openEMS with a CUDA engine

A fork of the electromagnetic field solver [openEMS](https://openems.de) (base: **v0.0.35**) with a GPU engine for
the FDTD time-stepping loop, selected with `--engine=cuda`. This repository also builds a **self-contained
package** for Windows: the executables, all DLLs, and a private Python with the matching Python modules, in one
folder that can be copied to another computer.

> **Status: experimental.** The engine stops with a clear error instead of computing something it cannot
> compute correctly, but it cannot guarantee that a result is physically right. Read
> [Known limitations](FDTD_CUDA/README.md#known-limitations) first.

## What it is good for

On a real model (a microstrip structure with lumped ports, about 6 million cells, RTX 3060) the CUDA engine ran
**about 12 times faster** than the multithreaded CPU engine, and the S-parameters computed from the port signals
of both engines differed by less than 5e-7 (relative; 25 000 time steps, `float` fields). This is one model on one
GPU, not a promise for every model. Details, verification status and limits: [FDTD_CUDA/README.md](FDTD_CUDA/README.md).

## Build (Windows)

Needs: Visual Studio with MSVC v143 (toolset 14.44), CUDA Toolkit 12.2, CMake 3.18 or newer, Ninja, Git, an NVIDIA
GPU and internet access (the first build downloads and builds the dependencies into `third_party\`, including a
private Python; nothing is installed outside the project folder; the dependencies are not pinned).

From a **plain cmd window** (not a "Developer Command Prompt", and a new window for every build):

```
build.cmd
```

Result: `build\out`, a complete package:

| Folder / file | Content |
|---|---|
| `openEMS.exe`, `nf2ff.exe`, `*.dll`, `include\`, `lib\`, `matlab\` | the solver, laid out like the official Windows package |
| `bin\` | a copy of the executables and DLLs |
| `venv\Scripts\` | a private CPython with the Python modules built from the same sources (`CSXCAD`, `openEMS`) and numpy, h5py, matplotlib; a plain copy of Python, not a virtual environment |
| `licenses\` | license texts and the exact sources of the build, see [NOTICE.md](NOTICE.md) |

Copy `build\out` to any place or to another computer as it is (an NVIDIA driver is needed there), or install it:

```
install_package.cmd C:\openEMS
```

(refuses a folder that it did not create itself: rename an old installation first).

## Use

```
openEMS.exe model.xml --engine=cuda
```

The Python modules are in `venv\Scripts\python.exe`. The KiCad plugin
RFsim (in the version that has the CUDA engine setting) finds `<folder>\bin\openEMS.exe` and
`<folder>\venv\Scripts\python.exe` by itself when the folder is `C:\openEMS` (otherwise set `OPENEMS_PATH`).

## Tests

```
third_party\python\python.exe tests\cuda\run_tests.py --exe build\out\openEMS.exe
```

28 cases: CUDA against the CPU engine, the multithreaded CPU engine against the basic one, refusals and error
handling. See [tests/cuda/README.md](tests/cuda/README.md).

## Documentation

* [FDTD_CUDA/README.md](FDTD_CUDA/README.md): the engine, options, exit codes, limitations, verification.
* [FDTD_CUDA/CHANGELOG_CUDA.md](FDTD_CUDA/CHANGELOG_CUDA.md): all changes relative to upstream v0.0.35.
* The original upstream README of openEMS is in the file `README`.

## License

GPLv3 (`COPYING`); the package contains other software under its own licenses: [NOTICE.md](NOTICE.md).
