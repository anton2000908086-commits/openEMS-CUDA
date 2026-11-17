#!/usr/bin/env python3
"""Run compute-sanitizer tools over the test models with the CUDA engine.

  python run_sanitizer.py [--tools memcheck racecheck initcheck synccheck] [--models selftest selftest_pml ...]

Needs compute-sanitizer from the CUDA toolkit (found through --sanitizer, COMPUTE_SANITIZER, PATH or CUDA_PATH).
Under the sanitizer a run is much slower than normally. Exit code 0: no errors reported.
"""
import argparse, glob, os, shutil, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import run_tests

DEFAULT_MODELS = ["selftest", "selftest_pml", "selftest_sheet"]
DEFAULT_TOOLS = ["memcheck", "racecheck", "initcheck", "synccheck"]

def find_sanitizer(given):
    exe = "compute-sanitizer.exe" if os.name == "nt" else "compute-sanitizer"
    cands = [given, os.environ.get("COMPUTE_SANITIZER"), shutil.which("compute-sanitizer")]
    if os.environ.get("CUDA_PATH"):
        cands.append(os.path.join(os.environ["CUDA_PATH"], "compute-sanitizer", exe))
    if os.name == "nt":
        cands += sorted(glob.glob(r"C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA\v*\compute-sanitizer\compute-sanitizer.exe"), reverse=True)
    else:
        cands += sorted(glob.glob("/usr/local/cuda*/compute-sanitizer/compute-sanitizer"), reverse=True)
    for c in cands:
        if c and os.path.isfile(c):
            return c
    return None

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--tools", nargs="+", default=DEFAULT_TOOLS)
    ap.add_argument("--models", nargs="+", default=DEFAULT_MODELS, help="model names without .xml (from models/)")
    ap.add_argument("--repo", default=os.path.abspath(os.path.join(HERE, "..", "..")))
    ap.add_argument("--exe")
    ap.add_argument("--sanitizer")
    ap.add_argument("--work", default=os.path.join(HERE, "work", "sanitizer"))
    ap.add_argument("--timeout", type=int, default=3600)
    a = ap.parse_args()

    exe = a.exe or run_tests.default_exe(a.repo)
    san = find_sanitizer(a.sanitizer)
    if not os.path.isfile(exe):
        print("openEMS executable not found: %s" % exe)
        return 2
    if not san:
        print("compute-sanitizer not found (use --sanitizer or set COMPUTE_SANITIZER)")
        return 2
    env = run_tests.make_env(a.repo)
    bad = 0
    for m in a.models:
        for t in a.tools:
            model = os.path.join(HERE, "models", m + ".xml")
            code, text = run_tests.run_engine([san, "--tool", t, "--error-exitcode", "99", exe], model, "cuda",
                                              os.path.join(a.work, "%s_%s" % (m, t)), env, a.timeout)
            summary = [l.strip("= \r") for l in text.splitlines() if "SUMMARY" in l]
            ok = code == 0 and bool(summary) and all("0 errors" in l for l in summary)
            bad += not ok
            print("%-16s %-10s %s  %s" % (m, t, "PASS" if ok else "FAIL", "; ".join(summary) or "exit code %d, no summary" % code), flush=True)
    print("\n%s" % ("all runs clean" if not bad else "%d run(s) reported problems" % bad))
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
