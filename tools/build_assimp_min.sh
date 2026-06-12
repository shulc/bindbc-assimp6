#!/usr/bin/env bash
#
# build_assimp_min.sh — reproducible MINIMAL libassimp build for vibe3d.
#
# vibe3d only uses assimp for OBJ / glTF / FBX import+export. Everything else
# (notably LWO, which vibe3d handles itself) is disabled. This keeps the static
# library small and the transitive dependency surface tiny.
#
# Produces, by default, a STATIC self-contained libassimp.a (+ bundled
# libzlibstatic.a) under D-Assimp/lib/. A shared build is available via --shared.
#
# Usage:
#   tools/build_assimp_min.sh                 # static (default)
#   tools/build_assimp_min.sh --shared        # shared libassimp.so.*
#   LINK=shared tools/build_assimp_min.sh     # same, via env
#
# Overridable env:
#   ASSIMP_SRC   source dir   (default: extern/assimp submodule, else ../assimp)
#   BUILD_DIR    cmake build  (default: $D_ASSIMP/build-min)
#   OUT_DIR      artifact dir (default: $D_ASSIMP/lib)
#   LINK         static|shared (default: static; overridden by --static/--shared)
#
set -euo pipefail

# --- locate D-Assimp root (this script lives in $ROOT/tools) ------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D_ASSIMP="$(cd "$SCRIPT_DIR/.." && pwd)"

# --- parse args ---------------------------------------------------------------
LINK="${LINK:-static}"
for arg in "$@"; do
  case "$arg" in
    --static) LINK=static ;;
    --shared) LINK=shared ;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed -E 's/^# ?//' | sed -n '1,40p'
      exit 0 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

case "$LINK" in
  static) BUILD_SHARED=OFF ;;
  shared) BUILD_SHARED=ON  ;;
  *) echo "LINK must be static|shared (got: $LINK)" >&2; exit 2 ;;
esac

# --- resolve source dir -------------------------------------------------------
if [[ -n "${ASSIMP_SRC:-}" ]]; then
  SRC="$ASSIMP_SRC"
elif [[ -d "$D_ASSIMP/.git" || -f "$D_ASSIMP/.git" ]]; then
  if [[ ! -f "$D_ASSIMP/extern/assimp/CMakeLists.txt" ]]; then
    echo "==> initializing assimp submodule"
    git -C "$D_ASSIMP" submodule sync --quiet extern/assimp
    git -C "$D_ASSIMP" submodule update --init --recursive --quiet extern/assimp
  fi
  if [[ -f "$D_ASSIMP/extern/assimp/CMakeLists.txt" ]]; then
    SRC="$D_ASSIMP/extern/assimp"
  else
    echo "Cannot find assimp source after submodule init: $D_ASSIMP/extern/assimp" >&2
    exit 1
  fi
elif [[ -f "$D_ASSIMP/extern/assimp/CMakeLists.txt" ]]; then
  SRC="$D_ASSIMP/extern/assimp"
elif [[ -f "$D_ASSIMP/../assimp/CMakeLists.txt" ]]; then
  SRC="$(cd "$D_ASSIMP/../assimp" && pwd)"
else
  echo "Cannot find assimp source. Set ASSIMP_SRC, or run:" >&2
  echo "  git submodule update --init extern/assimp" >&2
  exit 1
fi
SRC="$(cd "$SRC" && pwd)"

BUILD_DIR="${BUILD_DIR:-$D_ASSIMP/build-min}"
OUT_DIR="${OUT_DIR:-$D_ASSIMP/lib}"

cmake_path() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*)
      cygpath -w "$1"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

is_windows_shell() {
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) return 0 ;;
    *) return 1 ;;
  esac
}

# --- tool checks --------------------------------------------------------------
command -v cmake >/dev/null || { echo "cmake not found" >&2; exit 1; }
if command -v ninja >/dev/null; then
  GEN=(-G Ninja)
elif command -v make >/dev/null; then
  GEN=()  # default Makefiles generator
else
  echo "neither ninja nor make found" >&2; exit 1
fi
JOBS="$(nproc 2>/dev/null || echo 4)"

ASSIMP_VER="$(grep -m1 -oE 'VERSION [0-9]+\.[0-9]+\.[0-9]+' "$SRC/CMakeLists.txt" | awk '{print $2}')"

echo "==> D-Assimp     : $D_ASSIMP"
echo "==> assimp source: $SRC  (v${ASSIMP_VER:-?})"
echo "==> build dir    : $BUILD_DIR"
echo "==> output dir   : $OUT_DIR"
echo "==> link mode    : $LINK (BUILD_SHARED_LIBS=$BUILD_SHARED)"
echo "==> jobs         : $JOBS"

CMAKE_SRC="$(cmake_path "$SRC")"
CMAKE_BUILD_DIR="$(cmake_path "$BUILD_DIR")"

# Assimp's vendored zlib 1.3.1 trips over AppleClang 21's TARGET_OS_MAC
# predefines: zutil.h takes an old classic-Mac branch, macro-defines fdopen,
# then breaks the SDK stdio.h declaration. Use the system zlib on Darwin.
ASSIMP_BUILD_ZLIB=ON
if [[ "$(uname -s)" == "Darwin" ]]; then
  ASSIMP_BUILD_ZLIB=OFF
fi

# --- configure ----------------------------------------------------------------
# Formats vibe3d needs: OBJ, glTF, FBX — importer AND exporter. Everything else
# off. NOTE: LWO stays OFF on purpose (vibe3d has its own LWO code).
CFG=(
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=$BUILD_SHARED

  -DASSIMP_BUILD_ALL_IMPORTERS_BY_DEFAULT=OFF
  -DASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT=OFF

  -DASSIMP_BUILD_OBJ_IMPORTER=ON
  -DASSIMP_BUILD_OBJ_EXPORTER=ON
  -DASSIMP_BUILD_GLTF_IMPORTER=ON
  -DASSIMP_BUILD_GLTF_EXPORTER=ON
  -DASSIMP_BUILD_FBX_IMPORTER=ON
  -DASSIMP_BUILD_FBX_EXPORTER=ON

  -DASSIMP_BUILD_ASSIMP_TOOLS=OFF
  -DASSIMP_BUILD_TESTS=OFF
  -DASSIMP_BUILD_SAMPLES=OFF
  -DASSIMP_INSTALL=OFF
  -DASSIMP_WARNINGS_AS_ERRORS=OFF
  -DASSIMP_BUILD_DRACO=OFF

  -DASSIMP_BUILD_ZLIB=$ASSIMP_BUILD_ZLIB
)

echo
echo "==> configure:"
echo "    cmake ${GEN[*]} -S \"$CMAKE_SRC\" -B \"$CMAKE_BUILD_DIR\" ${CFG[*]}"
echo
cmake "${GEN[@]}" -S "$CMAKE_SRC" -B "$CMAKE_BUILD_DIR" "${CFG[@]}"

# --- build --------------------------------------------------------------------
echo
echo "==> build (-j$JOBS)"
cmake --build "$CMAKE_BUILD_DIR" -j"$JOBS"

# --- collect artifacts --------------------------------------------------------
mkdir -p "$OUT_DIR"
echo
echo "==> collecting artifacts into $OUT_DIR"

collected=()
if [[ "$LINK" == "static" ]]; then
  # main static lib. MSVC emits assimp.lib / zlibstatic.lib; GNU/Clang emit
  # libassimp.a / libzlibstatic.a. Find whichever the toolchain produced and
  # copy it through verbatim (keeping its native name) so the dub static-config
  # lflags (libassimp.a on posix, assimp.lib on windows) resolve correctly.
  main="$(find "$BUILD_DIR" \( -name 'libassimp.a' -o -name 'assimp.lib' -o -name 'assimp-*.lib' \) | head -n1)"
  [[ -n "$main" ]] || { echo "libassimp.a / assimp.lib not found in build dir" >&2; exit 1; }
  if is_windows_shell; then
    cp -f "$main" "$OUT_DIR/assimp.lib"
    collected+=("$OUT_DIR/assimp.lib")
  else
    cp -f "$main" "$OUT_DIR/"
    collected+=("$OUT_DIR/$(basename "$main")")
  fi
  # bundled zlib static
  zlib="$(find "$BUILD_DIR" \( -name 'libzlibstatic.a' -o -name 'zlibstatic.lib' \) | head -n1)"
  if [[ -n "$zlib" ]]; then
    cp -f "$zlib" "$OUT_DIR/"
    collected+=("$OUT_DIR/$(basename "$zlib")")
  fi
else
  # shared lib + its symlinks (libassimp.so, libassimp.so.6, libassimp.so.6.0.x)
  while IFS= read -r so; do
    cp -a "$so" "$OUT_DIR/"
    collected+=("$OUT_DIR/$(basename "$so")")
  done < <(find "$BUILD_DIR" -name 'libassimp.so*' )
fi

echo
echo "==> artifacts:"
for f in "${collected[@]}"; do
  if [[ -e "$f" ]]; then
    printf '    %-40s %s\n' "$(basename "$f")" "$(du -h "$f" | awk '{print $1}')"
  fi
done

# --- verify compiled-in formats ----------------------------------------------
# Build+run a tiny C program that lists export formats and probes a couple of
# import format ids, linking against exactly the static lib we just produced.
echo
echo "==> verifying compiled-in formats"

PROBE_DIR="$BUILD_DIR/_probe"
mkdir -p "$PROBE_DIR"
cat > "$PROBE_DIR/probe.c" <<'EOF'
#include <stdio.h>
#include <string.h>
#include <assimp/cexport.h>
#include <assimp/cimport.h>

int main(void) {
    size_t n = aiGetExportFormatCount();
    printf("EXPORTERS (%zu):\n", n);
    for (size_t i = 0; i < n; ++i) {
        const struct aiExportFormatDesc* d = aiGetExportFormatDescription(i);
        if (d) printf("  id=%s  ext=%s  (%s)\n", d->id, d->fileExtension, d->description);
    }
    /* import side: aiIsExtensionSupported reflects registered importers */
    const char* imp[] = { ".obj", ".gltf", ".glb", ".fbx",
                          ".lwo", ".blend", ".dae", ".3ds", ".ply", ".stl" };
    printf("IMPORT EXTENSIONS:\n");
    for (size_t i = 0; i < sizeof(imp)/sizeof(imp[0]); ++i)
        printf("  %-7s %s\n", imp[i],
               aiIsExtensionSupported(imp[i]) ? "YES" : "no");
    return 0;
}
EOF

PROBE_OK=0
if [[ "$LINK" == "static" ]]; then
  ZLIB_LIB=""
  [[ -e "$OUT_DIR/libzlibstatic.a" ]] && ZLIB_LIB="$OUT_DIR/libzlibstatic.a"
  ZLIB_FLAGS=()
  [[ -n "$ZLIB_LIB" ]] || ZLIB_FLAGS=(-lz)
  if g++ -I"$SRC/include" -I"$BUILD_DIR/include" \
        "$PROBE_DIR/probe.c" \
        "$OUT_DIR/libassimp.a" ${ZLIB_LIB:+"$ZLIB_LIB"} \
        "${ZLIB_FLAGS[@]}" -lpthread -lm -ldl \
        -o "$PROBE_DIR/probe" 2> "$PROBE_DIR/link.log"; then
    PROBE_OK=1
  else
    echo "    (probe link failed — see $PROBE_DIR/link.log)"
    sed 's/^/      /' "$PROBE_DIR/link.log" | head -20
  fi
else
  if g++ -I"$SRC/include" -I"$BUILD_DIR/include" \
        "$PROBE_DIR/probe.c" -L"$OUT_DIR" -lassimp \
        -o "$PROBE_DIR/probe" 2> "$PROBE_DIR/link.log"; then
    PROBE_OK=1
  fi
fi

if [[ "$PROBE_OK" == "1" ]]; then
  if [[ "$LINK" == "shared" ]]; then
    LD_LIBRARY_PATH="$OUT_DIR" "$PROBE_DIR/probe"
  else
    "$PROBE_DIR/probe"
  fi
fi

echo
echo "==> done."
