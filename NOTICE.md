# License and components

This project (openEMS with the CUDA engine of this fork) is distributed under the **GNU General Public
License, version 3** (`COPYING`). A binary package built from it (`build\out`, made by `build.cmd`) contains
other software under its own licenses. Everything is collected below; the **authoritative texts** are the files
in the folder `licenses\` of the package (and, for the libraries of vcpkg, in `licenses\third-party\`).

| Component | Where it is | License (as declared by its project) |
|---|---|---|
| openEMS, nf2ff and the CUDA engine of this fork | `openEMS.exe`, `openEMS.dll`, `nf2ff.exe`, `nf2ff.dll` | GPLv3 (`openEMS-COPYING-GPLv3.txt`) |
| CSXCAD | `CSXCAD.dll`, Python module `CSXCAD` | LGPLv3 (`CSXCAD-COPYING-LGPLv3.txt`) |
| fparser | `fparser.dll` | LGPLv3 (`fparser-LGPLv3.txt`, `fparser-GPLv3.txt`) |
| Boost, HDF5 (with libaec), VTK, TinyXML, zlib, expat, lz4, liblzma, pugixml, double-conversion | DLLs in the package root and in `bin\` (there is no separate TinyXML DLL) | each under its own license, see `licenses\third-party\<name>-copyright.txt` |
| Microsoft Visual C++ runtime | `MSVCP140.dll`, `VCRUNTIME140.dll`, `VCRUNTIME140_1.dll` | redistributed under the terms of the Microsoft Visual C++ Redistributable |
| NVIDIA CUDA runtime | linked statically into `openEMS.dll` | NVIDIA CUDA Toolkit EULA (`NVIDIA-CUDA-EULA.txt`) |
| Python | `venv\Scripts\` (a copy of CPython) | Python Software Foundation License (`Python-LICENSE.txt`) |
| numpy, h5py, matplotlib and their dependencies | `venv\Scripts\Lib\site-packages\` | the license files of each package are in its `.dist-info` folder |

The combination is distributed under the GPLv3 because it links the GPL-licensed openEMS code.

## Source code

* This project: this repository, at the revision named in `licenses\SOURCES.txt`.
* CSXCAD and fparser are fetched from `github.com/thliebig/CSXCAD` and `github.com/thliebig/fparser` by
  `build_openems.ps1` (not pinned); the exact commits of a build are written to `licenses\SOURCES.txt`
  together with the vcpkg revision that provided the other libraries.
* Python and the wheels: <https://www.python.org/>, <https://pypi.org/>. The wheels `CSXCAD` and `openEMS` are
  built from the sources above by `build_python.ps1`.

## Credits

openEMS and CSXCAD are the work of Thorsten Liebig and contributors (<https://openems.de>). The first CUDA
prototype (2022) in the history of this fork comes from the repository `aWZHY0yQH81uOYvH/openEMS-CUDA`.
