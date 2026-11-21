#!/usr/bin/env bash
# Builds openEMS-CUDA on Linux. NOT VERIFIED: written without a Linux machine, see FDTD_CUDA/README.md.
#
# Boost, HDF5, TinyXML and VTK come from the system (development packages, see the message below if
# they are missing). fparser and CSXCAD are downloaded and built into third_party/ inside the project;
# nothing is installed outside the project folder. The dependencies are not pinned (same as Windows).
#
# Environment variables (all optional):
#   CUDA_ARCH         GPU architecture, default 86 (RTX 3060); "native" needs a visible GPU at build time
#   CUDACXX           path of nvcc (default: nvcc from PATH, then /usr/local/cuda/bin/nvcc)
#   CUDAHOSTCXX       host compiler for nvcc (CUDA 12.2 supports gcc up to 12; set e.g. g++-12)
#   OPENEMS_DEPS      install prefix of fparser and CSXCAD (default third_party/deps)
#   OPENEMS_SRC       source folder of fparser and CSXCAD (default third_party/src)
#   REBUILD_DEPS=1    rebuild fparser and CSXCAD
#   SKIP_SYS_CHECK=1  skip the check of the system development packages
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_ROOT="${OPENEMS_DEPS:-$ROOT/third_party/deps}"
SRC_ROOT="${OPENEMS_SRC:-$ROOT/third_party/src}"
ARCH="${CUDA_ARCH:-86}"
BUILD="$ROOT/build"
LOG="$ROOT/build_openems.log"

die() { echo "ERROR: $*" >&2; exit 1; }
run() { echo ">>> $*"; "$@"; }

# ---- tools -----------------------------------------------------------------------------------
for tool in cmake git g++; do
    command -v "$tool" >/dev/null 2>&1 || die "'$tool' not found in PATH"
done
if command -v ninja >/dev/null 2>&1; then
    GENERATOR=Ninja; KEEP_GOING=(-- -k 0)
else
    GENERATOR="Unix Makefiles"; KEEP_GOING=(-- -k -j"$(nproc)")
    echo "NOTE: ninja not found, using make"
fi

cmake_ver="$(cmake --version | head -n1 | sed 's/[^0-9.]*//; s/[^0-9.].*//')"
if [ "$(printf '%s\n3.18\n' "$cmake_ver" | sort -V | head -n1)" != "3.18" ]; then
    die "CMake $cmake_ver is too old, 3.18 or newer is required"
fi

NVCC="${CUDACXX:-}"
[ -z "$NVCC" ] && NVCC="$(command -v nvcc || true)"
[ -z "$NVCC" ] && [ -x /usr/local/cuda/bin/nvcc ] && NVCC=/usr/local/cuda/bin/nvcc
[ -n "$NVCC" ] && [ -x "$NVCC" ] || die "nvcc not found (put it in PATH or set CUDACXX=/path/to/nvcc)"
cuda_rel="$("$NVCC" --version | sed -n 's/.*release \([0-9]*\.[0-9]*\).*/\1/p' | head -n1)"
echo "nvcc: $NVCC (CUDA $cuda_rel)"

HOSTCXX="${CUDAHOSTCXX:-g++}"
command -v "$HOSTCXX" >/dev/null 2>&1 || die "host compiler '$HOSTCXX' not found"
gcc_major="$("$HOSTCXX" -dumpversion | cut -d. -f1)"
echo "host compiler: $HOSTCXX (version $gcc_major)"
# Refuse clearly instead of letting nvcc fail with a long message (and without --allow-unsupported-compiler).
# Known limits of the host gcc: CUDA 12.0-12.3 -> 12, 12.4-12.5 -> 13. Other CUDA versions are not checked.
max_gcc=""
case "$cuda_rel" in
    12.0|12.1|12.2|12.3) max_gcc=12 ;;
    12.4|12.5)           max_gcc=13 ;;
esac
if [ -n "$max_gcc" ] && [ "$gcc_major" -gt "$max_gcc" ] 2>/dev/null; then
    die "host compiler $HOSTCXX (gcc $gcc_major) is newer than CUDA $cuda_rel supports (gcc $max_gcc); install an older gcc and set CUDAHOSTCXX=g++-$max_gcc"
fi

# ---- system development packages ------------------------------------------------------------------
check_sys() {
    local missing=()
    local inc=(/usr/include /usr/local/include)
    have_file() { find "${inc[@]}" -maxdepth 3 -name "$1" 2>/dev/null | grep -q .; }
    [ -f /usr/include/boost/version.hpp ] || [ -f /usr/local/include/boost/version.hpp ] || missing+=(libboost-all-dev)
    have_file hdf5.h         || missing+=(libhdf5-dev)
    have_file tinyxml.h      || missing+=(libtinyxml-dev)
    have_file vtkVersion.h   || missing+=(libvtk9-dev)
    if [ ${#missing[@]} -gt 0 ]; then
        echo "Missing system development packages: ${missing[*]}" >&2
        echo "On Debian/Ubuntu: sudo apt install build-essential cmake ninja-build git ${missing[*]}" >&2
        echo "(package names differ on other distributions; SKIP_SYS_CHECK=1 skips this check)" >&2
        exit 1
    fi
}
[ "${SKIP_SYS_CHECK:-0}" = 1 ] || check_sys

# ---- fparser and CSXCAD in third_party ---------------------------------------------------------------
deps_present() {
    ls "$DEPS_ROOT"/lib/libCSXCAD.* >/dev/null 2>&1 && ls "$DEPS_ROOT"/lib/libfparser.* >/dev/null 2>&1
}

init_deps() {
    mkdir -p "$SRC_ROOT" "$DEPS_ROOT"
    local -a common=(-G "$GENERATOR" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$DEPS_ROOT"
                     -DCMAKE_INSTALL_LIBDIR=lib -DCMAKE_POLICY_VERSION_MINIMUM=3.5)

    [ -d "$SRC_ROOT/fparser" ] || run git clone https://github.com/thliebig/fparser.git "$SRC_ROOT/fparser"
    run cmake -S "$SRC_ROOT/fparser" -B "$SRC_ROOT/fparser/build" "${common[@]}"
    run cmake --build "$SRC_ROOT/fparser/build"
    run cmake --install "$SRC_ROOT/fparser/build"

    [ -d "$SRC_ROOT/CSXCAD" ] || run git clone https://github.com/thliebig/CSXCAD.git "$SRC_ROOT/CSXCAD"
    run cmake -S "$SRC_ROOT/CSXCAD" -B "$SRC_ROOT/CSXCAD/build" "${common[@]}" -DFPARSER_ROOT_DIR="$DEPS_ROOT"
    run cmake --build "$SRC_ROOT/CSXCAD/build"
    run cmake --install "$SRC_ROOT/CSXCAD/build"
}

if [ "${REBUILD_DEPS:-0}" = 1 ] || ! deps_present; then
    init_deps
fi
deps_present || die "fparser/CSXCAD were not found in $DEPS_ROOT/lib after the build"

# ---- openEMS -----------------------------------------------------------------------------------------
cuda_args=(-DWITH_CUDA=ON -DCMAKE_CUDA_COMPILER="$NVCC" -DCMAKE_CUDA_ARCHITECTURES="$ARCH")
[ -n "${CUDAHOSTCXX:-}" ] && cuda_args+=(-DCMAKE_CUDA_HOST_COMPILER="$(command -v "$CUDAHOSTCXX")" -DCMAKE_CXX_COMPILER="$(command -v "$CUDAHOSTCXX")")

run cmake -S "$ROOT" -B "$BUILD" -G "$GENERATOR" -DCMAKE_BUILD_TYPE=Release \
    -DFPARSER_ROOT_DIR="$DEPS_ROOT" -DCSXCAD_ROOT_DIR="$DEPS_ROOT" \
    -DHDF5_PREFER_PARALLEL=OFF -DCMAKE_POLICY_VERSION_MINIMUM=3.5 "${cuda_args[@]}"

# only the compile step goes into the log (not the configuration)
echo ">>> cmake --build $BUILD   (full log: $LOG)"
set +e
cmake --build "$BUILD" "${KEEP_GOING[@]}" 2>&1 | tee "$LOG" >/dev/null
code=${PIPESTATUS[0]}
set -e

echo
echo "===== errors (first 20) ====="
grep -E 'error|FAILED:|undefined reference' "$LOG" | grep -v -i 'warning' | head -n 20 || true
[ "$code" -eq 0 ] || die "Build failed ($code). Full log: $LOG"
echo
echo "Build finished: $BUILD/openEMS"
