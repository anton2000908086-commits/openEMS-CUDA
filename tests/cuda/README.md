# Tests of the CUDA engine

Regression tests that compare the CUDA engine with the CPU engine (`basic`) on small models, and check
that the engine refuses or stops with a clear error where it should. The cases `mt_*` compare the
multithreaded CPU engine with `basic`, so that a CPU engine that silently skips the extensions cannot
go unnoticed. They need a built `openEMS`, an
NVIDIA GPU and Python 3 (standard library only). Nothing is installed or written outside this folder:
the results go to `tests/cuda/work/`.

## Run

```
python tests/cuda/run_tests.py                 # all cases
python tests/cuda/run_tests.py pml wire        # cases whose name contains one of the words
python tests/cuda/run_tests.py --list          # list the cases
python tests/cuda/run_tests.py -v              # show the comparison tables also for passed cases
python tests/cuda/run_sanitizer.py             # compute-sanitizer: memcheck, racecheck, initcheck, synccheck
```

The executable is taken from `build/openEMS` (`build\openEMS.exe` on Windows); use `--exe` for another one.
The libraries in `third_party/` and `build/` are put on the path of the test runs automatically, and all
`OPENEMS_CUDA_*` variables of your shell are removed, so that a variable left over from an earlier
experiment cannot change a result. Exit code 0 means that all cases passed.

## Cases

| Case | Model | What it checks | Expected |
|---|---|---|---|
| `pec` | `selftest.xml` | E-field source in a PEC cavity (25x23x21 cells, 300 steps) | agree |
| `pml` | `selftest_pml.xml` | PML_8 on all faces | agree |
| `sheet` | `selftest_sheet.xml` | PML_8 and a Conducting Sheet | agree |
| `wire` | `selftest_wire.xml` | wire excitation that overlaps itself: entries summed in a fixed order | agree |
| `drude` | `selftest_drude.xml` | a slab of Drude material (plasma frequency and relaxation time) | agree |
| `lorentz` | `selftest_lorentz.xml` | a slab of Lorentz material, electric and magnetic poles (the Lorentz term of the ADE) | agree |
| `lorentz_e`, `lorentz_m` | `selftest_lorentz_e.xml`, `selftest_lorentz_m.xml` | the same slab with only the electric or only the magnetic pole | agree |
| `lorentz_host` | `selftest_lorentz.xml` | the Lorentz slab with `OPENEMS_CUDA_HOST_EXT=1` (all extensions on the host); separates a fault of the GPU extension from a fault of the engine | agree |
| `curr_z`, `curr_y`, `curr_x` | `selftest_curr.xml`, `..._curry.xml`, `..._currx.xml` | magnetic (current) source along z, y, x | agree |
| `sine_host` | `selftest_sine.xml` | periodic excitation; Steady-State Detection runs on the host | agree |
| `sine_refused` | `selftest_sine.xml` | the same without `OPENEMS_CUDA_ALLOW_HOST_EXT=1` | exit code 3, message |
| `mur_host` | `selftest_mur.xml` | Mur boundary on one face, on the host | agree |
| `mur_refused` | `selftest_mur.xml` | the same without the permission | exit code 3, message |
| `kernel_selftest` | `selftest.xml` | `OPENEMS_CUDA_SELFTEST=20`: kernels against the CPU reference | exit code 0 |
| `inject_fail` | `selftest.xml` | `OPENEMS_CUDA_TEST_FAIL_STEP=100`: error during the run | exit code 4, message |
| `inject_nan` | `selftest.xml` | `OPENEMS_CUDA_TEST_NAN_STEP=150`: NaN is detected | exit code 4, message |
| `mt_pec`, `mt_pml`, `mt_sheet`, `mt_wire`, `mt_drude`, `mt_lorentz`, `mt_curr_z`, `mt_sine`, `mt_mur` | the models of the cases above (`selftest*.xml`) | the multithreaded CPU engine (the default CPU engine of openEMS and RFsim) against `basic`: excitation, PML, sheet, dispersive materials, Steady-State and Mur must give the same probes. No CUDA run. Another CPU engine is added in `CPU_ENGINES` of `run_tests.py` | agree |

"Agree" means: both engines finish, and in every probe file the largest difference is below the tolerance
(1e-4 of the largest value; 5e-4 for `curr_x`, whose far probe has a weak signal).

Notes:

* Float results of the GPU and the CPU are not bit-identical. Compare the physically **excited**
  component: a quantity that is zero by symmetry (for example `E_z` of a magnetic line source along z)
  contains only rounding noise, and that noise differs from engine to engine. For this reason the probes
  of `selftest_curr.xml` measure the voltage along x.
* In `selftest_mur.xml` the only change against `selftest.xml` is `xmin="2"` (code 2 = Mur) in `BoundaryCond`.
* The comparison program `compare_runs.py` can also be used by hand:
  `python compare_runs.py <folder_basic> <folder_cuda>`.

## Speed measurement

`bench_model.py N STEPS [out.xml]` writes a model with N x N x N cells (1 mm), PML_8 on all faces, a copper
sheet and a source in the centre. For example `python bench_model.py 100 2000 bench.xml` is one million
cells; run it with `--engine=basic` and `--engine=cuda` and compare the `Speed:` lines of the logs.

## Adding a case

Put the model into `models/` and add a line to the list `CASES` in `run_tests.py`. For a case that
compares the engines the model must write numeric probe files (voltage or current probes); a model that
only produces dumps is skipped by the comparison and reported as "no numeric probe files found".
