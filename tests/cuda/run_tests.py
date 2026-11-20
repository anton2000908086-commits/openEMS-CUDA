#!/usr/bin/env python3
"""Regression tests of the CUDA engine (Windows and Linux, Python 3, standard library only).

  python run_tests.py [--exe PATH] [--repo PATH] [-v] [--list] [name ...]

Every case runs a model with the basic (CPU) engine and with the CUDA engine and compares the probe
files, or checks that the CUDA engine refuses / stops with the expected exit code.
The results are written to tests/cuda/work/ (not under version control). Exit code 0: all cases passed.
"""
import argparse, collections, contextlib, io, os, re, shutil, subprocess, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import compare_runs

ALLOW = {"OPENEMS_CUDA_ALLOW_HOST_EXT": "1"}

Case = collections.namedtuple("Case", "name model env kind arg tol note")

def C(name, model, env=None, kind="compare", arg=None, tol=1e-4, note=""):
    return Case(name, model, env or {}, kind, arg, tol, note)

# kind "compare": both engines must finish and agree within tol (relative to the largest value)
# kind "exit":    the CUDA run must end with exit code arg[0] and its log must contain arg[1]
CASES = [
    C("pec",         "selftest.xml",       note="E-field source in a PEC cavity"),
    C("pml",         "selftest_pml.xml",   note="PML_8 on all faces"),
    C("sheet",       "selftest_sheet.xml", note="PML_8 and a Conducting Sheet"),
    C("wire",        "selftest_wire.xml",  note="overlapping wire excitation (deterministic sum)"),
    C("drude",       "selftest_drude.xml", note="Drude slab (plasma frequency and relaxation time, no Lorentz pole)"),
    C("lorentz",     "selftest_lorentz.xml", note="Lorentz slab with electric and magnetic poles (Lorentz term of the ADE)"),
    C("lorentz_e",   "selftest_lorentz_e.xml", note="Lorentz slab, electric pole only"),
    C("lorentz_m",   "selftest_lorentz_m.xml", note="Lorentz slab, magnetic pole only"),
    C("lorentz_host","selftest_lorentz.xml", env={"OPENEMS_CUDA_HOST_EXT": "1"}, note="Lorentz slab, all extensions on the host inside the CUDA engine"),
    C("curr_z",      "selftest_curr.xml",  note="magnetic source along z, probe along x"),
    C("curr_y",      "selftest_curry.xml", note="magnetic source along y"),
    C("curr_x",      "selftest_currx.xml", tol=5e-4, note="magnetic source along x (weak far probe, looser tolerance)"),
    C("sine_host",   "selftest_sine.xml",  env=ALLOW, note="periodic excitation, Steady-State Detection on the host"),
    C("sine_refused","selftest_sine.xml",  kind="exit", arg=(3, "no GPU implementation"), note="same without the permission: refused"),
    C("mur_host",    "selftest_mur.xml",   env=ALLOW, note="Mur boundary on the host"),
    C("mur_refused", "selftest_mur.xml",   kind="exit", arg=(3, "no GPU implementation"), note="same without the permission: refused"),
    C("kernel_selftest", "selftest.xml",   env={"OPENEMS_CUDA_SELFTEST": "20"}, kind="exit", arg=(0, ""), note="kernels against the CPU reference (exit code only)"),
    C("inject_fail", "selftest.xml",       env={"OPENEMS_CUDA_TEST_FAIL_STEP": "100"}, kind="exit", arg=(4, "test failure injected"), note="error during the run"),
    C("inject_nan",  "selftest.xml",       env={"OPENEMS_CUDA_TEST_NAN_STEP": "150"}, kind="exit", arg=(4, "diverged"), note="NaN in the fields is detected"),
]

def default_exe(repo):
    return os.path.join(repo, "build", "openEMS.exe" if os.name == "nt" else "openEMS")

def make_env(repo, extra=None):
    """Environment of a run: no inherited OPENEMS_CUDA_* switches; the libraries of the project on the path."""
    env = {k: v for k, v in os.environ.items() if not k.startswith("OPENEMS_CUDA_")}
    dirs = [os.path.join(repo, "third_party", "deps", "bin"), os.path.join(repo, "third_party", "deps", "lib"),
            os.path.join(repo, "third_party", "vcpkg", "installed", "x64-windows", "bin"), os.path.join(repo, "build")]
    dirs = [d for d in dirs if os.path.isdir(d)]
    env["PATH"] = os.pathsep.join(dirs + [env.get("PATH", "")])
    if os.name != "nt":
        env["LD_LIBRARY_PATH"] = os.pathsep.join(dirs + [env.get("LD_LIBRARY_PATH", "")])
    env.update(extra or {})
    return env

def run_engine(cmd_prefix, model_path, engine, workdir, env, timeout):
    """Run one model; returns (exit code, log text). cmd_prefix: [exe] or [sanitizer, options..., exe]."""
    if os.path.isdir(workdir):
        shutil.rmtree(workdir)
    os.makedirs(workdir)
    shutil.copy(model_path, workdir)
    name = os.path.basename(model_path)
    cmd = list(cmd_prefix) + [name, "--engine=" + engine, "--disable-dumps"]
    t0 = time.time()
    try:
        with open(os.path.join(workdir, "run.log"), "wb") as log:
            code = subprocess.run(cmd, cwd=workdir, env=env, stdout=log, stderr=subprocess.STDOUT, timeout=timeout).returncode
    except subprocess.TimeoutExpired:
        code = -999
    text = open(os.path.join(workdir, "run.log"), errors="ignore").read()
    return code, text

def speed(text):
    m = re.findall(r"Speed:\s*([0-9.eE+-]+)\s*MCells/s", text)
    return float(m[-1]) if m else None

class Runner:
    def __init__(self, exe, repo, work, timeout, verbose):
        self.exe, self.repo, self.work, self.timeout, self.verbose = exe, repo, work, timeout, verbose
        self.basic = {}  # model -> (ok, dir, speed)

    def basic_run(self, model):
        if model not in self.basic:
            d = os.path.join(self.work, "basic", os.path.splitext(model)[0])
            code, text = run_engine([self.exe], os.path.join(HERE, "models", model), "basic", d, make_env(self.repo), self.timeout)
            self.basic[model] = (code == 0, d, speed(text), code)
        return self.basic[model]

    def run(self, case):
        model_path = os.path.join(HERE, "models", case.model)
        cdir = os.path.join(self.work, case.name)
        code, text = run_engine([self.exe], model_path, "cuda", cdir, make_env(self.repo, case.env), self.timeout)
        if case.kind == "exit":
            want, needle = case.arg
            ok = (code == want) and (needle in text)
            return ok, "exit code %d (expected %d)%s" % (code, want, "" if needle in text else ", message not found: '%s'" % needle)
        ok_b, bdir, sp_b, code_b = self.basic_run(case.model)
        if not ok_b:
            return False, "the basic engine failed (exit code %d)" % code_b
        if code != 0:
            return False, "the CUDA engine failed (exit code %d), see %s" % (code, os.path.join(cdir, "run.log"))
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = compare_runs.main(bdir, cdir, case.tol)
        if self.verbose or rc != 0:
            print("    " + buf.getvalue().replace("\n", "\n    ").rstrip())
        sp = speed(text)
        extra = "  (%.0f MCells/s GPU, %.0f MCells/s CPU)" % (sp, sp_b) if sp and sp_b else ""
        return rc == 0, "tolerance %g%s" % (case.tol, extra)

def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", help="run only the cases whose name contains one of these words")
    ap.add_argument("--repo", default=os.path.abspath(os.path.join(HERE, "..", "..")), help="repository root")
    ap.add_argument("--exe", help="openEMS executable (default: <repo>/build/openEMS[.exe])")
    ap.add_argument("--work", default=os.path.join(HERE, "work"), help="folder for the results")
    ap.add_argument("--timeout", type=int, default=900, help="seconds per run")
    ap.add_argument("--list", action="store_true", help="list the cases and exit")
    ap.add_argument("-v", "--verbose", action="store_true")
    a = ap.parse_args()

    if a.list:
        for c in CASES:
            print("%-16s %-22s %s" % (c.name, c.model, c.note))
        return 0
    exe = a.exe or default_exe(a.repo)
    if not os.path.isfile(exe):
        print("openEMS executable not found: %s" % exe)
        return 2
    cases = [c for c in CASES if not a.names or any(n in c.name for n in a.names)]
    if not cases:
        print("no case matches")
        return 2
    print("executable: %s\nresults:    %s\n" % (exe, a.work))
    r = Runner(exe, a.repo, a.work, a.timeout, a.verbose)
    results = []
    for c in cases:
        print("%-16s %-22s ..." % (c.name, c.model), flush=True)
        ok, detail = r.run(c)
        results.append((c, ok, detail))
        print("%-16s %s  %s" % (c.name, "PASS" if ok else "FAIL", detail), flush=True)
    failed = [c.name for c, ok, _ in results if not ok]
    print("\n%d of %d cases passed" % (len(results) - len(failed), len(results)))
    if failed:
        print("FAILED: " + ", ".join(failed))
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
