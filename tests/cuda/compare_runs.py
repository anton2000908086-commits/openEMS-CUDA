import os, sys

def read_table(path):
    rows = []
    with open(path, "r", errors="ignore") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("%") or line.startswith("#"):
                continue
            try:
                rows.append([float(v) for v in line.split()])
            except ValueError:
                return None
    return rows or None

def main(dir_a, dir_b, tol=1e-4):
    skip = (".xml", ".log", ".h5", ".vtk", ".vtr", ".vtp")
    names = sorted(n for n in os.listdir(dir_a)
                   if os.path.isfile(os.path.join(dir_a, n)) and not n.lower().endswith(skip))
    compared = 0
    failed = False
    for n in names:
        pb = os.path.join(dir_b, n)
        if not os.path.isfile(pb):
            print(f"{n}: missing in {dir_b}")
            failed = True
            continue
        a = read_table(os.path.join(dir_a, n))
        b = read_table(pb)
        if a is None or b is None:
            continue
        compared += 1
        if len(a) != len(b) or len(a[0]) != len(b[0]):
            print(f"{n}: different size ({len(a)}x{len(a[0])} vs {len(b)}x{len(b[0])})  FAILED")
            failed = True
            continue
        max_ref = max(abs(v) for row in a for v in row[1:]) if len(a[0]) > 1 else 0.0
        max_err = max(abs(x - y) for ra, rb in zip(a, b) for x, y in zip(ra[1:], rb[1:])) if len(a[0]) > 1 else 0.0
        rel = max_err / max_ref if max_ref > 0 else max_err
        ok = rel < tol and max_ref > 0
        failed |= not ok
        note = "" if max_ref > 0 else "  (reference is all zero)"
        print(f"{n}: {len(a)} rows, max|ref|={max_ref:.6g}, max abs err={max_err:.3g}, relative={rel:.3g}  {'OK' if ok else 'FAILED'}{note}")
    if compared == 0:
        print("no numeric probe files found to compare")
        failed = True
    print("RESULT:", "FAILED" if failed else "OK")
    return 1 if failed else 0

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: compare_runs.py <dir_basic> <dir_cuda>")
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
