#!/usr/bin/env bash
# Linux counterpart of build.cmd (NOT VERIFIED). Usage:
#   ./build.sh            build into ./build
#   ./build.sh clean      remove ./build first (the dependencies in third_party are kept)
# Settings: see the header of build_openems.sh (CUDA_ARCH, CUDACXX, CUDAHOSTCXX, REBUILD_DEPS, ...).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "${1:-}" = clean ]; then
    rm -rf "$ROOT/build"
fi
exec bash "$ROOT/build_openems.sh"
