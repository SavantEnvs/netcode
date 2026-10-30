#!/usr/bin/env bash
#
# mayhem/build.sh — build netcode's libFuzzer harnesses (sanitized, DWARF 3), their standalone
# reproducers, and the project's unit-test runner (normal flags). Runs in /mayhem as `mayhem`.
# Offline-safe: netcode vendors its libsodium subset (sodium/), so nothing is fetched.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

OBJ="$SRC/mayhem-build"
mkdir -p "$OBJ"

# 1) vendored libsodium, sanitized except UBSan alignment (SIMD kernels use unaligned loads; same as
#    upstream's NETCODE_SANITIZE build). Not coverage-instrumented: crypto kernels would only inflate edges.
$CC $SANITIZER_FLAGS -fno-sanitize=alignment $DEBUG_FLAGS -ffp-contract=off -w \
    -c "$SRC/sodium/sodium.c" -I"$SRC/sodium" -o "$OBJ/sodium.o"

# 2) LeakSanitizer off (ASan + UBSan stay on)
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OBJ/lsan_off.o"

# 3) harnesses: each #includes netcode.c, so the whole library is instrumented
for t in fuzz_read_packet fuzz_connect_token fuzz_parse_address; do
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS -DNETCODE_DEBUG -ffp-contract=off $LIB_FUZZING_ENGINE \
        -I"$SRC" -I"$SRC/sodium" "$SRC/fuzz/$t.c" "$OBJ/sodium.o" "$OBJ/lsan_off.o" -o "$SRC/$t"
    $CC $SANITIZER_FLAGS $DEBUG_FLAGS -DNETCODE_DEBUG -ffp-contract=off \
        -I"$SRC" -I"$SRC/sodium" "$STANDALONE_FUZZ_MAIN" "$SRC/fuzz/$t.c" "$OBJ/sodium.o" "$OBJ/lsan_off.o" \
        -o "$SRC/$t-standalone"
done

# 4) the project's own unit tests, NORMAL flags, independent build tree (build*/ is gitignored)
env -u CFLAGS -u CXXFLAGS -u LDFLAGS cmake -S "$SRC" -B "$SRC/build-tests" \
    -DCMAKE_C_COMPILER="$CC" -DCMAKE_CXX_COMPILER="$CXX" -DCMAKE_BUILD_TYPE=Release \
    -DNETCODE_BUILD_TESTS=ON -DNETCODE_INSTALL=OFF \
    -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS"
cmake --build "$SRC/build-tests" -j"$MAYHEM_JOBS" --target netcode_test
